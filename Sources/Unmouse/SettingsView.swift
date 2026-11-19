import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(Settings.Keys.language) private var language = "en"

    var body: some View {
        TabView {
            GeneralTab().tabItem { Label(tr("General", "일반"), systemImage: "gearshape") }
            GridTab().tabItem { Label(tr("Grid", "그리드"), systemImage: "squareshape.split.3x3") }
            ScrollTab().tabItem { Label(tr("Scroll", "스크롤"), systemImage: "arrow.up.arrow.down") }
            MissionControlTab().tabItem { Label("Mission Control", systemImage: "rectangle.3.group") }
            LabelTab().tabItem { Label(tr("Labels", "라벨"), systemImage: "tag") }
        }
        .frame(width: 480, height: 520)
        // 언어를 바꾸면 모든 탭의 문구를 다시 만든다.
        .id(language)
    }
}

private struct GeneralTab: View {
    @AppStorage(Settings.Keys.includeMenuBar) private var includeMenuBar = true
    @AppStorage(Settings.Keys.language) private var language = "en"

    var body: some View {
        Form {
            Section {
                Picker(tr("Language", "언어"), selection: $language) {
                    Text("English").tag("en")
                    Text("한국어").tag("ko")
                }
            }
            Section {
                LabeledContent(tr("Click mode shortcut", "클릭 모드 단축키")) {
                    ShortcutRecorder(
                        keyCodeKey: Settings.Keys.clickHotkeyKeyCode, modifiersKey: Settings.Keys.clickHotkeyModifiers)
                }
                Toggle(tr("Show labels on menu bar items", "메뉴바 항목에도 라벨 표시"), isOn: $includeMenuBar)
            } footer: {
                Text(tr("Press the last label character with ⇧ to right-click, ⌥ to double-click, ⌘ to Command-click, or ⌃ to move the cursor without clicking.", "라벨의 마지막 글자를 ⇧와 함께 누르면 우클릭, ⌥는 더블클릭, ⌘는 커맨드 클릭, ⌃는 클릭 없이 커서만 이동입니다."))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Button(tr("Quit Unmouse", "Unmouse 종료")) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct GridTab: View {
    @AppStorage(Settings.Keys.gridEnabled) private var gridEnabled = true
    @AppStorage(Settings.Keys.gridFontSize) private var fontSize = 13.0
    @AppStorage(Settings.Keys.gridBackgroundColor) private var background = "#FFD60A"
    @AppStorage(Settings.Keys.gridBackgroundOpacity) private var backgroundOpacity = 0.9
    @AppStorage(Settings.Keys.gridTextColor) private var text = "#000000"
    @AppStorage(Settings.Keys.gridLineColor) private var line = "#FFD60A"
    @AppStorage(Settings.Keys.gridLineOpacity) private var lineOpacity = 0.6
    @AppStorage(Settings.Keys.labelFontFamily) private var fontFamily = Settings.monospacedFontFamily
    @AppStorage(Settings.Keys.labelFontWeight) private var fontWeight = "bold"
    @AppStorage(Settings.Keys.labelUppercase) private var uppercase = true

    var body: some View {
        Form {
            Section {
                Toggle(tr("Enable grid mode", "그리드 모드 사용"), isOn: $gridEnabled)
                LabeledContent(tr("Grid mode shortcut", "그리드 모드 단축키")) {
                    ShortcutRecorder(
                        keyCodeKey: Settings.Keys.gridHotkeyKeyCode, modifiersKey: Settings.Keys.gridHotkeyModifiers)
                }
            } footer: {
                Text(tr("Divides the screen that has the cursor into a grid. Type two characters to select a cell, which is then divided again. One more character clicks that position. ↩ or Space clicks the center of the selected cell, and ⌫ goes back one step. Modifier keys work as in click mode.", "커서가 있는 화면을 격자로 나눕니다. 두 글자로 칸을 고르면 그 칸을 다시 나누고, 한 글자를 더 누르면 그 위치를 클릭합니다. ↩나 Space는 고른 칸의 중앙을 클릭하고, ⌫는 이전 단계로 돌아갑니다. 수식키는 클릭 모드와 같습니다."))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                LabeledContent(tr("Preview", "미리보기")) {
                    HStack(spacing: 0) {
                        ForEach(["sa", "sd", "sf"], id: \.self) { sample in
                            Text(uppercase ? sample.uppercased() : sample)
                                .font(Font(Settings.labelFont(family: fontFamily, weight: fontWeight, size: fontSize) as CTFont))
                                .foregroundColor(color(text))
                                .padding(.horizontal, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3).fill(color(background).opacity(backgroundOpacity)))
                                .frame(width: 64, height: 44)
                                .border(color(line).opacity(lineOpacity), width: 1)
                        }
                    }
                }
                LabeledContent(tr("Font size", "글자 크기")) {
                    HStack {
                        Slider(value: $fontSize, in: 8...24, step: 1)
                        Text("\(Int(fontSize))").monospacedDigit().frame(width: 28, alignment: .trailing)
                    }
                }
                ColorPicker(tr("Background color", "배경색"), selection: colorBinding($background), supportsOpacity: false)
                LabeledContent(tr("Background opacity", "배경 불투명도")) {
                    HStack {
                        Slider(value: $backgroundOpacity, in: 0...1, step: 0.05)
                        Text("\(Int((backgroundOpacity * 100).rounded()))%").monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                ColorPicker(tr("Text color", "글자색"), selection: colorBinding($text), supportsOpacity: false)
                ColorPicker(tr("Line color", "선 색"), selection: colorBinding($line), supportsOpacity: false)
                LabeledContent(tr("Line opacity", "선 불투명도")) {
                    HStack {
                        Slider(value: $lineOpacity, in: 0...1, step: 0.05)
                        Text("\(Int((lineOpacity * 100).rounded()))%").monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } footer: {
                Text(tr("Grid labels use the font and weight from the Labels tab, but not its font size, padding, or Liquid Glass. In small cells the text shrinks to fit.", "그리드 라벨은 라벨 탭의 서체와 굵기를 따르고, 글자 크기와 여백, Liquid Glass는 따르지 않습니다. 작은 칸에서는 글자가 칸에 맞게 줄어듭니다."))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Button(tr("Reset to defaults", "기본값으로 되돌리기")) {
                    Settings.gridStyleKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ScrollTab: View {
    @AppStorage(Settings.Keys.scrollEnabled) private var enabled = true
    @AppStorage(Settings.Keys.scrollSpeed) private var speed = 2.0
    @AppStorage(Settings.Keys.scrollArrowKeys) private var arrowKeys = false

    var body: some View {
        Form {
            Section {
                Toggle(tr("Enable scroll mode", "스크롤 모드 사용"), isOn: $enabled)
                LabeledContent(tr("Scroll mode shortcut", "스크롤 모드 단축키")) {
                    ShortcutRecorder(
                        keyCodeKey: Settings.Keys.scrollHotkeyKeyCode, modifiersKey: Settings.Keys.scrollHotkeyModifiers)
                }
                LabeledContent(tr("Speed", "속도")) {
                    HStack {
                        Slider(value: $speed, in: 0.5...6, step: 0.5)
                        Text(String(format: "%.1f px/ms", speed)).monospacedDigit().frame(width: 80, alignment: .trailing)
                    }
                }
                Toggle(tr("Also scroll with arrow keys", "방향키로도 스크롤"), isOn: $arrowKeys)
            } footer: {
                Text(tr("J/K scroll down and up, H/L left and right, D/U half a page, G to the top, ⇧G to the bottom. Hold ⇧ to scroll at 3x speed. With several scroll areas, scrolling starts in the one under the cursor, and number keys switch areas. ESC or any other key turns it off.", "J/K 아래·위, H/L 왼쪽·오른쪽, D/U 반 페이지, G 맨 위, ⇧G 맨 아래. ⇧와 함께 누르면 3배 속도로 움직입니다. 영역이 여러 개면 커서가 놓인 영역부터 시작하고 숫자 키로 바꿉니다. ESC나 다른 키를 누르면 끝납니다."))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }
}

private struct MissionControlTab: View {
    @AppStorage(Settings.Keys.missionControlEnabled) private var enabled = true
    @AppStorage(Settings.Keys.missionControlAutoActivate) private var autoActivate = true

    var body: some View {
        Form {
            Section {
                Toggle(tr("Use labels in Mission Control", "Mission Control에서 라벨 사용"), isOn: $enabled)
                Toggle(tr("Show labels automatically when Mission Control opens", "Mission Control이 열리면 자동으로 라벨 표시"), isOn: $autoActivate).disabled(!enabled)
            } footer: {
                Text(tr("When automatic labels are off, press the click mode shortcut while Mission Control is open to show labels.", "자동 표시를 끄면 Mission Control이 열린 상태에서 클릭 모드 단축키를 눌러야 라벨이 나타납니다."))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LabelTab: View {
    @AppStorage(Settings.Keys.labelCharacters) private var characters = ""
    @AppStorage(Settings.Keys.labelFontFamily) private var fontFamily = Settings.monospacedFontFamily
    @AppStorage(Settings.Keys.labelFontWeight) private var fontWeight = "bold"
    @AppStorage(Settings.Keys.labelFontSize) private var fontSize = 12.0
    @AppStorage(Settings.Keys.labelPaddingWidth) private var paddingWidth = 6.0
    @AppStorage(Settings.Keys.labelPaddingHeight) private var paddingHeight = 2.0
    @AppStorage(Settings.Keys.labelBackgroundColor) private var background = "#FFD60A"
    @AppStorage(Settings.Keys.labelBackgroundOpacity) private var backgroundOpacity = 1.0
    @AppStorage(Settings.Keys.labelTextColor) private var text = "#000000"
    @AppStorage(Settings.Keys.labelCornerRadius) private var cornerRadius = 3.0
    @AppStorage(Settings.Keys.labelUppercase) private var uppercase = true
    @AppStorage(Settings.Keys.labelGlass) private var glass = false
    @AppStorage(Settings.Keys.labelGlassTint) private var glassTint = true
    @AppStorage(Settings.Keys.labelPointer) private var pointer = true

    var body: some View {
        Form {
            Section {
                LabeledContent(tr("Preview", "미리보기")) {
                    HStack(spacing: 8) {
                        ForEach(["s", "sa", "dk"], id: \.self) { sample in
                            VStack(spacing: -1) {
                                if pointer {
                                    PointerShape()
                                        .fill(color(background).opacity(backgroundOpacity))
                                        .frame(width: max(4, fontSize * 0.4) * 1.6, height: max(4, fontSize * 0.4))
                                }
                                Text(uppercase ? sample.uppercased() : sample)
                                    .font(Font(Settings.labelFont(family: fontFamily, weight: fontWeight, size: fontSize) as CTFont))
                                    .foregroundColor(color(text))
                                    .padding(.horizontal, paddingWidth / 2)
                                    .padding(.vertical, paddingHeight / 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: cornerRadius)
                                            .fill(color(background).opacity(backgroundOpacity)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: cornerRadius)
                                            .stroke(color(text).opacity(0.45), lineWidth: 1))
                            }
                        }
                    }
                }
            }
            Section {
                TextField(tr("Label characters", "라벨 문자"), text: $characters)
                Picker(tr("Font", "서체"), selection: $fontFamily) {
                    Text(tr("System Monospaced", "시스템 고정폭")).tag(Settings.monospacedFontFamily)
                    Text(tr("System", "시스템")).tag(Settings.systemFontFamily)
                    Divider()
                    ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { Text($0).tag($0) }
                }
                Picker(tr("Weight", "굵기"), selection: $fontWeight) {
                    ForEach(Settings.fontWeights, id: \.key) { Text($0.title).tag($0.key) }
                }
                LabeledContent(tr("Font size", "글자 크기")) {
                    HStack {
                        Slider(value: $fontSize, in: 8...24, step: 1)
                        Text("\(Int(fontSize))").monospacedDigit().frame(width: 28, alignment: .trailing)
                    }
                }
                LabeledContent(tr("Horizontal padding", "가로 여백")) {
                    HStack {
                        Slider(value: $paddingWidth, in: 0...24, step: 1)
                        Text("\(Int(paddingWidth))").monospacedDigit().frame(width: 28, alignment: .trailing)
                    }
                }
                LabeledContent(tr("Vertical padding", "세로 여백")) {
                    HStack {
                        Slider(value: $paddingHeight, in: 0...16, step: 1)
                        Text("\(Int(paddingHeight))").monospacedDigit().frame(width: 28, alignment: .trailing)
                    }
                }
                ColorPicker(tr("Background color", "배경색"), selection: colorBinding($background), supportsOpacity: false)
                LabeledContent(tr("Background opacity", "배경 불투명도")) {
                    HStack {
                        Slider(value: $backgroundOpacity, in: 0...1, step: 0.05)
                        Text("\(Int((backgroundOpacity * 100).rounded()))%").monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                .disabled(glass)
                ColorPicker(tr("Text color", "글자색"), selection: colorBinding($text), supportsOpacity: false)
                LabeledContent(tr("Corner radius", "모서리 둥글기")) {
                    HStack {
                        Slider(value: $cornerRadius, in: 0...10, step: 1)
                        Text("\(Int(cornerRadius))").monospacedDigit().frame(width: 28, alignment: .trailing)
                    }
                }
                Toggle(tr("Show in uppercase", "대문자로 표시"), isOn: $uppercase)
                Toggle(tr("Point at the target with an arrow", "화살표로 대상 가리키기"), isOn: $pointer)
            }
            Section {
                Toggle("Liquid Glass", isOn: $glass)
                Toggle(tr("Tint the glass with the background color", "유리에 배경색 입히기"), isOn: $glassTint).disabled(!glass)
            } footer: {
                Text(tr("Applies on macOS 26 or later. The preview does not show it, so turn on click mode to check. Without the tint, the text color follows the system color. The glass shows better with padding of at least 12 horizontal and 6 vertical, and a corner radius of 8 or more.", "macOS 26 이상에서 적용됩니다. 미리보기에는 반영되지 않으니 클릭 모드를 켜서 확인하세요. 배경색을 입히지 않으면 글자색은 시스템 색을 따릅니다. 여백을 가로 12, 세로 6 이상으로 넓히고 모서리 둥글기를 8 이상으로 올리면 유리 느낌이 더 잘 보입니다."))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                Button(tr("Reset to defaults", "기본값으로 되돌리기")) {
                    Settings.labelStyleKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
                }
            }
        }
        .formStyle(.grouped)
    }

}

private func color(_ hex: String) -> Color {
    Color(nsColor: NSColor(hex: hex) ?? .black)
}

private func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
    Binding(
        get: { color(hex.wrappedValue) },
        set: { hex.wrappedValue = NSColor($0).hexString })
}

private struct PointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct ShortcutRecorder: View {
    @AppStorage private var keyCode: Int
    @AppStorage private var modifiers: Int
    @State private var recording = false
    @State private var monitor: Any?

    init(keyCodeKey: String, modifiersKey: String) {
        _keyCode = AppStorage(wrappedValue: 0, keyCodeKey)
        _modifiers = AppStorage(wrappedValue: 0, modifiersKey)
    }

    var body: some View {
        Button(recording ? tr("Press a shortcut (ESC to cancel)", "키 조합을 누르세요 (ESC 취소)") : current.display) {
            recording ? stop() : start()
        }
        .onDisappear(perform: stop)
    }

    private var current: Hotkey {
        Hotkey(
            keyCode: Int64(keyCode),
            flags: CGEventFlags(rawValue: UInt64(modifiers)).intersection(Hotkey.modifierMask))
    }

    private func start() {
        recording = true
        ShortcutRecording.isActive = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = Int64(event.keyCode)
            if code == KeyCodes.escape {
                stop()
                return nil
            }
            var flags = CGEventFlags()
            if event.modifierFlags.contains(.command) { flags.insert(.maskCommand) }
            if event.modifierFlags.contains(.shift) { flags.insert(.maskShift) }
            if event.modifierFlags.contains(.control) { flags.insert(.maskControl) }
            if event.modifierFlags.contains(.option) { flags.insert(.maskAlternate) }
            // 수식키 없는 일반 키를 단축키로 잡으면 그 키로 타이핑을 못 하게 된다.
            let usable = !flags.subtracting(.maskShift).isEmpty || KeyCodes.functionKeys.contains(code)
            guard usable else {
                NSSound.beep()
                return nil
            }
            keyCode = Int(code)
            modifiers = Int(flags.rawValue)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        ShortcutRecording.isActive = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
