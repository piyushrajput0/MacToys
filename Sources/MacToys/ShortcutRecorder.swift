import AppKit
import Carbon.HIToolbox
import MacToysCore

/// A click-then-press control for rebinding a shortcut.
///
/// While recording it installs a *local* key monitor, so the keystroke is
/// captured by this view rather than triggering whatever it is currently bound
/// to. Modifier-only presses are ignored, because a shortcut with no key would
/// fire on every ⌘ press.
final class ShortcutRecorderView: NSView {

    var spec: HotKeySpec? {
        didSet { needsDisplay = true }
    }
    /// Called with the new binding, or nil when the user clears it.
    var onChange: ((HotKeySpec?) -> Void)?

    private var recording = false {
        didSet { needsDisplay = true }
    }
    private var monitor: Any?

    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    deinit { removeMonitor() }

    // MARK: - Recording

    override func mouseDown(with event: NSEvent) {
        recording ? stop() : start()
    }

    private func start() {
        guard !recording else { return }
        recording = true
        window?.makeFirstResponder(self)

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.recording else { return event }

            if event.type == .flagsChanged { return nil }   // swallow bare modifiers

            if event.keyCode == UInt16(kVK_Escape) {
                self.stop()
                return nil
            }
            if event.keyCode == UInt16(kVK_Delete) {
                self.spec = nil
                self.onChange?(nil)
                self.stop()
                return nil
            }

            let mods = ShortcutRecorderView.mods(from: event.modifierFlags)
            // A bare letter would shadow ordinary typing everywhere, so at
            // least one real modifier is required.
            guard !mods.intersection(.bindable).isEmpty else { return nil }

            let captured = HotKeySpec(keyCode: event.keyCode, mods: mods.intersection(.bindable))
            self.spec = captured
            self.onChange?(captured)
            self.stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        removeMonitor()
    }

    private func removeMonitor() {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    static func mods(from flags: NSEvent.ModifierFlags) -> Mods {
        var m: Mods = []
        if flags.contains(.command)  { m.insert(.command) }
        if flags.contains(.shift)    { m.insert(.shift) }
        if flags.contains(.option)   { m.insert(.option) }
        if flags.contains(.control)  { m.insert(.control) }
        return m
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)

        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.14)
                   : NSColor.controlBackgroundColor).setFill()
        path.fill()

        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()

        let text: String
        let colour: NSColor
        if recording {
            text = "Press keys… (esc cancels, ⌫ clears)"
            colour = .secondaryLabelColor
        } else if let spec = spec {
            text = spec.description
            colour = .labelColor
        } else {
            text = "Click to set"
            colour = .tertiaryLabelColor
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: recording ? 10 : 12,
                                     weight: recording ? .regular : .medium),
            .foregroundColor: colour,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2,
                              y: bounds.midY - size.height / 2),
                  withAttributes: attributes)
    }
}
