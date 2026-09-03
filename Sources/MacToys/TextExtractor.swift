import AppKit
import Vision
import MacToysCore

/// Pulls selectable text out of anything on screen — PowerToys' Text Extractor.
///
/// This is the feature that has no macOS equivalent at all: Live Text works
/// inside Photos and Preview, but there is no way to drag a box around a chunk
/// of a video call, an error dialog or a screenshot someone pasted into Slack
/// and just get the text. Vision does the recognition entirely on-device.
enum TextExtractor {

    enum Failure: Error, LocalizedError {
        case cancelled
        case captureFailed
        case unreadableImage
        case noTextFound
        case vision(Error)

        var errorDescription: String? {
            switch self {
            case .cancelled:       return nil
            case .captureFailed:   return "Screen capture failed"
            case .unreadableImage: return "Could not read the capture"
            case .noTextFound:     return "No text found in that area"
            case .vision(let e):   return "Recognition failed: \(e.localizedDescription)"
            }
        }
    }

    /// Captures a region, recognises text in it, and hands back the result.
    /// Always called back on the main queue.
    static func extract(languages: [String],
                        joinLines: Bool,
                        completion: @escaping (Result<String, Failure>) -> Void) {

        let target = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mactoys-ocr-\(UUID().uuidString).png")

        // Capture to a file rather than the clipboard: OCR should not clobber
        // whatever the user already had copied if it then finds nothing.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", target.path]

        process.terminationHandler = { proc in
            defer { try? FileManager.default.removeItem(at: target) }

            guard proc.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: target.path) else {
                // A non-zero exit is almost always the user pressing Escape.
                DispatchQueue.main.async { completion(.failure(.cancelled)) }
                return
            }

            let result = recognise(imageAt: target, languages: languages, joinLines: joinLines)
            DispatchQueue.main.async { completion(result) }
        }

        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: target)
            completion(.failure(.captureFailed))
        }
    }

    private static func recognise(imageAt url: URL,
                                  languages: [String],
                                  joinLines: Bool) -> Result<String, Failure> {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .failure(.unreadableImage)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if !languages.isEmpty { request.recognitionLanguages = languages }

        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            return .failure(.vision(error))
        }

        guard let observations = request.results, !observations.isEmpty else {
            return .failure(.noTextFound)
        }

        // Vision returns observations in reading order already, but each is a
        // separate visual line. Sorting top-to-bottom guards against the odd
        // out-of-order result on multi-column captures.
        let lines = observations
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard !lines.isEmpty else { return .failure(.noTextFound) }
        return .success(TextExtractor.assemble(lines, joinLines: joinLines))
    }

    /// Joins recognised lines. The rules live in `MacToysCore` so they can be
    /// tested without running recognition.
    static func assemble(_ lines: [String], joinLines: Bool) -> String {
        OCRTextAssembler.assemble(lines, joinLines: joinLines)
    }
}
