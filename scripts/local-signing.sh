#!/bin/bash
# Signs local builds with a self-made certificate that never changes, so macOS keeps
# Accessibility and Screen Recording permissions across updates.
#
# The certificate lives in its own keychain with a password this script creates and keeps in
# ~/.mywhisper/signing-password, so the login keychain password is never needed.
#
# Usage: scripts/local-signing.sh sign /path/to/VoiceInk.app /path/to/entitlements
# Exits non-zero (and leaves the app as it was) if anything fails.

set -uo pipefail

IDENTITY_NAME="My Whisper Local Signing"
STATE_DIR="$HOME/.mywhisper"
PASSWORD_FILE="$STATE_DIR/signing-password"
KEYCHAIN="$HOME/Library/Keychains/mywhisper-signing.keychain-db"
OPENSSL=/usr/bin/openssl

log() { echo "    $*"; }

identity_is_valid() {
    security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$IDENTITY_NAME\""
}

ensure_keychain() {
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"

    if [ ! -f "$KEYCHAIN" ] || [ ! -s "$PASSWORD_FILE" ]; then
        log "Creating a private keychain for the signing certificate..."
        rm -f "$KEYCHAIN"
        (umask 077 && "$OPENSSL" rand -hex 24 > "$PASSWORD_FILE") || return 1
        security create-keychain -p "$(cat "$PASSWORD_FILE")" "$KEYCHAIN" || return 1
    fi

    # No automatic locking, then unlock for this run.
    security set-keychain-settings "$KEYCHAIN" || return 1
    security unlock-keychain -p "$(cat "$PASSWORD_FILE")" "$KEYCHAIN" || return 1

    # codesign only finds identities in keychains on the user's search list.
    if ! security list-keychains -d user | grep -q "mywhisper-signing"; then
        local existing
        existing=$(security list-keychains -d user | xargs)
        # shellcheck disable=SC2086
        security list-keychains -d user -s "$KEYCHAIN" $existing || return 1
    fi
}

ensure_certificate() {
    if security find-certificate -c "$IDENTITY_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
        return 0
    fi

    log "Creating the signing certificate (one time)..."
    local work password
    work=$(mktemp -d) || return 1
    password=$(cat "$PASSWORD_FILE")

    cat > "$work/cert.cnf" <<CNF
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = ext
[ dn ]
CN = $IDENTITY_NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

    if ! "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
            -keyout "$work/key.pem" -out "$work/cert.pem" -config "$work/cert.cnf" >/dev/null 2>&1 \
        || ! "$OPENSSL" pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
            -name "$IDENTITY_NAME" -out "$work/identity.p12" -passout "pass:$password" >/dev/null 2>&1 \
        || ! security import "$work/identity.p12" -k "$KEYCHAIN" -P "$password" -T /usr/bin/codesign >/dev/null \
        || ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$KEYCHAIN" >/dev/null; then
        rm -rf "$work"
        return 1
    fi
    rm -rf "$work"
}

ensure_trust() {
    identity_is_valid && return 0

    local cert
    cert=$(mktemp) || return 1
    security find-certificate -c "$IDENTITY_NAME" -p "$KEYCHAIN" > "$cert" || { rm -f "$cert"; return 1; }

    echo ""
    echo "    macOS will now ask for your Mac login password ONE time, to trust the"
    echo "    certificate that keeps VoiceInk's permissions across updates."
    echo ""
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$cert"
    local status=$?
    rm -f "$cert"
    [ $status -eq 0 ] && identity_is_valid
}

sign_app() {
    local app="$1" entitlements="$2"
    [ -d "$app" ] || return 1
    [ -f "$entitlements" ] || return 1

    ensure_keychain || { log "Could not set up the signing keychain."; return 1; }
    ensure_certificate || { log "Could not create the signing certificate."; return 1; }
    ensure_trust || { log "The certificate was not trusted."; return 1; }

    # Work on a copy so a failure leaves the original ad-hoc build untouched.
    local copy="$app.signing"
    rm -rf "$copy"
    ditto "$app" "$copy" || return 1

    # Nested code first (frameworks, XPC services, helpers), keeping each one's own entitlements,
    # then the app itself with the app's entitlements.
    if codesign --force --deep --sign "$IDENTITY_NAME" --keychain "$KEYCHAIN" \
            --preserve-metadata=identifier,entitlements,flags,runtime "$copy" >/dev/null 2>&1 \
        && codesign --force --sign "$IDENTITY_NAME" --keychain "$KEYCHAIN" \
            --options runtime --entitlements "$entitlements" "$copy" >/dev/null 2>&1 \
        && codesign --verify --deep --strict "$copy" >/dev/null 2>&1; then
        rm -rf "$app"
        mv "$copy" "$app"
        log "Signed with \"$IDENTITY_NAME\"."
        return 0
    fi

    rm -rf "$copy"
    log "Signing failed; keeping the ad-hoc build."
    return 1
}

case "${1:-}" in
    sign)
        sign_app "${2:-}" "${3:-}"
        ;;
    *)
        echo "Usage: $0 sign /path/to/App.app /path/to/entitlements" >&2
        exit 2
        ;;
esac
