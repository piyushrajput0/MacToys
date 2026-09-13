#!/usr/bin/env bash
# Builds MacToys and assembles a runnable .app bundle.
#
# SwiftPM produces a bare executable; a menu-bar agent needs a real bundle so it
# has a bundle identifier (which is what macOS ties Accessibility permission to)
# and LSUIElement (which keeps it out of the Dock).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP_NAME="MacToys"
BUNDLE_ID="com.mactoys.MacToys"
VERSION="1.0.0"

cd "$ROOT"
echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --product "$APP_NAME"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
[ -x "$BIN" ] || { echo "build produced no executable at $BIN" >&2; exit 1; }

APP="$ROOT/dist/$APP_NAME.app"
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>        <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <!-- Menu-bar agent: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key>               <true/>
    <key>NSHumanReadableCopyright</key>  <string>MIT Licensed</string>
    <!-- Shown in the permission dialogs macOS raises for these features. -->
    <key>NSAppleEventsUsageDescription</key>
    <string>MacToys uses this to snap and move windows for you.</string>
</dict>
</plist>
PLIST

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# macOS ties Accessibility and Screen Recording grants to the code signature.
# An ad-hoc signature changes on every rebuild, so every rebuild silently
# revokes them. If Scripts/create-signing-identity.sh has been run there is a
# stable certificate to use instead, and grants then survive rebuilds.
IDENTITY="MacToys Self-Signed"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "==> Signing with '$IDENTITY' (permissions persist across rebuilds)"
    codesign --force --sign "$IDENTITY" --timestamp=none "$APP" 2>&1 | sed 's/^/    /' || true
else
    echo "==> Signing (ad-hoc — permissions will reset on each rebuild)"
    echo "    Run Scripts/create-signing-identity.sh once to stop that."
    codesign --force --sign - --timestamp=none "$APP" 2>&1 | sed 's/^/    /' || true
fi

echo "==> Built $APP"
