<div align="center">

<img src="Resources/icon-preview.png" width="120" alt="MacToys">

# MacToys

**The Windows features macOS never shipped — for people who just switched.**

Clipboard history · Screenshot to clipboard · Screen OCR · Colour picker · Aero-Snap tiling · Trackpad volume gesture · Windows keyboard behaviour

A single menu-bar app. No dependencies. No account. Nothing leaves your Mac.

</div>

---

## Why this exists

Switching from Windows to macOS, the hardware is lovely and then a dozen reflexes
stop working. Not big things — small ones, many times a day:

| You press | On Windows | On a Mac |
|---|---|---|
| `Win`+`V` | Your last 25 clipboard items | *Nothing. macOS has no clipboard history at all.* |
| `Win`+`Shift`+`S` | Screenshot lands on the clipboard, ready to paste | `⌘⇧4` drops a PNG on your Desktop instead |
| `Win`+`←` | Window snaps to the left half | Nothing. The green button throws you into a separate Space |
| `Home` / `End` | Jump to start / end of the line | Scrolls the whole document instead |
| `Ctrl`+`X` on a file | Cut, then paste to move it | Finder has no cut. The move is `⌘C` then `⌘⌥V` — undiscoverable |
| `Delete` on a file | Deletes it | Nothing. It's `⌘⌫` |
| `Ctrl`+`Shift`+`V` | Paste without formatting | Only some apps, under different shortcuts |
| PowerToys `Win`+`Shift`+`T` | Grab text off the screen with OCR | Live Text works in Photos and Preview only |
| Four fingers up/down | Change the volume | No equivalent — the gesture is Mission Control instead |

None of these are missing because they're hard. They're missing because Apple made
different choices, and there's no built-in way to choose otherwise. MacToys puts
them back, on the keys you already know.

## What it does

Everything is keyboard-first and runs from the menu bar.

| Feature | Shortcut | Notes |
|---|---|---|
| **Clipboard history** | `⇧⌘V` | Searchable, pinnable. Text, images and files. Keeps the last 15 by default — pin anything you want to keep longer, or raise the limit in Settings (up to 1000). |
| **Snip to clipboard** | `⇧⌘S` | Drag a region → straight onto the clipboard. |
| **Extract text (OCR)** | `⌃⌥T` | Drag over anything on screen; the text lands on your clipboard. Runs on-device. |
| **Colour picker** | `⌃⌥K` | Magnified loupe, copies as hex, `rgb()`, `hsl()`, SwiftUI or NSColor. |
| **Paste as plain text** | `⇧⌥⌘V` | Strips fonts, colours and links from whatever you copied. |
| **Snap left / right** | `⌃⌥←` `⌃⌥→` | Press again to cycle ½ → ⅓ → ⅔. |
| **Maximize / centre** | `⌃⌥↑` `⌃⌥↓` | A real maximize, not full-screen-in-its-own-Space. |
| **Snap to a corner** | `⌃⌥1`–`⌃⌥4` | |
| **Move to next display** | `⌃⌥⇧→` | Keeps the window's relative size and position. |
| **Windows `Home`/`End`** | `Home` `End` | Line start/end. `Ctrl` versions jump to document start/end. |
| **Cut & paste files** | `⌘X` then `⌘V` | In Finder. Uses Finder's own move, so undo still works. |
| **Delete a file** | `⌦` | In Finder. |
| **Volume gesture** | 4 fingers ↑↓ | Windows 11's "Change audio and volume". Speed is adjustable; a normal swipe covers the full range. Off by default — see below. |
| **Keep awake** | menu | Like PowerToys Awake. |
| **Settings** | `⌘,` from the menu | Every option, plus a click-and-press shortcut recorder. |

The clipboard picker takes `↑``↓` to move, `⏎` to paste, `⌘1`–`⌘9` to grab an item
directly, `⌘P` to pin, `⌘⌫` to delete, `esc` to dismiss. Just type to filter.

## Install

Requires macOS 13 or later. Xcode is **not** needed — the Command Line Tools are enough.

```bash
git clone https://github.com/piyushrajput0/MacToys.git
cd MacToys
make install        # builds, bundles, and copies to /Applications
open /Applications/MacToys.app
```

Or build without installing:

```bash
make app && open dist/MacToys.app
```

`make test` runs the test suite. `make clean` removes build output.

Settings live in the menu bar icon → **Settings…**, including a shortcut recorder
(click a binding, press the keys you want). Everything is also plain JSON at
`~/Library/Application Support/MacToys/preferences.json` if you prefer.

MacToys lives in the menu bar — there's no Dock icon. Opening it (a fresh
launch, or double-clicking it again while it's already running) always shows
the Settings window, so you can immediately see everything it does; the cheat
sheet opens alongside it the first time you run it. Everything is also reachable
from the menu bar icon at any time.

## Permissions — and what works without them

Most of MacToys needs **nothing at all**:

| Works immediately | Needs Accessibility |
|---|---|
| Clipboard history | Window snapping |
| Snip to clipboard | Move window to next display |
| Colour picker, volume gesture | Windows `Home`/`End` |
| Keep awake, settings, cheat sheet | Finder cut/paste and `⌦` |

Snip and text extraction use `screencapture`, so the first time you use either,
macOS will ask for **Screen Recording** — the same prompt any screenshot tool
triggers. Recognition itself runs on-device through Apple's Vision framework; no
image ever leaves your Mac.

Accessibility is required for the second column because macOS does not let one app
move another app's windows, or observe keystrokes, without explicit consent — which
is a good rule. It's a normal software permission (Rectangle, Raycast and Alfred all
ask for the same one) and it is granted per-app in
**System Settings › Privacy & Security › Accessibility**.

If you'd rather not grant it, the first column still works and MacToys will never
nag you — it just tells you once, at the moment you press a shortcut that needs it.

> **Rebuilding resets both permissions.** Accessibility and Screen Recording are
> both tied to the app's code signature. This project signs ad-hoc, so the
> signature changes on every build and macOS treats each rebuild as a new app —
> a grant given to yesterday's build does not carry over to today's, even though
> the entry can sit there checked in Settings and look like it should still work.
> If a feature says it needs a permission you're sure you already granted: open
> the relevant Settings pane, remove MacToys from the list (select it, click
> "–"), quit MacToys completely, reopen it, and allow it again when asked. Doing
> this from `make install` matters less than doing it *after every rebuild* —
> MacToys will tell you which permission and pane, at the point you hit it.

## Privacy

A clipboard manager sees everything you copy, so this one is deliberately careful:

- **Nothing leaves your Mac.** There is no network code in this repository.
- **Passwords are skipped.** Pasteboards flagged `org.nspasteboard.ConcealedType` —
  the convention password managers use — are never recorded, and copies made in
  1Password, Bitwarden, Dashlane, Enpass, LastPass, Keychain Access and Apple
  Passwords are ignored by bundle identifier.
- **History is a plain file** at
  `~/Library/Application Support/MacToys/clipboard-history.json`.
  It is not encrypted. Delete it, or use *Clear Clipboard History* in the menu, whenever
  you like. Set `persistClipboardHistory` to `false` in `preferences.json` next to it
  to keep history in memory only.

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

116 tests, 249 assertions, no permissions and no GUI required. XCTest ships with
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

## License

MIT — see [LICENSE](LICENSE).
