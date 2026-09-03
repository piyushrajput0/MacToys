import Foundation

/// Decides whether an observed pasteboard change is worth recording.
///
/// macOS offers no "pasteboard changed" notification and no way to ask who wrote
/// to it, so a clipboard manager has to poll `changeCount` and work out for
/// itself which changes are its own. Getting that bookkeeping wrong is subtle and
/// user-visible — an earlier version of this app set a "skip the next change"
/// flag *and* fast-forwarded its own counter, so the flag was never consumed and
/// silently swallowed the next thing the user copied. Keeping the state machine
/// here, separate from AppKit, means it can be tested directly.
public struct PasteboardGate: Equatable {

    public enum Decision: Equatable {
        /// Nothing happened since the last look.
        case unchanged
        /// A genuine copy by some other app: record it.
        case record
        /// The change this app just made by pasting from history: ignore it.
        case skipOwnWrite
    }

    private var lastSeen: Int
    /// The `changeCount` we expect to see from our own write, if it has not
    /// come back around yet.
    private var pendingOwnWrite: Int?

    public init(changeCount: Int) {
        self.lastSeen = changeCount
    }

    /// Records that this app just wrote to the pasteboard, producing
    /// `resultingChangeCount`.
    ///
    /// Deliberately does *not* move `lastSeen` forward. The next `observe` must
    /// still see the change so it can consume the marker; skipping it is exactly
    /// the bug described above.
    public mutating func noteOwnWrite(resultingChangeCount: Int) {
        pendingOwnWrite = resultingChangeCount
    }

    public mutating func observe(_ changeCount: Int) -> Decision {
        guard changeCount != lastSeen else { return .unchanged }
        lastSeen = changeCount

        if let own = pendingOwnWrite {
            // Always clear the marker, whether or not it matched. If another app
            // wrote first, our expected count will never arrive and a stale
            // marker would suppress an unrelated copy later on.
            pendingOwnWrite = nil
            if own == changeCount { return .skipOwnWrite }
        }
        return .record
    }

    /// Exposed for tests and diagnostics.
    public var hasPendingOwnWrite: Bool { pendingOwnWrite != nil }
    public var lastObserved: Int { lastSeen }
}
