import Foundation

/// Everything the user can configure. Persisted as JSON next to the clipboard
/// history so the whole configuration is one readable file the user can inspect,
/// edit or delete.
public struct Preferences: Codable, Equatable {

    // Feature switches
    public var clipboardHistoryEnabled: Bool
    public var snipEnabled: Bool
    public var windowSnapEnabled: Bool
    public var keyRemapEnabled: Bool

    // Clipboard
    public var clipboardCapacity: Int
    public var clipboardPollInterval: Double
    public var persistClipboardHistory: Bool
    public var autoPasteOnPick: Bool
    public var excludedApps: Set<String>

    // Window snapping
    public var snapGap: Double
    public var snapCyclingEnabled: Bool

    // Key remapping
    public var remap: RemapConfig

    // Shortcuts, stored as text so the JSON stays human-editable.
    public var shortcuts: [String: String]

    public var launchAtLogin: Bool

    public static let defaultShortcuts: [String: String] = [
        "clipboardHistory": "cmd+shift+v",
        "snipToClipboard":  "cmd+shift+s",
        "snapLeft":         "ctrl+alt+left",
        "snapRight":        "ctrl+alt+right",
        "snapUp":           "ctrl+alt+up",
        "snapDown":         "ctrl+alt+down",
        "snapTopLeft":      "ctrl+alt+1",
        "snapTopRight":     "ctrl+alt+2",
        "snapBottomLeft":   "ctrl+alt+3",
        "snapBottomRight":  "ctrl+alt+4",
        "snapCentre":       "ctrl+alt+c",
        "displayNext":      "ctrl+alt+shift+right",
        "displayPrev":      "ctrl+alt+shift+left",
    ]

    public init(clipboardHistoryEnabled: Bool = true,
                snipEnabled: Bool = true,
                windowSnapEnabled: Bool = true,
                keyRemapEnabled: Bool = false,
                clipboardCapacity: Int = 100,
                clipboardPollInterval: Double = 0.4,
                persistClipboardHistory: Bool = true,
                autoPasteOnPick: Bool = true,
                excludedApps: Set<String> = ClipboardPrivacy.defaultExcludedApps,
                snapGap: Double = 0,
                snapCyclingEnabled: Bool = true,
                remap: RemapConfig = RemapConfig(),
                shortcuts: [String: String] = Preferences.defaultShortcuts,
                launchAtLogin: Bool = false) {
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
        self.snipEnabled = snipEnabled
        self.windowSnapEnabled = windowSnapEnabled
        self.keyRemapEnabled = keyRemapEnabled
        self.clipboardCapacity = clipboardCapacity
        self.clipboardPollInterval = clipboardPollInterval
        self.persistClipboardHistory = persistClipboardHistory
        self.autoPasteOnPick = autoPasteOnPick
        self.excludedApps = excludedApps
        self.snapGap = snapGap
        self.snapCyclingEnabled = snapCyclingEnabled
        self.remap = remap
        self.shortcuts = shortcuts
        self.launchAtLogin = launchAtLogin
    }

    /// Missing keys fall back to the default binding, so a hand-edited or
    /// older config file cannot leave a feature unreachable.
    public func spec(_ name: String) -> HotKeySpec? {
        if let raw = shortcuts[name], let parsed = HotKeySpec.parse(raw) { return parsed }
        if let fallback = Preferences.defaultShortcuts[name] { return HotKeySpec.parse(fallback) }
        return nil
    }

    /// Clamps values that would make the app misbehave if hand-edited to
    /// something silly (a 0 s poll interval spins a core; a 0-item history makes
    /// the feature pointless).
    public func normalised() -> Preferences {
        var p = self
        p.clipboardCapacity = min(max(p.clipboardCapacity, 1), 1000)
        p.clipboardPollInterval = min(max(p.clipboardPollInterval, 0.1), 5.0)
        p.snapGap = min(max(p.snapGap, 0), 100)
        return p
    }

    // MARK: - Storage

    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MacToys", isDirectory: true)
    }

    public static var preferencesURL: URL { supportDirectory.appendingPathComponent("preferences.json") }
    public static var historyURL: URL { supportDirectory.appendingPathComponent("clipboard-history.json") }

    public static func ensureSupportDirectory() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }

    public static func load() -> Preferences {
        guard let data = try? Data(contentsOf: preferencesURL),
              let decoded = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return Preferences()
        }
        return decoded.normalised()
    }

    public func save() throws {
        try Preferences.ensureSupportDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        // Write via a temporary file so an interrupted save cannot leave a
        // truncated config that would reset every setting on next launch.
        let tmp = Preferences.preferencesURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try? FileManager.default.replaceItemAt(Preferences.preferencesURL, withItemAt: tmp)
        if FileManager.default.fileExists(atPath: tmp.path) {
            try? FileManager.default.removeItem(at: tmp)
            try data.write(to: Preferences.preferencesURL, options: .atomic)
        }
    }
}
