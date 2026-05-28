#!/usr/bin/env bash
# Builds AudioLeak.app, installs to /Applications/, signs with a
# stable self-signed cert so TCC grants (Mic, Screen Recording) persist
# across rebuilds without re-prompting.
#
# First run creates the cert + keychain, then pauses and asks you to
# trust the cert in a GUI Terminal. Re-run after trusting — it picks up
# where it left off and finishes the build + install.
#
# Re-running is safe: cert + keychain are only recreated if missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPM_DIR="$ROOT/app/MeetingTranscriber"

CERT_NAME="MeetingTranscriberDevSelfHosted"
CERT_ORG="meetingtranscriber-self-hosted"
DEV_KEYCHAIN="$HOME/Library/Keychains/meetingtranscriber-dev.keychain-db"
DEV_KEYCHAIN_PASS=""

BUILD_BINARY="$SPM_DIR/.build/release/MeetingTranscriber"
APP_BUNDLE="$SPM_DIR/.build/AudioLeak.app"
APP_MACOS="$APP_BUNDLE/Contents/MacOS"
APP_BINARY="$APP_MACOS/MeetingTranscriber"
INFO_PLIST="$SPM_DIR/Sources/Info.plist"
INSTALL_PATH="/Applications/AudioLeak.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

ARTIFACTS_DIR="/tmp/meetingtranscriber-setup"
CERT_PATH="$ARTIFACTS_DIR/dev-cert.crt"

log()  { printf '[build] %s\n' "$*"; }
fail() { printf '[build] FAIL: %s\n' "$*" >&2; exit 1; }

# Inline keychain-prepend: add $1 to front of user keychain search list.
prepend_keychain() {
    local keychain="$1"
    local lockfile="${TMPDIR:-/tmp}/keychain-search-list.lock"
    for _ in $(seq 1 100); do
        if shlock -f "$lockfile" -p $$ >/dev/null 2>&1; then
            trap "rm -f '$lockfile'" EXIT
            break
        fi
        sleep 0.05
    done
    [[ -f "$lockfile" ]] || fail "could not acquire keychain lock"
    local existing=()
    while IFS= read -r entry; do
        existing+=("$entry")
    done < <(
        security list-keychains -d user \
            | awk -v skip="$keychain" '
                {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                    gsub(/^"|"$/, "")
                    if ($0 != "" && $0 != skip) print
                }
            '
    )
    security list-keychains -d user -s "$keychain" "${existing[@]+"${existing[@]}"}"
}

# --- 1. Cert ------------------------------------------------------------

if [ -f "$DEV_KEYCHAIN" ] \
    && security find-identity -p codesigning "$DEV_KEYCHAIN" 2>/dev/null \
        | grep -q "$CERT_NAME"; then
    if [ ! -f "$CERT_PATH" ]; then
        log "Re-exporting cert from dev keychain → $CERT_PATH"
        mkdir -p "$ARTIFACTS_DIR" && chmod 0755 "$ARTIFACTS_DIR"
        security find-certificate -c "$CERT_NAME" -p "$DEV_KEYCHAIN" > "$CERT_PATH" \
            || fail "could not export cert from $DEV_KEYCHAIN"
        chmod 0644 "$CERT_PATH"
    else
        log "Cert '$CERT_NAME' already in dev keychain — skipping creation"
    fi
else
    log "Creating self-signed code-signing cert '$CERT_NAME'"
    TMPD="$(mktemp -d)"
    trap 'rm -rf "$TMPD"' EXIT

    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -subj "/CN=$CERT_NAME/O=$CERT_ORG" \
        -keyout "$TMPD/cert.key" -out "$TMPD/cert.crt" \
        -addext "keyUsage = critical, digitalSignature" \
        -addext "extendedKeyUsage = critical, codeSigning" \
        -addext "basicConstraints = critical, CA:false" >/dev/null 2>&1 \
        || fail "openssl req failed"

    openssl pkcs12 -export -legacy \
        -inkey "$TMPD/cert.key" -in "$TMPD/cert.crt" \
        -name "$CERT_NAME" -passout pass:dev -out "$TMPD/cert.p12" \
        || fail "openssl pkcs12 failed"

    if [ -f "$DEV_KEYCHAIN" ]; then
        log "Removing stale dev keychain"
        security delete-keychain "$DEV_KEYCHAIN" 2>/dev/null || true
    fi
    log "Creating dedicated keychain at $DEV_KEYCHAIN"
    security create-keychain -p "$DEV_KEYCHAIN_PASS" "$DEV_KEYCHAIN"
    security set-keychain-settings "$DEV_KEYCHAIN"
    security unlock-keychain -p "$DEV_KEYCHAIN_PASS" "$DEV_KEYCHAIN"
    prepend_keychain "$DEV_KEYCHAIN"

    log "Importing cert into dev keychain"
    security import "$TMPD/cert.p12" \
        -k "$DEV_KEYCHAIN" -P dev -A -t agg \
        || fail "security import failed"

    log "Setting partition list (codesign + apple tools)"
    security set-key-partition-list \
        -S "apple-tool:,apple:,codesign:" \
        -s -k "$DEV_KEYCHAIN_PASS" "$DEV_KEYCHAIN" >/dev/null \
        || fail "set-key-partition-list failed"

    mkdir -p "$ARTIFACTS_DIR" && chmod 0755 "$ARTIFACTS_DIR"
    cp "$TMPD/cert.crt" "$CERT_PATH" && chmod 0644 "$CERT_PATH"
    log "Cert .crt persisted at $CERT_PATH"

    rm -rf "$TMPD"
    trap - EXIT
