import Foundation
import CoreGraphics
import MacToysCore

let t = TinyTest()

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

exit(t.report())
