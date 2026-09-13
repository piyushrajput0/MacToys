import AppKit

/// Region screenshots that land on the clipboard — and, optionally, on disk.
///
/// On Windows, Win+Shift+S puts the capture straight on the clipboard and you
/// paste it wherever you were going. macOS's ⌘⇧4 instead drops a PNG on the
/// Desktop, and the clipboard variant is the four-finger ⌃⌘⇧4 that almost
/// nobody discovers. This gives you both at once: paste it immediately, and
/// still find the file later where every other screenshot lives.
enum SnipService {

    private static let tool = "/usr/sbin/screencapture"

    enum Mode {
        case region        // drag a rectangle
        case window        // click a window
        case fullScreen

        /// Flags other than the destination. `-c` is deliberately absent:
        /// `screencapture` treats it as "clipboard *instead of* a file" and
        /// writes nothing to disk, so the capture goes to a file and this app
        /// puts it on the clipboard itself.
        var arguments: [String] {
            switch self {
            // -o omits the window shadow, which otherwise pads the image with
            // a large transparent border that looks wrong when pasted.
            case .region:     return ["-i"]
            case .window:     return ["-i", "-w", "-o"]
            case .fullScreen: return ["-x"]
            }
        }
    }

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: tool)
    }

    /// Where macOS itself puts screenshots. Respects a custom location set with
    /// `defaults write com.apple.screencapture location`, so captures land
    /// wherever the user already expects to find them rather than somewhere
    /// this app picked.
    static var systemScreenshotDirectory: URL {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        if let path = defaults?.string(forKey: "location"), !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: expanded)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
    }

    /// Matches macOS's own naming, e.g. "Screenshot 2026-09-13 at 10.23.45 PM.png",
    /// including a custom prefix set via `com.apple.screencapture name`.
    static func screenshotURL(now: Date = Date()) -> URL {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        let prefix = defaults?.string(forKey: "name").flatMap { $0.isEmpty ? nil : $0 } ?? "Screenshot"

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let stamp = formatter.string(from: now)

        let directory = systemScreenshotDirectory
        var candidate = directory.appendingPathComponent("\(prefix) \(stamp).png")
        // Two captures inside the same second must not overwrite each other.
        var attempt = 2
        while FileManager.default.fileExists(atPath: candidate.path) && attempt < 100 {
            candidate = directory.appendingPathComponent("\(prefix) \(stamp) (\(attempt)).png")
            attempt += 1
        }
        return candidate
    }

    struct Result {
        /// True when the user actually captured something.
        let captured: Bool
        /// Where it was saved, when saving was asked for and succeeded.
        let savedTo: URL?
    }

    /// Takes a capture, puts it on the clipboard, and optionally leaves the file
    /// alongside the user's other screenshots.
    ///
    /// `completion` always runs on the main queue.
    static func capture(_ mode: Mode,
                        saveToDisk: Bool = true,
                        completion: ((Result) -> Void)? = nil) {
        guard isAvailable else {
            NSLog("[MacToys] screencapture not found at \(tool)")
            completion?(Result(captured: false, savedTo: nil))
            return
        }

        // When the file is not being kept, capture into a temporary directory
        // and delete it afterwards, so the only lasting effect is the clipboard.
        let keeping = saveToDisk
        let destination = keeping
            ? screenshotURL()
            : URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("mactoys-snip-\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = mode.arguments + [destination.path]

        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                defer { if !keeping { try? FileManager.default.removeItem(at: destination) } }

                // Escape leaves no file behind, which is the reliable signal —
                // the exit status is non-zero both for a cancel and for a
                // permission failure.
                guard FileManager.default.fileExists(atPath: destination.path),
                      let data = try? Data(contentsOf: destination),
                      !data.isEmpty else {
                    completion?(Result(captured: false, savedTo: nil))
                    return
                }

                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(data, forType: .png)

                completion?(Result(captured: true, savedTo: keeping ? destination : nil))
            }
        }

        do {
            try process.run()
        } catch {
            NSLog("[MacToys] snip failed: \(error)")
            if !keeping { try? FileManager.default.removeItem(at: destination) }
            completion?(Result(captured: false, savedTo: nil))
        }
    }
}
