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
    private let cheatSheet = CheatSheetWindow()

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

        loadHistory()

        panel = ClipboardPanelController(store: store, watcher: watcher, preferences: preferences)

        startClipboard()
        registerHotKeys()
        startRemapperIfEnabled()
        buildStatusItem()
        installLocalKeyMonitor()

        // Flush history periodically so a crash or forced quit loses at most a
        // few seconds rather than the whole session.
        saveTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.saveHistory()
        }

        installTerminationHandlers()

        if !hotKeys.conflicts.isEmpty {
            Toast.show("Some shortcuts were already taken: \(hotKeys.conflicts.joined(separator: ", "))", duration: 4)
        }
        if isFirstRun {
            cheatSheet.show()
            markFirstRunComplete()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveHistory()
        try? preferences.save()
        hotKeys.unregisterAll()
        remapper.stop()
        awake.deactivate()
        if let monitor = localKeyMonitor { NSEvent.removeMonitor(monitor) }
    }

    private var isFirstRun: Bool {
        !FileManager.default.fileExists(atPath: Preferences.preferencesURL.path)
    }

    private func markFirstRunComplete() {
        try? preferences.save()
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
            hotKeys.register(spec, name: "Snip to Clipboard") { SnipService.capture(.region) }
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
        Permissions.explain(feature: feature, reason: reason, openSettings: Permissions.openAccessibilitySettings)
        return false
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

    // MARK: - Key remapping

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
        rebuildMenu()
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // A template image adapts to light and dark menu bars automatically.
            let image = NSImage(systemSymbolName: "square.on.square.dashed", accessibilityDescription: "MacToys")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "MacToys"
        }
        rebuildMenu()
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

        let header = NSMenuItem(title: "MacToys", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        add("Clipboard History   \(preferences.spec("clipboardHistory")?.description ?? "")", #selector(showClipboard))
        add("Snip to Clipboard   \(preferences.spec("snipToClipboard")?.description ?? "")", #selector(snipRegion))
        add("Snip a Window", #selector(snipWindow))

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
    @objc private func snipRegion() { SnipService.capture(.region) }
    @objc private func snipWindow() { SnipService.capture(.window) }
    @objc private func nextDisplay() { moveDisplay(forward: true) }
    @objc private func showCheatSheet() { cheatSheet.show() }
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
        if #available(macOS 13.0, *) {
            do {
                if preferences.launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Registration only works from a signed bundle in /Applications;
                // say so instead of leaving a checkbox that silently lies.
                preferences.launchAtLogin.toggle()
                Toast.show("Move MacToys to /Applications first", duration: 3)
            }
        }
        try? preferences.save()
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
