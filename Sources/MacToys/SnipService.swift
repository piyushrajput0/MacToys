import AppKit

/// Region screenshots that land on the clipboard.
///
/// On Windows, Win+Shift+S puts the capture straight on the clipboard and you
/// paste it wherever you were going. macOS's ⌘⇧4 instead drops a PNG on the
/// Desktop, and the clipboard variant is the four-finger ⌃⌘⇧4 that almost
/// nobody discovers. This restores the Windows behaviour under a memorable key.
enum SnipService {

    private static let tool = "/usr/sbin/screencapture"

    enum Mode {
        case region        // drag a rectangle
        case window        // click a window
        case fullScreen

        var arguments: [String] {
            switch self {
            // -c copy to clipboard, -i interactive, -w window mode.
            // -o omits the window shadow, which otherwise pads the image with
            // a large transparent border that looks wrong when pasted.
            case .region:     return ["-c", "-i"]
            case .window:     return ["-c", "-i", "-w", "-o"]
            case .fullScreen: return ["-c"]
            }
        }
    }

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: tool)
    }

    /// Runs the capture. `completion` receives true when the user actually took
    /// a shot, false when they pressed Escape (screencapture exits non-zero).
    static func capture(_ mode: Mode, completion: ((Bool) -> Void)? = nil) {
        guard isAvailable else {
            NSLog("[MacToys] screencapture not found at \(tool)")
            completion?(false)
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = mode.arguments
        process.terminationHandler = { proc in
            DispatchQueue.main.async { completion?(proc.terminationStatus == 0) }
        }
        do {
            try process.run()
        } catch {
            NSLog("[MacToys] snip failed: \(error)")
            completion?(false)
        }
    }
}
