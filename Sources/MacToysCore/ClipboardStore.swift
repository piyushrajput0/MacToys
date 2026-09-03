import Foundation

public enum ClipKind: String, Codable {
    case text
    case image
    case files
}

public struct ClipItem: Codable, Identifiable, Equatable {
    public var id: UUID
    public var kind: ClipKind
    public var text: String?
    public var imageData: Data?
    public var filePaths: [String]
    public var createdAt: Date
    public var pinned: Bool
    public var sourceApp: String?

    public init(id: UUID = UUID(),
                kind: ClipKind,
                text: String? = nil,
                imageData: Data? = nil,
                filePaths: [String] = [],
                createdAt: Date = Date(),
                pinned: Bool = false,
                sourceApp: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageData = imageData
        self.filePaths = filePaths
        self.createdAt = createdAt
        self.pinned = pinned
        self.sourceApp = sourceApp
    }

    public static func text(_ s: String, sourceApp: String? = nil, createdAt: Date = Date()) -> ClipItem {
        ClipItem(kind: .text, text: s, createdAt: createdAt, sourceApp: sourceApp)
    }

    /// Content-identity used for de-duplication. Two copies of the same string are
    /// the same entry no matter when or where they were copied.
    public var contentKey: String {
        switch kind {
        case .text:  return "t:" + (text ?? "")
        case .image: return "i:\(imageData?.count ?? 0):" + (imageData?.prefix(64).map { String(format: "%02x", $0) }.joined() ?? "")
        case .files: return "f:" + filePaths.joined(separator: "\u{1}")
        }
    }

    /// Single-line summary for the picker list.
    public var preview: String {
        switch kind {
        case .text:
            let collapsed = (text ?? "")
                .replacingOccurrences(of: "\n", with: " ⏎ ")
                .replacingOccurrences(of: "\t", with: "  ")
                .trimmingCharacters(in: .whitespaces)
            return collapsed.count > 120 ? String(collapsed.prefix(120)) + "…" : collapsed
        case .image:
            let kb = (imageData?.count ?? 0) / 1024
            return "🖼 Image (\(kb) KB)"
        case .files:
            if filePaths.count == 1 { return "📄 " + ((filePaths[0] as NSString).lastPathComponent) }
            return "📄 \(filePaths.count) files"
        }
    }

    /// Text used when matching a search query.
    public var searchableText: String {
        switch kind {
        case .text:  return text ?? ""
        case .image: return "image"
        case .files: return filePaths.map { ($0 as NSString).lastPathComponent }.joined(separator: " ")
        }
    }
}

/// Ordered, de-duplicated, size-bounded clipboard history.
///
/// Ordering is: pinned items first (most recently pinned first), then unpinned by
/// recency. Eviction only ever removes unpinned items, so a pinned snippet
/// survives indefinitely.
public final class ClipboardStore {
    public private(set) var items: [ClipItem] = []
    public private(set) var capacity: Int

    public init(capacity: Int = 100) {
        self.capacity = max(1, capacity)
    }

    /// Resizing takes effect immediately: shrinking evicts down to the new limit
    /// rather than waiting for the next copy, so the setting visibly does what
    /// it says.
    public func setCapacity(_ newValue: Int) {
        capacity = min(max(newValue, 1), 10_000)
        evict()
    }

    @discardableResult
    public func insert(_ item: ClipItem) -> Bool {
        // Re-copying something already in history promotes it instead of
        // creating a duplicate, and must not clobber its pinned state.
        if let existing = items.firstIndex(where: { $0.contentKey == item.contentKey }) {
            var moved = items.remove(at: existing)
            moved.createdAt = item.createdAt
            items.insert(moved, at: 0)
            sort()
            return false
        }
        items.insert(item, at: 0)
        sort()
        evict()
        return true
    }

    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    public func clearUnpinned() {
        items.removeAll { !$0.pinned }
    }

    public func clearAll() {
        items.removeAll()
    }

