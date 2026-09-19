import AppKit
import MacToysCore

/// Shows the health report, with a button next to anything that needs doing.
final class DiagnosticsWindowController: NSObject {

    private var window: NSWindow?
    private var stack: NSStackView?

    /// Re-run the checks; the app owns the state so it builds the report.
    var reportProvider: (() -> DiagnosticsReport)?

    func show() {
        if window == nil { build() }
        refresh()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "MacToys Diagnostics"
        w.isReleasedWhenClosed = false

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        content.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.documentView = content
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        w.contentView = scroll
        NSLayoutConstraint.activate([content.widthAnchor.constraint(equalToConstant: 560)])

        stack = content
        window = w
    }

    func refresh() {
        guard let stack = stack, let report = reportProvider?() else { return }
        for view in stack.arrangedSubviews { view.removeFromSuperview() }

        let title = NSTextField(labelWithString: report.summary)
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = report.isHealthy ? .systemGreen : .labelColor
        stack.addArrangedSubview(title)

        let hint = NSTextField(wrappingLabelWithString:
            "Every feature, and whether it is actually doing anything right now. A grey dot means you switched it off on purpose.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 500
        stack.addArrangedSubview(hint)

        for item in report.items {
            stack.addArrangedSubview(row(for: item))
        }

        let copy = NSButton(title: "Copy Report", target: self, action: #selector(copyReport))
        copy.bezelStyle = .rounded
        stack.addArrangedSubview(copy)
    }

    private func row(for item: DiagnosticItem) -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .top
        container.spacing = 8

        let symbol = NSTextField(labelWithString: item.symbol)
        symbol.font = .systemFont(ofSize: 13)
        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.widthAnchor.constraint(equalToConstant: 20).isActive = true
        container.addArrangedSubview(symbol)

        let text = NSStackView()
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let name = NSTextField(labelWithString: item.feature)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        text.addArrangedSubview(name)

        let detail = NSTextField(wrappingLabelWithString: item.detail)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.preferredMaxLayoutWidth = 460
        text.addArrangedSubview(detail)

        if let fix = item.fix {
            let action = NSTextField(wrappingLabelWithString: "→ " + fix)
            action.font = .systemFont(ofSize: 11, weight: .medium)
            action.textColor = item.state == .broken ? .systemRed : .systemOrange
            action.preferredMaxLayoutWidth = 460
            text.addArrangedSubview(action)
        }

        container.addArrangedSubview(text)
        return container
    }

    @objc private func copyReport() {
        guard let report = reportProvider?() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.plainText(), forType: .string)
        Toast.show("Diagnostics copied")
    }
}
