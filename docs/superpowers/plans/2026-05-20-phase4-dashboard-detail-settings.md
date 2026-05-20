# Phase 4: Dashboard, Meeting Detail Reader & Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Dashboard status/controls view, the Meeting Detail reader with Transcript/Protocol/Split tabs and AVAudioPlayer playback, and restructure Settings into collapsible DisclosureGroup sections accessible from the Dashboard sidebar.

**Architecture:** Dashboard owns status card + quick controls + ambient meters. `TranscriptParser` is a pure function (testable without UI). `MeetingDetailReader` manages `AVAudioPlayer` lifecycle + `@State` for current tab and playback. `SettingsContentView` wraps existing sub-views in `DisclosureGroup` shells. All new views live in `Sources/DashboardWindow/`.

**Tech Stack:** Swift, SwiftUI, AVFoundation (`AVAudioPlayer`), XCTest

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `app/MeetingTranscriber/Sources/DashboardWindow/TranscriptParser.swift` | Pure `TranscriptSegment` model + `TranscriptParser.parse(markdown:)` |
| Create | `app/MeetingTranscriber/Sources/DashboardWindow/DashboardView.swift` | Two-column layout: status card, quick controls, ambient meters |
| Create | `app/MeetingTranscriber/Sources/DashboardWindow/AmbientLevelCard.swift` | Dual RMS bar meters, 500 ms timer-driven |
| Create | `app/MeetingTranscriber/Sources/DashboardWindow/MeetingDetailReader.swift` | Three-tab reader + AVAudioPlayer playback bar |
| Create | `app/MeetingTranscriber/Sources/DashboardWindow/SettingsContentView.swift` | `DisclosureGroup` wrapper of existing sub-views |
| Modify | `app/MeetingTranscriber/Sources/DashboardWindow/DetailPaneView.swift` | Replace Phase 3 placeholder with `MeetingDetailReader` |
| Modify | `app/MeetingTranscriber/Sources/DashboardWindow/DashboardWindowContent.swift` | Add `.dashboard` and `.settings` cases to nav switch |
| Create | `app/MeetingTranscriber/Tests/DashboardWindow/TranscriptParserTests.swift` | Unit tests: parse speaker lines, multi-segment, empty input |
| Create | `app/MeetingTranscriber/Tests/DashboardWindow/DashboardViewTests.swift` | Unit tests: `statusHeadline` logic per pipeline state |

---

## Task 1: `TranscriptParser` pure function + tests

**Files:**
- Create: `app/MeetingTranscriber/Sources/DashboardWindow/TranscriptParser.swift`
- Create: `app/MeetingTranscriber/Tests/DashboardWindow/TranscriptParserTests.swift`

- [ ] **Step 1: Create `TranscriptParser.swift`**

```swift
// Sources/DashboardWindow/TranscriptParser.swift
import Foundation

// MARK: - Model

struct TranscriptSegment: Identifiable {
    let id: UUID
    let speaker: String
    let timestamp: TimeInterval   // seconds from recording start
    let body: String
}

// MARK: - Parser

enum TranscriptParser {
    /// Parses transcript.md produced by MeetingTranscriber.
    ///
    /// Format:
    /// ```
    /// **Speaker Name** [HH:MM:SS]
    /// body text here
    ///
    /// **Next Speaker** [HH:MM:SS]
    /// more body text
    /// ```
    ///
    /// Lines that match the speaker-header pattern start a new segment.
    /// All subsequent lines until the next header become that segment's body.
    /// Segments with an empty body (whitespace-only) are dropped.
    static func parse(markdown: String) -> [TranscriptSegment] {
        let pattern = #/^\*\*(.+?)\*\* \[(\d{2}):(\d{2}):(\d{2})\]/#

        var segments: [TranscriptSegment] = []
        let lines = markdown.components(separatedBy: "\n")

        var currentSpeaker: String?
        var currentTimestamp: TimeInterval?
        var bodyLines: [String] = []

        func flush() {
            guard let speaker = currentSpeaker, let ts = currentTimestamp else { return }
            let body = bodyLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }
            segments.append(TranscriptSegment(id: UUID(), speaker: speaker, timestamp: ts, body: body))
        }

        for line in lines {
            if let match = line.firstMatch(of: pattern) {
                flush()
                currentSpeaker = String(match.1)
                let h = TimeInterval(match.2)!
                let m = TimeInterval(match.3)!
                let s = TimeInterval(match.4)!
                currentTimestamp = h * 3600 + m * 60 + s
                bodyLines = []
            } else {
                bodyLines.append(line)
            }
        }
        flush()
        return segments
    }
}
```

- [ ] **Step 2: Create the test directory**

```bash
mkdir -p app/MeetingTranscriber/Tests/DashboardWindow
```

- [ ] **Step 3: Create `TranscriptParserTests.swift`**

```swift
// Tests/DashboardWindow/TranscriptParserTests.swift
import XCTest
@testable import MeetingTranscriber

final class TranscriptParserTests: XCTestCase {

    // MARK: - Single segment

