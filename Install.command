#!/bin/bash
# Double-click this file in Finder to build VoiceInk and install it to /Applications.
# Run it again any time to update after pulling new code.
set -euo pipefail

# Braces make bash read the whole script before running it, so the git pull below can safely update this file.
{

cd "$(dirname "$0")"

echo "==> Getting the latest version..."
# Builds can rewrite the strings catalog; discard that so the update applies cleanly.
git checkout -- VoiceInk/Localizable.xcstrings 2>/dev/null || true
git pull --ff-only || echo "Could not download updates; building the version already on this Mac."

echo "==> Checking for Xcode..."
if ! xcodebuild -version >/dev/null 2>&1; then
    echo ""
    echo "Xcode is required to build the app (free on the Mac App Store)."
    echo "Install it, open it once to accept the license, then double-click Install.command again."
    open "macappstore://apps.apple.com/app/xcode/id497799835" || true
    read -r -p "Press Return to close..."
    exit 1
fi

echo "==> Checking for the Metal Toolchain..."
if ! xcrun metal -v >/dev/null 2>&1; then
    echo "Downloading the Metal Toolchain (one-time, a few hundred MB)..."
    xcodebuild -downloadComponent MetalToolchain
fi

if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

echo "==> Checking for CMake..."
if ! command -v cmake >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        echo "Installing CMake with Homebrew..."
        brew install cmake
    else
        echo ""
        echo "CMake is required to build the speech engine, and it installs with Homebrew."
        echo "1. Install Homebrew by pasting the command shown on https://brew.sh into Terminal."
        echo "2. Double-click Install.command again. It will install CMake for you."
        open "https://brew.sh" || true
        read -r -p "Press Return to close..."
        exit 1
    fi
fi

# Signing with a certificate asks for the login keychain password. When that password
# isn't known, `touch ~/.voiceink-adhoc-signing` keeps every update on ad-hoc signing.
ADHOC_MARKER="$HOME/.voiceink-adhoc-signing"
if [ -f "$ADHOC_MARKER" ]; then
    export LOCAL_CODESIGN_IDENTITY="-"
fi

# An Apple Development certificate that's listed but not valid is usually missing Apple's
# WWDR G3 intermediate certificate, so the build would quietly fall back to ad-hoc signing.
if [ ! -f "$ADHOC_MARKER" ] \
    && ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development" \
    && security find-identity -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    echo "==> Adding Apple's intermediate certificate so your Apple Development certificate is trusted..."
    WWDR_CER="${TMPDIR:-/tmp}/AppleWWDRCAG3.cer"
    if curl -fsSL -o "$WWDR_CER" https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer; then
        security import "$WWDR_CER" -k "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || true
    fi
    rm -f "$WWDR_CER"
fi

# macOS ties permissions to the app's signature ("designated requirement"). Remember the installed
# app's one, so permissions are only reset when the new build's signature really differs.
OLD_REQUIREMENT=$(codesign -dr - "/Applications/VoiceInk.app" 2>/dev/null || true)

AD_HOC_SIGNED=false
if [ -f "$ADHOC_MARKER" ] || ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    AD_HOC_SIGNED=true
fi

echo "==> Building (the first build takes several minutes)..."
make local

if [ "$AD_HOC_SIGNED" = true ]; then
    echo "==> Signing with your local certificate so permissions survive updates..."
    if ./scripts/local-signing.sh sign "$HOME/Downloads/VoiceInk.app" "$PWD/VoiceInk/VoiceInk.local.entitlements"; then
        AD_HOC_SIGNED=false
    else
        echo "    The app stays ad-hoc signed; you'll need to turn it on again in Accessibility after this update."
    fi
fi

echo "==> Installing to /Applications..."
osascript -e 'quit app "VoiceInk"' >/dev/null 2>&1 || true
sleep 1
rm -rf "/Applications/VoiceInk.app"
ditto "$HOME/Downloads/VoiceInk.app" "/Applications/VoiceInk.app"
rm -rf "$HOME/Downloads/VoiceInk.app"
xattr -cr "/Applications/VoiceInk.app"
# Tell Finder and the Dock the app changed, so a new icon shows up right away.
touch "/Applications/VoiceInk.app"
NEW_REQUIREMENT=$(codesign -dr - "/Applications/VoiceInk.app" 2>/dev/null || true)
PERMISSIONS_RESET=false
if [ "$AD_HOC_SIGNED" = true ] || [ "$OLD_REQUIREMENT" != "$NEW_REQUIREMENT" ]; then
    # The old grants no longer match the new build but still look switched on. Clear them so VoiceInk asks again.
    tccutil reset Accessibility com.prakashjoshipax.VoiceInk >/dev/null 2>&1 || true
    tccutil reset ScreenCapture com.prakashjoshipax.VoiceInk >/dev/null 2>&1 || true
    PERMISSIONS_RESET=true
fi

# "Update My Whisper…" in the app runs this installer from here.
defaults write com.prakashjoshipax.VoiceInk MyWhisperRepoPath -string "$PWD"

echo "==> Setting up free local AI for meeting notes and text cleanup..."
setup_local_ai() {
    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew not found, skipping local AI. Meeting notes will only include the transcript."
        return 0
    fi
    command -v ollama >/dev/null 2>&1 || brew install ollama || return 1
    # Runs quietly in the background and starts again at login.
    brew services start ollama >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
        curl -s http://localhost:11434/api/tags >/dev/null 2>&1 && break
        sleep 1
    done

    # Bigger model only when the Mac has the memory for it.
    local ram_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
    local model="gemma3:4b"
    if [ "$ram_gb" -ge 24 ]; then
        model="gemma3:12b"
    fi
    echo "Downloading $model for ${ram_gb} GB of memory (one-time, a few GB)..."
    ollama pull "$model" || return 1

    local domain="com.prakashjoshipax.VoiceInk"
    # Meeting notes always fall back to this local model.
    defaults write "$domain" OllamaSelectedModel -string "$model"
    defaults write "$domain" ollamaSelectedModel -string "$model"

    local provider
    provider=$(defaults read "$domain" selectedAIProvider 2>/dev/null || echo "")
    # Only take over dictation cleanup when no AI provider was picked yet (Gemini is the untouched default).
    if [ -z "$provider" ] || [ "$provider" = "Gemini" ] || [ "$provider" = "Ollama" ]; then
        defaults write "$domain" selectedAIProvider -string "Ollama"
        echo "VoiceInk will use $model for meeting notes and Wispr-style cleanup."
    else
        echo "Meeting notes will use $model. Dictation keeps your AI provider ($provider)."
    fi
}
setup_local_ai || echo "Local AI setup didn't finish; run Install.command again to retry."

echo "==> Launching..."
open "/Applications/VoiceInk.app"

echo ""
echo "Done. VoiceInk is in /Applications and running in your menu bar."
if [ "$PERMISSIONS_RESET" = true ]; then
    echo "When macOS asks, turn VoiceInk on in Accessibility, then quit and reopen VoiceInk."
    if [ "$AD_HOC_SIGNED" = false ]; then
        echo "This should be the last time: future updates keep the permission."
    fi
else
    echo "Permissions were kept; nothing to turn on again."
fi
echo "Tip: set System Settings > Keyboard > 'Press globe key to' > Do Nothing, then pick Fn as the shortcut in VoiceInk."
read -r -p "Press Return to close..."
exit 0
}
