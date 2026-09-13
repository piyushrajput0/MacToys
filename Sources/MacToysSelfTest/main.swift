import Foundation
import CoreGraphics
import AppKit
import MacToysCore

let t = TinyTest()

/// Mirrors SettingsWindowController's speed mapping, which lives in the app
/// target and so cannot be imported here.
enum SettingsSpeed {
    static func stepDistance(fromSpeed speed: Double) -> Double {
        let slowest = 0.070, fastest = 0.012
        let t = min(max(speed, 0), 1)
        return slowest + (fastest - slowest) * t
    }
    static func speed(fromStepDistance distance: Double) -> Double {
        let slowest = 0.070, fastest = 0.012
        return min(max((distance - slowest) / (fastest - slowest), 0), 1)
    }
}


/// Mirrors `SettingsWindowController.serialise`, which lives in the app target
/// and so cannot be imported here.
func serialiseSpec(_ spec: HotKeySpec) -> String {
    var parts: [String] = []
    if spec.mods.contains(.control) { parts.append("ctrl") }
    if spec.mods.contains(.option)  { parts.append("alt") }
    if spec.mods.contains(.shift)   { parts.append("shift") }
    if spec.mods.contains(.command) { parts.append("cmd") }
    if let name = KeyCode.named.first(where: { $0.value == spec.keyCode })?.key { parts.append(name) }
    else if let l = KeyCode.letters.first(where: { $0.value == spec.keyCode })?.key { parts.append(l) }
    else if let d = KeyCode.digits.first(where: { $0.value == spec.keyCode })?.key { parts.append(d) }
    else { return "" }
    return parts.joined(separator: "+")
}


// ───────────────────────────────────────────────────────────── HotKeySpec ────
t.group("HotKeySpec parsing")

t.test("parses a modifier combination") {
    let s = HotKeySpec.parse("cmd+shift+v")
    t.expect(s != nil, "cmd+shift+v should parse")
    t.equal(s?.keyCode, KeyCode.v, "keyCode")
    t.equal(s?.mods, [.command, .shift], "mods")
}

t.test("parses arrow keys and control+option") {
    let s = HotKeySpec.parse("ctrl+alt+left")
    t.equal(s?.keyCode, KeyCode.left, "keyCode")
    t.equal(s?.mods, [.control, .option], "mods")
}

t.test("accepts alternate modifier spellings and dashes") {
    let a = HotKeySpec.parse("command-option-right")
    let b = HotKeySpec.parse("cmd+opt+right")
    t.equal(a, b, "spellings should agree")
}

t.test("is case and whitespace insensitive") {
    t.equal(HotKeySpec.parse("CMD + Shift + V"), HotKeySpec.parse("cmd+shift+v"))
}

t.test("parses digits") {
    t.equal(HotKeySpec.parse("ctrl+alt+1")?.keyCode, KeyCode.digits["1"])
}

t.test("rejects malformed specs") {
    t.expect(HotKeySpec.parse("cmd") == nil, "modifier with no key must fail")
    t.expect(HotKeySpec.parse("cmd+v+x") == nil, "two keys must fail")
    t.expect(HotKeySpec.parse("cmd+banana") == nil, "unknown key must fail")
    t.expect(HotKeySpec.parse("") == nil, "empty must fail")
}

t.test("renders a readable description") {
    t.equal(HotKeySpec.parse("cmd+shift+v")?.description, "⇧⌘V")
    t.equal(HotKeySpec.parse("ctrl+alt+left")?.description, "⌃⌥←")
}

// ─────────────────────────────────────────────────────────── SnapGeometry ────
t.group("SnapGeometry")

let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

t.test("halves tile the screen exactly with no gap") {
    let l = SnapGeometry.frame(for: .leftHalf, in: screen)
    let r = SnapGeometry.frame(for: .rightHalf, in: screen)
    t.equal(l, CGRect(x: 0, y: 0, width: 500, height: 800), "left")
    t.equal(r, CGRect(x: 500, y: 0, width: 500, height: 800), "right")
    t.equal(l.maxX, r.minX, "halves must touch")
    t.equal(l.width + r.width, screen.width, "halves must cover the screen")
}

t.test("quarters tile the screen exactly") {
    let quarters: [SnapAction] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    let area = quarters.map { SnapGeometry.frame(for: $0, in: screen) }
        .reduce(0.0) { $0 + $1.width * $1.height }
    t.equal(area, screen.width * screen.height, "quarters must cover the screen")
}

t.test("thirds sum to the full width") {
    let a = SnapGeometry.frame(for: .leftThird, in: screen)
    let b = SnapGeometry.frame(for: .centreThird, in: screen)
    let c = SnapGeometry.frame(for: .rightThird, in: screen)
    t.nearlyEqual(a.width + b.width + c.width, screen.width, tolerance: 1.5, "thirds width")
    t.equal(a.minX, 0.0, "left third starts at 0")
    t.equal(c.maxX, 1000.0, "right third ends at screen edge")
}

t.test("gap produces one gap between tiles and one at the edges") {
    let gap: CGFloat = 10
    let l = SnapGeometry.frame(for: .leftHalf, in: screen, gap: gap)
    let r = SnapGeometry.frame(for: .rightHalf, in: screen, gap: gap)
    t.equal(l.minX, gap, "outer left margin")
    t.equal(screen.maxX - r.maxX, gap, "outer right margin")
    t.equal(r.minX - l.maxX, gap, "inner gap should equal the configured gap, not double it")
    t.equal(l.minY, gap, "outer top margin")
}

t.test("maximize respects the gap and never exceeds the screen") {
    let m = SnapGeometry.frame(for: .maximize, in: screen, gap: 12)
    t.equal(m, CGRect(x: 12, y: 12, width: 976, height: 776))
    t.expect(screen.contains(m), "maximized frame must stay on screen")
}

t.test("a degenerate gap cannot produce an invalid frame") {
    let m = SnapGeometry.frame(for: .leftHalf, in: CGRect(x: 0, y: 0, width: 20, height: 20), gap: 100)
    t.expect(m.width > 0 && m.height > 0, "must not return an empty or negative rect")
}

