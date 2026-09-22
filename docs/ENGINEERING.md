# Engineering notes

Background on the parts of [MacToys](../README.md) that were more involved than
they look, kept out of the README so that stays short.

## How some of it works

A few parts were more interesting than they look:

**Tiling that actually adds up.** Rounding each window rect independently
(`CGRect.integral`) expands every tile outward, so three thirds of a 1000px screen
each become 334px and overlap. `SnapGeometry` rounds the *shared boundaries*
instead, so tiles stay flush and the pieces sum back to the screen exactly. There's
a test for it.

**Two coordinate systems.** Cocoa measures screens from the bottom-left; the
Accessibility API measures from the top-left. Every rect has to be flipped between
them, and the transform is its own inverse — also tested, because getting it wrong
puts windows off-screen on multi-display setups.

**Finder cut/paste without touching your files.** MacToys never moves anything
itself. `⌘X` is rewritten to `⌘C` plus a flag, and the following `⌘V` becomes
`⌘⌥V` — Finder's own *Move Item Here*. Finder does the work, so conflict handling,
the progress sheet and undo all behave normally. Copying something else cancels the
pending move, as it does in Explorer.

**Hotkeys without permissions.** Carbon's `RegisterEventHotKey` is the only public
API that delivers a shortcut to a background app *and* swallows it, without
Accessibility. It's why the clipboard picker works the moment you launch.

**The event tap stays cheap.** macOS silently disables a keyboard tap that responds
too slowly, so the callback never makes cross-process calls — the frontmost app is
cached from a workspace notification instead. It also rewrites `keyUp` as well as
`keyDown`, or apps would wait forever for the release of a key they never saw pressed.

**Losing nothing on logout.** `applicationWillTerminate` is not called for a
`SIGTERM`, which is what macOS sends agents at shutdown. A dispatch signal source
catches it and flushes history first.

**Knowing which clipboard change was yours.** macOS will not tell you who wrote to
the pasteboard, so the app has to recognise its own writes when it pastes from
history. An early version set a "skip the next change" flag *and* fast-forwarded its
counter, so the flag was never consumed and silently swallowed the next thing you
copied. That bookkeeping now lives in `PasteboardGate` in the core module, with a
named regression test for exactly that sequence.

**Upgrading without resetting your settings.** Synthesised `Codable` rejects a JSON
file that is missing any field, so adding a single preference would have wiped every
choice the user had made. `Preferences` decodes field by field with per-field
fallbacks, and merges new default shortcuts into existing ones rather than replacing
them.

**Losing most of a swipe.** The first version rate-limited volume changes to one
every 35 ms — but trackpad frames arrive every ~12 ms, and the limiter simply
returned, while the recogniser had already counted those steps as delivered. They
were gone for good, so a quick swipe moved the volume roughly a quarter of the
distance it should have. Steps are now carried over to the next frame instead of
dropped, and direction is locked once a gesture proves itself vertical, so a
sideways wobble halfway through no longer stalls it.

**Volume by trackpad, without permissions.** Changing the volume by synthesising
the media keys would give the native HUD for free, but posting system events needs
Accessibility. CoreAudio needs nothing at all, so the gesture works on a fresh
install and MacToys draws its own HUD instead.

**Reading the trackpad is the unsupported part.** There is no public API: `NSEvent`
gestures only arrive for the focused window, and macOS consumes four-finger swipes
before any app sees them. `MultitouchSupport` — the private framework
BetterTouchTool and Jitouch use — is the only route, so it is treated as untrusted.
It is `dlopen`ed rather than linked, so a macOS that drops it disables one feature
instead of breaking the app; only the finger count (a plain callback argument) and
the first touch's position (a fixed offset) are read, so nothing depends on
`sizeof(MTTouch)`; and coordinates are range-checked, with the feature switching
itself off if they stop looking like the documented 0...1 values.

**What it cannot do.** Reading the trackpad is passive — MacToys cannot take a
gesture away from macOS. With four fingers selected, a swipe changes the volume
*and* opens Mission Control. Freeing that up in System Settings › Trackpad › More
Gestures is a manual step, which is why the feature ships switched off.

**The delete key that wasn't.** `⌘⌫` in the clipboard picker used to do nothing.
Cocoa text fields don't send `deleteBackward(_:)` for `⌘⌫` the way you'd expect —
they send `deleteToBeginningOfLine(_:)`, the same selector as plain `⌘Backspace`
in TextEdit. The handler was checking the wrong selector, so the field silently
ran its own default edit instead of deleting the highlighted item.

## Architecture

