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
    public var textExtractorEnabled: Bool
    public var colorPickerEnabled: Bool

    // Clipboard
    public var clipboardCapacity: Int
    public var clipboardPollInterval: Double
    public var persistClipboardHistory: Bool
    public var autoPasteOnPick: Bool
    public var excludedApps: Set<String>

    // Window snapping
    public var snapGap: Double
    public var snapCyclingEnabled: Bool

    // Colour picker
    public var colorFormat: ColorFormat

    // Text extractor
    public var ocrLanguages: [String]
    /// Join wrapped lines back into paragraphs instead of keeping the layout.
    public var ocrJoinLines: Bool

    // Key remapping
    public var remap: RemapConfig

    // Shortcuts, stored as text so the JSON stays human-editable.
    public var shortcuts: [String: String]

    public var launchAtLogin: Bool

    public static let defaultShortcuts: [String: String] = [
        "clipboardHistory": "cmd+shift+v",
        "snipToClipboard":  "cmd+shift+s",
        "pasteAsPlainText": "cmd+shift+alt+v",
        "textExtract":      "ctrl+alt+t",
        "colorPicker":      "ctrl+alt+k",
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
                textExtractorEnabled: Bool = true,
                colorPickerEnabled: Bool = true,
                clipboardCapacity: Int = 15,
                clipboardPollInterval: Double = 0.4,
                persistClipboardHistory: Bool = true,
                autoPasteOnPick: Bool = true,
                excludedApps: Set<String> = ClipboardPrivacy.defaultExcludedApps,
                snapGap: Double = 0,
                snapCyclingEnabled: Bool = true,
                colorFormat: ColorFormat = .hex,
                ocrLanguages: [String] = ["en-US"],
                ocrJoinLines: Bool = false,
                remap: RemapConfig = RemapConfig(),
                shortcuts: [String: String] = Preferences.defaultShortcuts,
                launchAtLogin: Bool = false) {
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
        self.snipEnabled = snipEnabled
        self.windowSnapEnabled = windowSnapEnabled
        self.keyRemapEnabled = keyRemapEnabled
        self.textExtractorEnabled = textExtractorEnabled
        self.colorPickerEnabled = colorPickerEnabled
        self.clipboardCapacity = clipboardCapacity
        self.clipboardPollInterval = clipboardPollInterval
        self.persistClipboardHistory = persistClipboardHistory
        self.autoPasteOnPick = autoPasteOnPick
        self.excludedApps = excludedApps
        self.snapGap = snapGap
        self.snapCyclingEnabled = snapCyclingEnabled
        self.colorFormat = colorFormat
        self.ocrLanguages = ocrLanguages
        self.ocrJoinLines = ocrJoinLines
        self.remap = remap
        self.shortcuts = shortcuts
        self.launchAtLogin = launchAtLogin
    }

    /// Missing keys fall back to the default binding, so a hand-edited or
    /// older config file cannot leave a feature unreachable.
    // A config file written by an older version has none of the newer keys.
    // Synthesised Codable would reject it outright and reset every setting the
    // user had chosen, so each field falls back to its default instead.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decode(T.self, forKey: key)) ?? fallback
        }
        clipboardHistoryEnabled = v(.clipboardHistoryEnabled, d.clipboardHistoryEnabled)
        snipEnabled             = v(.snipEnabled, d.snipEnabled)
        windowSnapEnabled       = v(.windowSnapEnabled, d.windowSnapEnabled)
        keyRemapEnabled         = v(.keyRemapEnabled, d.keyRemapEnabled)
        textExtractorEnabled    = v(.textExtractorEnabled, d.textExtractorEnabled)
        colorPickerEnabled      = v(.colorPickerEnabled, d.colorPickerEnabled)
        clipboardCapacity       = v(.clipboardCapacity, d.clipboardCapacity)
        clipboardPollInterval   = v(.clipboardPollInterval, d.clipboardPollInterval)
        persistClipboardHistory = v(.persistClipboardHistory, d.persistClipboardHistory)
        autoPasteOnPick         = v(.autoPasteOnPick, d.autoPasteOnPick)
        excludedApps            = v(.excludedApps, d.excludedApps)
        snapGap                 = v(.snapGap, d.snapGap)
        snapCyclingEnabled      = v(.snapCyclingEnabled, d.snapCyclingEnabled)
        colorFormat             = v(.colorFormat, d.colorFormat)
        ocrLanguages            = v(.ocrLanguages, d.ocrLanguages)
        ocrJoinLines            = v(.ocrJoinLines, d.ocrJoinLines)
        remap                   = v(.remap, d.remap)
        launchAtLogin           = v(.launchAtLogin, d.launchAtLogin)
        // Merge rather than replace, so a new default shortcut appears for
        // someone upgrading without wiping the ones they customised.
        var merged = Preferences.defaultShortcuts
        for (k, val) in v(.shortcuts, d.shortcuts) { merged[k] = val }
        shortcuts = merged
    }

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
        if p.ocrLanguages.isEmpty { p.ocrLanguages = ["en-US"] }
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
        // `.atomic` already writes to a temporary file and renames it into
        // place, so an interrupted save cannot leave a truncated config that
        // would reset every setting on the next launch.
        try data.write(to: Preferences.preferencesURL, options: .atomic)
    }
}
