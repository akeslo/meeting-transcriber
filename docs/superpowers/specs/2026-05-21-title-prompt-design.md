# Title Prompt on Recording Stop

**Date:** 2026-05-21
**Status:** Approved for implementation

## Summary

When a meeting recording stops (auto-detected or manual), show a floating SwiftUI window asking the user to name the recording. Pipeline processing waits until the user confirms or skips. On skip or dismiss, the auto-detected title is used and the pipeline proceeds.

## State Model

Add to `WatchLoop`:

```swift
struct PendingTitleEntry {
    let suggestedTitle: String
    let appName: String
    let recording: DualSourceRecorder
}

var pendingTitle: PendingTitleEntry?
```

- `pendingTitle` is `nil` when nothing is waiting.
- Only one entry at a time. If a second recording stops while one is pending, the first auto-confirms with its suggested title before the new one is stored.
- Pipeline does not start until `confirmTitle(_:)` or `skipTitle()` is called.

## WatchLoop Changes

Two call sites replaced (`handleMeeting` and `stopManualRecording`):

```swift
// Flush any existing pending entry before storing new one
if let existing = pendingTitle { confirmTitle(existing.suggestedTitle) }

pendingTitle = PendingTitleEntry(
    suggestedTitle: title,
    appName: info.appName,
    recording: recording
)
NotificationCenter.default.post(name: .showTitlePrompt, object: nil)
```

Two new public methods:

```swift
func confirmTitle(_ title: String)
// Trims whitespace; falls back to suggestedTitle if empty.
// Calls enqueueRecording(title:appName:recording:), sets pendingTitle = nil.

func skipTitle()
// Uses suggestedTitle unchanged.
// Calls enqueueRecording(title:appName:recording:), sets pendingTitle = nil.
```

`record-only` mode is unaffected — `enqueueRecording` branches internally.

## Notification

Add to `Notification.Name` extension in `MeetingTranscriberApp.swift`:

```swift
static let showTitlePrompt = Notification.Name("showTitlePrompt")
```

## UI — TitlePromptView

New file: `Sources/TitlePromptView.swift`

- `TextField` pre-filled with `pendingTitle.suggestedTitle`, auto-focused on appear, all text selected.
- **Save** button (primary, triggered by Return key): calls `watchLoop.confirmTitle(titleText)`, closes window.
- **Skip** button: calls `watchLoop.skipTitle()`, closes window.
- If `pendingTitle` becomes `nil` externally (e.g. second recording flushed it), window closes itself via `.onChange`.

## Window Scene

In `MeetingTranscriberApp.swift`:

```swift
Window("Name this Recording", id: "title-prompt") {
    TitlePromptView(watchLoop: appState.watchLoop)
}
.windowResizability(.contentSize)
.defaultSize(width: 380, height: 130)
```

Opening trigger in `MenuBarExtra` label:

```swift
.onReceive(NotificationCenter.default.publisher(for: .showTitlePrompt)) { _ in
    openWindow(id: "title-prompt")
    bringWindowToFront(id: "title-prompt")
}
```

## Edge Cases

| Scenario | Behaviour |
|---|---|
| User ignores dialog | Window stays open; pipeline blocked until acted on |
| Second recording stops while prompt open | First auto-confirms with suggested title; prompt updates to second entry |
| User quits app while prompt open | Recording files orphaned on disk (acceptable v1) |
| Recording is manual (user already typed title) | Prompt still shown, pre-filled with that title — user can refine or Save immediately |
| Empty text field on Save | Falls back to `suggestedTitle` |

## Files Changed

| File | Change |
|---|---|
| `Sources/WatchLoop.swift` | Add `PendingTitleEntry`, `pendingTitle`, `confirmTitle(_:)`, `skipTitle()`; replace direct `enqueueRecording` calls at both stop sites |
| `Sources/TitlePromptView.swift` | New file — prompt UI |
| `Sources/MeetingTranscriberApp.swift` | Add `.showTitlePrompt` notification name; add `Window` scene; add `.onReceive` trigger in `MenuBarExtra` label |

## Out of Scope (v1)

- Recovering orphaned recordings after app quit
- Persisting pending state across launches
- Showing the prompt for file-import jobs
