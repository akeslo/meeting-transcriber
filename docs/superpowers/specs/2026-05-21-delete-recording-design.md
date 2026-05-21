# Delete Recording Design

**Goal:** Allow users to delete a completed recording from the library, moving its files to Trash.

**Architecture:** Add context menus to session row and grid card views, plus swipe-to-delete in list view. Deletion moves the session folder to Trash via `NSWorkspace.shared.recycle` and removes the `RecordingSession` from SwiftData.

---

## Interaction Surface

### List view (`LibraryView` + `SessionRowView`)
- `.onDelete` modifier on the `List` — enables swipe-to-delete gesture on session rows
- Right-click context menu on `SessionRowView` with a "Move to Trash" item

### Grid view (`SessionGridCardView`)
- Right-click context menu with a "Move to Trash" item
- No swipe gesture — macOS grid views do not support `.onDelete`

### In-flight job rows
- Context menu shows **"Cancel"** instead of "Move to Trash"
- Routes to the existing `PipelineQueue.cancelJob(id:)` — no new logic needed
- Only completed and error-state sessions show "Move to Trash"

---

## Delete Behavior

1. Call `NSWorkspace.shared.recycle([url], completionHandler:)` where `url` is `URL(fileURLWithPath: session.folderPath)`
2. Delete the `RecordingSession` from SwiftData `modelContext` regardless of whether recycle succeeded
3. If recycle fails (files already absent, permissions error), log the error but do not block the user or show an alert — the record is still removed from the list

No confirmation dialog. Trash is recoverable, consistent with standard macOS Finder behavior.

---

## Code Changes

| File | Change |
|---|---|
| `Sources/DashboardWindow/LibraryView.swift` | Add `.onDelete` to the session `List`; pass a `onDelete: (RecordingSession) -> Void` closure down to rows |
| `Sources/DashboardWindow/SessionRowView.swift` | Add `.contextMenu` with "Move to Trash" (trash icon) for completed/error sessions; pass `onCancel` closure for in-flight rows |
| `Sources/DashboardWindow/SessionGridCardView.swift` | Add `.contextMenu` with "Move to Trash" for completed/error sessions |
| `Sources/DashboardWindow/DashboardWindowContent.swift` | Wire delete action: recycle folder + `modelContext.delete(session)` |

No new files. No new model fields.

---

## Error Handling

- `recycle` failure: log at `.error` level, continue with SwiftData delete
- `folderPath` empty or nonexistent directory: skip recycle, delete SwiftData record, log warning
- Both branches always remove the session from the UI

---

## Out of Scope

- Undo (Trash itself is the undo mechanism)
- Bulk delete / multi-select
- Deleting in-flight jobs' output files (cancel already handles cleanup via `cancelJob`)
