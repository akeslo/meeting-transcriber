# Design: Live Log Viewer Tab + Recording Row Redesign

**Date:** 2026-05-26
**Scope:** Two independent UI improvements to the macOS app

---

## 1. Live Log Viewer — New "Logs" Settings Tab

### Goal
Surface `os.Logger` output inside the app so users can diagnose issues without opening Console.app or exporting a file.

### Architecture

**Data source (Homebrew / `#if !APPSTORE`)**
- Tail `PersistentDiagnosticLog.logDirectory/diagnostics-YYYY-MM-DD.log` — the file the already-running `Streamer` subprocess writes.
- On tab appear: read last 500 lines from the file.
- Poll every 500 ms using a `Timer` (or `DispatchSource` file-descriptor notification) for new bytes appended since last read offset.
- Ring buffer: keep max 2000 `LogLine` structs in memory; drop oldest when limit exceeded.

**Data source (App Store / `#if APPSTORE`)**
- `OSLogStore.local()` polled every 1 s with predicate `subsystem CONTAINS 'com.meetingtranscriber'`.
- Same ring buffer, same filtering layer.

**`LogLine` model**
```swift
struct LogLine: Identifiable {
    let id: UUID
    let raw: String       // original text for copy/display
    let category: String  // parsed from syslog format, empty if unparseable
    let timestamp: String // parsed from syslog format, empty if unparseable
}
```

**Category parsing**
Syslog lines from `log stream --style syslog` contain the OSLog category in the process field section. Parse via regex to extract the bracketed category token. If unparseable, category = `""` (shown as "Other" in the chip).

### `LogsSettingsView` — New Settings Tab

**Tab:** added to `SettingsTab` enum as `.logs` with label `"Logs"` and SF Symbol `scroll`.

**Layout (top to bottom):**
1. **Toolbar row** — search field (free-text, filters `raw` case-insensitive) + "Clear" button + "Copy Filtered" button (copies all visible lines to clipboard)
2. **Category chips row** — scrollable horizontal row of chips, one per unique `category` seen in the buffer. "All" chip always first. Tapping a chip filters to that category. Multiple chips not selectable simultaneously (single active filter).
3. **Log area** — `ScrollViewReader` + `LazyVStack` of monospace `Text` rows. Each row: timestamp (secondary, fixed width) + category badge (small, colored by hash) + message text. Alternating very-slight row tint for readability.
4. **Status bar** — "N lines · auto-scroll" or "N lines · paused ↓ Jump to bottom" (button) when user has scrolled up.

**Scroll behavior**
- `isAtBottom: Bool` state. On new lines: if `isAtBottom`, scroll to bottom ID. If not, show "Jump to bottom" button.
- Detect "scrolled up" by tracking scroll position via `GeometryReader` or a `ScrollView` preference key; set `isAtBottom = false` on upward scroll, `true` when bottom anchor is visible.

**No-data state**
The streamer always starts at app launch (`AppState.init` calls `PersistentDiagnosticLog.startForToday()` unconditionally). The log file will have content whenever the app is running. The viewer shows a "No log entries yet" placeholder only if the file is empty or unreadable (e.g. fresh launch before the first write, or streamer failed to start due to permissions).

### `SettingsView` changes
- Add `.logs` case to `SettingsTab` enum
- Add `LogsSettingsView()` case to `detailView(for:)` switch
- No new constructor parameters needed (log viewer reads the file directly)

### Files to create / modify
| File | Change |
|---|---|
| `Settings/LogsSettingsView.swift` | New file |
| `SettingsView.swift` | Add `.logs` tab case |

---

## 2. Recording Row Redesign (`SessionRowView`)

### Problem
`SessionRowView` uses `frame(height: 48)` with a single `HStack`: icon + title/date VStack + Spacer + duration + status chip. At the ~200 px panel width typical in the split view, the "Summarized" chip wraps to two lines, title truncates, and date cuts off mid-string.

### Fix: Two-line layout at 60 px

**Row structure:**
```
┌──────────────────────────────────────────────┐
│  [icon]  Title of the Recording              │  ← line 1: full width
│          May 26, 2026 · 3:58   [Summarized]  │  ← line 2: date+duration left, chip right
└──────────────────────────────────────────────┘
```

- **Row height:** `frame(minHeight: 60)` (not fixed — allows titles that wrap to 2 lines to expand rather than clip)
- **Title:** `lineLimit(1)`, `.truncationMode(.tail)`, takes all available width since chip is on line 2
- **Line 2:** `HStack` with `Text("\(dateString) · \(durationString)")` on left + `Spacer()` + `StatusChipView` on right
- **Status chip:** always single-line; chip text is short enough at this width

### `InFlightRowView`
Same two-line treatment: title line 1, date + progress indicator + status chip line 2.

### Files to modify
| File | Change |
|---|---|
| `DashboardWindow/SessionRowView.swift` | Restructure `SessionRowView.body` + `InFlightRowView.baseRow` |

---

## Out of scope
- Log viewer on App Store variant (OSLogStore path is noted above but deprioritized — implement Homebrew path first, add `#if APPSTORE` stub later)
- Log persistence / export from within the viewer (existing Export Diagnostics button covers this)
- Virtualization of the log list beyond the 2000-line ring buffer
- Recording row grid card (`SessionGridCardView`) — separate card layout, not broken in the same way