t.test("repeated presses cycle half -> third -> two-thirds") {
    let cycle: [SnapAction] = [.leftHalf, .leftThird, .leftTwoThirds]
    let half = SnapGeometry.frame(for: .leftHalf, in: screen)
    let third = SnapGeometry.frame(for: .leftThird, in: screen)
    let two = SnapGeometry.frame(for: .leftTwoThirds, in: screen)

    t.equal(SnapGeometry.nextInCycle(cycle, current: half, visibleFrame: screen), .leftThird)
    t.equal(SnapGeometry.nextInCycle(cycle, current: third, visibleFrame: screen), .leftTwoThirds)
    t.equal(SnapGeometry.nextInCycle(cycle, current: two, visibleFrame: screen), .leftHalf, "cycle must wrap")
}

t.test("an unrecognised window position starts the cycle from the beginning") {
    let odd = CGRect(x: 137, y: 42, width: 613, height: 391)
    t.equal(SnapGeometry.nextInCycle([.leftHalf, .leftThird], current: odd, visibleFrame: screen), .leftHalf)
}

t.test("cycle tolerates a few pixels of window drift") {
    // Apps such as Terminal resize in whole character cells, so the window
    // never lands exactly on the requested frame.
    var half = SnapGeometry.frame(for: .leftHalf, in: screen)
    half.size.width -= 6
    t.equal(SnapGeometry.nextInCycle([.leftHalf, .leftThird], current: half, visibleFrame: screen),
            .leftThird, "a 6px drift must still count as snapped")
}

t.test("vertical flip is its own inverse") {
    let r = CGRect(x: 10, y: 20, width: 300, height: 100)
    let flipped = SnapGeometry.flipVertically(r, primaryHeight: 800)
    t.equal(flipped, CGRect(x: 10, y: 680, width: 300, height: 100))
    t.equal(SnapGeometry.flipVertically(flipped, primaryHeight: 800), r, "flipping twice returns the original")
}

t.test("picks the display holding most of the window") {
    let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800),
                   CGRect(x: 1000, y: 0, width: 1600, height: 900)]
    t.equal(SnapGeometry.bestScreenIndex(for: CGRect(x: 1200, y: 100, width: 400, height: 300), screens: screens), 1)
    t.equal(SnapGeometry.bestScreenIndex(for: CGRect(x: 10, y: 10, width: 200, height: 200), screens: screens), 0)
    // Straddling: 300px on the left screen, 100px on the right.
    t.equal(SnapGeometry.bestScreenIndex(for: CGRect(x: 700, y: 0, width: 400, height: 100), screens: screens), 0,
            "should pick the screen with the larger overlap")
}

t.test("an off-screen window falls back to the nearest display") {
    let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800),
                   CGRect(x: 1000, y: 0, width: 1600, height: 900)]
    let orphan = CGRect(x: 5000, y: 5000, width: 100, height: 100)
    t.equal(SnapGeometry.bestScreenIndex(for: orphan, screens: screens), 1, "nearest, not nil")
    t.expect(SnapGeometry.bestScreenIndex(for: orphan, screens: []) == nil, "no screens means no answer")
}

t.test("moving between displays preserves the relative layout") {
    let a = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let b = CGRect(x: 1000, y: 0, width: 1600, height: 900)
    let leftHalf = SnapGeometry.frame(for: .leftHalf, in: a)
    let moved = SnapGeometry.translate(window: leftHalf, from: a, to: b)
    t.equal(moved, CGRect(x: 1000, y: 0, width: 800, height: 900), "left half stays a left half")
    t.expect(b.contains(moved), "translated window must land on the destination screen")
}

t.test("a window larger than the destination is clamped onto it") {
    let big = CGRect(x: 0, y: 0, width: 2000, height: 1000)
    let small = CGRect(x: 0, y: 0, width: 800, height: 600)
    let moved = SnapGeometry.translate(window: big, from: CGRect(x: 0, y: 0, width: 2000, height: 1000), to: small)
    t.expect(small.contains(moved), "must be clamped inside the small display, got \(moved)")
}

// ────────────────────────────────────────────────────────── ClipboardStore ────
t.group("ClipboardStore")

func item(_ s: String, at seconds: TimeInterval) -> ClipItem {
    ClipItem.text(s, createdAt: Date(timeIntervalSince1970: seconds))
}

t.test("newest item comes first") {
    let store = ClipboardStore(capacity: 10)
    store.insert(item("one", at: 1))
    store.insert(item("two", at: 2))
    t.equal(store.items.first?.text, "two")
    t.equal(store.items.count, 2)
}

t.test("re-copying promotes instead of duplicating") {
    let store = ClipboardStore(capacity: 10)
    store.insert(item("alpha", at: 1))
    store.insert(item("beta", at: 2))
    let inserted = store.insert(item("alpha", at: 3))
    t.equal(store.items.count, 2, "must not duplicate")
    t.equal(store.items.first?.text, "alpha", "must move to the front")
    t.expect(inserted == false, "insert should report that this was a duplicate")
}

t.test("history is bounded by capacity") {
    let store = ClipboardStore(capacity: 3)
    for i in 1...6 { store.insert(item("item\(i)", at: TimeInterval(i))) }
    t.equal(store.items.count, 3)
    t.equal(store.items.map { $0.text ?? "" }, ["item6", "item5", "item4"])
}

t.test("pinned items survive eviction and sort to the top") {
    let store = ClipboardStore(capacity: 3)
    store.insert(item("keepme", at: 1))
    let pinnedID = store.items[0].id
    _ = store.togglePin(id: pinnedID)
    for i in 2...6 { store.insert(item("item\(i)", at: TimeInterval(i))) }

    t.equal(store.items.count, 3)
    t.equal(store.items.first?.text, "keepme", "pinned item must sort first")
    t.expect(store.items.contains { $0.text == "keepme" }, "oldest item survived because it is pinned")
}

t.test("re-copying a pinned item keeps it pinned") {
    let store = ClipboardStore(capacity: 5)
    store.insert(item("snippet", at: 1))
    _ = store.togglePin(id: store.items[0].id)
    store.insert(item("snippet", at: 9))
    t.equal(store.items.count, 1)
    t.expect(store.items[0].pinned, "pin state must not be lost when the item is re-copied")
}

t.test("clearUnpinned keeps pins") {
    let store = ClipboardStore(capacity: 10)
    store.insert(item("a", at: 1))
    store.insert(item("b", at: 2))
    _ = store.togglePin(id: store.items.first(where: { $0.text == "a" })!.id)
    store.clearUnpinned()
    t.equal(store.items.count, 1)
    t.equal(store.items[0].text, "a")
}

