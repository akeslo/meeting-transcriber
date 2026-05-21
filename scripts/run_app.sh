#!/usr/bin/env bash
# Launch the Meeting Transcriber menu bar app.
# Builds an .app bundle so macOS APIs (notifications, etc.) work correctly.
#
# --build-only: Build the bundle but skip `open -W`. Used by the Pattern-C
#   E2E driver (scripts/e2e-app.sh) which deploys the bundle to a stable
#   path and launches it itself; opening the in-tree bundle there would
#   confuse macOS LaunchServices about which one to use for TCC.
# --fast: Skip the .build wipe and rely on incremental swift build. Faster
#   iteration; combine with the dev keychain cert (see setup-self-hosted-runner.sh)
#   to keep TCC permissions persistent across rebuilds — TCC keys by cert
#   leaf SHA-1 for self-signed certs, so the cdhash can change freely without
#   re-prompting Mic / Screen Recording grants.

set -euo pipefail

BUILD_ONLY=false
FAST=false
for arg in "$@"; do
    case "$arg" in
        --build-only) BUILD_ONLY=true ;;
        --fast) FAST=true ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRANSCRIBER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export TRANSCRIBER_ROOT

SPM_DIR="$TRANSCRIBER_ROOT/app/MeetingTranscriber"
BUILD_BINARY="$SPM_DIR/.build/release/MeetingTranscriber"
APP_BUNDLE="$SPM_DIR/.build/MeetingTranscriber-Dev.app"
APP_MACOS="$APP_BUNDLE/Contents/MacOS"
APP_BINARY="$APP_MACOS/MeetingTranscriber"
INFO_PLIST="$SPM_DIR/Sources/Info.plist"

# Kill any running instance
if pgrep -x "MeetingTranscriber" > /dev/null 2>&1; then
    echo "Killing existing MeetingTranscriber instance..."
    pkill -x "MeetingTranscriber" || true
    sleep 1
fi

# Clean stale build artifacts (skipped in --fast mode for incremental rebuilds)
if [ "$FAST" = true ]; then
    echo "Fast mode — skipping .build wipe (incremental rebuild)"
else
    echo "Cleaning build artifacts..."
    rm -rf "$SPM_DIR/.build"
fi

echo "Building Meeting Transcriber app..."
cd "$SPM_DIR"
swift build -c release

# Assemble .app bundle
mkdir -p "$APP_MACOS"
# Use dev bundle identifier to keep permissions separate from release
sed 's/com\.meetingtranscriber\.app/com.meetingtranscriber.dev/' \
    "$INFO_PLIST" > "$APP_BUNDLE/Contents/Info.plist"

# Inject version from VERSION file
APP_VERSION=$(cat "$TRANSCRIBER_ROOT/VERSION" | tr -d '[:space:]')
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_BUNDLE/Contents/Info.plist"

# Inject git commit hash into Info.plist
GIT_HASH=$(git -C "$TRANSCRIBER_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
/usr/libexec/PlistBuddy -c "Add :GitCommitHash string $GIT_HASH" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :GitCommitHash $GIT_HASH" "$APP_BUNDLE/Contents/Info.plist"

cp "$BUILD_BINARY" "$APP_BINARY"

# Build app icon: compile Assets.xcassets PNGs → AppIcon.icns via iconutil
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

# Code-sign so macOS keeps Screen Recording / Mic permissions across rebuilds.
# Prefer the dev self-signed cert created by setup-self-hosted-runner.sh —
# TCC keys by cert leaf SHA-1 for self-signed certs, so the cdhash can change
# on every rebuild without re-prompting permission grants.
DEV_CERT_NAME="MeetingTranscriberDevSelfHosted"
SIGN_HASH=$(security find-identity -v -p codesigning | grep "$DEV_CERT_NAME" | head -1 | awk '{print $2}')
if [ -z "$SIGN_HASH" ]; then
    SIGN_HASH=$(security find-identity -v -p codesigning | head -1 | awk '{print $2}')
fi
if [ -n "$SIGN_HASH" ]; then
    codesign --force --sign "$SIGN_HASH" "$APP_BUNDLE" 2>/dev/null && \
        echo "  Signed with: $SIGN_HASH"
else
    echo "  WARNING: no codesigning identity found — signing ad-hoc."
    echo "  macOS TCC will re-prompt Mic / Screen Recording on every rebuild."
    echo "  Run ./scripts/setup-self-hosted-runner.sh once to create a stable dev cert."
    codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true
fi

if [ "$BUILD_ONLY" = true ]; then
    echo "Bundle ready: $APP_BUNDLE"
    exit 0
fi

echo "Starting Meeting Transcriber..."
echo "  TRANSCRIBER_ROOT=$TRANSCRIBER_ROOT"

# Launch via `open` so macOS LaunchServices properly registers the app
# (required for notification permissions, etc.).
# The app discovers the project root by walking up from the executable.
open -W "$APP_BUNDLE"
