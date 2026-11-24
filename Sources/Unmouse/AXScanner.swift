import AppKit
import ApplicationServices

struct Target {
    // AX 좌표계(주 디스플레이 좌상단 원점) 기준으로 화면에 보이는 영역
    let frame: CGRect
    var point: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
}

final class AXScanner {
    enum Mode { case click, scroll }

    private static let clickableRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXTextField", "AXTextArea", "AXComboBox", "AXSlider", "AXIncrementor",
        "AXDisclosureTriangle", "AXColorWell", "AXMenuItem", "AXMenuBarItem", "AXDockItem",
        "AXSwitch", "AXToggle",
    ]
    // 역할만으로는 클릭 가능 여부를 알 수 없어서 AXPress 액션이 있는지 따로 확인하는 역할
    private static let pressCheckedRoles: Set<String> = ["AXGroup", "AXStaticText", "AXImage", "AXCell"]
    // 클릭 핸들러를 상위 요소에 위임한 웹 요소는 AXPress가 없어서 클래스 이름으로 판단한다.
    private static let clickableClasses: Set<String> = [
        "is-clickable", "tappable", "clickable", "mod-clickable", "cm-underline",
    ]
    private static let leafRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXTextField", "AXTextArea", "AXComboBox", "AXSlider", "AXStaticText", "AXImage",
        "AXScrollBar", "AXSwitch", "AXToggle",
    ]
    private static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "org.chromium.Chromium", "com.operasoftware.Opera",
        "com.naver.Whale",
    ]
    private static let attributes = [
        "AXRole", "AXPosition", "AXSize", "AXChildren", "AXVisibleRows", "AXEnabled", "AXSelected",
        "AXDOMClassList",
    ] as CFArray

    private let mode: Mode
    private let deadline: Date
    private var visited = 0
    private var targets: [Target] = []

    init(mode: Mode = .click, timeout: TimeInterval = 1.5) {
        self.mode = mode
        deadline = Date().addingTimeInterval(timeout)
    }

    // Chromium과 Electron은 요청받기 전에는 웹 콘텐츠의 접근성 트리를 만들지 않는다.
    static func enableAccessibility(for app: NSRunningApplication) {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if let bundleID = app.bundleIdentifier, chromiumBundleIDs.contains(bundleID) {
            AXUIElementSetAttributeValue(element, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    func scan(app: NSRunningApplication) -> [Target] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        let screenBounds = Self.screenBounds
        let menuBar = element(appElement, "AXMenuBar")

        if mode == .click {
            // 메뉴가 열려 있으면 그 뒤의 창은 클릭할 수 없으므로 메뉴 항목만 보여 준다.
            for child in elements(appElement, "AXChildren") where string(child, "AXRole") == "AXMenu" {
                visit(child, clip: screenBounds, insideTarget: false, inWeb: false, depth: 0)
            }
            if let menuBar {
                for item in elements(menuBar, "AXChildren") where bool(item, "AXSelected") {
                    for menu in elements(item, "AXChildren") {
                        visit(menu, clip: screenBounds, insideTarget: false, inWeb: false, depth: 0)
                    }
                }
            }
            if !targets.isEmpty { return finish() }
        }

        var windows: [AXUIElement] = []
        if let focused = element(appElement, "AXFocusedWindow") ?? element(appElement, "AXMainWindow") {
            windows = [focused]
        } else {
            windows = elements(appElement, "AXWindows")
        }
        for window in windows {
            visit(window, clip: screenBounds, insideTarget: false, inWeb: false, depth: 0)
        }

        if mode == .click, Settings.includeMenuBar, let menuBar {
            visit(menuBar, clip: screenBounds, insideTarget: false, inWeb: false, depth: 0)
        }
        // 스크롤 영역을 노출하지 않는 앱은 창 전체를 스크롤 대상으로 쓴다.
        if mode == .scroll, targets.isEmpty {
            targets = windows.compactMap { frame(of: $0) }.map { Target(frame: $0.intersection(screenBounds)) }
                .filter { !$0.frame.isNull }
        }
        return finish()
    }

    // event tap 콜백 안에서 부르기 때문에 응답이 없는 앱을 오래 기다리지 않는다.
    func focusedWindowFrame(of app: NSRunningApplication) -> CGRect? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.1)
        guard let window = element(appElement, "AXFocusedWindow") ?? element(appElement, "AXMainWindow")
        else { return nil }
        return frame(of: window)
    }

    func isMissionControlOpen() -> Bool {
        !missionControlGroups().isEmpty
    }

    func scanMissionControl() -> [Target] {
        let screenBounds = Self.screenBounds
        for group in missionControlGroups() {
            // 스페이스 추가 버튼처럼 디스플레이 밖 좌표를 보고하는 요소는 디스플레이 영역으로 잘라서 제외한다.
            let clip = frame(of: group)?.intersection(screenBounds) ?? screenBounds
            visit(group, clip: clip, insideTarget: false, inWeb: false, depth: 0)
        }
        return finish()
    }

    // Mission Control을 macOS 27부터는 WindowManager가, 그 전에는 Dock이 그린다.
    // 열려 있는 동안에만 디스플레이별 그룹이 자식 요소로 생긴다.
    private func missionControlGroups() -> [AXUIElement] {
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            guard let windowManager = Self.systemElement("com.apple.WindowManager") else { return [] }
            return elements(windowManager, "AXChildren")
        }
        guard let dock = Self.systemElement("com.apple.dock") else { return [] }
        return elements(dock, "AXChildren").filter { string($0, "AXRole") != "AXList" }
    }

    private static func systemElement(_ bundleID: String) -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.5)
        return element
    }

    private static var screenBounds: CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union(axRect(of: $1)) }
    }

    private func finish() -> [Target] {
        var result: [Target] = []
        for target in targets.sorted(by: { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }) {
            let duplicated = result.contains {
                abs($0.point.x - target.point.x) < 4 && abs($0.point.y - target.point.y) < 4
            }
            if !duplicated { result.append(target) }
        }
        return result
    }

    private func visit(_ element: AXUIElement, clip: CGRect, insideTarget: Bool, inWeb: Bool, depth: Int) {
        guard depth < 80, visited < 20_000, Date() < deadline else { return }
        visited += 1

        var rawValues: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element, Self.attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &rawValues)
        guard error == .success, let values = rawValues as? [AnyObject], values.count == 8 else { return }

        let role = values[0] as? String ?? ""
        var children = values[3] as? [AXUIElement] ?? []
        // 행이 많은 표는 화면에 보이는 행만 내려간다. Chromium은 표가 아닌 요소에도 빈 배열을 돌려준다.
        if role == "AXTable" || role == "AXOutline", let rows = values[4] as? [AXUIElement], !rows.isEmpty {
            children = rows
        }
        let enabled = values[5] as? Bool ?? true
        let selected = values[6] as? Bool ?? false

        var clip = clip
        var visible = CGRect.null
        var full = CGRect.null
        if let origin = point(values[1]), let size = size(values[2]), size.width > 0, size.height > 0 {
            full = CGRect(origin: origin, size: size)
            visible = full.intersection(clip)
            if visible.isNull { return }
            // 자식이 박스 밖으로 넘치는 웹 요소는 높이가 1px로 보고되기도 해서 하위는 계속 방문한다.
            if visible.width < 3 || visible.height < 3 {
                visible = .null
            } else if role == "AXScrollArea" || role == "AXWindow" {
                clip = visible
            }
        }

        if mode == .scroll {
            let scrollable = role == "AXScrollArea" || (role == "AXWebArea" && !insideTarget)
            if scrollable, !visible.isNull, visible.width >= 50, visible.height >= 50,
                role != "AXScrollArea" || !isFittingTextInput(element, frame: full, children: children)
            {
                targets.append(Target(frame: visible))
            }
            if role == "AXWebArea" || Self.leafRoles.contains(role) { return }
            for child in children {
                visit(child, clip: clip, insideTarget: insideTarget || scrollable, inWeb: false, depth: depth + 1)
            }
            return
        }

        var clickable = false
        var wrapperIndex: Int?
        if !visible.isNull, enabled {
            if Self.clickableRoles.contains(role) {
                clickable = true
            } else if role == "AXRow" {
                clickable = !insideTarget
            } else if !insideTarget, Self.pressCheckedRoles.contains(role) {
                if !inWeb {
                    clickable = hasPressAction(element)
                } else if role != "AXStaticText" {
                    // WebKit은 클릭 가능한 요소 안의 텍스트에도 AXPress를 보고해서 텍스트는 검사하지 않는다.
                    clickable = isWebClickable(element, classes: values[7] as? [String] ?? [], frame: full)
                    if clickable { wrapperIndex = targets.count }
                }
            }
        }
        if clickable { targets.append(Target(frame: visible)) }

        // CodeMirror 같은 웹 편집기는 본문 전체가 AXTextArea 하나이고 링크가 그 안에 들어 있다.
        let webEditor = inWeb && role == "AXTextArea"
        if Self.leafRoles.contains(role), !webEditor { return }
        // 닫힌 메뉴의 항목도 트리에는 들어 있어서, 열려 있는 메뉴만 내려간다.
        if role == "AXMenuBarItem" && !selected { return }

        let childInWeb = inWeb || role == "AXWebArea"
        for child in children {
            visit(
                child, clip: clip, insideTarget: insideTarget || (clickable && !webEditor), inWeb: childInWeb,
                depth: depth + 1)
        }
        // label 안의 체크박스처럼 안쪽에 실제 컨트롤이 있으면 감싸는 요소는 같은 동작의 중복 대상이다.
        if let wrapperIndex, targets.count > wrapperIndex + 1 { targets.remove(at: wrapperIndex) }
    }

    private func isWebClickable(_ element: AXUIElement, classes: [String], frame: CGRect) -> Bool {
        if !Self.clickableClasses.isDisjoint(with: classes) { return true }
        // 스크롤 컨테이너처럼 내용을 감싸는 큰 요소도 AXPress를 보고한다.
        guard frame.width < 200 || frame.height < 200 else { return false }
        return hasPressAction(element)
    }

    // 내용이 다 보이는 텍스트 입력란은 스크롤할 것이 없어서 대상에서 뺀다. 메신저의 한두 줄짜리 입력란이 여기에 해당한다.
    // 웹 영역을 감싼 스크롤 영역도 내용 크기가 영역과 같게 나오기 때문에 텍스트 입력란으로만 좁힌다.
    private func isFittingTextInput(_ area: AXUIElement, frame: CGRect, children: [AXUIElement]) -> Bool {
        guard !children.isEmpty, value(area, "AXVerticalScrollBar") == nil,
            value(area, "AXHorizontalScrollBar") == nil
        else { return false }
        return children.allSatisfy { child in
            guard let role = string(child, "AXRole"), role == "AXTextArea" || role == "AXTextField",
                let content = self.frame(of: child)
            else { return false }
            return content.width <= frame.width + 1 && content.height <= frame.height + 1
        }
    }

    private func hasPressAction(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success, let actions = names as? [String] else {
            return false
        }
        return actions.contains("AXPress")
    }

    private func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        value(element, attribute) as? [AXUIElement] ?? []
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        value(element, attribute) as? Bool ?? false
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = value(element, "AXPosition"), let size = value(element, "AXSize"),
            let origin = point(position), let extent = self.size(size)
        else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private func point(_ value: AnyObject) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private func size(_ value: AnyObject) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    static func axRect(of screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return CGRect(
            x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
            width: screen.frame.width, height: screen.frame.height)
    }
}