```
Sources/
  MacToysCore/        Pure logic. No AppKit, no permissions, no I/O.
    Keys.swift            Shortcut parsing, key codes, modifier sets
    SnapGeometry.swift    Tiling maths, cycling, coordinate flips, display moves
    ClipboardStore.swift  Ring buffer, dedupe, pinning, ranked search, privacy rules
    PasteboardGate.swift  Which clipboard changes are ours vs. a real copy
    RemapRules.swift      The whole key-remapping policy as one pure function
    ColorFormatting.swift Colour conversion and output formats
    VolumeGesture.swift   Trackpad swipe -> volume steps, with direction locking
    OCRTextAssembler.swift Rejoining recognised lines into readable text
    Preferences.swift     Config, validation, upgrades, atomic persistence
  MacToys/            The app. AppKit, Carbon, Accessibility, CGEventTap.
  MacToysSelfTest/    The test suite.
```

The split is the point: all the logic worth testing lives in `MacToysCore` and
depends on nothing, so it can be exercised headlessly. `RemapRules.outcome` decides
every keystroke rewrite and is a pure function of `(keystroke, frontmost app,
config)` — no event tap needed to test it.

## Testing

```bash
make test
```

122 tests, 262 assertions, no permissions and no GUI required. XCTest ships with
Xcode rather than the Command Line Tools, so the suite is a plain executable that
exits non-zero on failure — which also makes it trivial to run in CI.

Covered: shortcut parsing and rejection of malformed specs; exact tiling of halves,
thirds and quarters; gap arithmetic; snap cycling with tolerance for apps that
resize in steps; coordinate-flip involution; multi-display selection and clamping;
clipboard dedupe, pin-aware eviction, ranked search and round-trip persistence;
password-manager exclusion; every remap rule including app exclusions and the
`fn` modifier laptops add to `Home`/`End`; config clamping and fallback; the
pasteboard-ownership state machine including the swallowed-copy regression;
colour conversion including out-of-gamut clamping; OCR line rejoining; history
resizing; loading a config file written by an older version; and the volume
gesture, including that a sideways four-finger swipe (macOS switching Spaces)
never changes the volume, that resting fingers do not drift it, and that holding
still after a swipe stops rather than continuing, and that an identical swipe
moves the volume the same amount whether performed quickly or slowly.

## Releasing

Tag it and CI does the rest:

```bash
git tag v1.0.1 && git push origin v1.0.1
```

`.github/workflows/release.yml` runs the tests, builds and signs the bundle,
stamps the tag as the version, zips it with `ditto` (which preserves the code
signature — plain `zip` does not), publishes the GitHub release, and points
`Casks/mactoys.rb` at the new zip and its SHA.

### The signing certificate, and why it matters

macOS ties Accessibility and Screen Recording grants to an app's code signature.
An ad-hoc signature is different on every single build, so a user who updates an
ad-hoc release silently loses every permission they granted — while the
checkboxes in System Settings still look switched on. It is a miserable bug to
diagnose because nothing appears wrong.

So every release is signed with one certificate that never changes, created once
by `Scripts/create-release-identity.sh` and held in two repository secrets:

| Secret | What it is |
|---|---|
| `MACTOYS_SIGNING_CERT_P12` | base64 of the `.p12` |
| `MACTOYS_SIGNING_CERT_PASSWORD` | the password protecting it |

`bundle.sh` quietly falls back to ad-hoc signing when it cannot find the
identity, which is right for a local build and wrong for a release — so the
workflow asserts the shipped bundle really was signed with `MacToys Release` and
fails the build otherwise, rather than shipping something that resets everyone's
permissions a month later.

Losing that certificate is not fatal, but the next release signs under a new
identity and everyone re-grants permissions once. Keep the `.p12`.

This is a self-signed certificate, not an Apple Developer ID. It fixes the
permissions problem but not Gatekeeper: first launch still warns that the
developer cannot be verified, and only Apple's $99/year programme removes that.
The two are independent — this is the half that is free.

## Limitations

- **Full-screen windows can't be snapped.** macOS gives them their own Space and
  ignores placement. MacToys tells you instead of failing silently.
- **Some apps refuse to resize.** Apps with fixed or stepped window sizes (terminals,
  some editors) land a few pixels off. That's counted as success.
- **`Home`/`End` is skipped in terminals and editors** — they already do the right
  thing, and rewriting would break them. The list is `homeEndExcludedApps` in
  `preferences.json`.
- **Source attribution is a guess.** macOS doesn't record which app wrote to the
  pasteboard, so MacToys infers it from what was frontmost.
- **Ad-hoc signing** means the Accessibility grant resets on every rebuild.
- **OCR is offered in one language at a time** (English by default). Change
  `ocrLanguages` in `preferences.json` to any language Vision supports.
- **Always-on-top is deliberately absent.** macOS exposes no public API for it, and
  the private one breaks between releases.
- **The volume gesture cannot suppress Mission Control.** See above; either free
  the four-finger swipe in System Settings or use three fingers.
- **Some outputs have no software volume.** Certain HDMI and external DACs expose
  no adjustable level; the gesture does nothing there, as does the volume key.
