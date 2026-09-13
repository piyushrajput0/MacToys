import AppKit
import ServiceManagement
import MacToysCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var preferences = Preferences.load()
    private let store: ClipboardStore
    private let watcher = ClipboardWatcher()
    private let hotKeys = HotKeyManager()
    private let remapper = KeyRemapper()
    private let awake = AwakeService()
    private let volumeGesture = VolumeGestureService()
    private let cheatSheet = CheatSheetWindow()
    private let diagnostics = DiagnosticsWindowController()
    private var settings: SettingsWindowController!

    private var panel: ClipboardPanelController!
    private var statusItem: NSStatusItem!
    private var localKeyMonitor: Any?
    private var saveTimer: Timer?
    private var pendingSave: DispatchWorkItem?
    private var signalSources: [DispatchSourceSignal] = []

    override init() {
        store = ClipboardStore(capacity: preferences.clipboardCapacity)
        super.init()
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Captured before anything writes the file, or the first-run check below
        // would always be false.
        let firstRun = isFirstRun

        // Rewrite the config on launch so options added in a newer version show
        // up in the file the user can actually see and edit. The decoder already
        // filled in defaults for anything missing.
        try? preferences.save()

        loadHistory()

        panel = ClipboardPanelController(store: store, watcher: watcher, preferences: preferences)
        panel.onStoreMutated = { [weak self] in self?.scheduleSave() }
        settings = SettingsWindowController(preferences: preferences)
        settings.onChange = { [weak self] updated in self?.apply(updated) }
        diagnostics.reportProvider = { [weak self] in
            self?.buildDiagnostics() ?? DiagnosticsReport(generatedAt: Date(), items: [])
        }

        startClipboard()
        registerHotKeys()
        startRemapperIfEnabled()
        startVolumeGestureIfEnabled()
        buildStatusItem()
        installLocalKeyMonitor()

        // Flush history periodically so a crash or forced quit loses at most a
        // few seconds rather than the whole session.
        saveTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.saveHistory()
        }

        installTerminationHandlers()
        writeDiagnostics()

        if !hotKeys.conflicts.isEmpty {
            Toast.show("Some shortcuts were already taken: \(hotKeys.conflicts.joined(separator: ", "))", duration: 4)
        }
        if firstRun {
            cheatSheet.show()
        }
        // The app has no Dock icon and no window by design (it lives in the
        // menu bar), so launching it manually — double-clicking it in Finder,
        // Spotlight, opening it again while it is already running — produced
        // no visible feedback at all. That is indistinguishable from "it did
        // not open". Showing Settings here guarantees something appears every
        // time the user actually asks to open the app.
        settings.update(preferences: preferences)
        settings.show()
    }

    /// Called when the user tries to open the app again while it is already
    /// running — e.g. double-clicking it in Finder a second time. Without this,
    /// LaunchServices just re-activates the existing background process, which
    /// has no window to bring forward, so nothing visibly happens.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.update(preferences: preferences)
        settings.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveHistory()
        try? preferences.save()
        hotKeys.unregisterAll()
        remapper.stop()
        volumeGesture.stop()
        awake.deactivate()
        if let monitor = localKeyMonitor { NSEvent.removeMonitor(monitor) }
    }

    private var isFirstRun: Bool {
        !FileManager.default.fileExists(atPath: Preferences.preferencesURL.path)
    }

    // MARK: - Clipboard

    private func startClipboard() {
        watcher.excludedApps = preferences.excludedApps
        watcher.onNewItem = { [weak self] item in
            guard let self = self, self.preferences.clipboardHistoryEnabled else { return }
            self.store.insert(item)
            self.scheduleSave()
        }
        watcher.onAnyChange = { [weak self] in
            // A copy from anywhere invalidates a pending Finder cut.
            self?.remapper.clipboardChangedExternally()
        }
        if preferences.clipboardHistoryEnabled {
            watcher.start(interval: preferences.clipboardPollInterval)
        }
    }

    private func loadHistory() {
        guard preferences.persistClipboardHistory,
              let data = try? Data(contentsOf: Preferences.historyURL) else { return }
        try? store.load(from: data)
    }

    /// Writes the history shortly after a change rather than only on the 20 s
    /// timer, so an abrupt exit loses at most a couple of seconds.
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveHistory() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// `applicationWillTerminate` is only called for a normal quit. A SIGTERM —
    /// which is what macOS sends at logout and shutdown, and what `pkill` sends —
    /// kills the process outright, taking any unsaved history with it.
    private func installTerminationHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            // The default disposition must be ignored, or the process dies
            // before the dispatch source ever runs.
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.saveHistory()
                try? self?.preferences.save()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.saveHistory()
            try? self?.preferences.save()
        }
    }

    private func saveHistory() {
        guard preferences.persistClipboardHistory else { return }
        pendingSave?.cancel()
        do {
            try Preferences.ensureSupportDirectory()
            let data = try store.encode()
            try data.write(to: Preferences.historyURL, options: .atomic)
        } catch {
            NSLog("[MacToys] could not save history: \(error)")
        }
    }

    /// ⌘-digit and ⌘P inside the picker never reach the text field, because
    /// AppKit routes command chords to the menu first.
    private func installLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.panel.handleKeyDown(event) ? nil : event
        }
    }

    // MARK: - Hotkeys

    private func registerHotKeys() {
        hotKeys.unregisterAll()

        if preferences.clipboardHistoryEnabled, let spec = preferences.spec("clipboardHistory") {
            hotKeys.register(spec, name: "Clipboard History") { [weak self] in self?.panel.toggle() }
        }

        if preferences.snipEnabled, let spec = preferences.spec("snipToClipboard") {
            hotKeys.register(spec, name: "Snip to Clipboard") { [weak self] in self?.snip(.region) }
        }

        if let spec = preferences.spec("pasteAsPlainText") {
            hotKeys.register(spec, name: "Paste as Plain Text") { [weak self] in self?.pasteAsPlainText() }
        }

        if preferences.textExtractorEnabled, let spec = preferences.spec("textExtract") {
            hotKeys.register(spec, name: "Extract Text") { [weak self] in self?.extractText() }
        }

        if preferences.colorPickerEnabled, let spec = preferences.spec("colorPicker") {
            hotKeys.register(spec, name: "Pick Colour") { [weak self] in self?.pickColour() }
        }

        guard preferences.windowSnapEnabled else { return }

        let snaps: [(String, SnapAction)] = [
            ("snapLeft", .leftHalf), ("snapRight", .rightHalf),
            ("snapUp", .maximize),   ("snapDown", .centre),
            ("snapTopLeft", .topLeft), ("snapTopRight", .topRight),
            ("snapBottomLeft", .bottomLeft), ("snapBottomRight", .bottomRight),
            ("snapCentre", .centre),
        ]
        for (name, action) in snaps {
            guard let spec = preferences.spec(name) else { continue }
            hotKeys.register(spec, name: action.title) { [weak self] in self?.performSnap(action) }
        }

        if let spec = preferences.spec("displayNext") {
            hotKeys.register(spec, name: "Next Display") { [weak self] in self?.moveDisplay(forward: true) }
        }
        if let spec = preferences.spec("displayPrev") {
            hotKeys.register(spec, name: "Previous Display") { [weak self] in self?.moveDisplay(forward: false) }
        }
    }

    // MARK: - Window actions

    private func requireAccessibility(for feature: String, reason: String) -> Bool {
        if Permissions.accessibilityGranted { return true }
        Permissions.requestAccessibility()
        Permissions.explain(feature: feature, permission: "Accessibility", reason: reason,
                            openSettings: Permissions.openAccessibilitySettings)
        return false
    }

    /// Screen Recording is checked ourselves, rather than letting
    /// `screencapture` fail silently or rely solely on the system's own prompt:
    /// that prompt gives no way to explain the ad-hoc-signing nuance to someone
    /// who is sure they already granted it.
    /// Explains a screen-capture failure, but only after one has actually
    /// happened.
    ///
    /// This used to run *before* the capture and refuse to continue when
    /// `CGPreflightScreenCaptureAccess` said no. That was a mistake: the check
    /// is a prediction, and it goes stale. MacToys is ad-hoc signed, so every
    /// rebuild changes its signature and macOS stops recognising a grant that
    /// was given to an earlier build — and macOS also caches the answer per
    /// process, so granting while the app is running keeps reporting "denied"
    /// until it is restarted. Either way the prediction said no while the
    /// capture itself would have worked, and the feature was blocked for no
    /// reason. Now the capture is always attempted and this only runs if
    /// nothing came back.
    private func explainScreenCaptureFailure() {
        guard !Permissions.screenRecordingGranted else { return }
        Permissions.requestScreenRecording()
        Permissions.explainScreenRecording()
    }

    private func performSnap(_ action: SnapAction) {
        guard requireAccessibility(for: "Window snapping",
                                   reason: "macOS only lets an app move another app's windows once you allow it.") else { return }

        switch WindowManager.snap(action,
                                  gap: CGFloat(preferences.snapGap),
                                  cycling: preferences.snapCyclingEnabled) {
        case .moved:
            break
        case .noWindow:
            Toast.show("No window to snap")
        case .fullScreen:
            Toast.show("That window is in full screen — press esc first")
        case .failed:
            Toast.show("\(action.title) — the app refused to resize")
        }
    }

    private func moveDisplay(forward: Bool) {
        guard requireAccessibility(for: "Moving windows between displays",
                                   reason: "macOS only lets an app move another app's windows once you allow it.") else { return }

        switch WindowManager.moveToAdjacentDisplay(forward: forward, gap: CGFloat(preferences.snapGap)) {
        case .moved:     break
        case .noWindow:  Toast.show("No window to move")
        case .fullScreen: Toast.show("That window is in full screen — press esc first")
        case .failed:    Toast.show(NSScreen.screens.count < 2 ? "Only one display connected" : "Could not move the window")
        }
    }

    // MARK: - Clipboard extras

    /// Windows users reach for Ctrl+Shift+V everywhere; on macOS "paste and
    /// match style" only exists in some apps, under shortcuts that differ.
    /// Stripping the clipboard itself works in every app.
    private func pasteAsPlainText() {
        guard watcher.stripFormatting() != nil else {
            Toast.show("Nothing on the clipboard to paste")
            return
        }
        guard Permissions.accessibilityGranted else {
            Toast.show("Formatting removed — press ⌘V to paste")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { KeyRemapper.sendPaste() }
    }

    private func snip(_ mode: SnipService.Mode) {
        SnipService.capture(mode, saveToDisk: preferences.snipSavesToDisk) { [weak self] result in
            guard let self = self else { return }
            guard result.captured else {
                // Nothing came back: either Escape, or the capture was blocked.
                self.explainScreenCaptureFailure()
                return
            }
            if let url = result.savedTo {
                Toast.show("Copied — also saved as \(url.lastPathComponent)")
            }
        }
    }

    private func extractText() {
        TextExtractor.extract(languages: preferences.ocrLanguages,
                              joinLines: preferences.ocrJoinLines) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let text):
                self.watcher.writeText(text)
                // Recognised text is worth keeping in history even though the
                // app wrote it, so it is inserted explicitly.
                self.store.insert(ClipItem(kind: .text, text: text, sourceApp: "Text Extractor"))
                self.scheduleSave()
                let lines = text.components(separatedBy: "\n").count
                Toast.show("Copied \(text.count) characters (\(lines) line\(lines == 1 ? "" : "s"))")
            case .failure(let error):
                // A capture that produced nothing is either Escape or a
                // permission block; only the second deserves a dialog.
                if case .cancelled = error {
                    self.explainScreenCaptureFailure()
                    return
                }
                if case .captureFailed = error {
                    self.explainScreenCaptureFailure()
                    return
                }
                if let message = error.errorDescription { Toast.show(message) }
            }
        }
    }

    private func pickColour() {
        ColorPickerService.pick(format: preferences.colorFormat) { [weak self] text, _ in
            guard let self = self, let text = text else { return }
            self.watcher.writeText(text)
            self.store.insert(ClipItem(kind: .text, text: text, sourceApp: "Colour Picker"))
            self.scheduleSave()
            Toast.show("Copied \(text)")
        }
    }

    // MARK: - Applying changed preferences

    /// Re-applies the whole configuration without a relaunch.
    private func apply(_ updated: Preferences) {
        let previous = preferences
        preferences = updated.normalised()
        try? preferences.save()

        store.setCapacity(preferences.clipboardCapacity)
        watcher.excludedApps = preferences.excludedApps

        if preferences.clipboardHistoryEnabled {
            if !previous.clipboardHistoryEnabled
                || previous.clipboardPollInterval != preferences.clipboardPollInterval {
                watcher.start(interval: preferences.clipboardPollInterval)
            }
        } else {
            watcher.stop()
        }

        if preferences.keyRemapEnabled {
            if remapper.isRunning {
                remapper.update(config: preferences.remap)
            } else if Permissions.accessibilityGranted {
                remapper.start(config: preferences.remap)
            } else if !previous.keyRemapEnabled {
                // Switched on just now without the permission it needs. Saying
                // nothing left the checkbox ticked over a feature that could
                // not possibly work, so ask, and turn it back off if the answer
                // is no rather than leaving the UI claiming otherwise.
                _ = requireAccessibility(for: "Windows key behaviour",
                                         reason: "Rewriting Home, End and Finder's cut-and-paste means watching keystrokes, which macOS gates behind this permission.")
                if Permissions.accessibilityGranted {
                    remapper.start(config: preferences.remap)
                } else {
                    preferences.keyRemapEnabled = false
                    try? preferences.save()
                    settings.update(preferences: preferences)
                }
            }
        } else if remapper.isRunning {
            remapper.stop()
        }

        if preferences.volumeGestureEnabled {
            if volumeGesture.isRunning {
                volumeGesture.update(fingers: preferences.volumeGestureFingers,
                                     sensitivity: preferences.volumeGestureSensitivity)
            } else if !volumeGesture.start(fingers: preferences.volumeGestureFingers,
                                           sensitivity: preferences.volumeGestureSensitivity) {
                // The private framework this relies on can disappear in a
                // future macOS; say so rather than leaving a dead checkbox.
                preferences.volumeGestureEnabled = false
                try? preferences.save()
                settings.update(preferences: preferences)
                Toast.show(volumeGesture.lastFailure ?? "Volume gesture is unavailable", duration: 4)
            }
        } else if volumeGesture.isRunning {
            volumeGesture.stop()
        }

        if previous.launchAtLogin != preferences.launchAtLogin {
            applyLaunchAtLogin()
        }

        panel.update(preferences: preferences)
        registerHotKeys()
        saveHistory()
        writeDiagnostics()
        rebuildMenu()
        refreshStatusIcon()
    }

    private func applyLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if preferences.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration only works from a signed bundle in a normal location;
            // say so rather than leaving a checkbox that silently lies.
            preferences.launchAtLogin = false
            try? preferences.save()
            settings.update(preferences: preferences)
            Toast.show("Move MacToys to /Applications to launch it at login", duration: 3)
        }
    }

    // MARK: - Key remapping

    private func startVolumeGestureIfEnabled() {
        guard preferences.volumeGestureEnabled else { return }
        if !volumeGesture.start(fingers: preferences.volumeGestureFingers,
                                sensitivity: preferences.volumeGestureSensitivity) {
            NSLog("[MacToys] volume gesture unavailable: \(volumeGesture.lastFailure ?? "unknown")")
        }
    }

    private func startRemapperIfEnabled() {
        guard preferences.keyRemapEnabled else { return }
        if !remapper.start(config: preferences.remap) {
            // Do not nag on every launch; the menu shows the real state.
            NSLog("[MacToys] key remapping enabled but Accessibility not granted")
        }
    }

    @objc private func toggleKeyRemap() {
        if remapper.isRunning {
            remapper.stop()
            preferences.keyRemapEnabled = false
        } else {
            guard requireAccessibility(for: "Windows key behaviour",
                                       reason: "Rewriting Home, End and Finder's cut-and-paste means watching keystrokes, which macOS gates behind this permission.") else { return }
            if remapper.start(config: preferences.remap) {
                preferences.keyRemapEnabled = true
                Toast.show("Windows key behaviour on")
            }
        }
        try? preferences.save()
        settings.update(preferences: preferences)
        rebuildMenu()
    }

    // MARK: - Diagnostics

    /// Builds the health report. Everything here is observed state, not a
    /// restatement of the settings: whether the event tap is genuinely
    /// installed, whether a hotkey was actually claimed, whether the trackpad
    /// reader started. Those are the things that silently differ from what the
    /// checkboxes claim.
    private func buildDiagnostics() -> DiagnosticsReport {
        var items: [DiagnosticItem] = []

        let accessibility = Permissions.accessibilityGranted
        items.append(DiagnosticItem(
            feature: "Accessibility permission",
            state: accessibility ? .ok : .blocked,
            detail: accessibility
                ? "Granted to this build."
                : "Not granted to this build of MacToys. Window snapping and Windows key behaviour cannot work without it.",
            fix: accessibility ? nil
                : "System Settings › Privacy & Security › Accessibility. If MacToys is already listed, remove it first — rebuilding changes its signature, so an old grant stops applying."))

        let screen = Permissions.screenRecordingGranted
        items.append(DiagnosticItem(
            feature: "Screen Recording permission",
            state: screen ? .ok : .blocked,
            detail: screen
                ? "Granted to this build."
                : "macOS says this build cannot capture the screen. Snip and text extraction will be refused.",
            fix: screen ? nil
                : "Try the shortcut anyway — this answer is cached per launch and goes stale. If it really fails, grant it and reopen MacToys."))

        items.append(DiagnosticItem(
            feature: "Clipboard history",
            state: preferences.clipboardHistoryEnabled ? .ok : .off,
            detail: preferences.clipboardHistoryEnabled
                ? "Watching the clipboard. \(store.items.count) of \(preferences.clipboardCapacity) items kept."
                : "Switched off in Settings."))

        // The Finder shortcuts and Home/End all ride on one event tap; if it is
        // not installed, none of them do anything, whatever the boxes say.
        let wantsRemap = preferences.keyRemapEnabled
        let tapRunning = remapper.isRunning
        items.append(DiagnosticItem(
            feature: "Windows key behaviour (⌘X/⌘V in Finder, Home/End, ⌦)",
            state: !wantsRemap ? .off : (tapRunning ? .ok : .blocked),
            detail: !wantsRemap
                ? "Switched off in Settings › Keyboard."
                : (tapRunning
                    ? "Keyboard tap is installed and rewriting keys."
                    : "Switched on, but the keyboard tap is NOT running, so none of these shortcuts do anything."),
            fix: (wantsRemap && !tapRunning)
                ? (accessibility
                    ? "Accessibility is granted but the tap did not start — reopen MacToys."
                    : "Grant Accessibility, then reopen MacToys.")
                : nil))

        let snapOK = preferences.windowSnapEnabled && accessibility
        items.append(DiagnosticItem(
            feature: "Window snapping",
            state: !preferences.windowSnapEnabled ? .off : (snapOK ? .ok : .blocked),
            detail: !preferences.windowSnapEnabled
                ? "Switched off in Settings."
                : (snapOK ? "Ready." : "Switched on, but needs Accessibility before it can move windows."),
            fix: (preferences.windowSnapEnabled && !accessibility) ? "Grant Accessibility, then reopen MacToys." : nil))

        let gestureWanted = preferences.volumeGestureEnabled
        let gestureRunning = volumeGesture.isRunning
        items.append(DiagnosticItem(
            feature: "Trackpad volume gesture",
            state: !gestureWanted ? .off : (gestureRunning ? .ok : .broken),
            detail: !gestureWanted
                ? "Switched off in Settings › Trackpad."
                : (gestureRunning
                    ? "Reading the trackpad with \(preferences.volumeGestureFingers) fingers."
                    : (volumeGesture.lastFailure ?? "Could not read the trackpad.")),
            fix: (gestureWanted && !gestureRunning) ? "Reopen MacToys; if it persists, switch it off in Settings › Trackpad." : nil))

        let volume = AudioController.volume
        items.append(DiagnosticItem(
            feature: "Volume control",
            state: volume == nil ? .broken : .ok,
            detail: volume == nil
                ? "The current output device exposes no adjustable volume, so the gesture cannot change it."
                : "Output volume is \(Int((volume! * 100).rounded()))%.",
            fix: volume == nil ? "Switch to an output that has its own volume, such as the built-in speakers." : nil))

        if hotKeys.conflicts.isEmpty {
            items.append(DiagnosticItem(
                feature: "Keyboard shortcuts",
                state: .ok,
                detail: "All shortcuts were claimed successfully."))
        } else {
            items.append(DiagnosticItem(
                feature: "Keyboard shortcuts",
                state: .broken,
                detail: "Another app already owns: \(hotKeys.conflicts.joined(separator: ", ")).",
                fix: "Pick different keys in Settings › Shortcuts."))
        }

        return DiagnosticsReport(generatedAt: Date(), items: items)
    }

    /// Also written to disk each launch, so the state can be inspected without
    /// opening the app.
    private func writeDiagnostics() {
        let report = buildDiagnostics()
        guard let data = try? JSONEncoder().encode(report) else { return }
        try? Preferences.ensureSupportDirectory()
        try? data.write(to: Preferences.supportDirectory.appendingPathComponent("diagnostics.json"),
                        options: .atomic)
    }

    @objc private func showDiagnostics() { diagnostics.show() }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refreshStatusIcon()
        rebuildMenu()
    }

    /// The icon carries a warning when something is switched on but not
    /// actually working, so a dead feature is visible without hunting for it.
    private func refreshStatusIcon() {
        guard let button = statusItem?.button else { return }
        let report = buildDiagnostics()
        let name = report.isHealthy ? "square.on.square.dashed" : "exclamationmark.triangle"
        // A template image adapts to light and dark menu bars automatically.
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "MacToys")
        image?.isTemplate = true
        button.image = image
        button.toolTip = report.isHealthy ? "MacToys" : "MacToys — \(report.summary)"
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        func add(_ title: String, _ selector: Selector?, key: String = "", enabled: Bool = true, state: NSControl.StateValue? = nil) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.target = self
            item.isEnabled = enabled
            if let state = state { item.state = state }
            menu.addItem(item)
        }

        let report = buildDiagnostics()
        let header = NSMenuItem(title: "MacToys", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // Lead with anything broken rather than burying it.
        for problem in report.problems.prefix(3) {
            let item = NSMenuItem(title: "\(problem.symbol) \(problem.feature)",
                                  action: #selector(showDiagnostics), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())

        add("Clipboard History   \(preferences.spec("clipboardHistory")?.description ?? "")", #selector(showClipboard))
        add("Snip to Clipboard   \(preferences.spec("snipToClipboard")?.description ?? "")", #selector(snipRegion))
        add("Snip a Window", #selector(snipWindow))
        add("Extract Text (OCR)   \(preferences.spec("textExtract")?.description ?? "")", #selector(extractTextFromMenu))
        add("Pick a Colour   \(preferences.spec("colorPicker")?.description ?? "")", #selector(pickColourFromMenu))
        add("Paste as Plain Text   \(preferences.spec("pasteAsPlainText")?.description ?? "")", #selector(pastePlainFromMenu))

        menu.addItem(.separator())

        // Window submenu
        let windowItem = NSMenuItem(title: "Snap Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu()
        let entries: [(String, SnapAction)] = [
            ("Left Half", .leftHalf), ("Right Half", .rightHalf),
            ("Maximize", .maximize), ("Centre", .centre),
            ("Top Left", .topLeft), ("Top Right", .topRight),
            ("Bottom Left", .bottomLeft), ("Bottom Right", .bottomRight),
        ]
        for (title, action) in entries {
            let item = NSMenuItem(title: title, action: #selector(snapFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            windowMenu.addItem(item)
        }
        windowMenu.addItem(.separator())
        let next = NSMenuItem(title: "Move to Next Display", action: #selector(nextDisplay), keyEquivalent: "")
        next.target = self
        windowMenu.addItem(next)
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)

        menu.addItem(.separator())

        add("Windows Key Behaviour", #selector(toggleKeyRemap),
            state: remapper.isRunning ? .on : .off)
        add("Keep Awake", #selector(toggleAwake),
            state: awake.isActive ? .on : .off)

        menu.addItem(.separator())

        let permissionTitle = Permissions.accessibilityGranted
            ? "Accessibility: granted"
            : "Accessibility: not granted — click to fix"
        add(permissionTitle, Permissions.accessibilityGranted ? nil : #selector(openAccessibility))

        add("Settings…", #selector(showSettings), key: ",")
        add("Diagnostics…", #selector(showDiagnostics))
        add("Cheat Sheet…", #selector(showCheatSheet))
        add("Open Config Folder", #selector(openConfigFolder))
        add("Clear Clipboard History", #selector(clearHistory))

        menu.addItem(.separator())
        add("Launch at Login", #selector(toggleLaunchAtLogin), state: preferences.launchAtLogin ? .on : .off)
        add("Quit MacToys", #selector(quit), key: "q")

        statusItem.menu = menu
    }

    // MARK: - Menu actions

    @objc private func showClipboard() { panel.toggle() }
    @objc private func snipRegion() { snip(.region) }
    @objc private func snipWindow() { snip(.window) }
    @objc private func nextDisplay() { moveDisplay(forward: true) }
    @objc private func showCheatSheet() { cheatSheet.show() }
    @objc private func showSettings() { settings.update(preferences: preferences); settings.show() }
    @objc private func extractTextFromMenu() { extractText() }
    @objc private func pickColourFromMenu() { pickColour() }
    @objc private func pastePlainFromMenu() { pasteAsPlainText() }
    @objc private func openAccessibility() { Permissions.openAccessibilitySettings() }

    @objc private func snapFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = SnapAction(rawValue: raw) else { return }
        performSnap(action)
    }

    @objc private func toggleAwake() {
        if awake.isActive {
            awake.deactivate()
            Toast.show("Keep Awake off")
        } else {
            _ = awake.activate(keepDisplayOn: true)
            Toast.show("Keep Awake on")
        }
        rebuildMenu()
    }

    @objc private func openConfigFolder() {
        try? Preferences.ensureSupportDirectory()
        NSWorkspace.shared.open(Preferences.supportDirectory)
    }

    @objc private func clearHistory() {
        store.clearUnpinned()
        saveHistory()
        Toast.show("Clipboard history cleared (pinned items kept)")
    }

    @objc private func toggleLaunchAtLogin() {
        preferences.launchAtLogin.toggle()
        applyLaunchAtLogin()
        try? preferences.save()
        settings.update(preferences: preferences)
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
