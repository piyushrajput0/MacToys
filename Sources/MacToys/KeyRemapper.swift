import AppKit
import CoreGraphics
import MacToysCore

/// Rewrites keystrokes so Windows muscle memory keeps working.
///
/// A `CGEventTap` sits ahead of every application and may modify events in
/// flight. The policy itself lives in `RemapRules` in the core module, with no
/// system dependencies, so it can be unit tested; this class is only the plumbing
/// that feeds it real events.
final class KeyRemapper {

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var config = RemapConfig()
    private var frontmostBundleID: String?

    /// Set by a Finder ⌘X, cleared by the paste that consumes it.
    private var cutModeArmed = false
    private var cutArmedAt: Date?

    private(set) var isRunning = false

    /// Retained so repeated start/stop cycles do not stack up duplicate
    /// observers, each firing the same handler again.
    private var frontmostObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    /// Returns false when Accessibility has not been granted; the caller is
    /// expected to explain and offer to open Settings rather than silently
    /// leaving the feature dead.
    @discardableResult
    func start(config: RemapConfig) -> Bool {
        self.config = config
        stop()

        guard Permissions.accessibilityGranted else { return false }

        // keyUp is watched as well as keyDown: rewriting only the press would
        // leave the app waiting for a release of a key it never saw pressed,
        // which breaks auto-repeat and shift-selection.
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: { _, type, event, userInfo in
                                              guard let userInfo = userInfo else {
                                                  return Unmanaged.passUnretained(event)
                                              }
                                              let remapper = Unmanaged<KeyRemapper>.fromOpaque(userInfo).takeUnretainedValue()
                                              return remapper.handle(type: type, event: event)
                                          },
                                          userInfo: context) else {
            NSLog("[MacToys] failed to create event tap")
            return false
        }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true

        observeFrontmostApp()
        return true
    }

    func stop() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        runLoopSource = nil
        tap = nil
        isRunning = false
        cutModeArmed = false
    }

    func update(config: RemapConfig) {
        self.config = config
    }

    // MARK: - Frontmost application

    /// The frontmost bundle id is cached from a workspace notification rather
    /// than queried inside the tap callback. The callback runs for every
    /// keystroke on a latency budget: if it is slow, macOS disables the tap
    /// outright, so it must not make cross-process calls.
    private func observeFrontmostApp() {
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard frontmostObserver == nil else { return }
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontmostBundleID = app?.bundleIdentifier
            // Leaving Finder abandons a pending cut, matching Explorer, where
            // the marching-ants selection is dropped when you go elsewhere.
            if app?.bundleIdentifier != RemapRules.finderBundleID {
                self?.cutModeArmed = false
            }
        }
    }

    /// Called when something else writes to the clipboard. A pending Finder cut
    /// refers to whatever was on the pasteboard at cut time, so a later copy
    /// must cancel it or the next paste would move the wrong files.
    func clipboardChangedExternally() {
        // The ⌘X we rewrite into ⌘C is itself a clipboard change; ignore the
        // one that arrives immediately after arming.
        if let armedAt = cutArmedAt, Date().timeIntervalSince(armedAt) < 1.0 { return }
        cutModeArmed = false
    }

    var hasPendingCut: Bool { cutModeArmed }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables a tap that takes too long, or after certain input
        // events. Re-arming is the documented recovery.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let stroke = KeyStroke(keyCode: keyCode, mods: KeyRemapper.mods(from: event.flags))
        let context = RemapContext(frontmostBundleID: frontmostBundleID, cutModeArmed: cutModeArmed)

        switch RemapRules.outcome(for: stroke, context: context, config: config) {
        case .passthrough:
            return Unmanaged.passUnretained(event)

        case .replace(let replacement, let sideEffect):
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(replacement.keyCode))

            var flags = event.flags
            flags.remove([.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn])
            flags.insert(KeyRemapper.cgFlags(replacement.mods))
            event.flags = flags

            // State changes belong to the press only; applying them again on
            // release would immediately undo them.
            if type == .keyDown, let effect = sideEffect {
                switch effect {
                case .armCutMode:
                    cutModeArmed = true
                    cutArmedAt = Date()
                case .disarmCutMode:
                    cutModeArmed = false
                    cutArmedAt = nil
                }
            }
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Flag conversion

    static func mods(from flags: CGEventFlags) -> Mods {
        var m: Mods = []
        if flags.contains(.maskCommand)     { m.insert(.command) }
        if flags.contains(.maskShift)       { m.insert(.shift) }
        if flags.contains(.maskAlternate)   { m.insert(.option) }
        if flags.contains(.maskControl)     { m.insert(.control) }
        if flags.contains(.maskSecondaryFn) { m.insert(.fn) }
        return m
    }

    static func cgFlags(_ mods: Mods) -> CGEventFlags {
        var flags: CGEventFlags = []
        if mods.contains(.command) { flags.insert(.maskCommand) }
        if mods.contains(.shift)   { flags.insert(.maskShift) }
        if mods.contains(.option)  { flags.insert(.maskAlternate) }
        if mods.contains(.control) { flags.insert(.maskControl) }
        return flags
    }

    // MARK: - Synthesis

    /// Sends ⌘V to whatever is frontmost. Used to complete a clipboard-history
    /// pick so the user does not have to press paste themselves.
    static func sendPaste() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        // Suppress our own synthetic events from being fed back into local taps.
        source.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                          state: .eventSuppressionStateSuppressionInterval)

        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(KeyCode.v), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(KeyCode.v), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
