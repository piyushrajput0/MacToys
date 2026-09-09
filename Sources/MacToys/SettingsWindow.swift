import AppKit
import MacToysCore

/// The preferences UI.
///
/// Everything here is also editable in `preferences.json`, but expecting a
/// Windows switcher to hand-edit JSON to change a shortcut is not a real
/// product. Changes apply immediately: `onChange` hands the whole struct back so
/// the app can re-register hotkeys and restart services without a relaunch.
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var preferences: Preferences
    var onChange: ((Preferences) -> Void)?

    /// Guards against feedback: rebuilding controls from a struct fires their
    /// actions, which would write the struct back and loop.
    private var populating = false

    private var checkboxes: [String: NSButton] = [:]
    private var recorders: [String: ShortcutRecorderView] = [:]
    private var capacityField: NSTextField!
    private var capacityStepper: NSStepper!
    private var gapSlider: NSSlider!
    private var gapLabel: NSTextField!
    private var colorFormatPopup: NSPopUpButton!
    private var fingersPopup: NSPopUpButton!
    private var keyboardStatusLabel: NSTextField!
    private var grantAccessibilityButton: NSButton!

    init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
    }

    func update(preferences: Preferences) {
        self.preferences = preferences
        if window != nil { populate() }
    }

    // MARK: - Presentation

    func show() {
        if window == nil { build() }
        populate()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
                         styleMask: [.titled, .closable],
                         backing: .buffered,
                         defer: false)
        w.title = "MacToys Settings"
        w.isReleasedWhenClosed = false
        w.delegate = self

        let tabs = NSTabView(frame: NSRect(x: 0, y: 0, width: 520, height: 470))
        tabs.autoresizingMask = [.width, .height]
        tabs.addTabViewItem(tab("General", generalPane()))
        tabs.addTabViewItem(tab("Clipboard", clipboardPane()))
        tabs.addTabViewItem(tab("Windows", windowsPane()))
        tabs.addTabViewItem(tab("Trackpad", trackpadPane()))
        tabs.addTabViewItem(tab("Keyboard", keyboardPane()))
        tabs.addTabViewItem(tab("Shortcuts", shortcutsPane()))

        w.contentView = tabs
        window = w
    }

    private func tab(_ title: String, _ view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = view
        return item
    }

    // MARK: - Building blocks

    private func pane(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 20, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
        ])
        return container
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 460
        return label
    }

    private func checkbox(_ key: String, _ title: String) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(controlChanged))
        button.font = .systemFont(ofSize: 12)
        checkboxes[key] = button
        return button
    }

    private func row(_ label: String, _ control: NSView, width: CGFloat = 190) -> NSView {
        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 12)
        text.translatesAutoresizingMaskIntoConstraints = false
        text.widthAnchor.constraint(equalToConstant: width).isActive = true

        let stack = NSStackView(views: [text, control])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        return stack
    }

    // MARK: - Panes

    private func generalPane() -> NSView {
        pane([
            heading("Features"),
            checkbox("clipboardHistoryEnabled", "Clipboard history"),
            checkbox("snipEnabled", "Snip to clipboard"),
            checkbox("windowSnapEnabled", "Window snapping"),
            checkbox("textExtractorEnabled", "Text extractor (OCR)"),
            checkbox("colorPickerEnabled", "Colour picker"),
            checkbox("keyRemapEnabled", "Windows key behaviour"),
            note("Window snapping and Windows key behaviour need Accessibility permission. Everything else works without granting anything."),
            heading("Startup"),
            checkbox("launchAtLogin", "Launch MacToys at login"),
        ])
    }

    private func clipboardPane() -> NSView {
        capacityField = NSTextField(labelWithString: "100")
        capacityField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        capacityField.translatesAutoresizingMaskIntoConstraints = false
        capacityField.widthAnchor.constraint(equalToConstant: 44).isActive = true

        capacityStepper = NSStepper()
        capacityStepper.minValue = 5
        capacityStepper.maxValue = 1000
        capacityStepper.increment = 5
        capacityStepper.target = self
        capacityStepper.action = #selector(controlChanged)

        let capacityRow = NSStackView(views: [capacityField, capacityStepper])
        capacityRow.orientation = .horizontal
        capacityRow.spacing = 6

        return pane([
            heading("History"),
            row("Items to keep", capacityRow),
            checkbox("persistClipboardHistory", "Remember history after quitting"),
            checkbox("autoPasteOnPick", "Paste immediately when an item is chosen"),
            note("Automatic pasting needs Accessibility. Without it, choosing an item still copies it — press ⌘V yourself."),
            heading("Privacy"),
            note("Pasteboards marked as concealed are never recorded, and copies made in 1Password, Bitwarden, Dashlane, Enpass, LastPass, Keychain Access and Apple Passwords are ignored.\n\nHistory is stored unencrypted at ~/Library/Application Support/MacToys/. Turn off “Remember history” above to keep it in memory only."),
        ])
    }

    private func windowsPane() -> NSView {
        gapSlider = NSSlider(value: 0, minValue: 0, maxValue: 40, target: self, action: #selector(controlChanged))
        gapSlider.translatesAutoresizingMaskIntoConstraints = false
        gapSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true

        gapLabel = NSTextField(labelWithString: "0 px")
        gapLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        gapLabel.textColor = .secondaryLabelColor

        let gapRow = NSStackView(views: [gapSlider, gapLabel])
        gapRow.orientation = .horizontal
        gapRow.spacing = 8

        colorFormatPopup = NSPopUpButton()
        colorFormatPopup.target = self
        colorFormatPopup.action = #selector(controlChanged)
        for format in ColorFormat.allCases { colorFormatPopup.addItem(withTitle: format.title) }

        return pane([
            heading("Snapping"),
            row("Gap between windows", gapRow),
            checkbox("snapCyclingEnabled", "Pressing the same direction cycles ½ → ⅓ → ⅔"),
            note("⌃⌥ with the arrow keys snaps; ⌃⌥1–4 snap to a corner; ⌃⌥⇧← and ⌃⌥⇧→ move a window between displays."),
            heading("Colour picker"),
            row("Copy colours as", colorFormatPopup),
            heading("Text extractor"),
            checkbox("ocrJoinLines", "Join wrapped lines into paragraphs"),
        ])
    }

    private func trackpadPane() -> NSView {
        fingersPopup = NSPopUpButton()
        fingersPopup.target = self
        fingersPopup.action = #selector(controlChanged)
        fingersPopup.addItem(withTitle: "Three fingers")
        fingersPopup.addItem(withTitle: "Four fingers (matches Windows)")

        let master = checkbox("volumeGestureEnabled", "Swipe up and down to change the volume")
        master.font = .systemFont(ofSize: 13, weight: .semibold)

        return pane([
            heading("Volume gesture"),
            master,
            row("Fingers", fingersPopup, width: 110),
            note("Windows 11 offers this under Touchpad › Four-finger gestures › “Change audio and volume”. macOS has no equivalent."),
            heading("Before it will work"),
            note("macOS already uses four-finger swipes for Mission Control and App Exposé. MacToys can watch the trackpad, but it cannot take those gestures away from the system — so with four fingers selected, swiping will change the volume *and* trigger Mission Control at the same time.\n\nOpen System Settings › Trackpad › More Gestures and set Mission Control and App Exposé to three fingers or Off, or choose three fingers above instead."),
            note("Volume is changed through CoreAudio, so this needs no permission at all. Reading the trackpad uses a private Apple framework — the same one BetterTouchTool relies on — so a future macOS could remove it. If that happens MacToys switches this off and tells you, rather than failing quietly."),
        ])
    }

    private func keyboardPane() -> NSView {
        // The master switch lives here, next to the options it governs. It used
        // to sit alone on the General tab, so these three could be ticked on
        // while the whole feature was switched off — they looked active and did
        // nothing, with no way to tell why.
        let master = checkbox("keyRemapEnabled", "Enable Windows key behaviour")
        master.font = .systemFont(ofSize: 13, weight: .semibold)

        keyboardStatusLabel = NSTextField(wrappingLabelWithString: "")
        keyboardStatusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        keyboardStatusLabel.preferredMaxLayoutWidth = 440

        grantAccessibilityButton = NSButton(title: "Grant Accessibility Permission…",
                                            target: self,
                                            action: #selector(openAccessibility))
        grantAccessibilityButton.bezelStyle = .rounded
        grantAccessibilityButton.controlSize = .small

        return pane([
            heading("Windows key behaviour"),
            master,
            keyboardStatusLabel,
            grantAccessibilityButton,
            heading("What it changes"),
            checkbox("windowsHomeEnd", "Home and End jump to the start/end of the line"),
            checkbox("finderCutPaste", "⌘X then ⌘V moves files in Finder"),
            checkbox("finderForwardDelete", "⌦ moves the selected file to the Trash"),
            note("These rewrite keystrokes as they pass through the system, which macOS gates behind Accessibility permission. Terminals and code editors are left alone — they already handle Home and End the way you expect."),
            note("Finder's cut-and-paste never moves files itself. ⌘X becomes an ordinary copy, and the following ⌘V becomes Finder's own “Move Item Here”, so conflict handling and undo behave normally."),
        ])
    }

    @objc private func openAccessibility() {
        Permissions.requestAccessibility()
        Permissions.openAccessibilitySettings()
    }

    /// Keeps the Keyboard tab honest about whether the feature is actually
    /// doing anything: switched off, blocked on permission, or genuinely live.
    private func refreshKeyboardStatus() {
        guard let label = keyboardStatusLabel else { return }

        let enabled = checkboxes["keyRemapEnabled"]?.state == .on
        let granted = Permissions.accessibilityGranted

        // Sub-options are meaningless while the feature is off, so they are
        // greyed out rather than left looking active.
        for key in ["windowsHomeEnd", "finderCutPaste", "finderForwardDelete"] {
            checkboxes[key]?.isEnabled = enabled
        }

        if !enabled {
            label.stringValue = "Off — nothing below is active."
            label.textColor = .secondaryLabelColor
            grantAccessibilityButton?.isHidden = granted
        } else if !granted {
            label.stringValue = "Needs Accessibility permission before it can do anything."
            label.textColor = .systemOrange
            grantAccessibilityButton?.isHidden = false
        } else {
            label.stringValue = "Active."
            label.textColor = .systemGreen
            grantAccessibilityButton?.isHidden = true
        }
    }

    private func shortcutsPane() -> NSView {
        let labels: [(String, String)] = [
            ("clipboardHistory", "Clipboard history"),
            ("snipToClipboard",  "Snip to clipboard"),
            ("pasteAsPlainText", "Paste as plain text"),
            ("textExtract",      "Extract text (OCR)"),
            ("colorPicker",      "Pick a colour"),
            ("snapLeft",         "Snap left"),
            ("snapRight",        "Snap right"),
            ("snapUp",           "Maximize"),
            ("snapDown",         "Centre"),
            ("displayNext",      "Next display"),
        ]

        var views: [NSView] = [heading("Shortcuts")]
        for (key, title) in labels {
            let recorder = ShortcutRecorderView()
            recorder.translatesAutoresizingMaskIntoConstraints = false
            recorder.widthAnchor.constraint(equalToConstant: 170).isActive = true
            recorder.heightAnchor.constraint(equalToConstant: 24).isActive = true
            recorder.onChange = { [weak self] spec in
                guard let self = self else { return }
                if let spec = spec {
                    self.preferences.shortcuts[key] = SettingsWindowController.serialise(spec)
                } else {
                    self.preferences.shortcuts[key] = ""
                }
                self.commit()
            }
            recorders[key] = recorder
            views.append(row(title, recorder, width: 170))
        }
        views.append(note("Click a shortcut and press the combination you want. Esc cancels, ⌫ clears. A shortcut another app has already claimed will not register — MacToys tells you at launch when that happens."))
        return pane(views)
    }

    /// Turns a captured shortcut back into the text form stored in the config.
    static func serialise(_ spec: HotKeySpec) -> String {
        var parts: [String] = []
        if spec.mods.contains(.control) { parts.append("ctrl") }
        if spec.mods.contains(.option)  { parts.append("alt") }
        if spec.mods.contains(.shift)   { parts.append("shift") }
        if spec.mods.contains(.command) { parts.append("cmd") }

        if let name = KeyCode.named.first(where: { $0.value == spec.keyCode })?.key {
            parts.append(name)
        } else if let letter = KeyCode.letters.first(where: { $0.value == spec.keyCode })?.key {
            parts.append(letter)
        } else if let digit = KeyCode.digits.first(where: { $0.value == spec.keyCode })?.key {
            parts.append(digit)
        } else {
            return ""   // an unmappable key cannot be stored as text
        }
        return parts.joined(separator: "+")
    }

    // MARK: - Binding

    private func populate() {
        populating = true
        defer { populating = false }

        let p = preferences
        let values: [String: Bool] = [
            "clipboardHistoryEnabled": p.clipboardHistoryEnabled,
            "snipEnabled": p.snipEnabled,
            "windowSnapEnabled": p.windowSnapEnabled,
            "textExtractorEnabled": p.textExtractorEnabled,
            "colorPickerEnabled": p.colorPickerEnabled,
            "keyRemapEnabled": p.keyRemapEnabled,
            "launchAtLogin": p.launchAtLogin,
            "persistClipboardHistory": p.persistClipboardHistory,
            "autoPasteOnPick": p.autoPasteOnPick,
            "snapCyclingEnabled": p.snapCyclingEnabled,
            "ocrJoinLines": p.ocrJoinLines,
            "windowsHomeEnd": p.remap.windowsHomeEnd,
            "finderCutPaste": p.remap.finderCutPaste,
            "finderForwardDelete": p.remap.finderForwardDelete,
        ]
        for (key, value) in values { checkboxes[key]?.state = value ? .on : .off }

        capacityStepper?.integerValue = p.clipboardCapacity
        capacityField?.stringValue = String(p.clipboardCapacity)
        gapSlider?.doubleValue = p.snapGap
        gapLabel?.stringValue = "\(Int(p.snapGap)) px"
        if let index = ColorFormat.allCases.firstIndex(of: p.colorFormat) {
            colorFormatPopup?.selectItem(at: index)
        }
        fingersPopup?.selectItem(at: p.volumeGestureFingers == 3 ? 0 : 1)
        for (key, recorder) in recorders { recorder.spec = p.spec(key) }
        refreshKeyboardStatus()
    }

    @objc private func controlChanged() {
        guard !populating else { return }

        var p = preferences
        func on(_ key: String) -> Bool { checkboxes[key]?.state == .on }

        p.clipboardHistoryEnabled = on("clipboardHistoryEnabled")
        p.snipEnabled             = on("snipEnabled")
        p.windowSnapEnabled       = on("windowSnapEnabled")
        p.textExtractorEnabled    = on("textExtractorEnabled")
        p.colorPickerEnabled      = on("colorPickerEnabled")
        p.keyRemapEnabled         = on("keyRemapEnabled")
        p.launchAtLogin           = on("launchAtLogin")
        p.persistClipboardHistory = on("persistClipboardHistory")
        p.autoPasteOnPick         = on("autoPasteOnPick")
        p.snapCyclingEnabled      = on("snapCyclingEnabled")
        p.ocrJoinLines            = on("ocrJoinLines")
        p.volumeGestureEnabled    = on("volumeGestureEnabled")
        if let popup = fingersPopup { p.volumeGestureFingers = popup.indexOfSelectedItem == 0 ? 3 : 4 }
        p.remap.windowsHomeEnd      = on("windowsHomeEnd")
        p.remap.finderCutPaste      = on("finderCutPaste")
        p.remap.finderForwardDelete = on("finderForwardDelete")

        if let stepper = capacityStepper { p.clipboardCapacity = stepper.integerValue }
        if let slider = gapSlider { p.snapGap = slider.doubleValue.rounded() }
        if let popup = colorFormatPopup {
            let index = popup.indexOfSelectedItem
            if index >= 0 && index < ColorFormat.allCases.count {
                p.colorFormat = ColorFormat.allCases[index]
            }
        }

        preferences = p.normalised()
        refreshKeyboardStatus()
        capacityField?.stringValue = String(preferences.clipboardCapacity)
        gapLabel?.stringValue = "\(Int(preferences.snapGap)) px"
        commit()
    }

    private func commit() {
        onChange?(preferences)
    }
}
