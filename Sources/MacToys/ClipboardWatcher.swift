import AppKit
import MacToysCore

/// Notices when the clipboard changes and turns each change into a `ClipItem`.
///
/// macOS has no "pasteboard changed" notification, so polling `changeCount` is
/// the only option available to a normal app. `changeCount` is a cheap integer
/// read, and the default 0.4 s interval keeps latency imperceptible while the
/// cost stays in the noise.
final class ClipboardWatcher: NSObject {

    private var timer: Timer?
    private var lastChangeCount: Int
    private let pasteboard: NSPasteboard

    /// Set while the app writes to the pasteboard itself, so pasting from the
    /// history does not re-record the item and shuffle it to the top.
    private var ignoreNextChange = false

    var onNewItem: ((ClipItem) -> Void)?
    /// Fired for any change, including ones that were not recorded.
    var onAnyChange: (() -> Void)?

    var excludedApps: Set<String> = ClipboardPrivacy.defaultExcludedApps

    /// macOS does not record which app wrote to the pasteboard, so the source is
    /// inferred from what is frontmost. When one of our own windows has focus —
    /// the picker or the cheat sheet — that inference names MacToys, which is
    /// never the real answer. Remembering the last app that was not us keeps the
    /// attribution useful.
    private let ownBundleID = Bundle.main.bundleIdentifier
    private var lastExternalApp: String?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        super.init()
        trackFrontmostApp()
    }

    private func trackFrontmostApp() {
        let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if current != ownBundleID { lastExternalApp = current }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let id = app?.bundleIdentifier, id != self.ownBundleID {
                self.lastExternalApp = id
            }
        }
    }

    /// Best-effort guess at which app the copy came from.
    private var attributedSourceApp: String? {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let frontmost = frontmost, frontmost != ownBundleID { return frontmost }
        return lastExternalApp
    }

    func start(interval: TimeInterval) {
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        // Common modes keeps polling alive while a menu is open or a window is
        // being dragged, which is exactly when people copy things.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call immediately before writing to the pasteboard from within the app.
    func suppressNextChange() {
        ignoreNextChange = true
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        onAnyChange?()

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        guard let item = readCurrentItem() else { return }
        onNewItem?(item)
    }

    private func readCurrentItem() -> ClipItem? {
        let types = (pasteboard.types ?? []).map { $0.rawValue }
        let sourceApp = attributedSourceApp

        guard ClipboardPrivacy.shouldRecord(types: types,
                                            sourceBundleID: sourceApp,
                                            excludedApps: excludedApps) else { return nil }

        // Files are checked before text: copying a file in Finder also puts its
        // path on the pasteboard as a string, and the file entry is the useful one.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty, urls.allSatisfy({ $0.isFileURL }) {
            return ClipItem(kind: .files, filePaths: urls.map { $0.path }, sourceApp: sourceApp)
        }

        if let string = pasteboard.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ClipItem(kind: .text, text: string, sourceApp: sourceApp)
        }

        // Prefer PNG: TIFF from a screenshot can be tens of megabytes.
        if let png = pasteboard.data(forType: .png) {
            return ClipItem(kind: .image, imageData: png, sourceApp: sourceApp)
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return ClipItem(kind: .image, imageData: png, sourceApp: sourceApp)
        }

        return nil
    }

    /// Puts an item back on the clipboard.
    func write(_ item: ClipItem) {
        suppressNextChange()
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            if let text = item.text { pasteboard.setString(text, forType: .string) }
        case .image:
            if let data = item.imageData { pasteboard.setData(data, forType: .png) }
        case .files:
            let urls = item.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
            if !urls.isEmpty { pasteboard.writeObjects(urls) }
        }
        lastChangeCount = pasteboard.changeCount
    }
}