t.test("search ranks a prefix above a later substring") {
    let store = ClipboardStore(capacity: 10)
    store.insert(item("the receipt is prepaid", at: 1))
    store.insert(item("report.pdf", at: 2))
    let hits = store.search("rep")
    t.equal(hits.count, 2)
    t.equal(hits.first?.text, "report.pdf", "prefix match should win")
}

t.test("search falls back to subsequence matching") {
    let store = ClipboardStore(capacity: 10)
    store.insert(item("configuration", at: 1))
    t.equal(store.search("cfg").count, 1, "cfg should match configuration as a subsequence")
    t.equal(store.search("zzz").count, 0, "non-matching query returns nothing")
}

t.test("an empty query returns the full history unchanged") {
    let store = ClipboardStore(capacity: 10)
    store.insert(item("a", at: 1))
    store.insert(item("b", at: 2))
    t.equal(store.search("   ").map { $0.text ?? "" }, ["b", "a"])
}

t.test("search is case-insensitive") {
    let store = ClipboardStore(capacity: 10)
    store.insert(item("Hello World", at: 1))
    t.equal(store.search("hello world").count, 1)
    t.equal(store.search("HELLO").count, 1)
}

t.test("history survives a save/load round trip") {
    let store = ClipboardStore(capacity: 5)
    store.insert(item("first", at: 1))
    store.insert(item("second", at: 2))
    _ = store.togglePin(id: store.items.first(where: { $0.text == "first" })!.id)

    let data = try store.encode()
    let restored = ClipboardStore(capacity: 5)
    try restored.load(from: data)

    t.equal(restored.items.count, 2)
    t.equal(restored.items.first?.text, "first", "pin ordering must survive")
    t.expect(restored.items.first?.pinned == true, "pin flag must survive")
}

t.test("oversized images are dropped at save time rather than bloating the file") {
    let store = ClipboardStore(capacity: 5)
    store.insert(ClipItem(kind: .image, imageData: Data(repeating: 0xAB, count: 50_000)))
    store.insert(item("text stays", at: 5))
    let data = try store.encode(maxImageBytes: 1000)
    let restored = ClipboardStore(capacity: 5)
    try restored.load(from: data)
    t.equal(restored.items.count, 1, "the huge image should not be restored")
    t.equal(restored.items.first?.text, "text stays")
}

t.test("previews are single-line and bounded") {
    let multi = ClipItem.text("line one\nline two\nline three")
    t.expect(!multi.preview.contains("\n"), "preview must not contain newlines")
    let long = ClipItem.text(String(repeating: "x", count: 500))
    t.expect(long.preview.count <= 121, "preview must be truncated, got \(long.preview.count)")
}

t.test("file items preview by filename") {
    let one = ClipItem(kind: .files, filePaths: ["/Users/me/Documents/report.pdf"])
    t.expect(one.preview.contains("report.pdf"), "got \(one.preview)")
    let many = ClipItem(kind: .files, filePaths: ["/a/1.txt", "/a/2.txt", "/a/3.txt"])
    t.expect(many.preview.contains("3 files"), "got \(many.preview)")
}

// ──────────────────────────────────────────────────────── ClipboardPrivacy ────
t.group("ClipboardPrivacy")

t.test("records an ordinary copy") {
    t.expect(ClipboardPrivacy.shouldRecord(types: ["public.utf8-plain-text"], sourceBundleID: "com.apple.Safari"),
             "a normal copy should be recorded")
}

t.test("never records a pasteboard marked concealed") {
    t.expect(!ClipboardPrivacy.shouldRecord(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"],
                                            sourceBundleID: "com.apple.Safari"),
             "concealed marker must suppress recording")
}

t.test("never records copies made in a password manager") {
    t.expect(!ClipboardPrivacy.shouldRecord(types: ["public.utf8-plain-text"],
                                            sourceBundleID: "com.1password.1password"),
             "password manager copies must be ignored")
}

t.test("ignores transient and auto-generated pasteboards") {
    t.expect(!ClipboardPrivacy.shouldRecord(types: ["org.nspasteboard.TransientType"], sourceBundleID: nil))
    t.expect(!ClipboardPrivacy.shouldRecord(types: ["org.nspasteboard.AutoGeneratedType"], sourceBundleID: nil))
}

// ───────────────────────────────────────────────────────────── RemapRules ────
t.group("RemapRules")

let cfg = RemapConfig()
let safari = RemapContext(frontmostBundleID: "com.apple.Safari")
let finder = RemapContext(frontmostBundleID: RemapRules.finderBundleID)

t.test("Home goes to the start of the line, as on Windows") {
    let out = RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.home, mods: []), context: safari, config: cfg)
    t.equal(out, .replace(KeyStroke(keyCode: KeyCode.left, mods: .command), nil))
}

t.test("End goes to the end of the line") {
    let out = RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.end, mods: []), context: safari, config: cfg)
    t.equal(out, .replace(KeyStroke(keyCode: KeyCode.right, mods: .command), nil))
}

t.test("Shift+Home extends the selection instead of just moving") {
    let out = RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.home, mods: .shift), context: safari, config: cfg)
    t.equal(out, .replace(KeyStroke(keyCode: KeyCode.left, mods: [.command, .shift]), nil))
}

t.test("Ctrl+Home jumps to the top of the document") {
    let out = RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.home, mods: .control), context: safari, config: cfg)
    t.equal(out, .replace(KeyStroke(keyCode: KeyCode.up, mods: .command), nil))
    let end = RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.end, mods: .control), context: safari, config: cfg)
    t.equal(end, .replace(KeyStroke(keyCode: KeyCode.down, mods: .command), nil))
}

t.test("Ctrl+Shift+End selects to the end of the document") {
    let out = RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.end, mods: [.control, .shift]), context: safari, config: cfg)
    t.equal(out, .replace(KeyStroke(keyCode: KeyCode.down, mods: [.command, .shift]), nil))
}

t.test("the fn modifier laptops add to Home/End is ignored") {
    let out = RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.home, mods: [.fn]), context: safari, config: cfg)
    t.equal(out, .replace(KeyStroke(keyCode: KeyCode.left, mods: .command), nil),
            "fn must be stripped, not leak into the synthesised event")
}

t.test("terminals and editors keep their own Home/End behaviour") {
    for app in ["com.apple.Terminal", "com.microsoft.VSCode", "com.googlecode.iterm2"] {
        let ctx = RemapContext(frontmostBundleID: app)
        t.equal(RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.home, mods: []), context: ctx, config: cfg),
                .passthrough, "\(app) must be left alone")
    }
}

