cask "mactoys" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/piyushrajput0/MacToys/releases/download/v#{version}/MacToys-#{version}.zip"
  name "MacToys"
  desc "Clipboard history, snip, OCR, window snapping — the Windows features macOS never shipped"
  homepage "https://github.com/piyushrajput0/MacToys"

  depends_on macos: ">= :ventura"

  app "MacToys.app"

  uninstall quit: "com.mactoys.MacToys"

  zap trash: [
    "~/Library/Application Support/MacToys",
  ]

  caveats <<~CAVEATS
    MacToys is signed, but not with a $99/year Apple Developer certificate, so
    macOS will say the developer cannot be verified the first time you open it.
    Go to System Settings -> Privacy & Security, scroll down, and click
    "Open Anyway". You only do this once.

    To skip that step entirely, reinstall with:
      brew install --cask --no-quarantine mactoys

    Window snapping and the remapped keys need Accessibility; snip and OCR need
    Screen Recording. Everything else works without granting anything.
  CAVEATS
end
