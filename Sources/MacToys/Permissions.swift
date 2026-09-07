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

    /// True when the user has granted Screen Recording, which `screencapture`
    /// needs on behalf of the app that invoked it — snipping and text
    /// extraction both shell out to it. Checking this ourselves, rather than
    /// letting `screencapture` fail silently, is what lets us explain a denial
    /// instead of the feature just doing nothing.
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

    /// Explains why a permission is needed and offers to open the right pane.
    /// Returns true if the user chose to open Settings.
    @discardableResult
    static func explain(feature: String, permission: String, reason: String,
                        openSettings: @escaping () -> Void) -> Bool {
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

    /// The explanation shown whenever a screen capture is attempted without
    /// Screen Recording access.
    ///
    /// This covers both a first-time grant and the far more confusing case of
    /// someone who is certain they already granted it: MacToys is ad-hoc
    /// signed (there is no paid Apple Developer certificate behind it), so
    /// every rebuild produces a new code signature, and macOS ties the grant
    /// to that signature. A grant given to yesterday's build does not carry
    /// over to today's — the entry can sit there checked in Settings and
    /// still not apply, which is indistinguishable from macOS ignoring you.
    static func explainScreenRecording() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording access needed"
        alert.informativeText = """
        Snipping and text extraction both use the screen capture tool, which needs this permission.

        1. Open Privacy & Security › Screen Recording
        2. If MacToys is already listed, remove it first (select it, click “–”) — rebuilding the app changes its signature, so an old grant can stop applying even while it still looks switched on
        3. Quit MacToys completely and reopen it
        4. Try again and allow it when macOS asks
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openScreenRecordingSettings()
        }
    }
}
