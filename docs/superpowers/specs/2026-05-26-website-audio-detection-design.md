# Website Audio Detection Design

**Date:** 2026-05-26
**Status:** Approved

## Problem

`BrowserTabDetector` detects meetings by URL pattern match alone. This causes two issues:

1. Recording starts on any matching tab, even when no meeting audio is present (e.g., Google Meet tab open but no active call).
2. Recording continues until the tab closes. If the meeting ends but the tab stays open, recording runs indefinitely.

App detectors (`PowerAssertionDetector`) avoid both problems via IOKit power assertions — the assertion appears when a call starts and disappears when it ends. Websites have no equivalent signal, so audio is the proxy.

## Goals

- Require audio activity before committing to a recording for any website-detected meeting.
- Stop recording when audio has been silent for `asymmetricSilenceWarningSeconds`.
- Leave app-detected meeting behavior unchanged.
- Reuse existing settings, thresholds, and pure policy types.

## Data Model

Two new fields on `DetectedMeeting` (both default `false`):

```swift
let audioConfirmRequired: Bool
let audioSilenceStopEnabled: Bool
```

`BrowserTabDetector` sets both `true` on every `DetectedMeeting` it returns. All other detectors leave both `false`.

## RecordingProvider: `discard()` method

New method added to the `RecordingProvider` protocol and implemented on `DualSourceRecorder`:

```swift
func discard()
```

Stops capture (if running) and deletes all temp files without returning a `RecordingResult`. Called when audio-confirm fails. Avoids the caller having to call `stop()` and throw away the result while leaving orphaned temp files.

## Audio-Confirm Phase

New method on `WatchLoop`:

```swift
func waitForAudioConfirm(_ meeting: DetectedMeeting, recorder: any RecordingProvider) async throws -> Bool
```

Called from `handleMeeting` after the recorder starts, before `waitForMeetingEnd`.

**Logic:**
- Polls `recorder.appLevelDBFS` every `pollInterval`.
- Returns `true` as soon as app audio exceeds `-60 dBFS`.
- Returns `false` after `audioConfirmTimeout` (default 60s) with no audio detected.
- Also returns `false` if `detector.isMeetingActive(meeting)` goes false during the confirm window (tab closed before audio appeared).

**On `false`:**
- Call `recorder.discard()`.
- Log `audio_confirm_timeout` or `audio_confirm_tab_closed` at info level.
- Return from `handleMeeting` without enqueuing.
- `WatchLoop.watchLoop` calls `detector.reset(appName:)` as normal and resumes watching.

**`handleMeeting` flow after this change:**

```
start recorder
if meeting.audioConfirmRequired:
    confirmed = await waitForAudioConfirm(meeting, recorder)
    if !confirmed:
        recorder.discard()
        return
waitForMeetingEnd(meeting)
recording = recorder.stop()
enqueue
```

`audioConfirmTimeout` is a new `WatchLoop` init parameter (`TimeInterval`, default `60`). Tests inject a small value.

## Silence-Stop in `waitForMeetingEnd`

### `WatchLoopEndConfig` changes

New field:

```swift
let silenceStopSeconds: TimeInterval  // 0 = disabled; populated from asymmetricSilenceWarningSeconds
```

### `WatchLoopEndPolicy.step` changes

New inputs:

```swift
audioSilenceStopEnabled: Bool
audioSilent: Bool       // caller computes from recorder levels
silenceStart: Date?     // caller-held state, parallel to graceStart
```

New decision:

```swift
case stopSilenceExceeded
```

**Logic added to `step`:**

```
if audioSilenceStopEnabled && config.silenceStopSeconds > 0:
    if audioSilent:
        if silenceStart == nil: silenceStart = now
        if now - silenceStart >= config.silenceStopSeconds: return .stopSilenceExceeded
    else:
        silenceStart = nil
```

Silence-stop is independent of the URL-active / grace logic — whichever terminal condition fires first wins.

### `WatchLoop.waitForMeetingEnd` changes

New local state: `var silenceStart: Date?`

Computes `audioSilent` each tick:

```swift
let appSilent = activeRecorder?.appLevelDBFS ?? -120 <= -60
let micSilent = activeRecorder?.micLevelDBFS ?? -120 <= -60

let audioSilent: Bool
if meeting.noMicOverride == true {
    audioSilent = appSilent          // mic not recording — app channel only
} else {
    audioSilent = appSilent && micSilent  // both channels
}
```

Passes `audioSilent`, `silenceStart`, and updated `silenceStart` through `WatchLoopEndPolicy.step`.

`WatchLoopEndConfig` is populated with:

```swift
silenceStopSeconds: meeting.audioSilenceStopEnabled ? asymmetricSilenceWarningSeconds : 0
```

`asymmetricSilenceWarningSeconds` is passed into `WatchLoop` via a closure (like `verboseDiagnostics`) so it reads the live setting value at runtime.

## Silence threshold

`-60 dBFS` throughout — the same constant used by `ChannelHealthMonitor` and `SilentRecordingMonitor`. No new setting.

## Files to Change

| File | Change |
|------|--------|
| `MeetingDetecting.swift` | Add `audioConfirmRequired`, `audioSilenceStopEnabled` to `DetectedMeeting` |
| `BrowserTabDetector.swift` | Set both new fields `true` in returned `DetectedMeeting` |
| `DualSourceRecorder.swift` | Add `discard()` to `RecordingProvider` protocol + implement on `DualSourceRecorder` and `MockRecordingProvider` |
| `WatchLoop.swift` | Add `audioConfirmTimeout` param; add `waitForAudioConfirm`; update `handleMeeting`; update `waitForMeetingEnd` |
| `WatchLoopEndPolicy.swift` | Add `audioSilenceStopEnabled`, `audioSilent`, `silenceStart` inputs; add `.stopSilenceExceeded` decision |
| `AppState.swift` | Pass `asymmetricSilenceWarningSeconds` closure into `WatchLoop` init |

## Out of Scope

- Silence-stop for app-detected meetings (IOKit assertions handle those).
- Pre-recording lightweight audio tap (adds infrastructure complexity with no UX benefit over the confirm phase).
- Per-site configurable thresholds or timeouts.
