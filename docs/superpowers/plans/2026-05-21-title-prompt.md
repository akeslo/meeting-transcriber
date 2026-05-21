# Title Prompt on Recording Stop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When any recording stops, hold it in a `pendingTitle` state and open a floating SwiftUI window so the user can name the meeting before the pipeline starts.

**Architecture:** `WatchLoop` gains a `PendingTitleEntry` struct and `pendingTitle: PendingTitleEntry?` observable property. Both stop call sites call `setPending(...)` (auto-flushing any existing entry) and post `.showTitlePrompt`. `confirmTitle(_:)` and `skipTitle()` resume the pipeline. A new `Window` scene hosts `TitlePromptView`. `AppState.watchLoop` is already `var watchLoop: WatchLoop?` — no exposure change needed.

**Tech Stack:** Swift, SwiftUI, XCTest, `@Observable`, `NotificationCenter`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `Sources/WatchLoop.swift` | Modify | Add `PendingTitleEntry`, `pendingTitle`, `setPending`, `confirmTitle`, `skipTitle`; replace two `enqueueRecording` call sites |
| `Sources/TitlePromptView.swift` | Create | Floating prompt UI — text field + Save + Skip; accepts `WatchLoop?` |
| `Sources/MeetingTranscriberApp.swift` | Modify | Add `.showTitlePrompt` notification name; add `Window` scene; add `.onReceive` trigger |
| `Tests/WatchLoopTitlePromptTests.swift` | Create | Unit tests for pending state machine |

---

### Task 1: Add `PendingTitleEntry` + state + methods to `WatchLoop`

**Files:**
- Modify: `app/MeetingTranscriber/Sources/WatchLoop.swift`
- Create: `app/MeetingTranscriber/Tests/WatchLoopTitlePromptTests.swift`

- [ ] **Step 1: Write failing tests**

Create `app/MeetingTranscriber/Tests/WatchLoopTitlePromptTests.swift`:

```swift
@testable import MeetingTranscriber
import XCTest

@MainActor
final class WatchLoopTitlePromptTests: XCTestCase {

    private func makeResult() -> RecordingResult {
        RecordingResult(
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil,
            micPath: nil,
            micDelay: 0,
            recordingStart: 0
        )
    }

    private func makeLoop(queue: PipelineQueue? = nil) -> WatchLoop {
        let detector = PowerAssertionDetector()
        detector.assertionProvider = { [:] }
        return WatchLoop(detector: detector, pipelineQueue: queue)
    }

    // MARK: - Initial state

    func testPendingTitleInitiallyNil() {
        XCTAssertNil(makeLoop().pendingTitle)
    }

    // MARK: - confirmTitle

    func testConfirmTitleClearsPendingTitle() {
        let loop = makeLoop()
        loop.pendingTitle = PendingTitleEntry(
            suggestedTitle: "Auto Title", appName: "Zoom",
            recording: makeResult(), participants: []
        )
        loop.confirmTitle("My Custom Title")
        XCTAssertNil(loop.pendingTitle)
    }

    func testConfirmTitleWithWhitespaceOnlyUsesSuggested() {
        let queue = PipelineQueue()
        let loop = makeLoop(queue: queue)
        loop.pendingTitle = PendingTitleEntry(
            suggestedTitle: "Auto Title", appName: "Zoom",
            recording: makeResult(), participants: []
        )
        loop.confirmTitle("   ")
        XCTAssertEqual(queue.jobs.first?.meetingTitle, "Auto Title")
    }

    func testConfirmTitlePassesTrimmedTitle() {
        let queue = PipelineQueue()
        let loop = makeLoop(queue: queue)
        loop.pendingTitle = PendingTitleEntry(
            suggestedTitle: "Auto Title", appName: "Zoom",
            recording: makeResult(), participants: []
        )
        loop.confirmTitle("  My Meeting  ")
        XCTAssertEqual(queue.jobs.first?.meetingTitle, "My Meeting")
    }

    // MARK: - skipTitle

    func testSkipTitleClearsPendingTitle() {
        let loop = makeLoop()
        loop.pendingTitle = PendingTitleEntry(
            suggestedTitle: "Auto Title", appName: "Zoom",
            recording: makeResult(), participants: []
        )
        loop.skipTitle()
        XCTAssertNil(loop.pendingTitle)
    }

    func testSkipTitleUsesSuggestedTitle() {
        let queue = PipelineQueue()
        let loop = makeLoop(queue: queue)
        loop.pendingTitle = PendingTitleEntry(
            suggestedTitle: "Auto Title", appName: "Zoom",
            recording: makeResult(), participants: []
        )
        loop.skipTitle()
        XCTAssertEqual(queue.jobs.first?.meetingTitle, "Auto Title")
    }

    // MARK: - setPending auto-flush

    func testSetPendingAutoFlushesExistingEntry() {
        let queue = PipelineQueue()
        let loop = makeLoop(queue: queue)

        loop.pendingTitle = PendingTitleEntry(
            suggestedTitle: "First Meeting", appName: "Zoom",
            recording: makeResult(), participants: []
        )
        loop.setPending(
            suggestedTitle: "Second Meeting", appName: "Teams",
            recording: makeResult(), participants: []
        )

        // First entry auto-enqueued with its suggested title
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(queue.jobs.first?.meetingTitle, "First Meeting")
        // Second entry now pending
        XCTAssertEqual(loop.pendingTitle?.suggestedTitle, "Second Meeting")
    }
}
```