t.test("Home/End remapping can be switched off") {
    var off = RemapConfig(); off.windowsHomeEnd = false
    t.equal(RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.home, mods: []), context: safari, config: off), .passthrough)
}

t.test("Cmd+X in Finder copies and arms a move") {
    let out = RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.x, mods: .command), context: finder, config: cfg)
    t.equal(out, .replace(KeyStroke(keyCode: KeyCode.c, mods: .command), .armCutMode))
}

t.test("Cmd+V after a cut becomes Finder's Move Item Here") {
    let armed = RemapContext(frontmostBundleID: RemapRules.finderBundleID, cutModeArmed: true)
    let out = RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.v, mods: .command), context: armed, config: cfg)
    t.equal(out, .replace(KeyStroke(keyCode: KeyCode.v, mods: [.command, .option]), .disarmCutMode))
}

t.test("Cmd+V without a preceding cut is an ordinary copy-paste") {
    let out = RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.v, mods: .command), context: finder, config: cfg)
    t.equal(out, .passthrough, "a paste with no cut must not move files")
}

t.test("a copy after a cut cancels the pending move") {
    let armed = RemapContext(frontmostBundleID: RemapRules.finderBundleID, cutModeArmed: true)
    let out = RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.c, mods: .command), context: armed, config: cfg)
    t.equal(out, .replace(KeyStroke(keyCode: KeyCode.c, mods: .command), .disarmCutMode),
            "changing your mind must turn the next paste back into a copy")
}

t.test("Finder shortcuts do not leak into other apps") {
    t.equal(RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.x, mods: .command), context: safari, config: cfg),
            .passthrough, "Cmd+X must still cut text in normal apps")
    let armedSafari = RemapContext(frontmostBundleID: "com.apple.Safari", cutModeArmed: true)
    t.equal(RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.v, mods: .command), context: armedSafari, config: cfg),
            .passthrough, "a stale cut flag must not alter paste in other apps")
}

t.test("Delete moves a file to the Trash in Finder") {
    let out = RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.forwardDelete, mods: []), context: finder, config: cfg)
    t.equal(out, .replace(KeyStroke(keyCode: KeyCode.delete, mods: .command), nil))
}

t.test("Delete elsewhere still deletes forward") {
    t.equal(RemapRules.outcome(for: KeyStroke(keyCode: KeyCode.forwardDelete, mods: []), context: safari, config: cfg),
            .passthrough)
}

t.test("unrelated keys are never touched") {
    for code in [KeyCode.a, KeyCode.space, KeyCode.returnKey, KeyCode.tab, KeyCode.escape] {
        t.equal(RemapRules.outcome(for: KeyStroke(keyCode: code, mods: []), context: finder, config: cfg),
                .passthrough, "keyCode \(code) must pass through")
    }
}

t.test("the tap only subscribes to keys it actually rewrites") {
    let watched = RemapRules.watchedKeyCodes(config: cfg)
    t.expect(watched.contains(KeyCode.home) && watched.contains(KeyCode.x), "must watch remapped keys")
    t.expect(!watched.contains(KeyCode.a), "must not watch keys it never rewrites")
    var none = RemapConfig(windowsHomeEnd: false, finderCutPaste: false, finderForwardDelete: false)
    none.homeEndExcludedApps = []
    t.equal(RemapRules.watchedKeyCodes(config: none).count, 0, "everything off means nothing is watched")
}

// ──────────────────────────────────────────────────────────── Preferences ────
t.group("Preferences")

t.test("ships with every shortcut resolvable") {
    let p = Preferences()
    for name in Preferences.defaultShortcuts.keys {
        t.expect(p.spec(name) != nil, "default shortcut \(name) must parse")
    }
}

t.test("a corrupt shortcut falls back to the default instead of disabling the feature") {
    var p = Preferences()
    p.shortcuts["clipboardHistory"] = "not-a-shortcut"
    t.equal(p.spec("clipboardHistory"), HotKeySpec.parse("cmd+shift+v"))
}

t.test("an unknown shortcut name resolves to nothing") {
    t.expect(Preferences().spec("noSuchAction") == nil)
}

t.test("hand-edited nonsense is clamped to a usable range") {
    var p = Preferences()
    p.clipboardCapacity = -5
    p.clipboardPollInterval = 0
    p.snapGap = 9999
    let n = p.normalised()
    t.equal(n.clipboardCapacity, 1, "capacity")
    t.equal(n.clipboardPollInterval, 0.1, "poll interval must not spin the CPU")
    t.equal(n.snapGap, 100, "gap")
}

t.test("survives a JSON round trip") {
    var p = Preferences()
    p.clipboardCapacity = 42
    p.remap.windowsHomeEnd = false
    p.shortcuts["snapLeft"] = "cmd+ctrl+left"
    let data = try JSONEncoder().encode(p)
    let back = try JSONDecoder().decode(Preferences.self, from: data)
    t.equal(back, p)
}


// ─────────────────────────────────────────────────────────── PasteboardGate ────
t.group("PasteboardGate")

t.test("an unchanged count is not a copy") {
    var g = PasteboardGate(changeCount: 7)
    t.equal(g.observe(7), .unchanged)
}

t.test("a change from another app is recorded") {
    var g = PasteboardGate(changeCount: 7)
    t.equal(g.observe(8), .record)
}

t.test("our own write is skipped exactly once") {
    var g = PasteboardGate(changeCount: 7)
    g.noteOwnWrite(resultingChangeCount: 8)
    t.equal(g.observe(8), .skipOwnWrite, "the paste we caused must not be re-recorded")
}

t.test("REGRESSION: the copy after a paste is still recorded") {
    // The original bug: write() set a skip flag *and* fast-forwarded the
    // counter, so the flag was never consumed and silently ate the user's next
    // copy. Every paste from history cost you the next thing you copied.
    var g = PasteboardGate(changeCount: 7)
    g.noteOwnWrite(resultingChangeCount: 8)
    t.equal(g.observe(8), .skipOwnWrite, "our paste")
    t.equal(g.observe(9), .record, "the user's NEXT copy must not be swallowed")
    t.expect(!g.hasPendingOwnWrite, "the marker must be cleared after use")
}

