import AppKit

// 설정 창에서 단축키를 녹화하는 동안에는 현재 단축키도 그대로 창에 전달한다.
enum ShortcutRecording {
    static var isActive = false
}

final class Controller {
    enum Purpose { case click, scroll, grid }
    private enum State { case idle, scanning, picking, scrolling }

    // 직접 만든 스크롤 이벤트를 사용자의 휠 입력과 구분하는 표시값
    private static let syntheticMarker: Int64 = 0x4B6B_756B

    private var state = State.idle
    private var purpose = Purpose.click
    private var inMissionControl = false
    private var generation = 0
    private var items: [LabelItem] = []
    private var typed = ""
    private var swallowedKeys = Set<Int64>()
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private let overlay = OverlayController()

    private static let digitKeys: [Int64: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]

    private var scrollTargets: [Target] = []
    private var scrollFrame = CGRect.zero
    private var heldScroll: [Int64: CGVector] = [:]
    private var scrollFast = false
    private var scrollRemainder = CGVector.zero
    private var scrollTimer: Timer?
    private var lastTick = CFAbsoluteTimeGetCurrent()

    private var gridScreen = CGRect.zero
    // 단계마다 고른 칸. 비어 있으면 아직 화면 전체를 나눈 단계다.
    private var gridPath: [CGRect] = []
    private var gridCell: CGRect? { gridPath.last }
    // 긴 변이 이 길이 이하인 칸은 더 나누지 않고 클릭한다.
    private static let gridStopCell: CGFloat = 28
    // 한 단계에서 칸을 이 길이보다 잘게 나누지 않는다.
    private static let gridFinestCell: CGFloat = 16

