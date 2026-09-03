import AppKit
import MacToysCore

/// A borderless panel still needs to accept keystrokes for the search field to
/// work, and `NSPanel` refuses by default unless it has a title bar.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The ⌘⇧V picker: Windows' Win+V, which macOS has never shipped an equivalent of.
final class ClipboardPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                                      NSTextFieldDelegate, NSWindowDelegate {

    private let store: ClipboardStore
    private let watcher: ClipboardWatcher
    private var preferences: Preferences

    private var panel: KeyablePanel!
    private var searchField: NSTextField!
    private var tableView: NSTableView!
    private var emptyLabel: NSTextField!

    private var results: [ClipItem] = []
    /// The app that was in front when the panel opened, so focus (and the
    /// synthesised paste) can be handed back to it.
    private var previousApp: NSRunningApplication?

    var isVisible: Bool { panel?.isVisible ?? false }

    init(store: ClipboardStore, watcher: ClipboardWatcher, preferences: Preferences) {
        self.store = store
        self.watcher = watcher
        self.preferences = preferences
        super.init()
        buildPanel()
    }

    func update(preferences: Preferences) {
        self.preferences = preferences
    }

    // MARK: - Construction

    private func buildPanel() {
        let width: CGFloat = 620
        let height: CGFloat = 420

        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                             styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                             backing: .buffered,
                             defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let content = NSView(frame: panel.contentLayoutRect)
        content.autoresizingMask = [.width, .height]

        // Search field
        searchField = NSTextField(frame: .zero)
        searchField.placeholderString = "Search clipboard history…"
        searchField.font = .systemFont(ofSize: 17)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(searchField)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(separator)

        // Results
        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 46
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(commitSelection)
        tableView.style = .inset

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)

        emptyLabel = NSTextField(labelWithString: "")
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(emptyLabel)

        let footer = NSTextField(labelWithString: "↑↓ move   ⏎ paste   ⌘1–9 pick   ⌘P pin   ⌘⌫ delete   esc close")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .center
        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footer)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),

            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -6),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),

            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
        ])

        panel.contentView = content
    }

    // MARK: - Show / hide

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        searchField.stringValue = ""
        reload()

        positionOnActiveScreen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        if !results.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Opens on whichever display holds the mouse, which is where the user is
    /// looking, rather than always on the primary one.
    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.midY - size.height / 2 + visible.height * 0.08)
        panel.setFrameOrigin(origin)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking away dismisses, like Spotlight.
        hide()
    }

    // MARK: - Data

    func reload() {
        results = store.search(searchField.stringValue)
        tableView.reloadData()

        if results.isEmpty {
            emptyLabel.stringValue = store.items.isEmpty
                ? "Nothing copied yet.\nCopy something and press ⌘⇧V again."
                : "No matches for “\(searchField.stringValue)”."
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
            let row = min(tableView.selectedRow < 0 ? 0 : tableView.selectedRow, results.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < results.count else { return nil }
        let item = results[row]

        let container = NSView()

        let badge = NSTextField(labelWithString: row < 9 ? "⌘\(row + 1)" : "")
        badge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        badge.textColor = .tertiaryLabelColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(badge)

        let title = NSTextField(labelWithString: (item.pinned ? "📌 " : "") + item.preview)
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        let subtitleText = [ClipboardPanelController.appName(item.sourceApp),
                            ClipboardPanelController.relativeTime(item.createdAt)]
            .compactMap { $0 }
            .joined(separator: " · ")
        let subtitle = NSTextField(labelWithString: subtitleText)
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(subtitle)

        var leading = badge.trailingAnchor
        if item.kind == .image, let data = item.imageData, let image = NSImage(data: data) {
            let thumb = NSImageView()
            thumb.image = image
            thumb.imageScaling = .scaleProportionallyDown
            thumb.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(thumb)
            NSLayoutConstraint.activate([
                thumb.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8),
                thumb.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                thumb.widthAnchor.constraint(equalToConstant: 46),
                thumb.heightAnchor.constraint(equalToConstant: 32),
            ])
            leading = thumb.trailingAnchor
        }

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            badge.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 26),

            title.leadingAnchor.constraint(equalTo: leading, constant: 8),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),

            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
        ])
        return container
    }

    // MARK: - Keyboard

    func controlTextDidChange(_ obj: Notification) {
        reload()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            move(by: 1); return true
        case #selector(NSResponder.moveUp(_:)):
            move(by: -1); return true
        case #selector(NSResponder.insertNewline(_:)):
            commitSelection(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            hide(); return true
        case #selector(NSResponder.deleteBackward(_:)):
            // ⌘⌫ deletes the highlighted entry; a plain backspace still edits
            // the search text.
            if NSEvent.modifierFlags.contains(.command) { deleteSelection(); return true }
            return false
        default:
            return false
        }
    }

    /// Handles the chords that `doCommandBy` never sees, because AppKit turns
    /// ⌘-digit and ⌘P into menu lookups rather than field commands.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isVisible, event.modifierFlags.contains(.command) else { return false }

        if let chars = event.charactersIgnoringModifiers {
            if let digit = Int(chars), digit >= 1, digit <= 9 {
                guard digit - 1 < results.count else { return true }
                tableView.selectRowIndexes(IndexSet(integer: digit - 1), byExtendingSelection: false)
                commitSelection()
                return true
            }
            if chars.lowercased() == "p" {
                togglePinOnSelection()
                return true
            }
        }
        return false
    }

    private func move(by delta: Int) {
        guard !results.isEmpty else { return }
        let current = tableView.selectedRow < 0 ? 0 : tableView.selectedRow
        let next = min(max(current + delta, 0), results.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    private var selectedItem: ClipItem? {
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else { return nil }
        return results[row]
    }

    @objc private func commitSelection() {
        guard let item = selectedItem else { return }
        watcher.write(item)
        hide()

        guard preferences.autoPasteOnPick, Permissions.accessibilityGranted else { return }
        // Give the previous app time to come back to the front before the
        // synthetic ⌘V lands, otherwise the keystroke goes nowhere.
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            KeyRemapper.sendPaste()
        }
    }

    private func deleteSelection() {
        guard let item = selectedItem else { return }
        let row = tableView.selectedRow
        store.remove(id: item.id)
        reload()
        if !results.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: min(row, results.count - 1)), byExtendingSelection: false)
        }
    }

    private func togglePinOnSelection() {
        guard let item = selectedItem else { return }
        _ = store.togglePin(id: item.id)
        reload()
    }

    // MARK: - Formatting

    static func appName(_ bundleID: String?) -> String? {
        guard let id = bundleID else { return nil }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return id.components(separatedBy: ".").last
    }

    static func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<5:      return "just now"
        case ..<60:     return "\(seconds)s ago"
        case ..<3600:   return "\(seconds / 60)m ago"
        case ..<86400:  return "\(seconds / 3600)h ago"
        default:        return "\(seconds / 86400)d ago"
        }
    }
}
