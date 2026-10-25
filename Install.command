#!/bin/bash
# Double-click this file in Finder to build VoiceInk and install it to /Applications.
# Run it again any time to update after pulling new code.
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Checking for Xcode..."
if ! xcodebuild -version >/dev/null 2>&1; then
    echo ""
    echo "Xcode is required to build the app (free on the Mac App Store)."
    echo "Install it, open it once to accept the license, then double-click Install.command again."
    open "macappstore://apps.apple.com/app/xcode/id497799835" || true
    read -r -p "Press Return to close..."
    exit 1
fi

if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    echo ""
    echo "Note: no Apple Development certificate found, so the app will be ad-hoc signed."
    echo "macOS may ask for Microphone/Accessibility permissions again after each update."
    echo "To avoid that: Xcode > Settings > Accounts > add your Apple ID > Manage Certificates > + Apple Development."
    echo ""
fi

echo "==> Building (the first build takes several minutes)..."
make local

echo "==> Installing to /Applications..."
osascript -e 'quit app "VoiceInk"' >/dev/null 2>&1 || true
sleep 1
rm -rf "/Applications/VoiceInk.app"
ditto "$HOME/Downloads/VoiceInk.app" "/Applications/VoiceInk.app"
rm -rf "$HOME/Downloads/VoiceInk.app"
xattr -cr "/Applications/VoiceInk.app"

echo "==> Launching..."
open "/Applications/VoiceInk.app"

echo ""
echo "Done. VoiceInk is in /Applications and running in your menu bar."
echo "Tip: set System Settings > Keyboard > 'Press globe key to' > Do Nothing, then pick Fn as the shortcut in VoiceInk."
read -r -p "Press Return to close..."
