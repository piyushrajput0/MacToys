# Contributing

Bug reports are as useful as patches — the issue forms ask for a Diagnostics
report because it usually answers the question on its own.

## Building

Xcode is not required. The Command Line Tools are enough.

```bash
git clone https://github.com/piyushrajput0/MacToys.git
cd MacToys
make test   # 126 tests, no GUI and no permissions needed
make app    # builds dist/MacToys.app without installing it
make run    # builds and launches it
```

Run `make cert` once if you are going to rebuild repeatedly. macOS ties
Accessibility and Screen Recording grants to the code signature, and an ad-hoc
signature changes on every build — so without it, every rebuild silently revokes
the permissions you granted while System Settings still shows them switched on.

## Where code goes

Two targets, and the split is the thing to understand:

- **`Sources/MacToysCore`** — pure logic. No AppKit, no permissions, no
  singletons. Snap geometry, clipboard storage, OCR line assembly, remap rules,
  colour formatting, the pasteboard gate. All of it runs headless, so all of it
  is tested.
- **`Sources/MacToys`** — the AppKit app. Windows, hotkeys, event taps, menu bar.

When you add something, push as much of it as you can into `MacToysCore` and
leave a thin shell in `MacToys`. Anything with a decision in it — which zone a
window snaps to, whether a pasteboard should be recorded, how OCR fragments join
into lines — belongs in Core where it can be tested without a GUI.

## Tests

`Sources/MacToysSelfTest` is a plain executable, not XCTest, because XCTest does
not ship with the Command Line Tools and the whole point is that this builds
without Xcode. It exits non-zero on failure, so CI just runs it.

Add tests for anything in Core. `make test` must pass before a PR.

## Two hard rules

- **No dependencies.** `Package.swift` has none and will keep having none.
- **No network code.** Not telemetry, not crash reporting, not an update check.
  This is a clipboard manager; the README promises nothing leaves your Mac, and
  that promise is worth more than any feature.

## Style

Match the code around you. It is written to be read: comments explain *why*
something is the way it is, especially where macOS forced the shape of it, and
not what the next line does.

## Pull requests

Small and single-purpose is easier to review than large and comprehensive. Say
what you tested by hand — most of this app cannot be tested any other way, and
"I snapped windows on two displays" is genuinely useful to know.

See [docs/ENGINEERING.md](docs/ENGINEERING.md) for how the trickier parts work
and why.
