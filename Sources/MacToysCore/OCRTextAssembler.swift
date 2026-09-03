import Foundation

/// Turns the per-line output of text recognition back into usable text.
///
/// Vision reports one observation per *visual* line, so pasting the raw result
/// gives text broken at whatever width the original happened to be. Rejoining is
/// the useful default for prose but wrong for code, tables and lists, so it is
/// opt-in and tries to preserve the breaks that carry meaning.
public enum OCRTextAssembler {

    public static func assemble(_ lines: [String], joinLines: Bool) -> String {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard joinLines else { return cleaned.joined(separator: "\n") }

        var out: [String] = []
        for line in cleaned {
            guard let previous = out.last else { out.append(line); continue }

            // A line that completes a sentence, or one that starts a new list
            // item, is a real break rather than a wrap.
            let endsParagraph = [".", "!", "?", ":", ";"].contains { previous.hasSuffix($0) }
            let startsListItem = ["-", "•", "*", "–", "‣"].contains { line.hasPrefix($0) }
                || isNumberedItem(line)

            if endsParagraph || startsListItem {
                out.append(line)
            } else if previous.hasSuffix("-") && !previous.hasSuffix(" -") {
                // A trailing hyphen at a wrap is a split word, not punctuation.
                out[out.count - 1] = String(previous.dropLast()) + line
            } else {
                out[out.count - 1] = previous + " " + line
            }
        }
        return out.joined(separator: "\n")
    }

    /// Matches "1.", "2)", "10." and similar list markers.
    public static func isNumberedItem(_ line: String) -> Bool {
        var digits = 0
        for ch in line {
            if ch.isNumber { digits += 1; continue }
            return digits > 0 && (ch == "." || ch == ")")
        }
        return false
    }
}
