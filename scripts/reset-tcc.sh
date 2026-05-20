#!/usr/bin/env bash
# Reset TCC permissions for all MeetingTranscriber build variants.
# Run this when accumulated dev builds clutter System Settings → Privacy.
set -euo pipefail

BUNDLE_IDS=(
    "com.meetingtranscriber.app"         # stable / Homebrew
    "com.meetingtranscriber.dev"         # dev build (run_app.sh)
    "com.meetingtranscriber.app.appstore" # App Store variant
)

SERVICES=(
    Microphone
    ScreenCapture   # Screen Recording
    Accessibility
    SystemPolicyAllFiles
)

for bundle_id in "${BUNDLE_IDS[@]}"; do
    for service in "${SERVICES[@]}"; do
        echo "  reset $service  $bundle_id"
        tccutil reset "$service" "$bundle_id" 2>/dev/null || true
    done
done

echo "Done. Re-launch the app to re-grant permissions."