- [ ] **Step 2: Run tests to confirm compile failure**

```bash
cd app/MeetingTranscriber && swift test --filter WatchLoopTitlePromptTests 2>&1 | grep -E "error:|FAILED|Build complete"
```

Expected: compile error — `PendingTitleEntry`, `pendingTitle`, `confirmTitle`, `skipTitle`, `setPending` not defined yet.

- [ ] **Step 3: Add `PendingTitleEntry` struct in `WatchLoop.swift`**

After the `ManualRecordingInfo` struct (around line 15), insert:

```swift
struct PendingTitleEntry {
    let suggestedTitle: String
    let appName: String
    let recording: RecordingResult
    let participants: [String]
}
```

- [ ] **Step 4: Add `pendingTitle` observable property to `WatchLoop`**

In the property block after `private(set) var manualRecordingInfo` (around line 32), add:

```swift
var pendingTitle: PendingTitleEntry?
```

- [ ] **Step 5: Add `setPending`, `confirmTitle`, `skipTitle` methods**

Insert before `private func enqueueRecording` (around line 392) in the `// MARK: - Helpers` section:

```swift
/// Stage a completed recording for user title confirmation.
/// Auto-flushes any existing pending entry with its suggested title.
func setPending(
    suggestedTitle: String,
    appName: String,
    recording: RecordingResult,
    participants: [String]
) {
    if let existing = pendingTitle {
        enqueueRecording(
            title: existing.suggestedTitle,
            appName: existing.appName,
            recording: existing.recording,
            participants: existing.participants
        )
        pendingTitle = nil
    }
    pendingTitle = PendingTitleEntry(
        suggestedTitle: suggestedTitle,
        appName: appName,
        recording: recording,
        participants: participants
    )
}

/// User confirmed a title. Trims whitespace; falls back to suggestedTitle if blank.
func confirmTitle(_ title: String) {
    guard let entry = pendingTitle else { return }
    pendingTitle = nil
    let resolved = title.trimmingCharacters(in: .whitespaces)
    enqueueRecording(
        title: resolved.isEmpty ? entry.suggestedTitle : resolved,
        appName: entry.appName,
        recording: entry.recording,
        participants: entry.participants
    )
}

/// User skipped naming. Enqueues with the auto-detected title.
func skipTitle() {
    guard let entry = pendingTitle else { return }
    pendingTitle = nil
    enqueueRecording(
        title: entry.suggestedTitle,
        appName: entry.appName,
        recording: entry.recording,
        participants: entry.participants
    )
}
```

- [ ] **Step 6: Run tests — all should pass**

```bash
cd app/MeetingTranscriber && swift test --filter WatchLoopTitlePromptTests 2>&1 | grep -E "passed|failed|error:"
```

Expected: 7 tests passed, 0 failed.

- [ ] **Step 7: Commit**

```bash
git add app/MeetingTranscriber/Sources/WatchLoop.swift \
        app/MeetingTranscriber/Tests/WatchLoopTitlePromptTests.swift
git commit -m "feat(app): add PendingTitleEntry + setPending/confirmTitle/skipTitle to WatchLoop"
```

---

### Task 2: Replace `enqueueRecording` call sites + add notification name

**Files:**
- Modify: `app/MeetingTranscriber/Sources/WatchLoop.swift`
- Modify: `app/MeetingTranscriber/Sources/MeetingTranscriberApp.swift` (notification name only)

- [ ] **Step 1: Add `.showTitlePrompt` to `Notification.Name` extension**

In `MeetingTranscriberApp.swift`, the extension is at lines 8–13. Add after `.closeSettings`:

```swift
static let showTitlePrompt = Notification.Name("showTitlePrompt")
```

- [ ] **Step 2: Replace the `stopManualRecording` call site in `WatchLoop.swift`**

Current code (around line 229–230):
```swift
let recording = try recorder.stop()
enqueueRecording(title: info.title, appName: info.appName, recording: recording)
```

