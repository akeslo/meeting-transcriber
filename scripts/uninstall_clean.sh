#!/usr/bin/env bash
# Clean uninstall of MeetingTranscriber-Dev.app.
# Removes the app, resets TCC permissions, and clears app data.
#
# By default keeps user recordings/transcripts in ~/Documents/Transcriber/.
# Pass --purge-data to also delete that directory.

set -euo pipefail

APP_NAME="MeetingTranscriber"
DEV_BUNDLE_ID="com.meetingtranscriber.dev"
INSTALL_PATH="$HOME/Applications/MeetingTranscriber-Dev.app"
APP_SUPPORT="$HOME/Library/Application Support/MeetingTranscriber"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

PURGE_DATA=false
for arg in "$@"; do
    case "$arg" in
        --purge-data) PURGE_DATA=true ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

# 1. Kill running instance
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    echo "Killing running instance..."
    pkill -x "$APP_NAME" || true
    sleep 1
fi

# 2. Remove installed app
if [ -d "$INSTALL_PATH" ]; then
    echo "Removing $INSTALL_PATH ..."
    "$LSREGISTER" -u "$INSTALL_PATH" 2>/dev/null || true
    rm -rf "$INSTALL_PATH"
else
    echo "App not found at $INSTALL_PATH (already removed)"
fi

# 3. Reset TCC permissions
echo "Resetting TCC permissions for $DEV_BUNDLE_ID ..."
tccutil reset Microphone       "$DEV_BUNDLE_ID" 2>/dev/null && echo "  Microphone reset"        || echo "  Microphone — nothing to reset"
tccutil reset ScreenCapture    "$DEV_BUNDLE_ID" 2>/dev/null && echo "  Screen Recording reset"  || echo "  Screen Recording — nothing to reset"
tccutil reset Accessibility    "$DEV_BUNDLE_ID" 2>/dev/null && echo "  Accessibility reset"     || echo "  Accessibility — nothing to reset"
tccutil reset SystemPolicyAllFiles "$DEV_BUNDLE_ID" 2>/dev/null || true

# 4. Remove app data (Application Support)
if [ -d "$APP_SUPPORT" ]; then
    echo "Removing app data at $APP_SUPPORT ..."
    rm -rf "$APP_SUPPORT"
else
    echo "App data not found at $APP_SUPPORT (already removed)"
fi

# 5. Clear UserDefaults (preferences)
echo "Clearing preferences for $DEV_BUNDLE_ID ..."
defaults delete "$DEV_BUNDLE_ID" 2>/dev/null || echo "  No preferences found"

# 6. Clear caches
rm -rf "$HOME/Library/Caches/$DEV_BUNDLE_ID" 2>/dev/null || true

# 7. Optionally purge user recordings/transcripts
if [ "$PURGE_DATA" = true ]; then
    DATA_DIR="$HOME/Documents/Transcriber"
    if [ -d "$DATA_DIR" ]; then
        echo "Purging user data at $DATA_DIR ..."
        rm -rf "$DATA_DIR"
    else
        echo "No user data found at $DATA_DIR"
    fi
else
    echo "Keeping recordings at ~/Documents/Transcriber (pass --purge-data to remove)"
fi

echo ""
echo "Uninstall complete."
echo "Run ./scripts/run_app.sh to rebuild and reinstall a fresh copy."