    func installTap() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [
            .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .mouseMoved,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << CGEventMask($1.rawValue)) }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<Controller>.fromOpaque(refcon).takeUnretainedValue()
            return controller.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // 권한이 없는 상태로 탭이 남아 있으면 키와 클릭이 다른 앱에 전달되지 않는다.
    func removeTap() {
        guard let tap else { return }
        deactivate()
        CGEvent.tapEnable(tap: tap, enable: false)
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        CFMachPortInvalidate(tap)
        tapSource = nil
        self.tap = nil
        swallowedKeys.removeAll()
    }

    func missionControlOpened() {
        guard Settings.missionControlEnabled, Settings.missionControlAutoActivate, state == .idle else { return }
        // 열리는 애니메이션이 끝나야 창 썸네일이 접근성 트리에 나타나서 몇 번 다시 시도한다.
        activate(.click, retries: 10, requireMissionControl: true)
    }

    func missionControlClosed() {
        if inMissionControl { deactivate() }
    }

    // 반환값이 true면 이벤트를 앱과 입력기에 전달하지 않는다.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            heldScroll.removeValue(forKey: keyCode)
            return swallowedKeys.remove(keyCode) != nil
        case .mouseMoved:
            if state != .idle, event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker {
                CursorHider.show()
            }
            return false
        default:
            if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker { return false }
            if state == .scrolling, type == .scrollWheel { return false }
            if state != .idle { deactivate() }
            return false
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Bool {
        if ShortcutRecording.isActive { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.intersection(Hotkey.modifierMask)
        let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        var requested: Purpose?
        if Settings.clickHotkey.matches(keyCode: keyCode, flags: flags) {
            requested = .click
        } else if Settings.scrollEnabled, Settings.scrollHotkey.matches(keyCode: keyCode, flags: flags) {
            requested = .scroll
        } else if Settings.gridEnabled, Settings.gridHotkey.matches(keyCode: keyCode, flags: flags) {
            requested = .grid
        }

        if let requested {
            swallowedKeys.insert(keyCode)
            guard !autorepeat else { return true }
            let toggledOff = state != .idle && purpose == requested
            deactivate()
            if !toggledOff { activate(requested) }
            return true
        }
        guard state != .idle else { return false }

        if keyCode == KeyCodes.escape {
            // Mission Control에서는 ESC가 Mission Control도 닫아야 한다.
            let passThrough = inMissionControl
            deactivate()
            if passThrough { return false }
            swallowedKeys.insert(keyCode)
            return true
        }

        switch state {
        case .picking:
            return handlePickingKey(keyCode, flags: flags)
        case .scrolling:
            return handleScrollKey(keyCode, flags: flags, autorepeat: autorepeat)
        default:
            swallowedKeys.insert(keyCode)
            return true
        }
    }

    private func handlePickingKey(_ keyCode: Int64, flags: CGEventFlags) -> Bool {
        if keyCode == KeyCodes.delete {
            swallowedKeys.insert(keyCode)
            if typed.isEmpty, !gridPath.isEmpty {
                gridPath.removeLast()
                showGrid()
                return true
            }
            if !typed.isEmpty { typed.removeLast() }
            overlay.update(typed: typed)
            return true
        }
        if let gridCell, keyCode == KeyCodes.return || keyCode == KeyCodes.space {
            swallowedKeys.insert(keyCode)
            deactivate()
            Clicker.click(at: CGPoint(x: gridCell.midX, y: gridCell.midY), modifiers: flags)
            return true
        }
        guard let character = KeyCodes.character(for: keyCode), Settings.labelCharacters.contains(character) else {
            // 라벨 키가 아닌 단축키(⌘Tab 등)는 모드를 끝내고 원래 동작을 하게 둔다.
            if inMissionControl || flags.contains(.maskCommand) || flags.contains(.maskControl) {
                deactivate()
                return false
            }
            swallowedKeys.insert(keyCode)
            return true
        }

        swallowedKeys.insert(keyCode)
        let candidate = typed + String(character)
        guard items.contains(where: { $0.label.hasPrefix(candidate) }) else { return true }
        typed = candidate
        guard let match = items.first(where: { $0.label == typed }) else {
            overlay.update(typed: typed)
            return true
        }
        let frame = match.target.frame
        if purpose == .grid, Self.gridDivision(of: frame, characters: Settings.labelCharacters.count) != (1, 1) {
            gridPath.append(frame)
            showGrid()
            return true
        }
        deactivate()
        Clicker.click(at: match.target.point, modifiers: flags)
        return true
    }

    private func handleScrollKey(_ keyCode: Int64, flags: CGEventFlags, autorepeat: Bool) -> Bool {
        let arrows = Settings.scrollArrowKeys
        var direction: CGVector?
        var jump: CGFloat?
        switch keyCode {
        case 38: direction = CGVector(dx: 0, dy: -1)  // j
        case 40: direction = CGVector(dx: 0, dy: 1)  // k
        case 4: direction = CGVector(dx: 1, dy: 0)  // h
        case 37: direction = CGVector(dx: -1, dy: 0)  // l
        case 125 where arrows: direction = CGVector(dx: 0, dy: -1)
        case 126 where arrows: direction = CGVector(dx: 0, dy: 1)
        case 123 where arrows: direction = CGVector(dx: 1, dy: 0)
        case 124 where arrows: direction = CGVector(dx: -1, dy: 0)
        case 2: jump = -scrollFrame.height / 2  // d
        case 32: jump = scrollFrame.height / 2  // u
        case 5: jump = flags.contains(.maskShift) ? -1_000_000 : 1_000_000  // g
        default: break
        }
        let hasShortcutModifier =
            flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
        if !hasShortcutModifier, let index = Self.digitKeys[keyCode], index < scrollTargets.count {
            swallowedKeys.insert(keyCode)
            selectScrollTarget(index)
            return true
        }
        guard !hasShortcutModifier, direction != nil || jump != nil else {
            // 스크롤 키가 아니면 모드를 끝내고 키를 그대로 전달해서 타이핑이 사라지지 않게 한다.
            deactivate()
            return false
        }

        swallowedKeys.insert(keyCode)
        if let direction {
            scrollFast = flags.contains(.maskShift)
            if !autorepeat { heldScroll[keyCode] = direction }
        } else if let jump, !autorepeat {
            postScroll(dx: 0, dy: Int32(jump))
        }
        return true
    }

    private func activate(_ purpose: Purpose, retries: Int = 0, requireMissionControl: Bool = false) {
        self.purpose = purpose
        if purpose == .grid {
            beginGrid()
            return
        }
        state = .scanning
        generation += 1
        let current = generation
        let frontmost = NSWorkspace.shared.frontmostApplication

        DispatchQueue.global(qos: .userInteractive).async {
            let scanner = AXScanner(mode: purpose == .click ? .click : .scroll)
            var targets: [Target] = []
            var missionControl = false
            if purpose == .click, Settings.missionControlEnabled, scanner.isMissionControlOpen() {
                missionControl = true
                targets = scanner.scanMissionControl()
            } else if !requireMissionControl, let frontmost {
                AXScanner.enableAccessibility(for: frontmost)
                targets = scanner.scan(app: frontmost)
            }

            DispatchQueue.main.async {
                guard self.state == .scanning, self.generation == current else { return }
                if targets.isEmpty {
                    self.state = .idle
                    if retries > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            guard self.state == .idle, self.generation == current else { return }
                            self.activate(purpose, retries: retries - 1, requireMissionControl: requireMissionControl)
                        }
                    } else if !requireMissionControl {
                        NSSound.beep()
                    }
                    return
                }
                self.present(targets, missionControl: missionControl)
            }
        }
    }

    private func present(_ targets: [Target], missionControl: Bool) {
        inMissionControl = missionControl
        CursorHider.hide()
        if purpose == .scroll {
            beginScrolling(targets)
            return
        }
        let labels = LabelGenerator.labels(count: targets.count, characters: Settings.labelCharacters)
        items = zip(labels, targets).map { LabelItem(label: $0, target: $1) }
        typed = ""
        overlay.show(items: items)
        state = .picking
    }

    private func beginGrid() {
        let screens = NSScreen.screens.map { AXScanner.axRect(of: $0) }
        func overlap(_ screen: CGRect, _ window: CGRect) -> CGFloat {
            let shared = screen.intersection(window)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        // 포커스된 창이 가장 많이 걸친 디스플레이를 나눈다. 창을 읽지 못하면 커서가 있는 디스플레이를 쓴다.
        var focused: CGRect?
        if let window = NSWorkspace.shared.frontmostApplication.flatMap({ AXScanner().focusedWindowFrame(of: $0) }) {
            focused = screens.max { overlap($0, window) < overlap($1, window) }
                .flatMap { overlap($0, window) > 0 ? $0 : nil }
        }
        let cursor = CGEvent(source: nil)?.location ?? .zero
        guard let screen = focused ?? screens.first(where: { $0.contains(cursor) }) ?? screens.first else { return }
        gridScreen = screen
        gridPath = []
        CursorHider.hide()
        showGrid()
    }

    // 고른 칸을 다시 나눌 열과 행의 수. 둘 다 1이면 더 나누지 않고 클릭한다.
    private static func gridDivision(of cell: CGRect, characters: Int) -> (columns: Int, rows: Int) {
        guard max(cell.width, cell.height) > gridStopCell else { return (1, 1) }
        let maxColumns = max(Int((cell.width / gridFinestCell).rounded()), 1)
        let maxRows = max(Int((cell.height / gridFinestCell).rounded()), 1)
        // 두 번째 단계부터는 한 글자로 고르기 때문에 칸 수를 라벨 문자 수 이하로 둔다.
        // 그 안에서 칸의 긴 변이 가장 짧아지는 조합을 고른다.
        var best = (columns: 1, rows: 1)
        var bestSide = CGFloat.infinity
        for columns in 1...maxColumns {
            for rows in 1...maxRows where columns * rows <= characters {
                let side = max(cell.width / CGFloat(columns), cell.height / CGFloat(rows))
                if side < bestSide {
                    best = (columns, rows)
                    bestSide = side
                }
            }
        }
        return best
    }

    private func showGrid() {
        let characters = Settings.labelCharacters
        let region = gridCell ?? gridScreen
        let columns: Int
        let rows: Int
        if gridCell == nil {
            columns = min(characters.count, max(Int(region.width / 90), 2))
            rows = min(characters.count, max(Int(region.height / 60), 2))
        } else {
            (columns, rows) = Self.gridDivision(of: region, characters: characters.count)
        }
        let size = CGSize(width: region.width / CGFloat(columns), height: region.height / CGFloat(rows))

        items = (0..<rows).flatMap { row in
            (0..<columns).map { column in
                let label =
                    gridCell == nil
                    ? String([characters[row], characters[column]]) : String(characters[row * columns + column])
                let frame = CGRect(
                    x: region.minX + CGFloat(column) * size.width, y: region.minY + CGFloat(row) * size.height,
                    width: size.width, height: size.height)
                return LabelItem(label: label, target: Target(frame: frame))
            }
        }
        typed = ""
        state = .picking
        // 라벨이 많아서 그리는 데 시간이 걸린다. event tap 콜백 안에서 그리면 tap이 시간 초과로 꺼진다.
        let current = generation
        DispatchQueue.main.async { [items, gridCell] in
            guard self.generation == current, self.state == .picking else { return }
            self.overlay.show(items: items, highlight: gridCell, pointers: false, cells: true)
        }
    }

    private func beginScrolling(_ targets: [Target]) {
        func area(_ target: Target) -> CGFloat { target.frame.width * target.frame.height }
        // 숫자 키 1~9로 고르기 때문에 큰 영역 9개까지만 쓴다.
        scrollTargets = targets.sorted { area($0) > area($1) }.prefix(9)
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        state = .scrolling
        heldScroll = [:]
        scrollRemainder = .zero

        // 커서가 놓인 영역 중 가장 작은 것을 먼저 고르고, 없으면 가장 큰 영역을 고른다.
        let cursor = CGEvent(source: nil)?.location ?? .zero
        let underCursor = scrollTargets.indices.filter { scrollTargets[$0].frame.contains(cursor) }
            .min { area(scrollTargets[$0]) < area(scrollTargets[$1]) }
        let largest = scrollTargets.indices.max { area(scrollTargets[$0]) < area(scrollTargets[$1]) }
        selectScrollTarget(underCursor ?? largest ?? 0, moveCursor: underCursor == nil)

        lastTick = CFAbsoluteTimeGetCurrent()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.scrollTick() }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
    }

    private func selectScrollTarget(_ index: Int, moveCursor: Bool = true) {
        let target = scrollTargets[index]
        scrollFrame = target.frame
        heldScroll = [:]

        // 스크롤 이벤트는 커서 아래의 뷰로 전달되므로 커서를 선택한 영역 안으로 옮긴다.
        if moveCursor {
            CGWarpMouseCursorPosition(target.point)
            CGAssociateMouseAndMouseCursorPosition(1)
            let moved = CGEvent(
                mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target.point, mouseButton: .left)
            moved?.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            moved?.post(tap: .cghidEventTap)
        }

        var numbers: [LabelItem] = []
        if scrollTargets.count > 1 {
            numbers = scrollTargets.enumerated().map { offset, target in
                let corner = CGRect(x: target.frame.minX + 8, y: target.frame.minY + 8, width: 20, height: 20)
                return LabelItem(label: String(offset + 1), target: Target(frame: corner))
            }
        }
        overlay.show(items: numbers, highlight: target.frame, pointers: false)
    }

    private func scrollTick() {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = min(now - lastTick, 0.05) * 1000
        lastTick = now
        guard state == .scrolling, !heldScroll.isEmpty else {
            scrollRemainder = .zero
            return
        }
        let speed = Settings.scrollSpeed * (scrollFast ? 3 : 1) * elapsed
        for direction in heldScroll.values {
            scrollRemainder.dx += direction.dx * speed
            scrollRemainder.dy += direction.dy * speed
        }
        let dx = scrollRemainder.dx.rounded(.towardZero)
        let dy = scrollRemainder.dy.rounded(.towardZero)
        scrollRemainder.dx -= dx
        scrollRemainder.dy -= dy
        if dx != 0 || dy != 0 { postScroll(dx: Int32(dx), dy: Int32(dy)) }
    }

    private func postScroll(dx: Int32, dy: Int32) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)
        else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    private func deactivate() {
        state = .idle
        generation += 1
        inMissionControl = false
        items = []
        typed = ""
        gridPath = []
        scrollTargets = []
        heldScroll = [:]
        scrollTimer?.invalidate()
        scrollTimer = nil
        overlay.hide()
        CursorHider.show()
    }
}

