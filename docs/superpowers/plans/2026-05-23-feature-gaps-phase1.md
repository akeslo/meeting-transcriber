# Feature Gaps — Phase 1 Quick Wins

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement 11 low-complexity feature gaps: dock badge, LLM retry, retry UI, regex URL patterns, VAD presets, date filter, sort options, inline prompt editor, speaker confidence display, start-time edit, detection dry-run.

**Architecture:** Pure additions to existing files + 2 new view files. No new model migrations needed.

**Tech Stack:** Swift/SwiftUI, AppKit (NSApp.dockTile), AVFoundation (mic test), NSRegularExpression

---

## Task 1: Dock badge (#22)

**Files:**
- Modify: `app/MeetingTranscriber/Sources/AppState.swift`

- [ ] Read `AppState.swift` around the `pipelineQueue.isProcessing` observer — find where `isRecording`, `pipelineQueue` state is observed.
- [ ] Add a private `updateDockBadge()` method to `AppState` and call it from `pipelineQueue` job changes.

Add in `AppState` (after the `modelContext` didSet, before `isRecordingChannelUnhealthy`):

```swift
private func updateDockBadge() {
    let activeCount = pipelineQueue.jobs.filter { [.waiting, .transcribing, .diarizing, .generatingProtocol].contains($0.state) }.count
    DispatchQueue.main.async {
        NSApp.dockTile.badgeLabel = activeCount > 0 ? "\(activeCount)" : nil
    }
}
```

- [ ] In `MeetingTranscriberApp.swift`, inside the `.task` block that already sets `appState.modelContext`, also observe pipeline changes. Actually, add a `withObservationTracking` loop in `AppState.init()` or use `onChange` in the App scene.

The simplest approach: in `AppState`, add to `init()` after the pipeline queue is created:

```swift
Task { @MainActor [weak self] in
    while !Task.isCancelled {
        guard let self else { break }
        self.updateDockBadge()
        try? await Task.sleep(for: .seconds(2))
    }
}
```

- [ ] Build to verify: `cd app/MeetingTranscriber && swift build 2>&1 | tail -20`
- [ ] Commit: `git add app/MeetingTranscriber/Sources/AppState.swift && git commit -m "feat(app): dock badge shows active pipeline job count"`

---

## Task 2: Date filter + sort options in LibraryView (#6, #8)

**Files:**
- Modify: `app/MeetingTranscriber/Sources/DashboardWindow/LibraryView.swift`

- [ ] Add state vars and sort enum to `LibraryView`:

```swift
enum SessionSort: String, CaseIterable {
    case newestFirst = "Newest"
    case oldestFirst = "Oldest"
    case longestFirst = "Longest"
    case shortestFirst = "Shortest"
    case titleAZ = "Title A–Z"

    var label: String { rawValue }
}

// In LibraryView:
@State private var sortOrder: SessionSort = .newestFirst
@State private var filterStartDate: Date? = nil
@State private var filterEndDate: Date? = nil
@State private var showDateFilter: Bool = false
```

- [ ] Update `filterSessions` static method to accept date range:

```swift
static func filterSessions(
    _ sessions: [RecordingSession],
    searchText: String,
    tag: String? = nil,
    folder: String? = nil,
    startDate: Date? = nil,
    endDate: Date? = nil
) -> [RecordingSession] {
    sessions.filter { s in
        let matchesSearch = searchText.isEmpty
            || s.title.localizedCaseInsensitiveContains(searchText)
            || s.appName.localizedCaseInsensitiveContains(searchText)
            || s.participantNames.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
        let matchesTag = tag == nil || s.tags.contains(tag!)
        let matchesFolder = folder == nil || s.folderGroup == folder!
        let matchesStart = startDate == nil || s.createdAt >= startDate!
        let matchesEnd = endDate == nil || s.createdAt <= endDate!
        return matchesSearch && matchesTag && matchesFolder && matchesStart && matchesEnd
    }
}
```

- [ ] Add `sortedSessions` computed property after `filteredSessions`:

```swift
private var sortedSessions: [RecordingSession] {
    let filtered = Self.filterSessions(
        sessions, searchText: searchText, tag: selectedTag,
        folder: selectedFolder, startDate: filterStartDate, endDate: filterEndDate
    )
    switch sortOrder {
    case .newestFirst: return filtered.sorted { $0.createdAt > $1.createdAt }
    case .oldestFirst: return filtered.sorted { $0.createdAt < $1.createdAt }
    case .longestFirst: return filtered.sorted { $0.duration > $1.duration }
    case .shortestFirst: return filtered.sorted { $0.duration < $1.duration }
    case .titleAZ: return filtered.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }
}
```

- [ ] Replace uses of `filteredSessions` in the body with `sortedSessions`.

