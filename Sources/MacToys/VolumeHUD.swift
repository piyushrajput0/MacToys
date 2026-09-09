import AppKit

/// A small volume readout, shown while the trackpad gesture is adjusting it.
///
/// The system HUD cannot be summoned directly; it only appears in response to
/// real media keys, and synthesising those needs Accessibility permission.
/// Drawing our own keeps the gesture working without granting anything.
enum VolumeHUD {

    private static var panel: NSPanel?
    private static var bar: NSView?
    private static var fill: NSView?
    private static var label: NSTextField?
    private static var dismiss: DispatchWorkItem?

    private static let width: CGFloat = 200
    private static let height: CGFloat = 78

    static func show(level: Float, muted: Bool) {
        let panel = existingPanel()
        dismiss?.cancel()

        let clamped = CGFloat(min(max(level, 0), 1))
        label?.stringValue = muted ? "Muted" : "\(Int((clamped * 100).rounded()))%"

        if let bar = bar, let fill = fill {
            let usable = bar.bounds.width
            fill.frame = NSRect(x: 0, y: 0, width: usable * (muted ? 0 : clamped), height: bar.bounds.height)
        }

        if !panel.isVisible {
            position(panel)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.10
                panel.animator().alphaValue = 1
            }
        }

        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }
        dismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private static func existingPanel() -> NSPanel {
        if let panel = panel { return panel }

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true

        let icon = NSTextField(labelWithString: "🔊")
        icon.font = .systemFont(ofSize: 22)
        icon.frame = NSRect(x: 16, y: 40, width: 30, height: 26)
        effect.addSubview(icon)

        let text = NSTextField(labelWithString: "100%")
        text.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        text.alignment = .right
        text.frame = NSRect(x: width - 90, y: 42, width: 74, height: 22)
        effect.addSubview(text)
        label = text

        let track = NSView(frame: NSRect(x: 16, y: 20, width: width - 32, height: 8))
        track.wantsLayer = true
        track.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.18).cgColor
        track.layer?.cornerRadius = 4
        track.layer?.masksToBounds = true
        effect.addSubview(track)
        bar = track

        let level = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: 8))
        level.wantsLayer = true
        level.layer?.backgroundColor = NSColor.labelColor.cgColor
        level.layer?.cornerRadius = 4
        track.addSubview(level)
        fill = level

        p.contentView = effect
        panel = p
        return p
    }

    private static func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: visible.midX - width / 2,
                                     y: visible.minY + 110))
    }
}
