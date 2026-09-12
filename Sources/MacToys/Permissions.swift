import AppKit
import ApplicationServices
import CoreGraphics

/// Which macOS privacy permissions each feature needs, and how to ask for them.
///
/// The app is deliberately split so the features that need nothing work
/// immediately: clipboard history, snipping and the menu bar are all usable
/// before the user grants anything. Only window snapping, key remapping, and
/// screen-based capture are gated, and each explains itself at the point of use.
enum Permissions {

    /// True when the user has granted Accessibility. Required to move other
    /// apps' windows and to install a keyboard event tap.
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks macOS to show the "grant Accessibility" prompt. This only appears
    /// once per app binary; afterwards the user must go to Settings themselves,
    /// which is why `openAccessibilitySettings` exists as a fallback.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Whether macOS currently believes this process may capture the screen.
    ///
    /// Only ever used to explain a failure that already happened, never to
    /// decide whether to attempt one: the answer is cached per process and tied
    /// to the code signature, so it goes stale and reports "denied" for a
    /// capture that would have succeeded.
    static var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system's own "would like to record this screen" prompt.
    /// Like Accessibility, this only appears once per app binary; afterwards
    /// the user must go to Settings themselves.
    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Restarts the app, which is what makes a newly granted permission take
    /// effect: macOS answers the "may this process capture the screen" question
    /// once per process and caches it.
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The delay lets this process finish quitting first, so the relaunch
        // does not race a still-running instance.
        task.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// Explains why a permission is needed and offers to open the right pane.
    /// Returns true if the user chose to open Settings.
    @discardableResult
    static func explain(feature: String, permission: String, reason: String,
                        openSettings: @escaping () -> Void) -> Bool {
        guard !isExplaining else { return false }
        isExplaining = true
        defer { isExplaining = false }

        let alert = NSAlert()
        alert.messageText = "\(feature) needs \(permission) access"
        alert.informativeText = reason + "\n\nOpen System Settings › Privacy & Security › \(permission) and switch on MacToys, then try again."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings()
            return true
        }
        return false
    }

    /// True while a permission dialog is on screen.
    ///
    /// `runModal()` spins a nested event loop, and global hotkeys keep firing
    /// inside it — so pressing the snip shortcut again while the dialog was up
    /// stacked another dialog behind it. Dismissing one just revealed the next,
    /// which looked exactly like the dialog refusing to close.
    private static var isExplaining = false

    /// Shown after a screen capture has actually come back empty.
    ///
    /// Two things make this confusing for someone certain they already granted
    /// access: macOS decides once per process and caches it, so a grant given
    /// while the app was running does nothing until it restarts; and MacToys is
    /// ad-hoc signed, so a rebuild changes its signature and macOS stops
    /// recognising the grant even though the entry still looks switched on.
    static func explainScreenRecording() {
        guard !isExplaining else { return }
        isExplaining = true
        defer { isExplaining = false }

        let alert = NSAlert()
        alert.messageText = "Screen Recording access needed"
        alert.informativeText = """
        Snipping and text extraction use the screen capture tool, which needs this permission.

        If you have already switched it on: macOS only re-checks this when an app starts, so MacToys has to be restarted before it takes effect. Use Quit & Reopen below.

        If that does not help, the grant may belong to an earlier build — MacToys is ad-hoc signed, so rebuilding changes its signature and macOS stops recognising it, even though the entry still looks switched on. Remove MacToys from the list (select it, click “–”), then reopen and allow it again.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Quit & Reopen")
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:  relaunch()
        case .alertSecondButtonReturn: openScreenRecordingSettings()
        default: break
        }
    }
}