t.test("many pastes in a row do not accumulate skips") {
    var g = PasteboardGate(changeCount: 0)
    for i in 1...5 {
        g.noteOwnWrite(resultingChangeCount: i)
        t.equal(g.observe(i), .skipOwnWrite, "paste \(i)")
    }
    t.equal(g.observe(6), .record, "a real copy after five pastes")
}

t.test("a stale marker cannot suppress an unrelated copy") {
    // Another app writes before our own change is observed, so the count we
    // were expecting never arrives.
    var g = PasteboardGate(changeCount: 7)
    g.noteOwnWrite(resultingChangeCount: 8)
    t.equal(g.observe(12), .record, "someone else's copy must still be recorded")
    t.expect(!g.hasPendingOwnWrite, "the never-matched marker must not linger")
    t.equal(g.observe(13), .record, "and must not suppress the one after it either")
}

t.test("tracks the last observed count") {
    var g = PasteboardGate(changeCount: 3)
    _ = g.observe(9)
    t.equal(g.lastObserved, 9)
}

// ───────────────────────────────────────────────────────── ColorFormatter ────
t.group("ColorFormatter")

t.test("formats hex in both cases") {
    t.equal(ColorFormatter.string(red: 74/255, green: 144/255, blue: 217/255, format: .hex), "#4A90D9")
    t.equal(ColorFormatter.string(red: 74/255, green: 144/255, blue: 217/255, format: .hexLower), "#4a90d9")
}

t.test("formats pure black and white without rounding drift") {
    t.equal(ColorFormatter.string(red: 0, green: 0, blue: 0, format: .hex), "#000000")
    t.equal(ColorFormatter.string(red: 1, green: 1, blue: 1, format: .hex), "#FFFFFF")
}

t.test("formats CSS functions") {
    t.equal(ColorFormatter.string(red: 74/255, green: 144/255, blue: 217/255, format: .rgb), "rgb(74, 144, 217)")
    t.equal(ColorFormatter.string(red: 1, green: 0, blue: 0, alpha: 1, format: .rgba), "rgba(255, 0, 0, 1)")
    t.equal(ColorFormatter.string(red: 1, green: 0, blue: 0, alpha: 0.5, format: .rgba), "rgba(255, 0, 0, 0.50)")
}

t.test("clamps out-of-gamut components instead of emitting nonsense") {
    // A wide-gamut display profile can hand back components outside 0...1.
    let s = ColorFormatter.string(red: 1.4, green: -0.2, blue: 0.5, format: .hex)
    t.equal(s, "#FF0080", "must clamp rather than overflow or go negative")
    t.expect(s.count == 7, "hex must stay six digits")
}

t.test("hsl matches known values") {
    let (h1, s1, l1) = ColorFormatter.hsl(r: 1, g: 0, b: 0)
    t.nearlyEqual(h1, 0, tolerance: 0.5, "red hue")
    t.nearlyEqual(s1, 1, tolerance: 0.01, "red saturation")
    t.nearlyEqual(l1, 0.5, tolerance: 0.01, "red lightness")

    let (h2, _, _) = ColorFormatter.hsl(r: 0, g: 1, b: 0)
    t.nearlyEqual(h2, 120, tolerance: 0.5, "green hue")
    let (h3, _, _) = ColorFormatter.hsl(r: 0, g: 0, b: 1)
    t.nearlyEqual(h3, 240, tolerance: 0.5, "blue hue")
}

t.test("grey has no hue rather than a garbage one") {
    let (h, s, l) = ColorFormatter.hsl(r: 0.5, g: 0.5, b: 0.5)
    t.nearlyEqual(h, 0, tolerance: 0.001)
    t.nearlyEqual(s, 0, tolerance: 0.001, "grey must be unsaturated")
    t.nearlyEqual(l, 0.5, tolerance: 0.001)
}

t.test("every format produces something non-empty") {
    for f in ColorFormat.allCases {
        t.expect(!ColorFormatter.string(red: 0.2, green: 0.4, blue: 0.6, format: f).isEmpty,
                 "\(f) produced nothing")
    }
}

// ─────────────────────────────────────────────────────── OCRTextAssembler ────
t.group("OCRTextAssembler")

t.test("keeps the original layout when joining is off") {
    t.equal(OCRTextAssembler.assemble(["one", "two", "three"], joinLines: false), "one\ntwo\nthree")
}

t.test("drops blank observations") {
    t.equal(OCRTextAssembler.assemble(["one", "   ", "", "two"], joinLines: false), "one\ntwo")
}

t.test("rejoins a wrapped sentence") {
    t.equal(OCRTextAssembler.assemble(["The quick brown", "fox jumps over"], joinLines: true),
            "The quick brown fox jumps over")
}

t.test("keeps a break after a finished sentence") {
    t.equal(OCRTextAssembler.assemble(["First sentence.", "Second one"], joinLines: true),
            "First sentence.\nSecond one")
}

t.test("keeps list items on their own lines") {
    t.equal(OCRTextAssembler.assemble(["Shopping", "- milk", "- eggs"], joinLines: true),
            "Shopping\n- milk\n- eggs")
    t.equal(OCRTextAssembler.assemble(["Steps", "1. open it", "2. close it"], joinLines: true),
            "Steps\n1. open it\n2. close it")
}

t.test("reunites a word split across a line break") {
    t.equal(OCRTextAssembler.assemble(["some inter-", "national text"], joinLines: true),
            "some international text")
}

t.test("a trailing dash that is punctuation is not treated as a split word") {
    t.equal(OCRTextAssembler.assemble(["a dash -", "then more"], joinLines: true), "a dash - then more")
}

t.test("recognises numbered list markers") {
    t.expect(OCRTextAssembler.isNumberedItem("12. thing"))
    t.expect(OCRTextAssembler.isNumberedItem("3) thing"))
    t.expect(!OCRTextAssembler.isNumberedItem("3 thing"), "a bare number is not a list marker")
    t.expect(!OCRTextAssembler.isNumberedItem("thing"))
}

t.test("empty input is handled") {
    t.equal(OCRTextAssembler.assemble([], joinLines: true), "")
    t.equal(OCRTextAssembler.assemble([], joinLines: false), "")
}

// ────────────────────────────────────────────── ClipboardStore capacity ────
t.group("ClipboardStore resizing")

