import AppKit

/// A one-screen reference mapping Windows habits to what MacToys binds.
///
/// The hardest part of switching is not knowing that a thing is possible. A
/// visible list of "you used to press this, now press that" is the single most
/// useful piece of onboarding for this audience.
final class CheatSheetWindow {

    private var window: NSWindow?

    private struct Row {
        let windowsKey: String
        let what: String
        let macKey: String
    }

    private let rows: [Row] = [
        Row(windowsKey: "Win + V",           what: "Clipboard history",              macKey: "⇧⌘V"),
        Row(windowsKey: "Win + Shift + S",   what: "Screenshot to clipboard",        macKey: "⇧⌘S"),
        Row(windowsKey: "Win + Shift + T",   what: "Grab text off the screen (OCR)",  macKey: "⌃⌥T"),
        Row(windowsKey: "Win + Shift + C",   what: "Pick a colour, copy as hex",      macKey: "⌃⌥K"),
        Row(windowsKey: "Ctrl + Shift + V",  what: "Paste without formatting",        macKey: "⇧⌥⌘V"),
        Row(windowsKey: "Win + ←",           what: "Snap window left (press again for ⅓, ⅔)", macKey: "⌃⌥←"),
        Row(windowsKey: "Win + →",           what: "Snap window right",              macKey: "⌃⌥→"),
        Row(windowsKey: "Win + ↑",           what: "Maximize window (not full screen)", macKey: "⌃⌥↑"),
        Row(windowsKey: "Win + ↓",           what: "Restore / centre window",        macKey: "⌃⌥↓"),
        Row(windowsKey: "—",                 what: "Snap to a corner",               macKey: "⌃⌥1 – 4"),
        Row(windowsKey: "Win + Shift + →",   what: "Move window to next display",    macKey: "⌃⌥⇧→"),
        Row(windowsKey: "Home / End",        what: "Jump to start / end of line",    macKey: "Home / End"),
        Row(windowsKey: "Ctrl + Home / End", what: "Jump to start / end of document", macKey: "Ctrl + Home / End"),
        Row(windowsKey: "Ctrl + X on a file", what: "Cut a file in Finder, then ⌘V to move it", macKey: "⌘X"),
        Row(windowsKey: "Delete on a file",  what: "Move a file to the Trash",       macKey: "⌦"),
    ]

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let width: CGFloat = 660
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 560),
                         styleMask: [.titled, .closable],
                         backing: .buffered,
                         defer: false)
        w.title = "MacToys — Windows to Mac Cheat Sheet"
        w.center()
        w.isReleasedWhenClosed = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let intro = NSTextField(labelWithString: "The Windows shortcut you already know, and what it is on this Mac.")
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor
        stack.addArrangedSubview(intro)
        stack.setCustomSpacing(14, after: intro)

        stack.addArrangedSubview(headerRow())

        for row in rows {
            stack.addArrangedSubview(makeRow(row))
        }

        let note = NSTextField(wrappingLabelWithString:
            "Home/End, Finder cut-and-paste and Delete-to-Trash are part of “Windows Key Behaviour”, which needs Accessibility permission. Everything else works without it.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.preferredMaxLayoutWidth = width - 44
        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(note)

        let scroll = NSScrollView()
        scroll.documentView = stack
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        w.contentView = scroll

        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: width),
        ])

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func headerRow() -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.spacing = 12

        for (text, width) in [("ON WINDOWS", CGFloat(150)), ("WHAT IT DOES", CGFloat(300)), ("ON THIS MAC", CGFloat(120))] {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.textColor = .tertiaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: width).isActive = true
            container.addArrangedSubview(label)
        }
        return container
    }

    private func makeRow(_ row: Row) -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.spacing = 12
        container.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)

        let from = NSTextField(labelWithString: row.windowsKey)
        from.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        from.textColor = .secondaryLabelColor

        let what = NSTextField(labelWithString: row.what)
        what.font = .systemFont(ofSize: 12)
        what.lineBreakMode = .byTruncatingTail

        let to = NSTextField(labelWithString: row.macKey)
        to.font = .systemFont(ofSize: 12, weight: .semibold)

        for (view, width) in [(from, CGFloat(150)), (what, CGFloat(300)), (to, CGFloat(120))] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: width).isActive = true
            container.addArrangedSubview(view)
        }
        return container
    }
}