- [ ] Add sort picker + date filter button to the search bar row. Find the HStack containing the search field and layout toggle and add:

```swift
// Sort picker
Picker("", selection: $sortOrder) {
    ForEach(SessionSort.allCases, id: \.self) { s in
        Text(s.label).tag(s)
    }
}
.pickerStyle(.menu)
.labelsHidden()
.frame(width: 90)

// Date filter toggle
Button {
    showDateFilter.toggle()
} label: {
    Image(systemName: filterStartDate != nil || filterEndDate != nil ? "calendar.badge.clock" : "calendar")
        .foregroundStyle(filterStartDate != nil || filterEndDate != nil ? Color.accentColor : Color.secondary)
}
.buttonStyle(.plain)
.help("Filter by date range")
```

- [ ] Add date filter row below the search bar (shown when `showDateFilter`):

```swift
if showDateFilter {
    HStack(spacing: 8) {
        DatePicker("From", selection: Binding(
            get: { filterStartDate ?? Date.distantPast },
            set: { filterStartDate = $0 }
        ), displayedComponents: .date)
        .labelsHidden()
        DatePicker("To", selection: Binding(
            get: { filterEndDate ?? Date() },
            set: { filterEndDate = $0 }
        ), displayedComponents: .date)
        .labelsHidden()
        if filterStartDate != nil || filterEndDate != nil {
            Button("Clear") {
                filterStartDate = nil
                filterEndDate = nil
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 6)
}
```

- [ ] Build: `cd app/MeetingTranscriber && swift build 2>&1 | tail -20`
- [ ] Commit: `git add app/MeetingTranscriber/Sources/DashboardWindow/LibraryView.swift && git commit -m "feat(app): date range filter and sort options for library view"`

---

## Task 3: VAD presets (#20)

**Files:**
- Modify: `app/MeetingTranscriber/Sources/AppSettings.swift`
- Modify: `app/MeetingTranscriber/Sources/Settings/AudioSettingsView.swift`

- [ ] Add `VadPreset` enum and `vadPreset` property to `AppSettings.swift` near the `vadThreshold` property:

```swift
enum VadPreset: String, CaseIterable, Codable {
    case quiet = "quiet"
    case balanced = "balanced"
    case aggressive = "aggressive"
    case custom = "custom"

    var label: String {
        switch self {
        case .quiet: return "Quiet Room"
        case .balanced: return "Balanced"
        case .aggressive: return "Noisy Environment"
        case .custom: return "Custom"
        }
    }

    var threshold: Float? {
        switch self {
        case .quiet: return 0.3
        case .balanced: return 0.5
        case .aggressive: return 0.7
        case .custom: return nil
        }
    }
}

var vadPreset: VadPreset {
    didSet {
        defaults.set(vadPreset.rawValue, forKey: "vadPreset")
        if let t = vadPreset.threshold { vadThreshold = t }
    }
}
```

- [ ] In `AppSettings.init()`, load `vadPreset` (after the `vadThreshold` line):

```swift
vadPreset = (defaults.string(forKey: "vadPreset").flatMap(VadPreset.init(rawValue:))) ?? .balanced
```

- [ ] In `AudioSettingsView.swift`, replace or add above the existing VAD threshold slider:

```swift
// Preset row
HStack {
    Text("VAD Mode")
    Spacer()
    Picker("", selection: $settings.vadPreset) {
        ForEach(VadPreset.allCases, id: \.self) { p in
            Text(p.label).tag(p)
        }
    }
    .pickerStyle(.menu)
    .frame(width: 160)
    .onChange(of: settings.vadPreset) { _, preset in
        if let t = preset.threshold { settings.vadThreshold = t }
    }
}
```

- [ ] Build: `cd app/MeetingTranscriber && swift build 2>&1 | tail -20`
- [ ] Commit

---

## Task 4: Regex URL patterns (#17)

**Files:**
- Modify: `app/MeetingTranscriber/Sources/WatchedWebsite.swift`
- Modify: `app/MeetingTranscriber/Sources/BrowserTabDetector.swift`
- Modify: `app/MeetingTranscriber/Sources/Settings/GeneralSettingsView.swift`

- [ ] Add `useRegex: Bool` field to `WatchedWebsite`:

```swift
struct WatchedWebsite: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var urlPattern: String
    var enabled: Bool
    var recordMic: Bool
    var useRegex: Bool

    init(id: UUID = UUID(), name: String, urlPattern: String, enabled: Bool = true, recordMic: Bool = false, useRegex: Bool = false) {
        self.id = id
        self.name = name
        self.urlPattern = urlPattern
        self.enabled = enabled
        self.recordMic = recordMic
        self.useRegex = useRegex
    }
}
```

- [ ] In `BrowserTabDetector.swift`, find where URL matching happens (the method that checks `urlPattern`) and update it:

