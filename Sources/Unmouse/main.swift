import AppKit

Settings.registerDefaults()

if CommandLine.arguments.contains("--check") {
    let labels = LabelGenerator.labels(count: 20, characters: Settings.labelCharacters)
    print("trusted:", AXIsProcessTrusted())
    print("labels:", labels.joined(separator: " "))
    exit(0)
}

// 사용법: Unmouse --preview [-labelGlass YES ...]. 주 화면 왼쪽 위에 견본 라벨을 3초 동안 띄운다.
if CommandLine.arguments.contains("--preview") {
    let preview = NSApplication.shared
    preview.setActivationPolicy(.accessory)
    var samples: [Target] = []
    // bundle id를 주면 견본 대신 그 앱의 실제 요소에 라벨을 띄운다.
    let previewID = CommandLine.arguments.drop { $0 != "--preview" }.dropFirst().first { !$0.hasPrefix("-") }
    if let previewID, let target = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == previewID }) {
        samples = AXScanner().scan(app: target)
        let bounds = samples.reduce(CGRect.null) { $0.union($1.frame) }.insetBy(dx: -30, dy: -30)
        print("\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width)),\(Int(bounds.height))")
        fflush(stdout)
    } else {
        for row in 0..<4 {
            for column in 0..<6 {
                samples.append(Target(frame: CGRect(
                    x: 100 + column * 110, y: 120 + row * 70, width: row % 2 == 0 ? 60 : 90,
                    height: row < 2 ? 24 : 44)))
            }
        }
    }
    let labels = LabelGenerator.labels(count: samples.count, characters: Settings.labelCharacters)
    let overlay = OverlayController()
    overlay.show(items: zip(labels, samples).map { LabelItem(label: $0, target: $1) })
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
    preview.run()
}

// 사용법: Unmouse --mission-control. Mission Control이 열려 있는지와 라벨이 붙을 요소를 출력한다.
if CommandLine.arguments.contains("--mission-control") {
    let open = AXScanner().isMissionControlOpen()
    let targets = open ? AXScanner().scanMissionControl() : []
    print("mission control open: \(open), targets \(targets.count)")
    targets.forEach { print("  ", $0.frame) }
    exit(0)
}

// 사용법: Unmouse --scan [bundle id] [--scroll]. 라벨이 붙을 요소 수와 스캔 시간을 출력한다.
if let index = CommandLine.arguments.firstIndex(of: "--scan") {
    let scroll = CommandLine.arguments.contains("--scroll")
    let bundleID = CommandLine.arguments.dropFirst(index + 1).first { !$0.hasPrefix("--") }
    let running = NSWorkspace.shared.runningApplications
    guard let target = bundleID.flatMap({ id in running.first { $0.bundleIdentifier == id } })
        ?? (bundleID == nil ? NSWorkspace.shared.frontmostApplication : nil)
    else {
        print("실행 중인 앱을 찾지 못함:", bundleID ?? "frontmost")
        exit(1)
    }
    AXScanner.enableAccessibility(for: target)
    let started = Date()
    let targets = AXScanner(mode: scroll ? .scroll : .click).scan(app: target)
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    print("\(target.bundleIdentifier ?? "?"): targets \(targets.count), \(elapsed)ms")
    if scroll { targets.forEach { print("  ", $0.frame) } }
    print("mission control open:", AXScanner().isMissionControlOpen())
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
