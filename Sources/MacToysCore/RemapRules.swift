import Foundation

/// A keystroke as seen by the event tap.
public struct KeyStroke: Equatable {
    public var keyCode: UInt16
    public var mods: Mods
    public init(keyCode: UInt16, mods: Mods) {
        self.keyCode = keyCode
        self.mods = mods
    }
}

/// Something the tap must do besides rewriting the keystroke.
public enum RemapSideEffect: Equatable {
    case armCutMode
    case disarmCutMode
}

public enum RemapOutcome: Equatable {
    /// Leave the keystroke alone.
    case passthrough
    /// Rewrite the keystroke in place, optionally updating cut-mode state.
    case replace(KeyStroke, RemapSideEffect?)
}

public struct RemapContext: Equatable {
    public var frontmostBundleID: String?
    /// True after a Finder ⌘X, until the matching paste or a cancel.
    public var cutModeArmed: Bool

    public init(frontmostBundleID: String?, cutModeArmed: Bool = false) {
        self.frontmostBundleID = frontmostBundleID
        self.cutModeArmed = cutModeArmed
    }
}

public struct RemapConfig: Codable, Equatable {
    /// Home/End jump to line start/end as they do on Windows, instead of
    /// scrolling the view to the top/bottom of the document.
    public var windowsHomeEnd: Bool
    /// ⌘X / ⌘V move files in Finder, instead of Finder having no cut at all.
    public var finderCutPaste: Bool
    /// ⌦ moves the selected file to Trash in Finder, as Del does on Windows.
    public var finderForwardDelete: Bool
    /// Apps that already implement Windows-style navigation, or that route keys
    /// to a remote/embedded environment where rewriting them would be wrong.
    public var homeEndExcludedApps: Set<String>

    public static let defaultHomeEndExclusions: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",   // Cursor
        "com.jetbrains.intellij",
        "org.vim.MacVim",
        "com.apple.dt.Xcode",
    ]

    public init(windowsHomeEnd: Bool = true,
                finderCutPaste: Bool = true,
                finderForwardDelete: Bool = true,
                homeEndExcludedApps: Set<String> = RemapConfig.defaultHomeEndExclusions) {
        self.windowsHomeEnd = windowsHomeEnd
        self.finderCutPaste = finderCutPaste
        self.finderForwardDelete = finderForwardDelete
        self.homeEndExcludedApps = homeEndExcludedApps
    }
}

public enum RemapRules {

    public static let finderBundleID = "com.apple.finder"

    /// Pure decision function for the event tap. Given a keystroke and what is in
    /// front, decide whether to rewrite it.
    ///
    /// Kept free of side effects and of any system call so the whole remapping
    /// policy can be exercised in tests without an event tap or Accessibility
    /// permission.
    public static func outcome(for stroke: KeyStroke,
                               context: RemapContext,
                               config: RemapConfig) -> RemapOutcome {
        // macOS reports fn as held for the Home/End/arrow cluster on laptop
        // keyboards. It is never part of the user's intent here, and leaving it
        // set makes the synthesised event ambiguous.
        let mods = stroke.mods.subtracting(.fn)
        let isFinder = context.frontmostBundleID == finderBundleID

        // --- Finder: cut and paste files, the way Explorer does ------------
        if config.finderCutPaste && isFinder {
            // ⌘X has no meaning in Finder, so claiming it costs the user nothing.
            // Finder can already *move* on paste via ⌘⌥V ("Move Item Here"), it
            // just has no way to express the intent at cut time. So ⌘X becomes a
            // plain ⌘C plus a flag, and the follow-up ⌘V becomes ⌘⌥V. Finder
            // performs the move itself, which keeps its conflict handling,
            // progress UI and undo intact.
            if stroke.keyCode == KeyCode.x && mods == .command {
                return .replace(KeyStroke(keyCode: KeyCode.c, mods: .command), .armCutMode)
            }
            if stroke.keyCode == KeyCode.v && mods == .command && context.cutModeArmed {
                return .replace(KeyStroke(keyCode: KeyCode.v, mods: [.command, .option]), .disarmCutMode)
            }
            // A copy after a cut means the user changed their mind; the next
            // paste must be a copy, not a move.
            if stroke.keyCode == KeyCode.c && mods == .command && context.cutModeArmed {
                return .replace(KeyStroke(keyCode: KeyCode.c, mods: .command), .disarmCutMode)
            }
        }

        if config.finderForwardDelete && isFinder {
            // Windows users press Del to delete a file; on macOS that key does
            // nothing in Finder and ⌘⌫ is the real binding.
            if stroke.keyCode == KeyCode.forwardDelete && mods.isEmpty {
                return .replace(KeyStroke(keyCode: KeyCode.delete, mods: .command), nil)
            }
        }

        // --- Windows-style Home / End --------------------------------------
        if config.windowsHomeEnd,
           stroke.keyCode == KeyCode.home || stroke.keyCode == KeyCode.end {

            if let id = context.frontmostBundleID, config.homeEndExcludedApps.contains(id) {
                return .passthrough
            }

            let isHome = stroke.keyCode == KeyCode.home
            // On Windows, Ctrl+Home/End go to the start/end of the *document*.
            // macOS spells that ⌘↑ / ⌘↓. Plain Home/End are line start/end,
            // which macOS spells ⌘← / ⌘→.
            let documentScope = mods.contains(.control)
            let target: UInt16
            if documentScope {
                target = isHome ? KeyCode.up : KeyCode.down
            } else {
                target = isHome ? KeyCode.left : KeyCode.right
            }

            // Shift is preserved so Shift+Home still extends the selection.
            var newMods: Mods = [.command]
            if mods.contains(.shift) { newMods.insert(.shift) }

            return .replace(KeyStroke(keyCode: target, mods: newMods), nil)
        }

        return .passthrough
    }

    /// Key codes the tap needs to see. Everything else can be ignored cheaply.
    public static func watchedKeyCodes(config: RemapConfig) -> Set<UInt16> {
        var codes: Set<UInt16> = []
        if config.windowsHomeEnd { codes.formUnion([KeyCode.home, KeyCode.end]) }
        if config.finderCutPaste { codes.formUnion([KeyCode.x, KeyCode.v, KeyCode.c]) }
        if config.finderForwardDelete { codes.insert(KeyCode.forwardDelete) }
        return codes
    }
}