Replace with:
```swift
let recording = try recorder.stop()
setPending(
    suggestedTitle: info.title,
    appName: info.appName,
    recording: recording,
    participants: []
)
NotificationCenter.default.post(name: .showTitlePrompt, object: nil)
```

- [ ] **Step 3: Replace the `handleMeeting` call site in `WatchLoop.swift`**

Current code (around line 346–354):
```swift
let recording = try recorder.stop()

// --- Enqueue for background processing ---
enqueueRecording(
    title: title,
    appName: meeting.pattern.appName,
    recording: recording,
    participants: participants,
)
```

Replace with:
```swift
let recording = try recorder.stop()

setPending(
    suggestedTitle: title,
    appName: meeting.pattern.appName,
    recording: recording,
    participants: participants
)
NotificationCenter.default.post(name: .showTitlePrompt, object: nil)
```

- [ ] **Step 4: Build**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 5: Run full test suite**

```bash
cd app/MeetingTranscriber && swift test --parallel 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/MeetingTranscriber/Sources/WatchLoop.swift \
        app/MeetingTranscriber/Sources/MeetingTranscriberApp.swift
git commit -m "feat(app): replace enqueueRecording call sites with setPending + showTitlePrompt"
```

---

### Task 3: Create `TitlePromptView.swift` + add `Window` scene + trigger

**Files:**
- Create: `app/MeetingTranscriber/Sources/TitlePromptView.swift`
- Modify: `app/MeetingTranscriber/Sources/MeetingTranscriberApp.swift`

- [ ] **Step 1: Create `TitlePromptView.swift`**

`AppState.watchLoop` is `WatchLoop?` (optional), so the view accepts an optional and shows nothing if nil (window won't open when watchLoop is nil anyway):

```swift
import SwiftUI

struct TitlePromptView: View {
    let watchLoop: WatchLoop?

    @State private var titleText: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name this recording")
                .font(.headline)

            TextField("Meeting title", text: $titleText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { confirm() }

            HStack {
                Spacer()
                Button("Skip") {
                    watchLoop?.skipTitle()
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Save") { confirm() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            titleText = watchLoop?.pendingTitle?.suggestedTitle ?? ""
        }
        .onChange(of: watchLoop?.pendingTitle?.suggestedTitle) { _, newTitle in
            if let newTitle {
                titleText = newTitle
            } else {
                // Entry cleared externally (auto-flushed by second recording) — close
                dismiss()
            }
        }
    }

    private func confirm() {
        watchLoop?.confirmTitle(titleText)
        dismiss()
    }
}
```

- [ ] **Step 2: Add `.onReceive` trigger in `MenuBarExtra` label**

The existing `.onReceive` calls are around lines 124–135 in `MeetingTranscriberApp.swift`. Add after the `.showSpeakerNaming` receiver:

```swift
.onReceive(NotificationCenter.default.publisher(for: .showTitlePrompt)) { _ in
    openWindow(id: "title-prompt")
    bringWindowToFront(id: "title-prompt")
}
```

- [ ] **Step 3: Add `Window` scene**

Find `Window("Record App", id: "record-app")` in `MeetingTranscriberApp.swift` and add after it:

```swift
Window("Name this Recording", id: "title-prompt") {
    TitlePromptView(watchLoop: appState.watchLoop)
}
.windowResizability(.contentSize)
.defaultSize(width: 380, height: 130)
```

- [ ] **Step 4: Build**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 5: Run full test suite**

```bash
cd app/MeetingTranscriber && swift test --parallel 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/MeetingTranscriber/Sources/TitlePromptView.swift \
        app/MeetingTranscriber/Sources/MeetingTranscriberApp.swift
git commit -m "feat(app): TitlePromptView + Window scene for meeting title entry"
```

---

### Task 4: Smoke test

- [ ] **Step 1: Launch the app**

```bash
./scripts/run_app.sh
```

- [ ] **Step 2: Trigger a manual recording**

Menu bar → Record App… → pick any app → Start Recording.

- [ ] **Step 3: Stop the recording**

Menu bar → Stop Recording.

- [ ] **Step 4: Verify title prompt appears**

A window "Name this Recording" opens with the auto-detected title pre-filled.

- [ ] **Step 5: Edit the title and click Save**

Change the title, click Save. Window closes. Open Dashboard — recording appears with the new title.

- [ ] **Step 6: Verify Skip**

Start and stop another recording. When prompt appears, click Skip (or press Escape). Window closes. Recording uses auto-detected title.

- [ ] **Step 7: Verify Return key saves**

Start and stop another recording. When prompt appears, press Return. Should behave identically to clicking Save.

- [ ] **Step 8: Commit any fixups**

```bash
cd app/MeetingTranscriber && swift test --parallel 2>&1 | tail -5
git add -p && git commit -m "fix(app): title prompt smoke test fixups"
```