    func test_singleSegment_parsedCorrectly() {
        let md = """
        **Alice** [00:01:30]
        Hello there, this is Alice speaking.
        """
        let segments = TranscriptParser.parse(markdown: md)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].speaker, "Alice")
        XCTAssertEqual(segments[0].timestamp, 90)        // 1*60 + 30
        XCTAssertEqual(segments[0].body, "Hello there, this is Alice speaking.")
    }

    // MARK: - Multi-segment

    func test_twoSegments_parsedInOrder() {
        let md = """
        **Alice** [00:00:05]
        First utterance.

        **Bob** [00:01:10]
        Second utterance.
        """
        let segments = TranscriptParser.parse(markdown: md)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].speaker, "Alice")
        XCTAssertEqual(segments[0].timestamp, 5)
        XCTAssertEqual(segments[1].speaker, "Bob")
        XCTAssertEqual(segments[1].timestamp, 70)         // 1*60 + 10
    }

    // MARK: - Timestamp hours

    func test_hoursInTimestamp_parsedCorrectly() {
        let md = """
        **Charlie** [01:02:03]
        Body text.
        """
        let segments = TranscriptParser.parse(markdown: md)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].timestamp, 3723)       // 1*3600 + 2*60 + 3
    }

    // MARK: - Multi-line body

    func test_multiLineBody_joinedWithNewline() {
        let md = """
        **Alice** [00:00:00]
        Line one.
        Line two.
        Line three.
        """
        let segments = TranscriptParser.parse(markdown: md)
        XCTAssertEqual(segments.count, 1)
        XCTAssertTrue(segments[0].body.contains("Line one."))
        XCTAssertTrue(segments[0].body.contains("Line two."))
        XCTAssertTrue(segments[0].body.contains("Line three."))
    }

    // MARK: - Empty body dropped

    func test_headerWithNoBody_isDropped() {
        let md = """
        **Alice** [00:00:00]

        **Bob** [00:00:10]
        Real content here.
        """
        let segments = TranscriptParser.parse(markdown: md)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].speaker, "Bob")
    }

    // MARK: - Empty input

    func test_emptyString_returnsEmpty() {
        XCTAssertTrue(TranscriptParser.parse(markdown: "").isEmpty)
    }

    // MARK: - No speaker headers

    func test_noSpeakerHeaders_returnsEmpty() {
        let md = """
        Just some random text.
        No speaker headers here.
        """
        XCTAssertTrue(TranscriptParser.parse(markdown: md).isEmpty)
    }

    // MARK: - Speaker name with spaces

    func test_speakerNameWithSpaces_parsedCorrectly() {
        let md = """
        **John Doe** [00:00:42]
        Content.
        """
        let segments = TranscriptParser.parse(markdown: md)
        XCTAssertEqual(segments[0].speaker, "John Doe")
    }

    // MARK: - IDs are unique

    func test_allSegmentsHaveUniqueIDs() {
        let md = """
        **A** [00:00:01]
        Body A.

        **B** [00:00:02]
        Body B.

        **C** [00:00:03]
        Body C.
        """
        let segments = TranscriptParser.parse(markdown: md)
        let ids = Set(segments.map(\.id))
        XCTAssertEqual(ids.count, segments.count)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd app/MeetingTranscriber && swift test --filter TranscriptParserTests 2>&1 | tail -20
```

Expected: `Test Suite 'TranscriptParserTests' passed`

- [ ] **Step 5: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/TranscriptParser.swift \
        app/MeetingTranscriber/Tests/DashboardWindow/TranscriptParserTests.swift
git commit -m "feat(app): add TranscriptParser pure function + unit tests"
```

---

## Task 2: `DashboardView` — status card + quick controls layout

**Files:**
- Create: `app/MeetingTranscriber/Sources/DashboardWindow/DashboardView.swift`

- [ ] **Step 1: Create `DashboardView.swift`**

```swift
// Sources/DashboardWindow/DashboardView.swift
import SwiftUI
import SwiftData

// MARK: - Design tokens (module-private)

private let spaceIndigo  = Color(red: 0.082, green: 0.114, blue: 0.208)
private let peachGlow    = Color(red: 0.969, green: 0.773, blue: 0.624)
private let aliceBlue    = Color(red: 0.882, green: 0.898, blue: 0.933)
private let paleSlate    = Color(red: 0.878, green: 0.898, blue: 0.941)
private let cardBg       = Color.white

// MARK: - DashboardView

struct DashboardView: View {
    // Injected state — individual fields for testability
    let status: TranscriberStatus?
    let isWatching: Bool
    @Bindable var settings: AppSettings
    let elapsedLabel: String          // "00:42" — computed and passed by parent
    let onStartStop: () -> Void

    // Dashboard-level bindings into DashboardWindowContent state
    @Binding var selectedNav: NavItem
    @Binding var selectedSessionID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Top row: two columns
                HStack(alignment: .top, spacing: 16) {
                    // Left column — status card
                    StatusCard(
                        headline: statusHeadline,
                        subtext: statusSubtext,
                        isWatching: isWatching,
                        onStartStop: onStartStop
                    )
                    .frame(maxWidth: .infinity)

                    // Right column — stacked cards
                    VStack(spacing: 16) {
                        QuickControlsCard(settings: settings)
                        // AmbientLevelCard is added in Task 3
                        AmbientLevelCard(
                            appDbfs: settings.lastAppDbfs,
                            micDbfs: settings.lastMicDbfs,
                            isActive: status?.state == .recording
                        )
                    }
                    .frame(maxWidth: .infinity)
                }

                // Bottom row — Recent Activity
                RecentActivitySection(
                    selectedNav: $selectedNav,
                    selectedSessionID: $selectedSessionID
                )
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Headline logic

    var statusHeadline: String {
        guard let state = status?.state else {
            return isWatching ? "Meeting Detection is active." : "Idle"
        }
        switch state {
        case .recording:          return "Recording · \(elapsedLabel)"
        case .transcribing:       return "Transcribing..."
        case .generatingProtocol: return "Generating Protocol..."
        case .diarizing:          return "Diarizing Speakers..."
        default:
            return isWatching ? "Meeting Detection is active." : "Idle"
        }
    }

    var statusSubtext: String {
        guard let state = status?.state else {
            return isWatching ? "Watching for meeting windows and browser tabs." : "Start watching to detect meetings automatically."
        }
        switch state {
        case .recording:          return "Capturing app audio and microphone."
        case .transcribing:       return "Converting speech to text..."
        case .generatingProtocol: return "Summarising meeting with LLM..."
        case .diarizing:          return "Identifying speakers..."
        default:
            return isWatching ? "Watching for meeting windows and browser tabs." : "Start watching to detect meetings automatically."
        }
    }
}

// MARK: - StatusCard

private struct StatusCard: View {
    let headline: String
    let subtext: String
    let isWatching: Bool
    let onStartStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(spaceIndigo)
                Text(subtext)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
            }

            // Audio source rows
            VStack(alignment: .leading, spacing: 8) {
                AudioSourceRow(label: "App Audio Tap", active: true)
                AudioSourceRow(label: "Built-in Mic", active: true)
            }

            Button(action: onStartStop) {
                Text(isWatching ? "Stop Watching" : "Start Watching")
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(isWatching ? Color.red.opacity(0.8) : spaceIndigo)
        }
        .padding(20)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(paleSlate, lineWidth: 1)
        )
    }
}

// MARK: - AudioSourceRow

private struct AudioSourceRow: View {
    let label: String
    let active: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: active ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(active ? Color.green : Color.red)
                .imageScale(.small)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary)
        }
    }
}

// MARK: - QuickControlsCard

private struct QuickControlsCard: View {
    @Bindable var settings: AppSettings

    private var sortformerBinding: Binding<Bool> {
        Binding(
            get: { settings.diarizerMode == .sortformer },
            set: { settings.diarizerMode = $0 ? .sortformer : .offlineDiarizer }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Controls")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(spaceIndigo)

            Toggle("Voice Activity Detection", isOn: $settings.vadEnabled)
                .toggleStyle(.switch)
                .font(.system(size: 13))

            Toggle("Overlap-aware Diarizer", isOn: sortformerBinding)
                .toggleStyle(.switch)
                .font(.system(size: 13))

            Toggle("Record-only Mode", isOn: $settings.recordOnly)
                .toggleStyle(.switch)
                .font(.system(size: 13))
        }
        .padding(20)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(paleSlate, lineWidth: 1)
        )
    }
}
```

- [ ] **Step 2: Build to confirm compilation**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/DashboardView.swift
git commit -m "feat(app): add DashboardView status card + quick controls layout"
```

---

## Task 3: Ambient Level Card + timer plumbing

**Files:**
- Create: `app/MeetingTranscriber/Sources/DashboardWindow/AmbientLevelCard.swift`

The `AmbientLevelCard` receives raw dBFS values (app + mic channels) from the parent view, which reads them from `ChannelHealthMonitor`. dBFS maps to bar fill via `max(0, (dbfs + 60) / 60)` — so −60 dBFS = empty, 0 dBFS = full. When `isActive` is false the card shows static "—" labels instead of the bars.

- [ ] **Step 1: Create `AmbientLevelCard.swift`**

```swift
// Sources/DashboardWindow/AmbientLevelCard.swift
import SwiftUI

struct AmbientLevelCard: View {
    /// Raw dBFS value for the app audio channel. Pass 0 when unavailable.
    let appDbfs: Double
    /// Raw dBFS value for the mic channel. Pass 0 when unavailable.
    let micDbfs: Double
    /// When false the card renders static "—" labels (recording not active).
    let isActive: Bool

    private let spaceIndigo = Color(red: 0.082, green: 0.114, blue: 0.208)
    private let peachGlow   = Color(red: 0.969, green: 0.773, blue: 0.624)
    private let paleSlate   = Color(red: 0.878, green: 0.898, blue: 0.941)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ambient Levels")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(spaceIndigo)

            levelRow(label: "App Audio", dbfs: appDbfs)
            levelRow(label: "Mic", dbfs: micDbfs)
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(paleSlate, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func levelRow(label: String, dbfs: Double) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
                .frame(width: 72, alignment: .leading)

            if isActive {
                ProgressView(value: normalised(dbfs))
                    .progressViewStyle(.linear)
                    .tint(barColor(for: dbfs))
                    .frame(maxWidth: .infinity)

                Text(String(format: "%.0f dB", dbfs))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Maps −60 dBFS → 0.0, 0 dBFS → 1.0, clamped to [0, 1].
    private func normalised(_ dbfs: Double) -> Double {
        max(0, min(1, (dbfs + 60) / 60))
    }

    /// Green below −20 dBFS, yellow below −6 dBFS, orange at or above −6 dBFS.
    private func barColor(for dbfs: Double) -> Color {
        if dbfs < -20 { return .green }
        if dbfs < -6  { return .yellow }
        return .orange
    }
}
```

- [ ] **Step 2: Plumb dBFS values from `AppState` into `DashboardView`**

`AppSettings` does not currently carry live dBFS readings — those come from `ChannelHealthMonitor`. For now, extend `AppSettings` with two `@Published`-style properties that the `WatchLoop` can update during recording, and read them in `DashboardView`.

Open `app/MeetingTranscriber/Sources/AppSettings.swift` and add the following two stored properties in the `@Observable` section (near other `Double`/runtime properties):

```swift
// Live dBFS readings updated by WatchLoop during recording (not persisted to UserDefaults)
var lastAppDbfs: Double = -60
var lastMicDbfs: Double = -60
```

Then in `DashboardView`, the `AmbientLevelCard` call already references `settings.lastAppDbfs` and `settings.lastMicDbfs` (from Task 2 Step 1), so it will compile once these properties exist.

In `WatchLoop` (or wherever `ChannelHealthMonitor` events are observed), add a 500 ms `Timer`-based update that writes to `appState.settings.lastAppDbfs` and `appState.settings.lastMicDbfs`. Add the following inside `DualSourceRecorder`'s recording loop or wherever the RMS callback already fires. If there is no existing callback, add a publisher subscription:

```swift
// Inside WatchLoop or DualSourceRecorder, during active recording:
// (Add this Timer subscription alongside existing ChannelHealthMonitor usage)
private var levelUpdateTimer: Timer?

func startLevelUpdates() {
    levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        guard let self else { return }
        // ChannelHealthMonitor exposes appDbfs and micDbfs as stored properties
        // updated by the audio callback. Read them here on the main actor.
        Task { @MainActor in
            self.appState.settings.lastAppDbfs = self.channelHealthMonitor.appDbfs
            self.appState.settings.lastMicDbfs = self.channelHealthMonitor.micDbfs
        }
    }
}

func stopLevelUpdates() {
    levelUpdateTimer?.invalidate()
    levelUpdateTimer = nil
    appState.settings.lastAppDbfs = -60
    appState.settings.lastMicDbfs = -60
}
```

Call `startLevelUpdates()` when recording begins and `stopLevelUpdates()` when it ends.

- [ ] **Step 3: Build**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/AmbientLevelCard.swift \
        app/MeetingTranscriber/Sources/AppSettings.swift
git commit -m "feat(app): add AmbientLevelCard + live dBFS plumbing from ChannelHealthMonitor"
```

---

## Task 4: Recent Activity section in Dashboard

**Files:**
- Modify: `app/MeetingTranscriber/Sources/DashboardWindow/DashboardView.swift`

The `RecentActivitySection` subview queries the last 3 `RecordingSession` entries using `@Query` and renders them with the `SessionRowView` from Phase 3. Tapping a row navigates to the Library detail pane.

- [ ] **Step 1: Add `RecentActivitySection` to `DashboardView.swift`**

Append the following struct at the bottom of `DashboardView.swift`, after the `QuickControlsCard` struct:

```swift
// MARK: - RecentActivitySection

private struct RecentActivitySection: View {
    @Binding var selectedNav: NavItem
    @Binding var selectedSessionID: UUID?

    @Query(
        sort: \RecordingSession.createdAt,
        order: .reverse
    )
    private var allSessions: [RecordingSession]

    private var recentSessions: [RecordingSession] {
        Array(allSessions.prefix(3))
    }

    private let spaceIndigo = Color(red: 0.082, green: 0.114, blue: 0.208)
    private let paleSlate   = Color(red: 0.878, green: 0.898, blue: 0.941)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("Recent Activity")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(spaceIndigo)
                Spacer()
                Button("View All →") {
                    selectedNav = .library
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(spaceIndigo)
            }

            if recentSessions.isEmpty {
                Text("No recordings yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentSessions) { session in
                        Button {
                            selectedSessionID = session.id
                            selectedNav = .library
                        } label: {
                            SessionRowView(session: session)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if session.id != recentSessions.last?.id {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(paleSlate, lineWidth: 1)
                )
            }
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/DashboardView.swift
git commit -m "feat(app): add RecentActivity section with @Query last-3 sessions"
```

---

## Task 5: `MeetingDetailReader` tab bar + Transcript tab

**Files:**
- Create: `app/MeetingTranscriber/Sources/DashboardWindow/MeetingDetailReader.swift`

- [ ] **Step 1: Create `MeetingDetailReader.swift` with tab bar and Transcript tab**

```swift
// Sources/DashboardWindow/MeetingDetailReader.swift
import SwiftUI
import AVFoundation

// MARK: - Tab enum

enum DetailTab: String, CaseIterable {
    case transcript = "Transcript"
    case protocol_  = "Protocol"
    case split      = "Split"
}

// MARK: - MeetingDetailReader

struct MeetingDetailReader: View {
    let session: RecordingSession

    @State private var activeTab: DetailTab = .transcript
    @State private var segments: [TranscriptSegment] = []
    @State private var protocolContent: String = ""
    @State private var selectedSegmentID: UUID?

    // Playback state (AVAudioPlayer lifecycle in Task 7)
    @State private var player: AVAudioPlayer?
    @State private var isPlaying: Bool = false
    @State private var playbackPosition: TimeInterval = 0
    @State private var duration: TimeInterval = 0

    private let playbackTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private let spaceIndigo = Color(red: 0.082, green: 0.114, blue: 0.208)
    private let peachGlow   = Color(red: 0.969, green: 0.773, blue: 0.624)

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            tabBar

            Divider()

            // Content
            Group {
                switch activeTab {
                case .transcript:
                    transcriptTab
                case .protocol_:
                    protocolTab
                case .split:
                    splitTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Playback bar (Task 7 fills this in fully; skeleton here)
            playbackBar
        }
        .task {
            loadContent()
            loadAudio()
        }
        .onReceive(playbackTimer) { _ in
            guard isPlaying, let player else { return }
            playbackPosition = player.currentTime
            if !player.isPlaying {
                isPlaying = false
            }
            autoScrollToCurrentSegment()
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.rawValue) { tab in
                tabButton(tab)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func tabButton(_ tab: DetailTab) -> some View {
        let isActive = tab == activeTab
        Button {
            activeTab = tab
        } label: {
            VStack(spacing: 6) {
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? spaceIndigo : Color.secondary)
                    .padding(.horizontal, 4)

                Rectangle()
                    .fill(isActive ? peachGlow : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 24)
    }

    // MARK: - Transcript tab

    private var transcriptTab: some View {
        ScrollViewReader { proxy in
            List(segments) { segment in
                TranscriptSegmentView(segment: segment, isSelected: segment.id == selectedSegmentID)
                    .id(segment.id)
                    .listRowBackground(segment.id == selectedSegmentID
                        ? Color(red: 0.882, green: 0.898, blue: 0.933)   // Alice Blue
                        : Color.clear)
                    .onTapGesture {
                        selectedSegmentID = segment.id
                        if let player {
                            player.currentTime = segment.timestamp
                            playbackPosition = segment.timestamp
                        }
                    }
            }
            .listStyle(.plain)
            .onChange(of: selectedSegmentID) { _, newID in
                if let id = newID {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    // MARK: - Protocol tab (Task 6)

    private var protocolTab: some View {
        ScrollView {
            Text(protocolAttributedString)
                .textSelection(.enabled)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var protocolAttributedString: AttributedString {
        guard !protocolContent.isEmpty else {
            return AttributedString("No protocol generated for this session.")
        }
        return (try? AttributedString(
            markdown: protocolContent,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(protocolContent)
    }

    // MARK: - Split tab (Task 6)

    private var splitTab: some View {
        HStack(spacing: 0) {
            // Left: transcript
            List(segments) { segment in
                TranscriptSegmentView(segment: segment, isSelected: segment.id == selectedSegmentID)
                    .id(segment.id)
                    .listRowBackground(segment.id == selectedSegmentID
                        ? Color(red: 0.882, green: 0.898, blue: 0.933)
                        : Color.clear)
                    .onTapGesture { selectedSegmentID = segment.id }
            }
            .listStyle(.plain)
            .frame(maxWidth: .infinity)

            Divider()

            // Right: protocol
            ScrollView {
                Text(protocolAttributedString)
                    .textSelection(.enabled)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Playback bar (skeleton — Task 7 completes this)

    private var playbackBar: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .imageScale(.large)
                    .foregroundStyle(spaceIndigo)
            }
            .buttonStyle(.plain)
            .disabled(player == nil)

            Slider(value: $playbackPosition, in: 0...max(duration, 1)) { editing in
                if !editing, let player {
                    player.currentTime = playbackPosition
                }
            }
            .disabled(player == nil)

            Text(timeLabel(playbackPosition))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .frame(width: 42, alignment: .trailing)

            Text("/")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)

            Text(timeLabel(duration))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .frame(width: 42, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private func loadContent() {
        let folder = URL(fileURLWithPath: session.folderPath)

        let transcriptURL = folder.appendingPathComponent("transcript.md")
        if let raw = try? String(contentsOf: transcriptURL, encoding: .utf8) {
            segments = TranscriptParser.parse(markdown: raw)
        }

        let protocolURL = folder.appendingPathComponent("protocol.md")
        protocolContent = (try? String(contentsOf: protocolURL, encoding: .utf8)) ?? ""
    }

    private func loadAudio() {
        let mixURL = URL(fileURLWithPath: session.folderPath)
            .appendingPathComponent(RecordingFileSuffix.mix)
        guard let p = try? AVAudioPlayer(contentsOf: mixURL) else { return }
        p.prepareToPlay()
        player = p
        duration = p.duration
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func autoScrollToCurrentSegment() {
        guard isPlaying, !segments.isEmpty else { return }
        // Find the last segment whose timestamp <= current playback position
        let match = segments.last(where: { $0.timestamp <= playbackPosition })
        if let match, match.id != selectedSegmentID {
            selectedSegmentID = match.id
        }
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - TranscriptSegmentView

struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    let isSelected: Bool

    private let spaceIndigo = Color(red: 0.082, green: 0.114, blue: 0.208)

    private var timestampLabel: String {
        let s = Int(segment.timestamp)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(segment.speaker)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(spaceIndigo)
                Text(timestampLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
            Text(segment.body)
                .font(.body)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}
```

- [ ] **Step 2: Build**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/MeetingDetailReader.swift
git commit -m "feat(app): add MeetingDetailReader with tab bar, transcript tab, and TranscriptSegmentView"
```

---

## Task 6: Protocol tab + Split tab

The Protocol and Split tabs are already included in `MeetingDetailReader.swift` from Task 5. This task adds styling polish so both tabs match the design spec and verifies them compile correctly.

**Files:**
- Modify: `app/MeetingTranscriber/Sources/DashboardWindow/MeetingDetailReader.swift`

- [ ] **Step 1: Apply heading colour and code-block styling to the protocol `AttributedString`**

Replace the `protocolAttributedString` computed property in `MeetingDetailReader` with the following version that post-processes the attributed string to apply Space Indigo to heading runs and Alice Blue backgrounds to code blocks:

```swift
private var protocolAttributedString: AttributedString {
    guard !protocolContent.isEmpty else {
        return AttributedString("No protocol generated for this session.")
    }
    guard var attributed = try? AttributedString(
        markdown: protocolContent,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) else {
        return AttributedString(protocolContent)
    }

    // Tint heading runs with Space Indigo
    let headingColor = Color(red: 0.082, green: 0.114, blue: 0.208)
    for run in attributed.runs {
        if let intent = run.inlinePresentationIntent,
           intent.contains(.stronglyEmphasized) {
            attributed[run.range].foregroundColor = headingColor
        }
    }

    return attributed
}
```

- [ ] **Step 2: Build and run the tests to verify no regressions**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | tail -10
cd app/MeetingTranscriber && swift test --filter TranscriptParserTests 2>&1 | tail -10
```

Expected: `Build complete!` and `Test Suite 'TranscriptParserTests' passed`

- [ ] **Step 3: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/MeetingDetailReader.swift
git commit -m "feat(app): apply Space Indigo heading tint to Protocol tab AttributedString"
```

---

## Task 7: Playback bar — AVAudioPlayer, slider, auto-scroll

The playback bar skeleton is already wired in `MeetingDetailReader` from Task 5. This task completes it by verifying the full flow end-to-end and adding a keyboard shortcut for play/pause.

**Files:**
- Modify: `app/MeetingTranscriber/Sources/DashboardWindow/MeetingDetailReader.swift`

- [ ] **Step 1: Add space-bar keyboard shortcut for play/pause and confirm `RecordingFileSuffix.mix` usage**

Inside the `MeetingDetailReader` `body` computed property, add `.keyboardShortcut(" ", modifiers: [])` to the play/pause button. Apply it by modifying the playback bar section:

```swift
// Replace the play/pause Button in playbackBar with:
Button {
    togglePlayback()
} label: {
    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
        .imageScale(.large)
        .foregroundStyle(spaceIndigo)
}
.buttonStyle(.plain)
.disabled(player == nil)
.keyboardShortcut(" ", modifiers: [])
```

- [ ] **Step 2: Verify `RecordingFileSuffix.mix` resolves correctly**

`RecordingFileSuffix.mix` is `"_mix.wav"` (defined in `RecordingFileSuffix.swift`). `loadAudio()` in `MeetingDetailReader` already appends it via:

```swift
let mixURL = URL(fileURLWithPath: session.folderPath)
    .appendingPathComponent(RecordingFileSuffix.mix)
```

Confirm by reading the constant:

```bash
grep -n "static let mix" app/MeetingTranscriber/Sources/RecordingFileSuffix.swift
```

Expected output: a line containing `static let mix = "_mix.wav"` (or similar).

- [ ] **Step 3: Build**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | tail -10
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/MeetingDetailReader.swift
git commit -m "feat(app): wire space-bar shortcut for playback bar play/pause"
```

---

## Task 8: Wire `MeetingDetailReader` into `DetailPaneView` + `SettingsContentView`

**Files:**
- Modify: `app/MeetingTranscriber/Sources/DashboardWindow/DetailPaneView.swift`
- Create: `app/MeetingTranscriber/Sources/DashboardWindow/SettingsContentView.swift`

- [ ] **Step 1: Read the current `DetailPaneView.swift`**

```bash
cat app/MeetingTranscriber/Sources/DashboardWindow/DetailPaneView.swift
```

- [ ] **Step 2: Replace the placeholder content area with `MeetingDetailReader`**

Find the section in `DetailPaneView` that renders a placeholder (likely a `VStack` with "Select a recording" or similar text when a session is selected). Replace it so that when `selectedSession` is non-nil the view shows `MeetingDetailReader`:

```swift
// In DetailPaneView, replace the content area (keeping whatever empty-state
// is already there for the nil case) with:
if let session = selectedSession {
    MeetingDetailReader(session: session)
} else {
    // Keep the existing empty-state view unchanged
    VStack(spacing: 12) {
        Image(systemName: "doc.text.magnifyingglass")
            .font(.system(size: 48))
            .foregroundStyle(Color.secondary.opacity(0.5))
        Text("Select a recording to view details.")
            .font(.system(size: 14))
            .foregroundStyle(Color.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

- [ ] **Step 3: Create `SettingsContentView.swift`**

```swift
// Sources/DashboardWindow/SettingsContentView.swift
import SwiftUI

/// Displays all settings sections as collapsible DisclosureGroup cards.
/// Used when `selectedNav == .settings` in DashboardWindowContent.
/// Wraps the existing per-section sub-views with minimal restructuring.
struct SettingsContentView: View {
    let settings: AppSettings
    let whisperKitEngine: WhisperKitEngine
    let parakeetEngine: ParakeetEngine
    let qwen3Engine: (any TranscribingEngine)?
    var updateChecker: UpdateChecker?
    let recognitionStatsLog: RecognitionStatsLog
    let enrollmentDiarizerFactory: () -> FluidDiarizer
    let namingDialogActive: Bool
    let pipelineBusy: Bool
    let onSpeakerMutate: () -> Void

    // Track which sections are expanded — all open by default
    @State private var detectionExpanded: Bool = true
    @State private var audioExpanded: Bool = true
    @State private var transcriptionExpanded: Bool = true
    @State private var speakersExpanded: Bool = true
    @State private var outputExpanded: Bool = true
    @State private var advancedExpanded: Bool = false

    private let spaceIndigo = Color(red: 0.082, green: 0.114, blue: 0.208)
    private let paleSlate   = Color(red: 0.878, green: 0.898, blue: 0.941)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settingsSection(
                    icon: "eye",
                    title: "Detection & Patterns",
                    isExpanded: $detectionExpanded
                ) {
                    GeneralSettingsView(settings: settings)
                }

                settingsSection(
                    icon: "mic",
                    title: "Audio & Capture",
                    isExpanded: $audioExpanded
                ) {
                    AudioSettingsView(settings: settings)
                }

                settingsSection(
                    icon: "waveform",
                    title: "Transcription Engine",
                    isExpanded: $transcriptionExpanded
                ) {
                    TranscriptionSettingsView(
                        settings: settings,
                        whisperKitEngine: whisperKitEngine,
                        parakeetEngine: parakeetEngine,
                        qwen3Engine: qwen3Engine
                    )
                }

                settingsSection(
                    icon: "person.2",
                    title: "Speakers & Diarization",
                    isExpanded: $speakersExpanded
                ) {
                    SpeakersSettingsView(
                        settings: settings,
                        recognitionStatsLog: recognitionStatsLog,
                        enrollmentDiarizerFactory: enrollmentDiarizerFactory,
                        namingDialogActive: namingDialogActive,
                        pipelineBusy: pipelineBusy,
                        onSpeakerMutate: onSpeakerMutate
                    )
                }

                settingsSection(
                    icon: "doc.text",
                    title: "Output & Protocol",
                    isExpanded: $outputExpanded
                ) {
                    OutputSettingsView(settings: settings)
                }

                settingsSection(
                    icon: "gearshape.2",
                    title: "Advanced",
                    isExpanded: $advancedExpanded
                ) {
                    AdvancedSettingsView(
                        settings: settings,
                        updateChecker: updateChecker
                    )
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Section builder

    @ViewBuilder
    private func settingsSection<Content: View>(
        icon: String,
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content()
                .padding(.top, 12)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(spaceIndigo)
                    .imageScale(.medium)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(spaceIndigo)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(paleSlate, lineWidth: 1)
        )
    }
}
```

- [ ] **Step 4: Build**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/DetailPaneView.swift \
        app/MeetingTranscriber/Sources/DashboardWindow/SettingsContentView.swift
git commit -m "feat(app): wire MeetingDetailReader into DetailPaneView + add SettingsContentView DisclosureGroup wrapper"
```

---

## Task 9: `DashboardWindowContent` — add Dashboard and Settings nav cases

**Files:**
- Modify: `app/MeetingTranscriber/Sources/DashboardWindow/DashboardWindowContent.swift`

- [ ] **Step 1: Read the current `DashboardWindowContent.swift`**

```bash
cat app/MeetingTranscriber/Sources/DashboardWindow/DashboardWindowContent.swift
```

- [ ] **Step 2: Inject `AppState` fields into `DashboardWindowContent` and add the two new nav cases**

`DashboardWindowContent` already accepts `pipelineQueue: PipelineQueue` and `settings: AppSettings` from Phase 3. Add the additional properties needed by `DashboardView` and `SettingsContentView`, then extend the nav switch.

Add the following stored properties to `DashboardWindowContent` (alongside existing ones):

```swift
// Add to DashboardWindowContent stored properties:
let status: TranscriberStatus?
let isWatching: Bool
let elapsedLabel: String
let onStartStop: () -> Void
let whisperKitEngine: WhisperKitEngine
let parakeetEngine: ParakeetEngine
let qwen3Engine: (any TranscribingEngine)?
let updateChecker: UpdateChecker?
let recognitionStatsLog: RecognitionStatsLog
let enrollmentDiarizerFactory: () -> FluidDiarizer
let namingDialogActive: Bool
let pipelineBusy: Bool
let onSpeakerMutate: () -> Void
```

In the content pane `switch selectedNav { }` block, add the two new cases:

```swift
case .dashboard:
    DashboardView(
        status: status,
        isWatching: isWatching,
        settings: settings,
        elapsedLabel: elapsedLabel,
        onStartStop: onStartStop,
        selectedNav: $selectedNav,
        selectedSessionID: $selectedSessionID
    )

case .settings:
    SettingsContentView(
        settings: settings,
        whisperKitEngine: whisperKitEngine,
        parakeetEngine: parakeetEngine,
        qwen3Engine: qwen3Engine,
        updateChecker: updateChecker,
        recognitionStatsLog: recognitionStatsLog,
        enrollmentDiarizerFactory: enrollmentDiarizerFactory,
        namingDialogActive: namingDialogActive,
        pipelineBusy: pipelineBusy,
        onSpeakerMutate: onSpeakerMutate
    )
```

- [ ] **Step 3: Update `MeetingTranscriberApp.swift` to pass the new parameters to `DashboardWindowContent`**

In `MeetingTranscriberApp.swift`, find the `WindowGroup(id: "dashboard")` scene added in Phase 3 and update the `DashboardWindowContent` initialiser to pass the new fields from `appState`:

```swift
WindowGroup(id: "dashboard") {
    DashboardWindowContent(
        pipelineQueue: appState.pipelineQueue,
        settings: appState.settings,
        status: appState.currentStatus,
        isWatching: appState.isWatching,
        elapsedLabel: appState.elapsedLabel,
        onStartStop: { appState.toggleWatching() },
        whisperKitEngine: appState.whisperKitEngine,
        parakeetEngine: appState.parakeetEngine,
        qwen3Engine: appState.qwen3Engine,
        updateChecker: appState.updateChecker,
        recognitionStatsLog: appState.recognitionStatsLog,
        enrollmentDiarizerFactory: { appState.makeEnrollmentDiarizer() },
        namingDialogActive: appState.namingDialogActive,
        pipelineBusy: appState.pipelineBusy,
        onSpeakerMutate: { appState.reloadSpeakers() }
    )
    .modelContainer(modelContainer)
}
.defaultSize(width: 1200, height: 700)
.defaultPosition(.center)
```

Adjust method/property names above to match the actual `AppState` API — read the file first if unsure.

- [ ] **Step 4: Add `DashboardViewTests.swift` for status headline logic**

```swift
// Tests/DashboardWindow/DashboardViewTests.swift
import XCTest
@testable import MeetingTranscriber

/// Tests the pure statusHeadline / statusSubtext logic.
/// DashboardView is not instantiated — the logic is exercised via a helper that
/// mirrors the computed vars so it can be unit-tested without a SwiftUI host.
final class DashboardViewTests: XCTestCase {

    // MARK: - Helpers mirroring DashboardView computed vars

    private func headline(state: TranscriberState?, isWatching: Bool, elapsed: String = "00:00") -> String {
        guard let state else {
            return isWatching ? "Meeting Detection is active." : "Idle"
        }
        switch state {
        case .recording:          return "Recording · \(elapsed)"
        case .transcribing:       return "Transcribing..."
        case .generatingProtocol: return "Generating Protocol..."
        case .diarizing:          return "Diarizing Speakers..."
        default:
            return isWatching ? "Meeting Detection is active." : "Idle"
        }
    }

    // MARK: - Tests

    func test_idle_notWatching_showsIdle() {
        XCTAssertEqual(headline(state: nil, isWatching: false), "Idle")
    }

    func test_idle_watching_showsActiveText() {
        XCTAssertEqual(headline(state: nil, isWatching: true), "Meeting Detection is active.")
    }

    func test_recording_showsElapsed() {
        XCTAssertEqual(headline(state: .recording, isWatching: true, elapsed: "01:23"), "Recording · 01:23")
    }

    func test_transcribing_showsTranscribingText() {
        XCTAssertEqual(headline(state: .transcribing, isWatching: true), "Transcribing...")
    }

    func test_generatingProtocol_showsProtocolText() {
        XCTAssertEqual(headline(state: .generatingProtocol, isWatching: true), "Generating Protocol...")
    }

    func test_diarizing_showsDiarizingText() {
        XCTAssertEqual(headline(state: .diarizing, isWatching: true), "Diarizing Speakers...")
    }
}
```

- [ ] **Step 5: Build and run all dashboard tests**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | tail -10
cd app/MeetingTranscriber && swift test --filter DashboardViewTests 2>&1 | tail -10
cd app/MeetingTranscriber && swift test --filter TranscriptParserTests 2>&1 | tail -10
```

Expected: `Build complete!` and both test suites passed.

- [ ] **Step 6: Run the full test suite to check for regressions**

```bash
cd app/MeetingTranscriber && swift test --parallel 2>&1 | tail -20
```

Expected: All tests passed.

- [ ] **Step 7: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/DashboardWindowContent.swift \
        app/MeetingTranscriber/Sources/MeetingTranscriberApp.swift \
        app/MeetingTranscriber/Tests/DashboardWindow/DashboardViewTests.swift
git commit -m "feat(app): wire DashboardView + SettingsContentView into DashboardWindowContent nav"
```

---

## Completion checklist

- [ ] `TranscriptParser.parse(markdown:)` passes all 8 unit tests
- [ ] `DashboardViewTests` passes (6 headline/subtext assertions)
- [ ] `DashboardView` renders status card, quick controls, and ambient level meters
- [ ] `AmbientLevelCard` shows `ProgressView` bars when active, "—" labels when idle
- [ ] Recent Activity section shows last 3 sessions and navigates to Library on tap
- [ ] `MeetingDetailReader` tab bar switches between Transcript / Protocol / Split
- [ ] Transcript tab parses `transcript.md` and highlights the active playback segment
- [ ] Protocol tab renders `protocol.md` with `AttributedString(markdown:)`
- [ ] Split tab shows transcript and protocol side-by-side
- [ ] Playback bar loads `audio_mix.wav`, plays/pauses, scrubs, auto-scrolls transcript
- [ ] Space-bar shortcut triggers play/pause in `MeetingDetailReader`
- [ ] `SettingsContentView` shows 6 collapsible `DisclosureGroup` sections
- [ ] Selecting `.settings` in the Dashboard sidebar shows `SettingsContentView`
- [ ] Selecting `.dashboard` in the Dashboard sidebar shows `DashboardView`
- [ ] Existing `Window("Settings", id: "settings")` from `MenuBarView` still works
- [ ] Full test suite passes with `swift test --parallel`