```swift
private func matches(url: String, site: WatchedWebsite) -> Bool {
    if site.useRegex {
        guard let regex = try? NSRegularExpression(pattern: site.urlPattern, options: .caseInsensitive) else { return false }
        let range = NSRange(url.startIndex..., in: url)
        return regex.firstMatch(in: url, range: range) != nil
    }
    return url.contains(site.urlPattern)
}
```

Replace all inline `url.contains(site.urlPattern)` calls with `matches(url:site:)`.

- [ ] In `GeneralSettingsView.swift`, find the watched-websites editor row and add a "Regex" toggle next to the URL pattern field.

- [ ] Build + commit

---

## Task 5: Inline prompt editor (#9)

**Files:**
- Create: `app/MeetingTranscriber/Sources/Settings/PromptEditorSheet.swift`
- Modify: `app/MeetingTranscriber/Sources/Settings/OutputSettingsView.swift`

- [ ] Create `PromptEditorSheet.swift`:

```swift
import SwiftUI

struct PromptEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""
    private let promptURL: URL

    init() {
        promptURL = AppPaths.customPromptFile
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Protocol Prompt")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            TextEditor(text: $content)
                .font(.system(size: 12, design: .monospaced))
                .padding(12)
                .frame(minHeight: 300)

            Divider()

            HStack {
                Button("Reset to Default") {
                    content = ProtocolGenerator.defaultPrompt
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 600, minHeight: 440)
        .onAppear {
            content = (try? String(contentsOf: promptURL, encoding: .utf8))
                ?? ProtocolGenerator.defaultPrompt
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: promptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? content.write(to: promptURL, atomically: true, encoding: .utf8)
    }
}
```

- [ ] In `OutputSettingsView.swift`, find the "Edit in Finder" / prompt-related button and replace with:

```swift
@State private var showPromptEditor = false

// In the relevant Section:
Button("Edit Prompt…") {
    showPromptEditor = true
}
.sheet(isPresented: $showPromptEditor) {
    PromptEditorSheet()
}
```

- [ ] Check that `ProtocolGenerator.defaultPrompt` is accessible (it may be `ProtocolGenerator.loadPrompt()` pattern — read `ProtocolGenerator.swift` to confirm and adjust).

- [ ] Build + commit

---

## Task 6: LLM retry with backoff (#29)

**Files:**
- Modify: `app/MeetingTranscriber/Sources/OpenAIProtocolGenerator.swift`
- Modify: `app/MeetingTranscriber/Sources/ClaudeCLIProtocolGenerator.swift`

- [ ] In `OpenAIProtocolGenerator.swift`, wrap the `generate` body in a retry loop. Add a private helper at the bottom:

```swift
private func generateOnce(transcript: String, title: String, diarized: Bool) async throws -> String {
    // move entire existing generate() body here
}

func generate(transcript: String, title: String, diarized: Bool) async throws -> String {
    var lastError: Error = ProtocolError.connectionFailed("No attempts made")
    for attempt in 1...3 {
        do {
            return try await generateOnce(transcript: transcript, title: title, diarized: diarized)
        } catch ProtocolError.connectionFailed(let msg) {
            lastError = ProtocolError.connectionFailed(msg)
            if attempt < 3 {
                let delay = Double(attempt * attempt) * 2.0  // 2s, 8s
                logger.warning("openai_retry attempt=\(attempt) delay=\(delay)s")
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        // Non-connection errors (bad API key, invalid response) propagate immediately
    }
    throw lastError
}
```

- [ ] Apply same pattern to `ClaudeCLIProtocolGenerator.swift` (rename existing `generate` → `generateOnce`, add retry wrapper). Only retry on `ProtocolError.timeout` and `ProtocolError.connectionFailed`.

- [ ] Build + test: `cd app/MeetingTranscriber && swift test --parallel -v 2>&1 | grep -E "passed|failed|error" | tail -20`
- [ ] Commit

---

## Task 7: Retry UI for failed sessions (#24)

**Files:**
- Modify: `app/MeetingTranscriber/Sources/DashboardWindow/DetailPaneView.swift`

- [ ] In the `DetailPaneView` struct, add a `var onRetry: ((RecordingSession) -> Void)?` parameter.

- [ ] In the `sessionDetail` view, in the actions HStack section, add a retry button that shows only when `session.status == "error"`:

```swift
if session.status == SessionStatus.error.rawValue {
    Button {
        onRetry?(session)
    } label: {
        Image(systemName: "arrow.clockwise")
    }
    .buttonStyle(.bordered)
    .help("Retry transcription")
}
```

- [ ] In `DashboardWindowContent.swift`, wire up `onRetry` to re-enqueue the session:

