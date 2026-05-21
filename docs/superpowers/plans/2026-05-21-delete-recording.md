# Delete Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users delete a completed recording from the library via right-click context menu ("Move to Trash") and swipe-to-delete in list view; in-flight jobs get a "Cancel" context menu item.

**Architecture:** `DashboardWindowContent` owns the delete action (it has `modelContext` and `settings`). It passes a closure to `LibraryView`, which threads it down to `SessionRowView` and `SessionGridCardView`. The list switches from `ScrollView+LazyVStack` to `List` so `.onDelete` (swipe/Delete-key) works. `InFlightRowView` gets a separate cancel closure routed to `PipelineQueue.cancelJob(id:)`.

**Tech Stack:** SwiftUI, SwiftData (`ModelContext.delete`), `NSWorkspace.shared.recycle`, `AppKit`, XCTest + ViewInspector.

---

## Files

| File | Change |
|---|---|
| `Sources/DashboardWindow/DashboardWindowContent.swift` | Add `deleteSession(_:)` method + `import os.log`; pass closure to `LibraryView` |
| `Sources/DashboardWindow/LibraryView.swift` | Add `onDeleteSession` param; switch list to `List`; wire `.onDelete` + cancel |
| `Sources/DashboardWindow/SessionRowView.swift` | Add `onDelete` param + `.contextMenu` to `SessionRowView`; add `onCancel` + `.contextMenu` to `InFlightRowView` |
| `Sources/DashboardWindow/SessionGridCardView.swift` | Add `onDelete` param + `.contextMenu` |
| `Tests/DashboardWindow/LibraryViewTests.swift` | Add `test_deleteSession_*` tests for the delete logic helpers |

---

## Task 1: `deleteSession` in DashboardWindowContent

**Files:**
- Modify: `Sources/DashboardWindow/DashboardWindowContent.swift`

`folderPath` on `RecordingSession` is stored relative to `settings.effectiveOutputDir` (see `PipelineQueue.persistRecordingSession`). Reconstruct full URL via `settings.effectiveOutputDir.appendingPathComponent(session.folderPath)`.

- [ ] **Step 1: Add import and logger**

At the top of `DashboardWindowContent.swift`, after the existing imports, add:

```swift
import os.log

private let dashboardLogger = Logger(subsystem: AppPaths.logSubsystem, category: "DashboardWindow")
```

- [ ] **Step 2: Add `deleteSession` method**

Add this private method to `DashboardWindowContent` (place before the `body`):

```swift
private func deleteSession(_ session: RecordingSession) {
    if selectedSessionID == session.id {
        selectedSessionID = nil
    }
    if !session.folderPath.isEmpty {
        let fullURL = settings.effectiveOutputDir.appendingPathComponent(session.folderPath)
        if FileManager.default.fileExists(atPath: fullURL.path) {
            NSWorkspace.shared.recycle([fullURL]) { _, error in
                if let error {
                    dashboardLogger.error("Trash failed '\(fullURL.path)': \(error)")
                }
            }
        }
    }
    modelContext.delete(session)
}
```

- [ ] **Step 3: Pass closure to LibraryView**

In `contentPane`, update the `.library` case. Replace:

```swift
case .library:
    LibraryView(
        pipelineQueue: pipelineQueue,
        selectedSessionID: $selectedSessionID
    )
```

With:

```swift
case .library:
    LibraryView(
        pipelineQueue: pipelineQueue,
        selectedSessionID: $selectedSessionID,
        onDeleteSession: deleteSession
    )
```

- [ ] **Step 4: Build — verify no compile errors**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber/app/MeetingTranscriber
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: compile errors because `LibraryView` doesn't have `onDeleteSession` yet — that's fine, confirms the call site is wired.

---

## Task 2: LibraryView — add `onDeleteSession` + switch to `List`

**Files:**
- Modify: `Sources/DashboardWindow/LibraryView.swift`