    @discardableResult
    public func togglePin(id: UUID) -> Bool {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return false }
        items[i].pinned.toggle()
        sort()
        evict()
        return items[i].pinned
    }

    private func sort() {
        items.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.createdAt > b.createdAt
        }
    }

    private func evict() {
        guard items.count > capacity else { return }
        // Drop the oldest unpinned entries until we are back within capacity.
        // If everything is pinned the history is allowed to exceed capacity
        // rather than silently discarding something the user asked to keep.
        var overflow = items.count - capacity
        var index = items.count - 1
        while overflow > 0 && index >= 0 {
            if !items[index].pinned {
                items.remove(at: index)
                overflow -= 1
            }
            index -= 1
        }
    }

    // MARK: - Search

    /// Filters history by `query`. An empty query returns everything in order.
    /// Matching is case-insensitive; a contiguous substring outranks a scattered
    /// subsequence, and an earlier match outranks a later one, so typing "rep"
    /// surfaces "report.pdf" above "the receipt is prepaid".
    public func search(_ query: String) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }

        var scored: [(ClipItem, Int, Int)] = []
        for (position, item) in items.enumerated() {
            if let score = ClipboardStore.matchScore(query: q, in: item.searchableText.lowercased()) {
                scored.append((item, score, position))
            }
        }
        // Higher score first; ties broken by original (recency/pin) ordering.
        scored.sort { a, b in a.1 != b.1 ? a.1 > b.1 : a.2 < b.2 }
        return scored.map { $0.0 }
    }

    /// Returns nil when `query` does not match, otherwise a score where higher is
    /// better. Both arguments must already be lowercased.
    public static func matchScore(query: String, in haystack: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        guard !haystack.isEmpty else { return nil }

        if let r = haystack.range(of: query) {
            let offset = haystack.distance(from: haystack.startIndex, to: r.lowerBound)
            // Contiguous hits get a large base so they always beat subsequences.
            var score = 1000 - min(offset, 500)
            if offset == 0 { score += 200 }
            return score
        }

        // Fall back to subsequence matching so "cfg" finds "config".
        var qi = query.startIndex
        var gaps = 0
        var lastHit = -1
        var index = 0
        for ch in haystack {
            if ch == query[qi] {
                if lastHit >= 0 { gaps += index - lastHit - 1 }
                lastHit = index
                qi = query.index(after: qi)
                if qi == query.endIndex { return max(1, 400 - gaps) }
            }
            index += 1
        }
        return nil
    }

    // MARK: - Persistence

    /// Items are written newest-first. Images are capped so a few screenshots
    /// cannot grow the history file without bound.
    public func encode(maxImageBytes: Int = 2_000_000) throws -> Data {
        let trimmed: [ClipItem] = items.map { item in
            guard item.kind == .image, let d = item.imageData, d.count > maxImageBytes else { return item }
            var copy = item
            copy.imageData = nil
            return copy
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(trimmed)
    }

    public func load(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([ClipItem].self, from: data)
        // An image entry whose data was dropped at save time is not restorable.
        items = decoded.filter { !($0.kind == .image && $0.imageData == nil) }
        sort()
        evict()
    }
}

// MARK: - Privacy

public enum ClipboardPrivacy {

    /// Pasteboard types that mean "do not record this".
    ///
    /// `org.nspasteboard.ConcealedType` is the cross-app convention password
    /// managers use to mark secrets; `TransientType`/`AutoGeneratedType` mark
    /// content that was never a deliberate user copy. Honouring these is what
    /// keeps a clipboard manager from quietly building a plaintext password log.
    public static let concealedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
        "com.typeit4me.clipping",
        "de.petermaurer.TransientPasteboardType",
        "Pasteboard generator type",
    ]

    /// Bundle identifiers whose copies are never recorded.
    public static let defaultExcludedApps: Set<String> = [
        "com.agilebits.onepassword7",
        "com.1password.1password",
        "com.apple.keychainaccess",
        "com.lastpass.LastPass",
        "com.bitwarden.desktop",
        "com.dashlane.dashlanephonefinal",
        "in.sinew.Enpass-Desktop",
        "com.apple.Passwords",
    ]

    /// Decides whether a pasteboard change should be recorded.
    public static func shouldRecord(types: [String],
                                    sourceBundleID: String?,
                                    excludedApps: Set<String> = defaultExcludedApps) -> Bool {
        for t in types where concealedTypes.contains(t) { return false }
        if let id = sourceBundleID, excludedApps.contains(id) { return false }
        return true
    }
}
