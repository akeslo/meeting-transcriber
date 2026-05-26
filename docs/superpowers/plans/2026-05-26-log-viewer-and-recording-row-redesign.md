# Log Viewer Tab + Recording Row Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a live streaming log viewer as a new "Logs" settings tab, and fix the recording list row layout so the status chip never wraps and titles have full width.

**Architecture:** Recording row switches from a single-line `HStack` at fixed 48px to a two-line `VStack` layout at min-60px — title on line 1, date+duration+chip on line 2. Log viewer tails `~/Library/Logs/MeetingTranscriber/diagnostics-YYYY-MM-DD.log` via a polling `@Observable @MainActor` model, with category chip filtering and auto-scroll.

**Tech Stack:** SwiftUI, Swift 6, `@Observable`, `FileHandle`, `NSRegularExpression`, `XCTest`

---

## Task 1: Recording Row — Two-Line Layout

**Files:**
- Modify: `app/MeetingTranscriber/Sources/DashboardWindow/SessionRowView.swift`

The problem: `SessionRowView.body` is a single `HStack` inside `frame(height: 48)`. When the panel is ~200px wide, `StatusChipView("Summarized")` wraps to two lines and the title/date truncate. Fix: move to a two-line VStack layout, putting the chip on line 2 alongside date and duration.

- [ ] **Step 1: Write a failing snapshot/visual regression test for row height**

There are no existing `SessionRowView` unit tests — add a `StatusChipView` test to confirm chip labels are single-line (testable without view rendering):

```swift
// In app/MeetingTranscriber/Tests/DashboardWindow/StatusChipViewTests.swift
// Append after existing tests:

func test_chipLabel_summarized_isSingleWord() {
    XCTAssertEqual(StatusChipView.chipLabel(for: "summarized"), "Summarized")
    // Ensure no spaces that would force wrap in narrow containers
    XCTAssertFalse(StatusChipView.chipLabel(for: "summarized").contains(" "))
}
```

