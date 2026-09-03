import Foundation

/// Modifier flags, expressed independently of AppKit/Carbon so this module stays
/// pure and testable. Adapters in the app target convert to `CGEventFlags` and to
/// Carbon's `RegisterEventHotKey` bitmask.
public struct Mods: OptionSet, Codable, Hashable, CustomStringConvertible {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let command = Mods(rawValue: 1 << 0)
    public static let shift   = Mods(rawValue: 1 << 1)
    public static let option  = Mods(rawValue: 1 << 2)
    public static let control = Mods(rawValue: 1 << 3)
    public static let fn      = Mods(rawValue: 1 << 4)

    /// Modifiers a user can actually bind. `fn` is excluded because macOS
    /// synthesises it for the arrow/navigation cluster on laptop keyboards.
    public static let bindable: Mods = [.command, .shift, .option, .control]

    public var description: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option)  { s += "⌥" }
        if contains(.shift)   { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// Virtual key codes we care about. These are the ANSI/HIToolbox constants; they
/// are hardware key positions and do not change with keyboard layout.
public enum KeyCode {
    public static let a: UInt16 = 0x00
    public static let c: UInt16 = 0x08
    public static let v: UInt16 = 0x09
    public static let x: UInt16 = 0x07
    public static let s: UInt16 = 0x01
    public static let t: UInt16 = 0x11
    public static let n: UInt16 = 0x2D

    public static let returnKey: UInt16 = 0x24
    public static let tab: UInt16       = 0x30
    public static let space: UInt16     = 0x31
    public static let delete: UInt16    = 0x33   // Backspace
    public static let escape: UInt16    = 0x35
    public static let forwardDelete: UInt16 = 0x75

    public static let home: UInt16     = 0x73
    public static let pageUp: UInt16   = 0x74
    public static let end: UInt16      = 0x77
    public static let pageDown: UInt16 = 0x79

    public static let left: UInt16  = 0x7B
    public static let right: UInt16 = 0x7C
    public static let down: UInt16  = 0x7D
    public static let up: UInt16    = 0x7E

    public static let digits: [String: UInt16] = [
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "5": 0x17,
        "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19, "0": 0x1D,
    ]

    public static let letters: [String: UInt16] = [
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E, "f": 0x03,
        "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26, "k": 0x28, "l": 0x25,
        "m": 0x2E, "n": 0x2D, "o": 0x1F, "p": 0x23, "q": 0x0C, "r": 0x0F,
        "s": 0x01, "t": 0x11, "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07,
        "y": 0x10, "z": 0x06,
    ]

    public static let named: [String: UInt16] = [
        "left": left, "right": right, "up": up, "down": down,
        "home": home, "end": end, "pageup": pageUp, "pagedown": pageDown,
        "space": space, "tab": tab, "return": returnKey, "enter": returnKey,
        "escape": escape, "esc": escape, "delete": delete, "backspace": delete,
        "forwarddelete": forwardDelete,
    ]

    /// Human-readable label for a key code, for display in menus.
    public static func label(for code: UInt16) -> String {
        switch code {
        case left: return "←"
        case right: return "→"
        case up: return "↑"
        case down: return "↓"
        case home: return "Home"
        case end: return "End"
        case pageUp: return "PgUp"
        case pageDown: return "PgDn"
        case space: return "Space"
        case tab: return "Tab"
        case returnKey: return "↩"
        case escape: return "Esc"
        case delete: return "⌫"
        case forwardDelete: return "⌦"
        default:
            if let m = letters.first(where: { $0.value == code }) { return m.key.uppercased() }
            if let m = digits.first(where: { $0.value == code }) { return m.key }
            return String(format: "0x%02X", code)
        }
    }
}

/// A parsed keyboard shortcut, e.g. `"cmd+shift+v"`.
public struct HotKeySpec: Codable, Hashable, CustomStringConvertible {
    public let keyCode: UInt16
    public let mods: Mods

    public init(keyCode: UInt16, mods: Mods) {
        self.keyCode = keyCode
        self.mods = mods
    }

    /// Parses a shortcut string. Accepts `cmd`/`command`/`⌘`, `ctrl`/`control`/`⌃`,
    /// `alt`/`option`/`opt`/`⌥`, `shift`/`⇧`, joined by `+` or `-`, plus one key.
    /// Returns nil when there is no key, an unknown token, or more than one key.
    public static func parse(_ raw: String) -> HotKeySpec? {
        let cleaned = raw.lowercased().replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }

        // Split on "+" but tolerate a literal "+" as the bound key (e.g. "cmd++").
        var tokens: [String] = []
        var current = ""
        for ch in cleaned {
            if ch == "+" || ch == "-" {
                if current.isEmpty { current.append(ch) } else { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        guard !tokens.isEmpty else { return nil }

        var mods: Mods = []
        var key: UInt16?

        for token in tokens {
            switch token {
            case "cmd", "command", "⌘": mods.insert(.command)
            case "ctrl", "control", "⌃": mods.insert(.control)
            case "alt", "option", "opt", "⌥": mods.insert(.option)
            case "shift", "⇧": mods.insert(.shift)
            default:
                guard key == nil else { return nil }   // two keys is a malformed spec
                if let c = KeyCode.named[token] { key = c }
                else if let c = KeyCode.letters[token] { key = c }
                else if let c = KeyCode.digits[token] { key = c }
                else { return nil }
            }
        }

        guard let k = key else { return nil }
        return HotKeySpec(keyCode: k, mods: mods)
    }

    public var description: String { "\(mods)\(KeyCode.label(for: keyCode))" }
}
