import AppKit

struct Hotkey: Equatable {
    static let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]

    var keyCode: Int64
    var flags: CGEventFlags

    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        self.keyCode == keyCode && self.flags == flags.intersection(Self.modifierMask)
    }

    var display: String {
        var text = ""
        if flags.contains(.maskControl) { text += "⌃" }
        if flags.contains(.maskAlternate) { text += "⌥" }
        if flags.contains(.maskShift) { text += "⇧" }
        if flags.contains(.maskCommand) { text += "⌘" }
        return text + KeyCodes.displayName(for: keyCode)
    }
}

struct LabelStyle {
    var fontSize: CGFloat
    var background: NSColor
    var text: NSColor
    var cornerRadius: CGFloat
    var uppercase: Bool
    var glass: Bool
    var glassTint: Bool
    var pointer: Bool
}

enum Settings {
    enum Keys {
        static let clickHotkeyKeyCode = "clickHotkeyKeyCode"
        static let clickHotkeyModifiers = "clickHotkeyModifiers"
        static let includeMenuBar = "includeMenuBar"
        static let scrollEnabled = "scrollEnabled"
        static let scrollHotkeyKeyCode = "scrollHotkeyKeyCode"
        static let scrollHotkeyModifiers = "scrollHotkeyModifiers"
        static let scrollSpeed = "scrollSpeed"
        static let scrollArrowKeys = "scrollArrowKeys"
        static let gridEnabled = "gridEnabled"
        static let gridHotkeyKeyCode = "gridHotkeyKeyCode"
        static let gridHotkeyModifiers = "gridHotkeyModifiers"
        static let missionControlEnabled = "missionControlEnabled"
        static let missionControlAutoActivate = "missionControlAutoActivate"
        static let labelCharacters = "labelCharacters"
        static let labelFontSize = "labelFontSize"
        static let labelBackgroundColor = "labelBackgroundColor"
        static let labelTextColor = "labelTextColor"
        static let labelCornerRadius = "labelCornerRadius"
        static let labelUppercase = "labelUppercase"
        static let labelGlass = "labelGlass"
        static let labelGlassTint = "labelGlassTint"
        static let labelPointer = "labelPointer"
    }

    static let defaults: [String: Any] = [
        Keys.clickHotkeyKeyCode: 39,
        Keys.clickHotkeyModifiers: Int(CGEventFlags.maskCommand.rawValue),
        Keys.includeMenuBar: true,
        Keys.scrollEnabled: true,
        Keys.scrollHotkeyKeyCode: 38,
        Keys.scrollHotkeyModifiers: Int(CGEventFlags([.maskCommand, .maskShift]).rawValue),
        Keys.scrollSpeed: 2.0,
        Keys.scrollArrowKeys: false,
        Keys.gridEnabled: true,
        Keys.gridHotkeyKeyCode: 39,
        Keys.gridHotkeyModifiers: Int(CGEventFlags([.maskCommand, .maskShift]).rawValue),
        Keys.missionControlEnabled: true,
        Keys.missionControlAutoActivate: true,
        Keys.labelCharacters: "sadfjklewcmpgh",
        Keys.labelFontSize: 12.0,
        Keys.labelBackgroundColor: "#FFD60A",
        Keys.labelTextColor: "#000000",
        Keys.labelCornerRadius: 3.0,
        Keys.labelUppercase: true,
        Keys.labelGlass: false,
        Keys.labelGlassTint: true,
        Keys.labelPointer: true,
    ]
    static let labelStyleKeys = [
        Keys.labelCharacters, Keys.labelFontSize, Keys.labelBackgroundColor, Keys.labelTextColor,
        Keys.labelCornerRadius, Keys.labelUppercase, Keys.labelGlass, Keys.labelGlassTint, Keys.labelPointer,
    ]

    private static var store: UserDefaults { .standard }

    static func registerDefaults() {
        store.register(defaults: defaults)
    }