fi

CERT_HASH="$(openssl x509 -in "$CERT_PATH" -noout -fingerprint -sha1 \
    | sed 's/^.*=//' | tr -d ':')"
[ -n "$CERT_HASH" ] || fail "could not extract cert SHA-1 from $CERT_PATH"
log "Cert SHA-1: $CERT_HASH"

CERT_TRUSTED=false
if security find-identity -v -p codesigning "$DEV_KEYCHAIN" 2>/dev/null \
        | grep -q "$CERT_NAME"; then
    CERT_TRUSTED=true
fi

if [ "$CERT_TRUSTED" = false ]; then
    cat <<MSG

[build] Phase 1 complete. ⏸  Cert generated but not yet trusted.

Run this one command in a GUI Terminal as user '$USER' (it pops a
TouchID / password prompt, can't be answered over SSH):

  security add-trusted-cert \\
      -r trustRoot -p codeSign \\
      -k "\$HOME/Library/Keychains/login.keychain-db" \\
      "$CERT_PATH"

Then re-run this script:

  bash $0

MSG
    exit 0
fi

# --- 2. Build -----------------------------------------------------------

if pgrep -x "MeetingTranscriber" > /dev/null 2>&1; then
    log "Killing existing MeetingTranscriber instance..."
    pkill -x "MeetingTranscriber" || true
    sleep 1
fi

log "Cleaning build artifacts..."
rm -rf "$SPM_DIR/.build" || rm -rf "$SPM_DIR/.build" 2>/dev/null || true

log "Building AudioLeak..."
cd "$SPM_DIR"
swift build -c release

# Assemble .app bundle
mkdir -p "$APP_MACOS"
sed 's/com\.meetingtranscriber\.app/com.meetingtranscriber.dev/' \
    "$INFO_PLIST" > "$APP_BUNDLE/Contents/Info.plist"

APP_VERSION=$(cat "$ROOT/VERSION" | tr -d '[:space:]')
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_BUNDLE/Contents/Info.plist"

GIT_HASH=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
/usr/libexec/PlistBuddy -c "Add :GitCommitHash string $GIT_HASH" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :GitCommitHash $GIT_HASH" "$APP_BUNDLE/Contents/Info.plist"

cp "$BUILD_BINARY" "$APP_BINARY"

ASSETS_DIR="$SPM_DIR/Sources/Assets.xcassets/AppIcon.appiconset"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
mkdir -p "$RESOURCES_DIR"
ICONSET_TMP=$(mktemp -d)
ICONSET_DIR="$ICONSET_TMP/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
cp "$ASSETS_DIR"/icon_*.png "$ICONSET_DIR/"
iconutil -c icns -o "$RESOURCES_DIR/AppIcon.icns" "$ICONSET_DIR" 2>/dev/null || \
    echo "  WARNING: iconutil failed — app will show generic icon"
rm -rf "$ICONSET_TMP"

# --- 3. Install to /Applications ----------------------------------------

log "Installing to $INSTALL_PATH ..."
mkdir -p /Applications
rm -rf "$INSTALL_PATH"
cp -R "$APP_BUNDLE" "$INSTALL_PATH"
rm -rf "$APP_BUNDLE"

# --- 4. Sign with stable cert -------------------------------------------

security unlock-keychain -p "$DEV_KEYCHAIN_PASS" "$DEV_KEYCHAIN" \
    || fail "could not unlock dev keychain"

log "Signing with $CERT_NAME"
codesign --force --sign "$CERT_HASH" \
    --keychain "$DEV_KEYCHAIN" \
    "$INSTALL_PATH" >/dev/null \
    || fail "codesign failed"

"$LSREGISTER" -f "$INSTALL_PATH" 2>/dev/null || true
log "Signed: $(codesign -dv "$INSTALL_PATH" 2>&1 | grep -E 'Identifier|Authority' | head -2 | tr '\n' ' ')"

cat <<MSG

[build] DONE. ✓
        Cert SHA-1 : $CERT_HASH
        Installed  : $INSTALL_PATH

If this is a first install, grant permissions in System Settings:
  → Privacy & Security → Microphone               → AudioLeak.app on
  → Privacy & Security → Screen & System Audio Recording → AudioLeak.app on

MSG

log "Launching $INSTALL_PATH ..."
open "$INSTALL_PATH"