enum Clicker {
    // ⇧ 우클릭, ⌥ 더블클릭, ⌘ 커맨드 클릭, ⌃ 클릭 없이 커서만 이동
    static func click(at point: CGPoint, modifiers: CGEventFlags) {
        let hoverOnly = modifiers.contains(.maskControl)
        let rightClick = modifiers.contains(.maskShift)
        let clickCount = modifiers.contains(.maskAlternate) ? 2 : 1
        let flags: CGEventFlags = modifiers.contains(.maskCommand) ? .maskCommand : []
        let button: CGMouseButton = rightClick ? .right : .left
        let downType: CGEventType = rightClick ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = rightClick ? .rightMouseUp : .leftMouseUp

        DispatchQueue.global(qos: .userInteractive).async {
            let source = CGEventSource(stateID: .hidSystemState)
            func post(_ type: CGEventType, clickState: Int64) {
                guard let event = CGEvent(
                    mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
                else { return }
                event.flags = flags
                event.setIntegerValueField(.mouseEventClickState, value: clickState)
                event.post(tap: .cghidEventTap)
            }
            post(.mouseMoved, clickState: 0)
            if hoverOnly { return }
            // 커서가 도착한 뒤에 눌러야 hover 상태를 요구하는 요소도 클릭된다.
            usleep(20_000)
            for count in 1...clickCount {
                post(downType, clickState: Int64(count))
                usleep(10_000)
                post(upType, clickState: Int64(count))
                usleep(10_000)
            }
        }
    }
}