```swift
onRetry: { session in
    pipelineQueue.retrySession(session, outputDir: settings.effectiveOutputDir)
}
```

- [ ] In `PipelineQueue.swift`, add `retrySession`:

```swift
func retrySession(_ session: RecordingSession, outputDir: URL) {
    let folder = outputDir.appendingPathComponent(session.folderPath)
    let audioFiles: [URL] = session.audioFiles.compactMap { name in
        let url = folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    guard !audioFiles.isEmpty else { return }
    session.status = SessionStatus.waiting.rawValue
    session.errorMessage = nil
    let job = PipelineJob(
        title: session.title,
        appName: session.appName,
        audioFiles: audioFiles,
        sessionID: session.id
    )
    enqueue(job)
}
```

- [ ] Build + commit

---

## Task 8: Speaker confidence display (#14)

**Files:**
- Modify: `app/MeetingTranscriber/Sources/KnownVoicesView.swift`
- Modify: `app/MeetingTranscriber/Sources/StoredSpeaker.swift` (read first)

- [ ] Read `StoredSpeaker.swift` to see what stats are available.

- [ ] In `KnownVoicesView`, in the table row for each speaker, add a stats column showing:
  - Recognition count (from `RecognitionStatsLog` or stored on `StoredSpeaker`)
  - Average confidence (if `StoredSpeaker` has it — else show sample count)

```swift
// If StoredSpeaker has `embeddings` (recent samples) and `centroid`:
Text(String(format: "%.0f%%", speaker.centroid != nil ? 100.0 * (1.0 - (speaker.centroid!.min() ?? 0)) : 0))
    .font(.system(size: 11))
    .foregroundStyle(.secondary)
```

- [ ] If confidence isn't directly available, show `embeddings.count` samples as a proxy confidence indicator with a filled-circle glyph (●●●○○).

- [ ] Build + commit

---

## Task 9: Start-time edit (#30)

**Files:**
- Modify: `app/MeetingTranscriber/Sources/DashboardWindow/DetailPaneView.swift`

- [ ] In `sessionDetail`, replace the calendar metadata chip with a tappable date that shows a `DatePicker` popover:

```swift
@State private var showDatePicker = false

// Replace metadataChip for createdAt with:
Button {
    showDatePicker.toggle()
} label: {
    HStack(spacing: 4) {
        Image(systemName: "calendar")
            .font(.system(size: 11))
        Text(Self.dateFormatter.string(from: session.createdAt))
            .font(.system(size: 11))
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Color.secondary.opacity(0.1))
    .clipShape(Capsule())
}
.buttonStyle(.plain)
.popover(isPresented: $showDatePicker) {
    DatePicker(
        "Recording Date",
        selection: Binding(
            get: { session.createdAt },
            set: { newDate in
                session.createdAt = newDate
                try? modelContext.save()
                let dir = AppPaths.transcriberRoot.appendingPathComponent(session.folderPath)
                // Update meta.json if needed
            }
        ),
        displayedComponents: [.date, .hourAndMinute]
    )
    .datePickerStyle(.graphical)
    .padding()
    .frame(width: 300)
}
```

- [ ] Build + commit

---

## Task 10: Detection dry-run (#18)

**Files:**
- Modify: `app/MeetingTranscriber/Sources/Settings/GeneralSettingsView.swift`
- Modify: `app/MeetingTranscriber/Sources/AppState.swift`

- [ ] Add to `AppState`:

```swift
@MainActor
func runDetectionDryRun() async -> String {
    guard let watchLoop else { return "Watch loop not started." }
    // Run one detection poll cycle
    let result = await watchLoop.runOnePoll()
    if let meeting = result {
        return "Detected: \"\(meeting.appName)\" via \(meeting.source)"
    }
    return "No meeting detected in current state."
}
```

Note: `WatchLoop.runOnePoll()` may not exist — add a public method there that calls the detector once and returns a `DetectedMeeting?`.

- [ ] In `GeneralSettingsView.swift`, in the detection section, add:

```swift
@State private var dryRunResult: String? = nil
@State private var isRunningDryRun = false

Button(isRunningDryRun ? "Testing…" : "Test Detection Now") {
    isRunningDryRun = true
    Task {
        dryRunResult = await appState.runDetectionDryRun()
        isRunningDryRun = false
    }
}
.disabled(isRunningDryRun)

if let result = dryRunResult {
    Text(result)
        .font(.system(size: 11))
        .foregroundStyle(result.hasPrefix("Detected") ? .green : .secondary)
        .fixedSize(horizontal: false, vertical: true)
}
```

- [ ] Build + commit

---

## Phase 1 Complete

Run full test suite: `cd app/MeetingTranscriber && swift test --parallel 2>&1 | tail -30`

Commit all remaining unstaged: stage and commit any cleanup.