t.test("shrinking the limit evicts immediately") {
    let store = ClipboardStore(capacity: 10)
    for i in 1...8 { store.insert(item("item\(i)", at: TimeInterval(i))) }
    store.setCapacity(3)
    t.equal(store.items.count, 3, "must evict as soon as the limit changes")
    t.equal(store.items.first?.text, "item8", "the newest must survive")
}

t.test("growing the limit keeps everything") {
    let store = ClipboardStore(capacity: 3)
    for i in 1...5 { store.insert(item("item\(i)", at: TimeInterval(i))) }
    store.setCapacity(50)
    t.equal(store.items.count, 3, "already-evicted items do not come back")
    store.insert(item("item6", at: 6))
    t.equal(store.items.count, 4, "but new ones are kept")
}

t.test("a nonsense capacity is clamped") {
    let store = ClipboardStore(capacity: 10)
    store.setCapacity(0)
    t.equal(store.capacity, 1)
    store.setCapacity(999_999)
    t.equal(store.capacity, 10_000)
}

t.test("shrinking never discards a pinned item") {
    let store = ClipboardStore(capacity: 10)
    for i in 1...8 { store.insert(item("item\(i)", at: TimeInterval(i))) }
    _ = store.togglePin(id: store.items.first(where: { $0.text == "item1" })!.id)
    store.setCapacity(2)
    t.expect(store.items.contains { $0.text == "item1" }, "a pinned item must survive resizing")
}

// ────────────────────────────────────── Preferences forward compatibility ────
t.group("Preferences upgrades")

t.test("a config file from an older version still loads") {
    // Exactly the keys the first release wrote — none of the newer ones.
    let old = """
    {"autoPasteOnPick":false,"clipboardCapacity":42,"clipboardHistoryEnabled":true,
     "clipboardPollInterval":0.4,"excludedApps":[],"keyRemapEnabled":true,
     "launchAtLogin":false,"persistClipboardHistory":true,
     "remap":{"finderCutPaste":true,"finderForwardDelete":true,"homeEndExcludedApps":[],"windowsHomeEnd":true},
     "shortcuts":{"clipboardHistory":"cmd+shift+b"},"snapCyclingEnabled":true,"snapGap":8,
     "snipEnabled":true,"windowSnapEnabled":true}
    """
    let p = try JSONDecoder().decode(Preferences.self, from: Data(old.utf8))
    t.equal(p.clipboardCapacity, 42, "existing settings must be preserved")
    t.equal(p.snapGap, 8.0, "existing settings must be preserved")
    t.expect(p.autoPasteOnPick == false, "an explicitly disabled setting must stay disabled")
    t.equal(p.colorFormat, .hex, "a new setting must fall back to its default")
    t.expect(p.textExtractorEnabled, "a new feature must default to on, not off")
}

t.test("a customised shortcut survives an upgrade, and new ones appear") {
    let old = #"{"shortcuts":{"clipboardHistory":"cmd+shift+b"}}"#
    let p = try JSONDecoder().decode(Preferences.self, from: Data(old.utf8))
    t.equal(p.spec("clipboardHistory"), HotKeySpec.parse("cmd+shift+b"), "the user's binding must be kept")
    t.expect(p.spec("colorPicker") != nil, "a shortcut added in a later version must appear")
}

t.test("a truncated or corrupt config does not throw away every setting") {
    let p = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    t.equal(p.clipboardCapacity, Preferences().clipboardCapacity)
    t.expect(p.spec("clipboardHistory") != nil)
}

t.test("round trip still works with the new fields") {
    var p = Preferences()
    p.colorFormat = .hsl
    p.ocrJoinLines = true
    p.textExtractorEnabled = false
    let back = try JSONDecoder().decode(Preferences.self, from: try JSONEncoder().encode(p))
    t.equal(back, p)
}

// ─────────────────────────────────────────── Shortcut recorder round trip ────
t.group("Shortcut serialisation")

t.test("every default shortcut survives parse then re-serialise") {
    // The settings recorder writes shortcuts back as text; a binding that does
    // not round trip would silently change when the window is opened.
    for (name, raw) in Preferences.defaultShortcuts {
        guard let spec = HotKeySpec.parse(raw) else {
            t.expect(false, "\(name) failed to parse"); continue
        }
        let text = serialiseSpec(spec)
        guard let reparsed = HotKeySpec.parse(text) else {
            t.expect(false, "\(name) re-serialised to unparseable \"\(text)\""); continue
        }
        t.equal(reparsed, spec, "\(name) changed across a round trip")
    }
}


// ────────────────────────────────────────────────────── Cocoa key bindings ────
t.group("Cocoa key binding facts")

t.test("REGRESSION: Cmd+Delete in a text field sends deleteToBeginningOfLine, not deleteBackward") {
    // NSTextField dispatches this selector for Cmd+Delete (same as Cmd+Backspace
    // in TextEdit/Mail/any Cocoa text field) -- never deleteBackward(_:), even
    // with Command held. The clipboard picker's delete-selected-item handler
    // switched on deleteBackward with a Command-flag check, which can never be
    // reached for this chord: AppKit already dispatched a different selector by
    // the time our handler runs, so the checked branch was unreachable and the
    // field's default line-delete ran instead of removing the highlighted item.
    // This does not exercise AppKit's dispatch (that needs a live text field and
    // real key event, which this headless suite cannot drive) -- it records the
    // platform fact so this cannot silently regress back to checking the wrong
    // selector again.
    t.expect(#selector(NSResponder.deleteToBeginningOfLine(_:)) != #selector(NSResponder.deleteBackward(_:)),
             "these must be handled as distinct selectors")
}


// ─────────────────────────────────────────────── VolumeGestureRecognizer ────
t.group("Volume gesture")

/// Feeds a straight swipe and returns the total steps emitted.
func swipe(_ r: inout VolumeGestureRecognizer, fingers: Int,
           from: (Double, Double), to: (Double, Double), frames: Int = 20) -> Int {
    var total = 0
    for i in 0...frames {
        let f = Double(i) / Double(frames)
        let x = from.0 + (to.0 - from.0) * f
        let y = from.1 + (to.1 - from.1) * f
        if case .steps(let n) = r.feed(GestureSample(fingerCount: fingers, x: x, y: y, time: Double(i) * 0.008)) {
            total += n
        }
    }
    return total
}

t.test("swiping up with four fingers raises the volume") {
    var r = VolumeGestureRecognizer()
    let steps = swipe(&r, fingers: 4, from: (0.5, 0.3), to: (0.5, 0.8))
    t.expect(steps > 0, "expected positive steps, got \(steps)")
}