The current `listContent` uses `ScrollView + LazyVStack`. SwiftUI's `.onDelete` modifier only works on `ForEach` inside a `List`. Switching to `List` with `.listStyle(.plain)` and per-row `.listRowInsets(EdgeInsets())` / `.listRowSeparator(.hidden)` / `.listRowBackground(Color.clear)` preserves the current visual look. The empty state moves to an `.overlay`.

- [ ] **Step 1: Add `onDeleteSession` parameter**

Replace the struct opening:

```swift
struct LibraryView: View {
    var pipelineQueue: PipelineQueue
    @Binding var selectedSessionID: UUID?
```

With:

```swift
struct LibraryView: View {
    var pipelineQueue: PipelineQueue
    @Binding var selectedSessionID: UUID?
    var onDeleteSession: (RecordingSession) -> Void
```

- [ ] **Step 2: Replace `listContent` with a `List`-based implementation**

Replace the entire `listContent` computed property and its two helper functions (`inFlightListRow` and `sessionListRow`):

```swift
// MARK: - List layout

private var listContent: some View {
    List {
        ForEach(inFlightJobs, id: \.id) { job in
            InFlightRowView(
                job: job,
                isSelected: selectedSessionID == job.id,
                onCancel: { pipelineQueue.cancelJob(id: job.id) }
            )
            .onTapGesture { selectedSessionID = job.id }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        ForEach(filteredSessions, id: \.id) { session in
            VStack(spacing: 0) {
                SessionRowView(
                    session: session,
                    isSelected: selectedSessionID == session.id,
                    onDelete: { onDeleteSession(session) }
                )
                .onTapGesture { selectedSessionID = session.id }
                Divider().padding(.leading, 60)
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .onDelete { indexSet in
            for index in indexSet {
                onDeleteSession(filteredSessions[index])
            }
        }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .overlay {
        if filteredSessions.isEmpty && inFlightJobs.isEmpty {
            emptySearchState
        }
    }
}
```

- [ ] **Step 3: Update `sessionGrid` to pass `onDelete`**

In the `sessionGrid` computed property, replace:

```swift
SessionGridCardView(
    session: session,
    isSelected: selectedSessionID == session.id
)
.onTapGesture { selectedSessionID = session.id }
```

With:

```swift
SessionGridCardView(
    session: session,
    isSelected: selectedSessionID == session.id,
    onDelete: { onDeleteSession(session) }
)
.onTapGesture { selectedSessionID = session.id }
```

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: errors for missing `onDelete`/`onCancel` params on `SessionRowView`, `InFlightRowView`, `SessionGridCardView` — confirms wiring is in place.

---

## Task 3: Context menu on `SessionRowView` + `InFlightRowView`

**Files:**
- Modify: `Sources/DashboardWindow/SessionRowView.swift`

- [ ] **Step 1: Add `onDelete` to `SessionRowView`**

In `SessionRowView`, add the parameter after `isSelected`:

```swift
struct SessionRowView: View {
    let session: RecordingSession
    let isSelected: Bool
    let onDelete: () -> Void
```

- [ ] **Step 2: Add `.contextMenu` to `SessionRowView.body`**

After `.contentShape(Rectangle())` in the `body`, add:

```swift
.contextMenu {
    Button(role: .destructive, action: onDelete) {
        Label("Move to Trash", systemImage: "trash")
    }
}
```

Full `body` tail should look like:

```swift
.padding(.horizontal, 16)
.frame(height: 48)
.background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
.contentShape(Rectangle())
.contextMenu {
    Button(role: .destructive, action: onDelete) {
        Label("Move to Trash", systemImage: "trash")
    }
}
```

- [ ] **Step 3: Add `onCancel` to `InFlightRowView`**

In `InFlightRowView`, add the parameter:

```swift
struct InFlightRowView: View {
    let job: PipelineJob
    let isSelected: Bool
    var onCancel: (() -> Void)? = nil
```

- [ ] **Step 4: Add `.contextMenu` to `InFlightRowView.body`**

After `.contentShape(Rectangle())` in `InFlightRowView.body`, add:

