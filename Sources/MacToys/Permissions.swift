import AppKit
import ApplicationServices

/// Which macOS privacy permissions each feature needs, and how to ask for them.
///
/// The app is deliberately split so the features that need nothing work
/// immediately: clipboard history, snipping and the menu bar are all usable
/// before the user grants anything. Only window snapping and key remapping are
/// gated, and each explains itself at the point of use.
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

    static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Explains why a permission is needed and offers to open the right pane.
    /// Returns true if the user chose to open Settings.
    @discardableResult
    static func explain(feature: String, reason: String, openSettings: @escaping () -> Void) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(feature) needs Accessibility access"
        alert.informativeText = reason + "\n\nOpen System Settings › Privacy & Security › Accessibility and switch on MacToys, then try again."
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
}