t.test("swiping down lowers it by a comparable amount") {
    var up = VolumeGestureRecognizer()
    var down = VolumeGestureRecognizer()
    let a = swipe(&up, fingers: 4, from: (0.5, 0.3), to: (0.5, 0.8))
    let b = swipe(&down, fingers: 4, from: (0.5, 0.8), to: (0.5, 0.3))
    t.equal(b, -a, "down should mirror up")
}

t.test("a sideways swipe never touches the volume") {
    // Four fingers left/right is macOS switching Spaces. Changing the volume
    // every time someone moves between desktops would be unusable.
    var r = VolumeGestureRecognizer()
    t.equal(swipe(&r, fingers: 4, from: (0.1, 0.5), to: (0.9, 0.5)), 0)
}

t.test("a mostly-sideways diagonal is still treated as sideways") {
    var r = VolumeGestureRecognizer()
    t.equal(swipe(&r, fingers: 4, from: (0.1, 0.45), to: (0.9, 0.55)), 0)
}

t.test("once ruled sideways it stays ruled out for the whole gesture") {
    // Otherwise a Spaces swipe that drifts upward at the end would fire.
    var r = VolumeGestureRecognizer()
    var total = 0
    func feed(_ x: Double, _ y: Double, _ i: Int) {
        if case .steps(let n) = r.feed(GestureSample(fingerCount: 4, x: x, y: y, time: Double(i) * 0.008)) { total += n }
    }
    feed(0.1, 0.5, 0)
    for i in 1...10 { feed(0.1 + Double(i) * 0.06, 0.5, i) }   // clearly horizontal
    for i in 11...25 { feed(0.7, 0.5 + Double(i - 10) * 0.03, i) }  // then upward
    t.equal(total, 0, "a sideways gesture must not start controlling volume midway")
}

t.test("the wrong number of fingers does nothing") {
    var r = VolumeGestureRecognizer(requiredFingers: 4)
    t.equal(swipe(&r, fingers: 2, from: (0.5, 0.2), to: (0.5, 0.9)), 0, "two fingers is scrolling")
    t.equal(swipe(&r, fingers: 3, from: (0.5, 0.2), to: (0.5, 0.9)), 0, "three is not four")
}

t.test("three-finger mode responds to three, not four") {
    var r = VolumeGestureRecognizer(requiredFingers: 3)
    t.expect(swipe(&r, fingers: 3, from: (0.5, 0.3), to: (0.5, 0.8)) > 0)
    var r2 = VolumeGestureRecognizer(requiredFingers: 3)
    t.equal(swipe(&r2, fingers: 4, from: (0.5, 0.3), to: (0.5, 0.8)), 0)
}

t.test("lifting a finger mid-swipe stops the gesture") {
    var r = VolumeGestureRecognizer()
    _ = r.feed(GestureSample(fingerCount: 4, x: 0.5, y: 0.3, time: 0))
    _ = r.feed(GestureSample(fingerCount: 4, x: 0.5, y: 0.5, time: 0.01))
    _ = r.feed(GestureSample(fingerCount: 3, x: 0.5, y: 0.6, time: 0.02))
    t.expect(!r.isTracking, "dropping to three fingers must end the gesture")
}

t.test("resting fingers do not drift the volume") {
    var r = VolumeGestureRecognizer()
    var total = 0
    // Tiny jitter, as from a hand resting on the trackpad.
    for i in 0...60 {
        let y = 0.5 + (i % 2 == 0 ? 0.0015 : -0.0015)
        if case .steps(let n) = r.feed(GestureSample(fingerCount: 4, x: 0.5, y: y, time: Double(i) * 0.008)) { total += n }
    }
    t.equal(total, 0, "jitter must stay inside the dead zone")
}

t.test("steps scale with distance travelled") {
    var short = VolumeGestureRecognizer()
    var long = VolumeGestureRecognizer()
    let a = swipe(&short, fingers: 4, from: (0.5, 0.45), to: (0.5, 0.60))
    let b = swipe(&long, fingers: 4, from: (0.5, 0.20), to: (0.5, 0.90))
    t.expect(b > a, "a longer swipe should move the volume further (\(a) vs \(b))")
}

t.test("sensitivity changes how far you must swipe per step") {
    var coarse = VolumeGestureRecognizer(stepDistance: 0.10)
    var fine = VolumeGestureRecognizer(stepDistance: 0.02)
    let a = swipe(&coarse, fingers: 4, from: (0.5, 0.2), to: (0.5, 0.9))
    let b = swipe(&fine, fingers: 4, from: (0.5, 0.2), to: (0.5, 0.9))
    t.expect(b > a, "a smaller step distance should emit more steps (\(a) vs \(b))")
}

t.test("a step is never emitted twice for the same distance") {
    // Holding still after swiping must not keep raising the volume.
    var r = VolumeGestureRecognizer()
    _ = swipe(&r, fingers: 4, from: (0.5, 0.3), to: (0.5, 0.7))
    var extra = 0
    for i in 0...30 {
        if case .steps(let n) = r.feed(GestureSample(fingerCount: 4, x: 0.5, y: 0.7, time: 1 + Double(i) * 0.008)) { extra += n }
    }
    t.equal(extra, 0, "holding still must not keep changing the volume")
}

t.test("reset clears tracking") {
    var r = VolumeGestureRecognizer()
    _ = r.feed(GestureSample(fingerCount: 4, x: 0.5, y: 0.5, time: 0))
    t.expect(r.isTracking)
    r.reset()
    t.expect(!r.isTracking)
}

t.test("finger count and sensitivity are clamped to something usable") {
    var p = Preferences()
    p.volumeGestureFingers = 9
    p.volumeGestureSensitivity = 0.0001
    let n = p.normalised()
    t.equal(n.volumeGestureFingers, 4, "nine fingers is not a gesture")
    t.equal(n.volumeGestureSensitivity, 0.01, "a near-zero step would be uncontrollable")
    var q = Preferences()
    q.volumeGestureFingers = 1
    t.equal(q.normalised().volumeGestureFingers, 3)
}

t.test("the gesture is off by default") {
    // It collides with Mission Control until the user frees that gesture up,
    // so it must never switch itself on behind their back.
    t.expect(!Preferences().volumeGestureEnabled)
}


// ──────────────────────────────────────────── Volume gesture throughput ────
t.group("Volume gesture reach")