```swift
.contextMenu {
    if let onCancel {
        Button(role: .destructive, action: onCancel) {
            Label("Cancel", systemImage: "xmark.circle")
        }
    }
}
```

- [ ] **Step 5: Build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: one remaining error for `SessionGridCardView.onDelete`.

---

## Task 4: Context menu on `SessionGridCardView`

**Files:**
- Modify: `Sources/DashboardWindow/SessionGridCardView.swift`

- [ ] **Step 1: Add `onDelete` parameter**

```swift
struct SessionGridCardView: View {
    let session: RecordingSession
    let isSelected: Bool
    let onDelete: () -> Void
```

- [ ] **Step 2: Add `.contextMenu` at the end of `body`**

The `body` currently ends with `.overlay(...)`. Append `.contextMenu` after that:

```swift
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .strokeBorder(
            isSelected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.12),
            lineWidth: 1
        )
)
.contextMenu {
    Button(role: .destructive, action: onDelete) {
        Label("Move to Trash", systemImage: "trash")
    }
}
```

- [ ] **Step 3: Build clean**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

---

## Task 5: Tests

**Files:**
- Modify: `Tests/DashboardWindow/LibraryViewTests.swift`

These tests verify that `filterInFlightJobs` correctly excludes done/error states (which shouldn't get "Cancel") and that a delete closure round-trip works without crashing.

- [ ] **Step 1: Add `filterInFlightJobs` exclusion tests**

Append to `LibraryViewTests`:

```swift
// MARK: - In-flight job filter

func test_filterInFlightJobs_excludesDoneAndError() {
    let activeJob = PipelineJob(meetingTitle: "Active", state: .transcribing)
    let doneJob   = PipelineJob(meetingTitle: "Done",   state: .done)
    let errorJob  = PipelineJob(meetingTitle: "Error",  state: .error)
    let result = LibraryView.filterInFlightJobs([activeJob, doneJob, errorJob])
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].meetingTitle, "Active")
}

func test_filterInFlightJobs_includesAllActiveStates() {
    let jobs = [
        PipelineJob(meetingTitle: "A", state: .waiting),
        PipelineJob(meetingTitle: "B", state: .transcribing),
        PipelineJob(meetingTitle: "C", state: .diarizing),
        PipelineJob(meetingTitle: "D", state: .generatingProtocol),
    ]
    XCTAssertEqual(LibraryView.filterInFlightJobs(jobs).count, 4)
}
```

- [ ] **Step 2: Add delete closure round-trip test**

```swift
// MARK: - Delete closure

func test_deleteSession_closureIsCalled() {
    var deletedSession: RecordingSession?
    let session = makeSession(title: "Meeting to Delete", appName: "Zoom")
    let onDelete: (RecordingSession) -> Void = { deletedSession = $0 }

    onDelete(session)

    XCTAssertEqual(deletedSession?.title, "Meeting to Delete")
}
```

- [ ] **Step 3: Run tests**

```bash
swift test --filter LibraryViewTests 2>&1 | grep -E "passed|failed|error"
```

Expected: all `LibraryViewTests` pass.

- [ ] **Step 4: Run full suite**

```bash
swift test 2>&1 | tail -5
```

Expected: `Executed N tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/DashboardWindow/DashboardWindowContent.swift \
        Sources/DashboardWindow/LibraryView.swift \
        Sources/DashboardWindow/SessionRowView.swift \
        Sources/DashboardWindow/SessionGridCardView.swift \
        Tests/DashboardWindow/LibraryViewTests.swift
git commit -m "feat(app): delete recording via context menu and swipe-to-delete

Right-click any completed session row or grid card to Move to Trash.
Swipe left (or press Delete key) in list view for the same action.
In-flight job rows get a Cancel context menu item routed to
PipelineQueue.cancelJob(id:). Delete moves the session folder to
Trash via NSWorkspace.recycle and removes the SwiftData record.
If the folder is already gone, the record is still removed."
```
