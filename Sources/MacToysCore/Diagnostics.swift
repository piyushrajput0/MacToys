import Foundation

/// A single line in the health report.
public struct DiagnosticItem: Codable, Equatable {

    public enum State: String, Codable {
        /// Working.
        case ok
        /// Deliberately switched off — not a fault.
        case off
        /// Switched on but cannot work until something is done.
        case blocked
        /// Switched on, should work, but something is wrong.
        case broken
    }

    public let feature: String
    public let state: State
    public let detail: String
    /// What the user has to do, when there is something to do.
    public let fix: String?

    public init(feature: String, state: State, detail: String, fix: String? = nil) {
        self.feature = feature
        self.state = state
        self.detail = detail
        self.fix = fix
    }

    public var symbol: String {
        switch state {
        case .ok:      return "✅"
        case .off:     return "⚪️"
        case .blocked: return "⚠️"
        case .broken:  return "❌"
        }
    }
}

/// Whole-app health report.
///
/// Exists because finding out a feature is dead by trying it, one at a time, is
/// a miserable way to use software — especially for this app, where several
/// features depend on permissions that macOS silently invalidates whenever the
/// app is rebuilt. Everything that can be checked is checked in one place, and
/// the answer says what to do about it.
public struct DiagnosticsReport: Codable, Equatable {
    public let generatedAt: Date
    public let items: [DiagnosticItem]

    public init(generatedAt: Date, items: [DiagnosticItem]) {
        self.generatedAt = generatedAt
        self.items = items
    }

    public var problems: [DiagnosticItem] {
        items.filter { $0.state == .blocked || $0.state == .broken }
    }

    public var isHealthy: Bool { problems.isEmpty }

    /// One-line summary for the menu bar.
    public var summary: String {
        let broken = items.filter { $0.state == .broken }.count
        let blocked = items.filter { $0.state == .blocked }.count
        if broken == 0 && blocked == 0 { return "Everything is working" }
        var parts: [String] = []
        if broken > 0 { parts.append("\(broken) broken") }
        if blocked > 0 { parts.append("\(blocked) need attention") }
        return parts.joined(separator: ", ")
    }

    public func plainText() -> String {
        var lines = ["MacToys diagnostics", ""]
        for item in items {
            lines.append("\(item.symbol)  \(item.feature) — \(item.detail)")
            if let fix = item.fix { lines.append("     → \(fix)") }
        }
        return lines.joined(separator: "\n")
    }
}