/// Total steps a swipe produces, sampled at the trackpad's real ~79 Hz.
func stepsFor(distance: Double, seconds: Double, stepDistance: Double = 0.028) -> Int {
    var r = VolumeGestureRecognizer(stepDistance: stepDistance)
    let frames = max(2, Int(seconds * 79))
    var total = 0
    for i in 0...frames {
        let f = Double(i) / Double(frames)
        let y = 0.2 + distance * f
        if case .steps(let n) = r.feed(GestureSample(fingerCount: 4, x: 0.5, y: y, time: Double(i) / 79.0)) {
            total += n
        }
    }
    return total
}

t.test("REGRESSION: a fast swipe delivers as many steps as a slow one") {
    // The bug: frames arrive every ~12ms, but the service refused to act more
    // often than every 35ms and simply dropped the steps in between. The
    // recogniser had already counted them as delivered, so they were gone --
    // a quick swipe moved the volume about a quarter of the intended distance.
    let slow = stepsFor(distance: 0.55, seconds: 1.2)
    let fast = stepsFor(distance: 0.55, seconds: 0.15)
    t.equal(fast, slow, "the same swipe must move the volume the same amount at any speed")
}

t.test("a comfortable swipe covers the whole volume range") {
    // macOS moves the volume in sixteenths, so 16 steps is 0 to 100%.
    let steps = stepsFor(distance: 0.55, seconds: 0.4)
    t.expect(steps >= 16, "expected at least 16 notches from a normal swipe, got \(steps)")
}

t.test("a short nudge still makes a small change") {
    let steps = stepsFor(distance: 0.08, seconds: 0.2)
    t.expect(steps >= 2 && steps <= 6, "expected a few notches, got \(steps)")
}

t.test("a sideways wobble mid-swipe does not stall the volume") {
    // Direction is locked once proven vertical. Re-testing every frame meant a
    // wobble could silently stop the gesture partway through.
    var r = VolumeGestureRecognizer()
    var total = 0
    func feed(_ x: Double, _ y: Double, _ i: Int) {
        if case .steps(let n) = r.feed(GestureSample(fingerCount: 4, x: x, y: y, time: Double(i) / 79.0)) { total += n }
    }
    feed(0.5, 0.20, 0)
    for i in 1...20 { feed(0.5, 0.20 + Double(i) * 0.015, i) }        // clearly vertical
    for i in 21...40 { feed(0.5 + Double(i - 20) * 0.012, 0.50 + Double(i - 20) * 0.012, i) }  // drifts sideways
    t.expect(total >= 16, "a swipe that drifts should keep working, got \(total)")
}

t.test("speed setting maps to distance and back") {
    for speed in [0.0, 0.25, 0.5, 0.75, 1.0] {
        let d = SettingsSpeed.stepDistance(fromSpeed: speed)
        t.nearlyEqual(SettingsSpeed.speed(fromStepDistance: d), speed, tolerance: 0.001, "round trip at \(speed)")
    }
}

t.test("turning the speed up needs less swiping per notch") {
    let slow = SettingsSpeed.stepDistance(fromSpeed: 0.0)
    let fast = SettingsSpeed.stepDistance(fromSpeed: 1.0)
    t.expect(fast < slow, "higher speed must mean a shorter distance per notch")
    t.expect(stepsFor(distance: 0.55, seconds: 0.4, stepDistance: fast)
             > stepsFor(distance: 0.55, seconds: 0.4, stepDistance: slow),
             "the fast end must move the volume further for the same swipe")
}

t.test("even the slowest setting reaches a usable amount of the range") {
    let slowest = SettingsSpeed.stepDistance(fromSpeed: 0.0)
    let steps = stepsFor(distance: 0.55, seconds: 0.4, stepDistance: slowest)
    t.expect(steps >= 6, "the slow end should still be usable, got \(steps)")
}


// ───────────────────────────────────────────────────────────── Diagnostics ────
t.group("Diagnostics")

t.test("a healthy report says so") {
    let r = DiagnosticsReport(generatedAt: Date(timeIntervalSince1970: 0), items: [
        DiagnosticItem(feature: "A", state: .ok, detail: "fine"),
        DiagnosticItem(feature: "B", state: .off, detail: "switched off"),
    ])
    t.expect(r.isHealthy, "deliberately-off features are not faults")
    t.equal(r.summary, "Everything is working")
    t.equal(r.problems.count, 0)
}

t.test("blocked and broken features are surfaced") {
    let r = DiagnosticsReport(generatedAt: Date(timeIntervalSince1970: 0), items: [
        DiagnosticItem(feature: "A", state: .ok, detail: "fine"),
        DiagnosticItem(feature: "B", state: .blocked, detail: "needs permission", fix: "grant it"),
        DiagnosticItem(feature: "C", state: .broken, detail: "failed"),
    ])
    t.expect(!r.isHealthy)
    t.equal(r.problems.count, 2)
    t.expect(r.summary.contains("1 broken"), "got \(r.summary)")
    t.expect(r.summary.contains("1 need attention"), "got \(r.summary)")
}

t.test("an off feature is never reported as a problem") {
    // Switching something off deliberately must not nag.
    let r = DiagnosticsReport(generatedAt: Date(timeIntervalSince1970: 0), items: [
        DiagnosticItem(feature: "A", state: .off, detail: "off"),
    ])
    t.expect(r.isHealthy)
}

t.test("the plain-text report includes fixes") {
    let r = DiagnosticsReport(generatedAt: Date(timeIntervalSince1970: 0), items: [
        DiagnosticItem(feature: "Keyboard", state: .blocked, detail: "tap not running", fix: "Grant Accessibility"),
    ])
    let text = r.plainText()
    t.expect(text.contains("Keyboard"))
    t.expect(text.contains("tap not running"))
    t.expect(text.contains("Grant Accessibility"), "the fix must be in the copyable report")
}

t.test("report survives a JSON round trip") {
    let r = DiagnosticsReport(generatedAt: Date(timeIntervalSince1970: 12345), items: [
        DiagnosticItem(feature: "A", state: .broken, detail: "d", fix: "f"),
    ])
    let back = try JSONDecoder().decode(DiagnosticsReport.self, from: try JSONEncoder().encode(r))
    t.equal(back, r)
}

t.test("snip-to-disk defaults to on") {
    t.expect(Preferences().snipSavesToDisk, "the file should be kept unless asked otherwise")
}

exit(t.report())