- [ ] **Step 2: Run test to confirm it passes (existing behavior)**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber/app/MeetingTranscriber
swift test --filter StatusChipViewTests 2>&1 | tail -5
```

Expected: `Test Suite 'StatusChipViewTests' passed`

- [ ] **Step 3: Rewrite `SessionRowView.body` to two-line layout**

Replace the entire `body` computed property in `SessionRowView` (lines 58–89 in `SessionRowView.swift`):

```swift
var body: some View {
    HStack(spacing: 12) {
        Image(systemName: iconName(for: session.appName))
            .font(.system(size: 20))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 7))

        VStack(alignment: .leading, spacing: 3) {
            Text(session.title.isEmpty ? "Untitled Recording" : session.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            HStack(spacing: 0) {
                Text("\(dateString) · \(durationString)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                StatusChipView(status: session.displayStatus)
            }
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(minHeight: 60)
    .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    .contentShape(Rectangle())
    .contextMenu {
        if let onRename {
            Button {
                promptText(
                    title: "Rename Recording",
                    message: "Enter a new name:",
                    placeholder: session.title,
                    initial: session.title
                ) { onRename($0) }
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
        }
        if let onAddTag {
            Button {
                promptText(
                    title: "Add Tag",
                    message: "Enter a tag name:",
                    placeholder: "tag name",
                    initial: ""
                ) { onAddTag($0) }
            } label: {
                Label("Add Tag…", systemImage: "tag")
            }
        }
        if let onSetFolder {
            Menu {
                if !session.folderGroup.isEmpty {
                    Button {
                        onSetFolder("")
                    } label: {
                        Label("Remove from Folder", systemImage: "folder.badge.minus")
                    }
                    Divider()
                }
                ForEach(allFolders.filter { $0 != session.folderGroup }, id: \.self) { folder in
                    Button(folder) { onSetFolder(folder) }
                }
                Button {
                    promptText(
                        title: "New Folder",
                        message: "Enter folder name:",
                        placeholder: "folder name",
                        initial: ""
                    ) { onSetFolder($0) }
                } label: {
                    Label("New Folder…", systemImage: "folder.badge.plus")
                }
            } label: {
                Label("Move to Folder", systemImage: "folder")
            }
        }
        Divider()
        Button(role: .destructive, action: onDelete) {
            Label("Move to Trash", systemImage: "trash")
        }
    }
}
```

- [ ] **Step 4: Rewrite `InFlightRowView.baseRow` to two-line layout**

Replace the `baseRow` computed property in `InFlightRowView` (the `@ViewBuilder private var baseRow: some View` block, lines 193–228):

```swift
@ViewBuilder private var baseRow: some View {
    HStack(spacing: 12) {
        Image(systemName: "waveform")
            .font(.system(size: 20))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 7))

        VStack(alignment: .leading, spacing: 3) {
            Text(job.meetingTitle.isEmpty ? "Recording…" : job.meetingTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            HStack(spacing: 6) {
                if let startedAt = job.startedAt {
                    Text(Self.dateFormatter.string(from: startedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if job.progress > 0 && job.progress < 1 {
                    ProgressView(value: job.progress)
                        .frame(width: 50)
                        .tint(Color(red: 0.969, green: 0.773, blue: 0.624))
                }
                StatusChipView(status: jobStatusString)
            }
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(minHeight: 60)
    .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    .contentShape(Rectangle())
}
```

- [ ] **Step 5: Build and verify no errors**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber/app/MeetingTranscriber
swift build 2>&1 | grep -E "error:" | head -10
```

Expected: no output (zero errors)

- [ ] **Step 6: Run tests**

```bash
swift test --parallel 2>&1 | tail -5
```

Expected: `Test Suite 'All tests' passed`

- [ ] **Step 7: Commit**

```bash
git -C /Users/akeslo/Scrypting/meeting-transcriber \
  add app/MeetingTranscriber/Sources/DashboardWindow/SessionRowView.swift \
      app/MeetingTranscriber/Tests/DashboardWindow/StatusChipViewTests.swift
git -C /Users/akeslo/Scrypting/meeting-transcriber commit -m \
  "fix(app): two-line row layout — chip on line 2, title gets full width"
```

---

## Task 2: `LogLine` Model + `LogTailModel`

**Files:**
- Create: `app/MeetingTranscriber/Sources/Settings/LogsSettingsView.swift` (model section)
- Create: `app/MeetingTranscriber/Tests/LogTailModelTests.swift`

`log stream --style syslog --info` lines look like:
```
May 26 12:34:56 hostname MeetingTranscriber(WatchLoop)[1234] <Notice>: actual message here
```
Timestamp = first 15 chars. Category = text between `(` and `)` before `[pid]`. Message = text after `<Level>: `.

- [ ] **Step 1: Write failing tests for `LogLine.parse`**

Create `app/MeetingTranscriber/Tests/LogTailModelTests.swift`:

```swift
import XCTest
@testable import MeetingTranscriber

final class LogTailModelTests: XCTestCase {

    func test_parse_extractsTimestamp() {
        let raw = "May 26 12:34:56 host MeetingTranscriber(WatchLoop)[123] <Notice>: hello"
        let line = LogLine.parse(raw: raw)
        XCTAssertEqual(line.timestamp, "May 26 12:34:56")
    }

    func test_parse_extractsCategory() {
        let raw = "May 26 12:34:56 host MeetingTranscriber(PipelineQueue)[123] <Notice>: msg"
        let line = LogLine.parse(raw: raw)
        XCTAssertEqual(line.category, "PipelineQueue")
    }

    func test_parse_extractsMessage() {
        let raw = "May 26 12:34:56 host MeetingTranscriber(WatchLoop)[123] <Notice>: job done"
        let line = LogLine.parse(raw: raw)
        XCTAssertEqual(line.message, "job done")
    }

    func test_parse_unparseable_returnsRawAsMessage() {
        let raw = "not a syslog line at all"
        let line = LogLine.parse(raw: raw)
        XCTAssertEqual(line.raw, raw)
        XCTAssertEqual(line.category, "")
        XCTAssertEqual(line.message, raw)
    }

    func test_parse_emptyCategoryWhenNoParens() {
        let raw = "May 26 12:34:56 host MeetingTranscriber[123] <Notice>: no category"
        let line = LogLine.parse(raw: raw)
        XCTAssertEqual(line.category, "")
    }

    // MARK: - LogTailModel ring buffer

    func test_ringBuffer_dropsOldestWhenExceedingMax() {
        let model = LogTailModel()
        let lines = (0 ..< (LogTailModel.maxLines + 10)).map { i in
            LogLine(id: UUID(), raw: "line \(i)", timestamp: "", category: "", message: "line \(i)")
        }
        model.appendForTesting(lines)
        XCTAssertEqual(model.lines.count, LogTailModel.maxLines)
        XCTAssertEqual(model.lines.first?.message, "line 10")
    }

    func test_categories_deduplicatedAndOrdered() {
        let model = LogTailModel()
        let a = LogLine(id: UUID(), raw: "", timestamp: "", category: "Alpha", message: "")
        let b = LogLine(id: UUID(), raw: "", timestamp: "", category: "Beta", message: "")
        let c = LogLine(id: UUID(), raw: "", timestamp: "", category: "Alpha", message: "")
        model.appendForTesting([a, b, c])
        XCTAssertEqual(model.categories, ["Alpha", "Beta"])
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber/app/MeetingTranscriber
swift test --filter LogTailModelTests 2>&1 | grep -E "error:|FAILED|cannot find" | head -10
```

Expected: compile error — `LogLine`, `LogTailModel` not defined yet.

- [ ] **Step 3: Create `LogsSettingsView.swift` with model types**

Create `app/MeetingTranscriber/Sources/Settings/LogsSettingsView.swift` with just the model (view comes in Task 3):

```swift
import Foundation
import SwiftUI

// MARK: - LogLine

struct LogLine: Identifiable, Sendable {
    let id: UUID
    let raw: String
    let timestamp: String
    let category: String
    let message: String

    // nonisolated(unsafe): regex objects are read-only after init, safe for concurrent use.
    nonisolated(unsafe) private static let categoryRegex =
        try? NSRegularExpression(pattern: #"\((\w[\w\s]*)\)\[\d"#)
    nonisolated(unsafe) private static let messageRegex =
        try? NSRegularExpression(pattern: #"<\w+>: (.+)$"#, options: .dotMatchesLineSeparators)

    static func parse(raw: String) -> LogLine {
        let ts = raw.count >= 15 ? String(raw.prefix(15)) : ""

        var category = ""
        if let m = categoryRegex?.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let r = Range(m.range(at: 1), in: raw) {
            category = String(raw[r])
        }

        var message = raw
        if let m = messageRegex?.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let r = Range(m.range(at: 1), in: raw) {
            message = String(raw[r])
        }

        return LogLine(id: UUID(), raw: raw, timestamp: ts, category: category, message: message)
    }
}

// MARK: - LogTailModel

@Observable
@MainActor
final class LogTailModel {
    private(set) var lines: [LogLine] = []
    private(set) var categories: [String] = []

    private var fileOffset: UInt64 = 0
    private var pollTask: Task<Void, Never>?

    static let maxLines = 2000
    private static let initialReadBytes: UInt64 = 65536  // ~500 syslog lines

    func start(logDirectory: URL) {
        stop()
        let url = logDirectory.appendingPathComponent(
            PersistentDiagnosticLog.logFileName(for: Date())
        )
        loadInitial(from: url)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.pollNewLines(from: url)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func loadInitial(from url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let readFrom = size > Self.initialReadBytes ? size - Self.initialReadBytes : 0
        try? handle.seek(toOffset: readFrom)
        let data = handle.readDataToEndOfFile()
        fileOffset = size
        let text = String(data: data, encoding: .utf8) ?? ""
        let parsed = text.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .suffix(500)
            .map { LogLine.parse(raw: $0) }
        lines = Array(parsed)
        updateCategories(from: lines)
    }

    private func pollNewLines(from url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: fileOffset)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }
        fileOffset += UInt64(data.count)
        let text = String(data: data, encoding: .utf8) ?? ""
        let newLines = text.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .map { LogLine.parse(raw: $0) }
        guard !newLines.isEmpty else { return }
        lines.append(contentsOf: newLines)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
        updateCategories(from: newLines)
    }

    private func updateCategories(from newLines: [LogLine]) {
        for line in newLines {
            let cat = line.category.isEmpty ? "Other" : line.category
            if !categories.contains(cat) {
                categories.append(cat)
            }
        }
    }

    /// Test seam: inject pre-built lines directly, bypassing file IO.
    func appendForTesting(_ newLines: [LogLine]) {
        lines.append(contentsOf: newLines)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
        updateCategories(from: newLines)
    }
}
```

- [ ] **Step 4: Run tests — confirm they pass**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber/app/MeetingTranscriber
swift test --filter LogTailModelTests 2>&1 | tail -5
```

Expected: `Test Suite 'LogTailModelTests' passed`

- [ ] **Step 5: Commit**

```bash
git -C /Users/akeslo/Scrypting/meeting-transcriber \
  add app/MeetingTranscriber/Sources/Settings/LogsSettingsView.swift \
      app/MeetingTranscriber/Tests/LogTailModelTests.swift
git -C /Users/akeslo/Scrypting/meeting-transcriber commit -m \
  "feat(app): add LogLine + LogTailModel for live log tailing"
```

---

## Task 3: `LogsSettingsView` UI

**Files:**
- Modify: `app/MeetingTranscriber/Sources/Settings/LogsSettingsView.swift` (append view code)

- [ ] **Step 1: Append `LogLineRow` and `LogsSettingsView` to `LogsSettingsView.swift`**

Open `app/MeetingTranscriber/Sources/Settings/LogsSettingsView.swift` and append after the closing `}` of `LogTailModel`:

```swift
// MARK: - LogLineRow

private struct LogLineRow: View {
    let line: LogLine

    private var categoryColor: Color {
        guard !line.category.isEmpty else { return .secondary }
        let hash = abs(line.category.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if !line.timestamp.isEmpty {
                Text(line.timestamp)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 105, alignment: .leading)
                    .lineLimit(1)
            }
            if !line.category.isEmpty {
                Text(line.category)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(categoryColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(categoryColor.opacity(0.12))
                    .clipShape(Capsule())
                    .frame(width: 90, alignment: .leading)
                    .lineLimit(1)
            } else {
                Color.clear.frame(width: 90, height: 1)
            }
            Text(line.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}

// MARK: - LogsSettingsView

struct LogsSettingsView: View {
    @State private var model = LogTailModel()
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var autoScroll = true

    private var visibleLines: [LogLine] {
        model.lines.filter { line in
            let catOK: Bool = {
                guard let sel = selectedCategory else { return true }
                let cat = line.category.isEmpty ? "Other" : line.category
                return cat == sel
            }()
            let searchOK = searchText.isEmpty
                || line.raw.localizedCaseInsensitiveContains(searchText)
            return catOK && searchOK
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbarRow
            if !model.categories.isEmpty {
                categoryChipsRow
            }
            Divider()
            logArea
        }
        .onAppear {
            model.start(logDirectory: PersistentDiagnosticLog.logDirectory)
        }
        .onDisappear {
            model.stop()
        }
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Filter…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            Button {
                let text = visibleLines.map(\.raw).joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy filtered log lines to clipboard")

            if !autoScroll {
                Button {
                    autoScroll = true
                } label: {
                    Label("Jump to Bottom", systemImage: "arrow.down.to.line")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Category chips

    private var categoryChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(label: "All", isActive: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(model.categories, id: \.self) { cat in
                    categoryChip(label: cat, isActive: selectedCategory == cat) {
                        selectedCategory = selectedCategory == cat ? nil : cat
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func categoryChip(
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isActive
                        ? Color.accentColor.opacity(0.12)
                        : Color.secondary.opacity(0.08)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log area

    @ViewBuilder
    private var logArea: some View {
        if model.lines.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "scroll")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("No log entries yet")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleLines) { line in
                            LogLineRow(line: line)
                                .id(line.id)
                        }
                        // Sentinel: fires onAppear when bottom is visible,
                        // onDisappear when user scrolls up past it.
                        Color.clear
                            .frame(height: 1)
                            .id("log-bottom-sentinel")
                            .onAppear { autoScroll = true }
                            .onDisappear { autoScroll = false }
                    }
                }
                .onChange(of: model.lines.count) { _, _ in
                    if autoScroll {
                        proxy.scrollTo("log-bottom-sentinel", anchor: .bottom)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify no errors**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber/app/MeetingTranscriber
swift build 2>&1 | grep -E "error:" | head -10
```

Expected: no output

- [ ] **Step 3: Run all tests**

```bash
swift test --parallel 2>&1 | tail -5
```

Expected: `Test Suite 'All tests' passed`

- [ ] **Step 4: Commit**

```bash
git -C /Users/akeslo/Scrypting/meeting-transcriber \
  add app/MeetingTranscriber/Sources/Settings/LogsSettingsView.swift
git -C /Users/akeslo/Scrypting/meeting-transcriber commit -m \
  "feat(app): add LogsSettingsView UI with category chips + auto-scroll"
```

---

## Task 4: Wire `LogsSettingsView` into `SettingsView`

**Files:**
- Modify: `app/MeetingTranscriber/Sources/SettingsView.swift`

- [ ] **Step 1: Add `.logs` case to `SettingsTab` enum**

In `SettingsView.swift`, find the `private enum SettingsTab` (line 84). Change:

```swift
private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, audio, transcription, speakers, output, advanced
```

To:

```swift
private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, audio, transcription, speakers, output, advanced, logs
```

- [ ] **Step 2: Add label for `.logs`**

In the `var label: String` switch, add after `case .advanced: "Advanced"`:

```swift
case .logs: "Logs"
```

- [ ] **Step 3: Add system image for `.logs`**

In the `var systemImage: String` switch, add after `case .advanced: "wrench.and.screwdriver"`:

```swift
case .logs: "scroll"
```

- [ ] **Step 4: Add `LogsSettingsView` to `detailView(for:)`**

In the `detailView(for tab:)` switch, add after the `.advanced` case:

```swift
case .logs:
    LogsSettingsView()
```

- [ ] **Step 5: Build**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber/app/MeetingTranscriber
swift build 2>&1 | grep -E "error:" | head -10
```

Expected: no output

- [ ] **Step 6: Run all tests**

```bash
swift test --parallel 2>&1 | tail -5
```

Expected: `Test Suite 'All tests' passed`

- [ ] **Step 7: Commit**

```bash
git -C /Users/akeslo/Scrypting/meeting-transcriber \
  add app/MeetingTranscriber/Sources/SettingsView.swift
git -C /Users/akeslo/Scrypting/meeting-transcriber commit -m \
  "feat(app): add Logs tab to settings — live log viewer"
```

---

## Self-Review Checklist

- [x] **Recording row** — two-line layout, `frame(minHeight: 60)`, chip on line 2 ✓
- [x] **InFlightRowView** — same treatment ✓
- [x] **LogLine.parse** — timestamp, category, message extraction, unparseable fallback ✓
- [x] **LogTailModel** — ring buffer capped at 2000, initial 500 lines, 500ms poll ✓
- [x] **Category chips** — deduped, "All" always first, single-select ✓
- [x] **Auto-scroll** — sentinel view drives `autoScroll` flag, "Jump to Bottom" button appears when paused ✓
- [x] **No-data state** — empty placeholder shown when `model.lines.isEmpty` ✓
- [x] **App Store** — `LogsSettingsView` reads `PersistentDiagnosticLog.logDirectory` which is available on both variants; file will be empty on App Store (streamer doesn't run), empty state handles it ✓
- [x] **`appendForTesting` test seam** — lets unit tests inject lines without file IO ✓
- [x] **Type consistency** — `LogLine.parse(raw:)` matches call sites; `LogTailModel.appendForTesting(_:)` matches test calls; `model.start(logDirectory:)` matches `onAppear` call ✓
