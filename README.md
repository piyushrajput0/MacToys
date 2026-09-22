<div align="center">

<img src="Resources/icon-preview.png" width="110" alt="MacToys">

# MacToys

**The Windows features macOS never shipped.**

Clipboard history · Screenshot to clipboard · Screen OCR · Colour picker<br>
Window snapping · Trackpad volume · Windows keyboard habits

One menu-bar app. No dependencies, no account, no network code.

</div>

---

## Install

Needs macOS 13 or newer.

```bash
brew tap piyushrajput0/mactoys https://github.com/piyushrajput0/MacToys
brew trust --cask piyushrajput0/mactoys/mactoys
brew install --cask mactoys
```

The middle line is Homebrew's doing, not mine: it will not install a cask from
anyone's personal tap until you say you trust that tap. It is asking a fair
question, so the answer is in the open — [Casks/mactoys.rb](Casks/mactoys.rb) is
twenty lines and CI is the only thing that ever writes to it.

Or [**download the latest release**][latest], unzip it, and drag `MacToys.app`
into your Applications folder.

MacToys then lives in the menu bar, and the Settings window opens on first
launch so you can see everything it does.

[latest]: https://github.com/piyushrajput0/MacToys/releases/latest

### The first-launch warning

macOS will say the developer cannot be verified. That is expected. MacToys is
signed — just not with the $99/year Apple certificate that would make the
warning go away. Open **System Settings → Privacy & Security**, scroll down, and
click **Open Anyway**. You only ever do this once.

To skip it, install with `brew install --cask --no-quarantine mactoys` instead.
That tells macOS not to flag the download, so read the source first if that
matters to you — it is 6,400 lines and there is no network code in any of them.

### Building it yourself

```bash
git clone https://github.com/piyushrajput0/MacToys.git
cd MacToys
make cert      # once: keeps permissions from resetting on every rebuild
make install   # builds and installs to /Applications
```

Xcode is not required — the Command Line Tools are enough. `make cert` creates a
local signing certificate so macOS stops forgetting the permissions you grant.
It asks for your password, stays on your machine, and gives nobody any access.
Skip it and everything still works; you will just re-grant permissions after
each rebuild.

## What you get

| Press | It does | On Windows this was |
|---|---|---|
| `⇧⌘V` | Clipboard history — searchable, pinnable | `Win`+`V` |
| `⇧⌘S` | Screenshot → clipboard *and* saved to your screenshots folder | `Win`+`Shift`+`S` |
| `⌃⌥T` | Grab text off the screen with OCR, on-device | PowerToys Text Extractor |
| `⌃⌥K` | Colour picker → hex, `rgb()`, `hsl()`, SwiftUI… | PowerToys Color Picker |
| `⇧⌥⌘V` | Paste without formatting | `Ctrl`+`Shift`+`V` |
| `⌃⌥` + arrows | Snap window left / right / maximize — press again for ⅓, ⅔ | `Win`+arrows |
| `⌃⌥1`–`4` | Snap to a corner | FancyZones |
| 4 fingers ↑↓ | Volume up / down on the trackpad | Win 11 touchpad gestures |
| `Home` / `End` | Jump to start / end of **line**, not the document | same |
| `⌘X` then `⌘V` | Actually move files in Finder | `Ctrl`+`X` / `Ctrl`+`V` |
| `⌦` | Send the selected file to the Trash | `Delete` |

In the clipboard picker: type to filter, `↑``↓` to move, `⏎` to paste,
`⌘1`–`⌘9` to grab one directly, `⌘P` to pin, `⌘⌫` to delete.

Every shortcut is rebindable in **Settings → Shortcuts** (click it, press the keys).

## Permissions

Most of it works with nothing granted. Two things need permission, because macOS
won't let any app do them otherwise:

- **Accessibility** — window snapping, and the `Home`/`End`, `⌘X`/`⌘V`, `⌦` keys
- **Screen Recording** — snip and OCR (the same prompt any screenshot tool triggers)

Not granting them is fine; the rest keeps working and MacToys won't nag.

**Something not working?** Menu bar → **Diagnostics**. It shows every feature,
whether it's genuinely running right now, and what to do about anything that isn't.

## Privacy

A clipboard manager sees everything you copy, so:

- **There is no network code in this repository.** Nothing leaves your Mac.
- Password managers are ignored, and pasteboards marked
  `org.nspasteboard.ConcealedType` are never recorded.
- History lives in a plain file you can delete any time:
  `~/Library/Application Support/MacToys/`. Turn off *Remember history* in
  Settings to keep it in memory only.

## Running in the background

Don't want another menu bar icon? **Settings → General → Menu bar** turns it off.
Every shortcut keeps working; open MacToys again any time to get back to Settings.

## Known issues

- **Four-finger swipes also trigger Mission Control**, because a passive reader
  can't take a gesture away from macOS. Either free it up in System Settings →
  Trackpad → More Gestures, or switch to three fingers in Settings → Trackpad.
- Some outputs (certain HDMI/external DACs) expose no software volume; the
  gesture can't change those.

## Development

```bash
make test   # 126 tests, no GUI or permissions needed
make app    # build without installing
```

The logic worth testing lives in `MacToysCore` and depends on nothing — no
AppKit, no permissions — so it runs headless. See
[docs/ENGINEERING.md](docs/ENGINEERING.md) for how the trickier parts work.

## License

MIT — see [LICENSE](LICENSE).