    static var clickHotkey: Hotkey { hotkey(Keys.clickHotkeyKeyCode, Keys.clickHotkeyModifiers) }
    static var scrollHotkey: Hotkey { hotkey(Keys.scrollHotkeyKeyCode, Keys.scrollHotkeyModifiers) }
    static var gridHotkey: Hotkey { hotkey(Keys.gridHotkeyKeyCode, Keys.gridHotkeyModifiers) }
    static var gridEnabled: Bool { store.bool(forKey: Keys.gridEnabled) }
    static var includeMenuBar: Bool { store.bool(forKey: Keys.includeMenuBar) }
    static var scrollEnabled: Bool { store.bool(forKey: Keys.scrollEnabled) }
    static var scrollSpeed: Double { max(store.double(forKey: Keys.scrollSpeed), 0.1) }
    static var scrollArrowKeys: Bool { store.bool(forKey: Keys.scrollArrowKeys) }
    static var missionControlEnabled: Bool { store.bool(forKey: Keys.missionControlEnabled) }
    static var missionControlAutoActivate: Bool { store.bool(forKey: Keys.missionControlAutoActivate) }

    static var labelCharacters: [Character] {
        let fallback = defaults[Keys.labelCharacters] as! String
        let raw = store.string(forKey: Keys.labelCharacters) ?? fallback
        var seen = Set<Character>()
        let chars = raw.lowercased().filter { KeyCodes.code(for: $0) != nil && seen.insert($0).inserted }
        return chars.count >= 2 ? Array(chars) : Array(fallback)
    }

    static var labelStyle: LabelStyle {
        LabelStyle(
            fontSize: max(store.double(forKey: Keys.labelFontSize), 6),
            background: NSColor(hex: store.string(forKey: Keys.labelBackgroundColor) ?? "") ?? .systemYellow,
            text: NSColor(hex: store.string(forKey: Keys.labelTextColor) ?? "") ?? .black,
            cornerRadius: max(store.double(forKey: Keys.labelCornerRadius), 0),
            uppercase: store.bool(forKey: Keys.labelUppercase),
            glass: store.bool(forKey: Keys.labelGlass),
            glassTint: store.bool(forKey: Keys.labelGlassTint),
            pointer: store.bool(forKey: Keys.labelPointer))
    }

    private static func hotkey(_ keyCodeKey: String, _ modifiersKey: String) -> Hotkey {
        Hotkey(
            keyCode: Int64(store.integer(forKey: keyCodeKey)),
            flags: CGEventFlags(rawValue: UInt64(store.integer(forKey: modifiersKey))).intersection(Hotkey.modifierMask))
    }
}

// 입력 소스와 무관하게 동작하도록 문자 대신 ANSI 키코드로 매칭한다.
enum KeyCodes {
    static let escape: Int64 = 53
    static let delete: Int64 = 51
    static let `return`: Int64 = 36
    static let space: Int64 = 49

    private static let table: [Character: Int64] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
        ";": 41, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
    ]
    private static let reverse: [Int64: Character] = Dictionary(uniqueKeysWithValues: table.map { ($1, $0) })
    private static let specialNames: [Int64: String] = [
        39: "'", 42: "\\", 33: "[", 30: "]", 27: "-", 24: "=", 50: "`", 49: "Space", 36: "↩", 48: "⇥",
        53: "⎋", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]
    static let functionKeys: Set<Int64> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    static func code(for character: Character) -> Int64? { table[character] }
    static func character(for code: Int64) -> Character? { reverse[code] }

    static func displayName(for code: Int64) -> String {
        if let name = specialNames[code] { return name }
        if let character = reverse[code] { return String(character).uppercased() }
        return "Key \(code)"
    }
}

enum LabelGenerator {
    // 어떤 라벨도 다른 라벨의 접두사가 되지 않게 만든다. 그래야 마지막 글자를 치는 즉시 클릭할 수 있다.
    static func labels(count: Int, characters: [Character]) -> [String] {
        guard count > 0 else { return [] }
        var hints = [""]
        var offset = 0
        while hints.count - offset < count || hints.count == 1 {
            let hint = hints[offset]
            offset += 1
            for character in characters {
                hints.append(String(character) + hint)
            }
        }
        return hints[offset..<(offset + count)].sorted().map { String($0.reversed()) }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let color = usingColorSpace(.sRGB) else { return "#000000" }
        return String(
            format: "#%02X%02X%02X", Int(round(color.redComponent * 255)), Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255)))
    }
}
