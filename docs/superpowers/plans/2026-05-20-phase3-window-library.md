# Phase 3: Window Shell + Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the main Dashboard window with a three-pane shell, sidebar navigation, and a working Library view backed by the SwiftData `RecordingSession` store from Phase 1.

**Architecture:** A new `WindowGroup(id: "dashboard")` hosts `DashboardWindowContent` which owns `selectedNav` state and renders three panes. The Library pane uses `@Query` for persisted sessions and merges in-flight `PipelineJob` entries from an `@ObservedObject PipelineQueue`. The detail pane shows session metadata when a row is selected.

**Tech Stack:** Swift, SwiftUI, SwiftData (`@Query`, `ModelContainer`, `ModelConfiguration`), XCTest, ViewInspector

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Modify | `app/MeetingTranscriber/Sources/MeetingTranscriberApp.swift` | Add `modelContainer` stored property, `WindowGroup(id: "dashboard")`, wire `onOpenDashboard` |
| Create | `app/MeetingTranscriber/Sources/DashboardWindow/DashboardWindowContent.swift` | Root view; owns `selectedNav` + `selectedSessionID` state; three-pane `HStack` |
| Create | `app/MeetingTranscriber/Sources/DashboardWindow/SidebarView.swift` | Sidebar nav items, active pill, bottom badge |
| Create | `app/MeetingTranscriber/Sources/DashboardWindow/StatusChipView.swift` | Reusable status chip (color + label) |
| Create | `app/MeetingTranscriber/Sources/DashboardWindow/SessionRowView.swift` | 48px list row for a `RecordingSession` |
| Create | `app/MeetingTranscriber/Sources/DashboardWindow/SessionGridCardView.swift` | ~180px grid card for a `RecordingSession` |
| Create | `app/MeetingTranscriber/Sources/DashboardWindow/DetailPaneView.swift` | Right pane; session metadata or empty state |
| Create | `app/MeetingTranscriber/Sources/DashboardWindow/LibraryView.swift` | Content pane; `@Query`, search, list/grid toggle, in-flight merge |
| Create | `app/MeetingTranscriber/Tests/DashboardWindow/StatusChipViewTests.swift` | Chip color per status string |
| Create | `app/MeetingTranscriber/Tests/DashboardWindow/LibraryViewTests.swift` | Search filter logic, in-flight merge ordering |

---

## Task 1: `ModelContainer` in `MeetingTranscriberApp` + `WindowGroup(id: "dashboard")` skeleton

**Files:**
- Modify: `app/MeetingTranscriber/Sources/MeetingTranscriberApp.swift`

- [ ] **Step 1: Read the current `MeetingTranscriberApp.swift` to understand existing structure**

```bash
cat app/MeetingTranscriber/Sources/MeetingTranscriberApp.swift
```

- [ ] **Step 2: Add `modelContainer` property and `WindowGroup(id: "dashboard")` to `MeetingTranscriberApp`**

Find the `@main struct MeetingTranscriberApp: App` and add the `modelContainer` stored property directly below the existing stored properties (after `appState`, before `body`). Then add the `WindowGroup` inside `body` after the existing `MenuBarExtra` scene. Also wire `onOpenDashboard` inside `MenuBarView` to call `openWindow(id: "dashboard")`.

The additions look like this — apply them as targeted edits to the actual file rather than replacing the whole file:

```swift
// Add this stored property to MeetingTranscriberApp, after the existing stored properties:
private let modelContainer: ModelContainer = {
    let config = ModelConfiguration(url: AppPaths.libraryStore)
    return try! ModelContainer(for: RecordingSession.self, configurations: config)
}()
```

```swift
// Add this Environment property to MeetingTranscriberApp body (or to the struct itself):
@Environment(\.openWindow) private var openWindow
```

```swift
// Add this WindowGroup scene inside `var body: some Scene { ... }` after the existing MenuBarExtra:
WindowGroup(id: "dashboard") {
    DashboardWindowContent(pipelineQueue: appState.pipelineQueue, settings: appState.settings)
        .modelContainer(modelContainer)
}
.defaultSize(width: 1200, height: 700)
.defaultPosition(.center)
```

```swift
// Inside the MenuBarExtra scene, update MenuBarView to pass onOpenDashboard:
// Find the existing MenuBarView(...) call and add the onOpenDashboard parameter:
MenuBarView(
    appState: appState,
    onOpenDashboard: { openWindow(id: "dashboard") }
)
```

- [ ] **Step 3: Build to confirm no compilation errors**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add app/MeetingTranscriber/Sources/MeetingTranscriberApp.swift
git commit -m "feat(app): add ModelContainer + WindowGroup(id: dashboard) skeleton"
```

---

## Task 2: `SidebarView` (nav items, active state pill, bottom badge)

**Files:**
- Create: `app/MeetingTranscriber/Sources/DashboardWindow/SidebarView.swift`

- [ ] **Step 1: Create the `DashboardWindow` source directory**

```bash
mkdir -p app/MeetingTranscriber/Sources/DashboardWindow
```

- [ ] **Step 2: Write `SidebarView.swift`**

```swift
// Sources/DashboardWindow/SidebarView.swift
import SwiftUI

// MARK: - NavItem

enum NavItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case library   = "Library"
    case settings  = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .library:   return "folder"
        case .settings:  return "gearshape"
        }
    }
}

// MARK: - SidebarView

struct SidebarView: View {
    @Binding var selectedNav: NavItem

    /// Injected from parent for the bottom badge — e.g. "WhisperKit · 1.2 GB"
    var engineLabel: String
    var storageLabel: String

    // Design tokens
    private let spaceIndigo = Color(red: 0.082, green: 0.114, blue: 0.208)
    private let peachGlow   = Color(red: 0.969, green: 0.773, blue: 0.624)
    private let aliceBlue   = Color(red: 0.882, green: 0.898, blue: 0.933)
    private let slateGrey   = Color(red: 0.780, green: 0.800, blue: 0.859)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App name header
            Text("Meeting Transcriber")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)

            // Nav items
            ForEach(NavItem.allCases) { item in
                navRow(item)
            }

            Spacer()

            // Bottom badge
            VStack(alignment: .leading, spacing: 4) {
                Text(engineLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(slateGrey)
                Text(storageLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(slateGrey)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 240)
        .background(spaceIndigo)
    }

    @ViewBuilder
    private func navRow(_ item: NavItem) -> some View {
        let isActive = selectedNav == item

        Button {
            selectedNav = item
        } label: {
            HStack(spacing: 10) {
                // Active indicator pill
                Rectangle()
                    .fill(isActive ? peachGlow : Color.clear)
                    .frame(width: 3, height: 20)
                    .cornerRadius(1.5)

                Image(systemName: item.systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(isActive ? .white : slateGrey)
                    .frame(width: 20)

                Text(item.rawValue)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .white : slateGrey)

                Spacer()
            }
            .padding(.leading, 0)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .background(
                isActive
                    ? aliceBlue.opacity(0.15)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    SidebarView(
        selectedNav: .constant(.library),
        engineLabel: "WhisperKit large-v3",
        storageLabel: "1.2 GB used"
    )
    .frame(height: 600)
}
```

- [ ] **Step 3: Build**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/SidebarView.swift
git commit -m "feat(app): add SidebarView with NavItem enum and active state pill"
```

---

## Task 3: `StatusChipView` + tests

**Files:**
- Create: `app/MeetingTranscriber/Sources/DashboardWindow/StatusChipView.swift`
- Create: `app/MeetingTranscriber/Tests/DashboardWindow/StatusChipViewTests.swift`

- [ ] **Step 1: Create the tests directory and write failing tests**

```bash
mkdir -p app/MeetingTranscriber/Tests/DashboardWindow
```

```swift
// Tests/DashboardWindow/StatusChipViewTests.swift
import XCTest
@testable import MeetingTranscriber

final class StatusChipViewTests: XCTestCase {

    func test_chipColor_done_isGreen() {
        XCTAssertEqual(StatusChipView.chipColor(for: "done"), StatusChipView.ChipColor.green)
    }

    func test_chipColor_saved_isSlateGrey() {
        XCTAssertEqual(StatusChipView.chipColor(for: "saved"), StatusChipView.ChipColor.slateGrey)
    }

    func test_chipColor_transcribing_isPeachGlow() {
        XCTAssertEqual(StatusChipView.chipColor(for: "transcribing"), StatusChipView.ChipColor.peachGlow)
    }

    func test_chipColor_diarizing_isPeachGlow() {
        XCTAssertEqual(StatusChipView.chipColor(for: "diarizing"), StatusChipView.ChipColor.peachGlow)
    }

    func test_chipColor_waiting_isPeachGlow() {
        XCTAssertEqual(StatusChipView.chipColor(for: "waiting"), StatusChipView.ChipColor.peachGlow)
    }

    func test_chipColor_generatingProtocol_isPeachGlow() {
        XCTAssertEqual(StatusChipView.chipColor(for: "generatingProtocol"), StatusChipView.ChipColor.peachGlow)
    }

    func test_chipColor_error_isRed() {
        XCTAssertEqual(StatusChipView.chipColor(for: "error"), StatusChipView.ChipColor.red)
    }

    func test_chipColor_unknown_isSlateGrey() {
        XCTAssertEqual(StatusChipView.chipColor(for: "someUnknownStatus"), StatusChipView.ChipColor.slateGrey)
    }

    func test_chipLabel_done() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "done"), "Done")
    }

    func test_chipLabel_transcribing() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "transcribing"), "Transcribing")
    }

    func test_chipLabel_diarizing() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "diarizing"), "Diarizing")
    }

    func test_chipLabel_waiting() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "waiting"), "Waiting")
    }

    func test_chipLabel_generatingProtocol() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "generatingProtocol"), "Protocol")
    }

    func test_chipLabel_error() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "error"), "Error")
    }

    func test_chipLabel_saved() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "saved"), "Saved")
    }

    func test_chipLabel_unknown_capitalizesFirst() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "pending"), "Pending")
    }
}
```

- [ ] **Step 2: Run tests — they must fail (type not found)**

```bash
cd app/MeetingTranscriber && swift test --filter StatusChipViewTests 2>&1 | tail -10
```

Expected: compiler error — `StatusChipView` type not found.

- [ ] **Step 3: Write `StatusChipView.swift`**

```swift
// Sources/DashboardWindow/StatusChipView.swift
import SwiftUI

struct StatusChipView: View {

    // MARK: - ChipColor

    enum ChipColor: Equatable {
        case green
        case peachGlow
        case red
        case slateGrey
    }

    // MARK: - Static helpers (testable)

    static func chipColor(for status: String) -> ChipColor {
        switch status {
        case "done":
            return .green
        case "transcribing", "diarizing", "waiting", "generatingProtocol":
            return .peachGlow
        case "error":
            return .red
        default:
            return .slateGrey
        }
    }

    static func chipLabel(for status: String) -> String {
        switch status {
        case "done":               return "Done"
        case "transcribing":       return "Transcribing"
        case "diarizing":          return "Diarizing"
        case "waiting":            return "Waiting"
        case "generatingProtocol": return "Protocol"
        case "error":              return "Error"
        case "saved":              return "Saved"
        default:
            return status.prefix(1).uppercased() + status.dropFirst()
        }
    }

    // MARK: - View

    let status: String

    private var resolvedColor: Color {
        switch Self.chipColor(for: status) {
        case .green:     return Color(red: 0.204, green: 0.780, blue: 0.349)
        case .peachGlow: return Color(red: 0.969, green: 0.773, blue: 0.624)
        case .red:       return Color(red: 0.906, green: 0.298, blue: 0.235)
        case .slateGrey: return Color(red: 0.780, green: 0.800, blue: 0.859)
        }
    }

    var body: some View {
        Text(Self.chipLabel(for: status))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(resolvedColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(resolvedColor.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 8) {
        StatusChipView(status: "done")
        StatusChipView(status: "transcribing")
        StatusChipView(status: "error")
        StatusChipView(status: "saved")
        StatusChipView(status: "waiting")
    }
    .padding()
}
```

- [ ] **Step 4: Run tests — they must pass**

```bash
cd app/MeetingTranscriber && swift test --filter StatusChipViewTests 2>&1 | tail -15
```

Expected: `Test Suite 'StatusChipViewTests' passed`

- [ ] **Step 5: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/StatusChipView.swift \
        app/MeetingTranscriber/Tests/DashboardWindow/StatusChipViewTests.swift
git commit -m "feat(app): add StatusChipView with testable static color/label helpers"
```

---

## Task 4: `SessionRowView` + `SessionGridCardView`

**Files:**
- Create: `app/MeetingTranscriber/Sources/DashboardWindow/SessionRowView.swift`
- Create: `app/MeetingTranscriber/Sources/DashboardWindow/SessionGridCardView.swift`

- [ ] **Step 1: Write `SessionRowView.swift`**

```swift
// Sources/DashboardWindow/SessionRowView.swift
import SwiftUI

struct SessionRowView: View {
    let session: RecordingSession
    let isSelected: Bool

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var durationString: String {
        let total = Int(session.duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var dateString: String {
        Self.dateFormatter.string(from: session.createdAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            // App icon (system image fallback)
            Image(systemName: iconName(for: session.appName))
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            // Title + date
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title.isEmpty ? "Untitled Recording" : session.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(dateString)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Duration
            Text(durationString)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)

            // Status chip
            StatusChipView(status: session.status)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    private func iconName(for appName: String) -> String {
        let lower = appName.lowercased()
        if lower.contains("zoom")    { return "video" }
        if lower.contains("teams")   { return "video.fill" }
        if lower.contains("meet")    { return "person.2.wave.2" }
        if lower.contains("webex")   { return "network" }
        if lower.contains("slack")   { return "bubble.left.and.bubble.right" }
        return "mic"
    }
}

// MARK: - In-flight row variant (PipelineJob)

struct InFlightRowView: View {
    let job: PipelineJob
    let isSelected: Bool

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var jobStatusString: String {
        switch job.state {
        case .waiting:              return "waiting"
        case .transcribing:         return "transcribing"
        case .diarizing:            return "diarizing"
        case .generatingProtocol:   return "generatingProtocol"
        case .speakerNamingPending: return "waiting"
        case .done:                 return "done"
        case .error:                return "error"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(job.meetingTitle.isEmpty ? "Recording…" : job.meetingTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(Self.dateFormatter.string(from: job.startedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Progress bar for active jobs
            if job.progress > 0 && job.progress < 1 {
                ProgressView(value: job.progress)
                    .frame(width: 60)
                    .tint(Color(red: 0.969, green: 0.773, blue: 0.624))
            }

            StatusChipView(status: jobStatusString)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 2: Write `SessionGridCardView.swift`**

```swift
// Sources/DashboardWindow/SessionGridCardView.swift
import SwiftUI

struct SessionGridCardView: View {
    let session: RecordingSession
    let isSelected: Bool

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private var durationString: String {
        let total = Int(session.duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Waveform placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))

                // Decorative blurred waveform bars
                HStack(alignment: .center, spacing: 2) {
                    ForEach(waveformHeights, id: \.self) { height in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 3, height: CGFloat(height))
                    }
                }
                .blur(radius: 1)

                Image(systemName: "waveform")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary.opacity(0.4))
            }
            .frame(height: 80)

            // Title
            Text(session.title.isEmpty ? "Untitled Recording" : session.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Date + duration
            HStack {
                Text(Self.dateFormatter.string(from: session.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Text(durationString)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Status chip
            StatusChipView(status: session.status)
        }
        .padding(12)
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected
                    ? Color.accentColor.opacity(0.08)
                    : Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.12),
                    lineWidth: 1
                )
        )
    }

    // Pseudo-random waveform shape seeded from session id
    private var waveformHeights: [Int] {
        let seed = session.id.uuidString.utf8.reduce(0) { $0 &+ Int($1) }
        return (0..<28).map { i in
            let v = abs((seed &+ i * 17) % 40) + 8
            return v
        }
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 16) {
        SessionGridCardView(
            session: {
                let s = RecordingSession(
                    id: UUID(),
                    createdAt: Date(),
                    title: "Weekly Team Sync",
                    appName: "Zoom",
                    folderPath: "",
                    duration: 2535,
                    participantNames: ["Alice", "Bob"],
                    hasTranscript: true,
                    hasProtocol: false,
                    audioFiles: [],
                    engine: "WhisperKit",
                    status: "done"
                )
                return s
            }(),
            isSelected: false
        )
        SessionGridCardView(
            session: {
                let s = RecordingSession(
                    id: UUID(),
                    createdAt: Date(),
                    title: "1:1 Conversation",
                    appName: "Teams",
                    folderPath: "",
                    duration: 900,
                    participantNames: [],
                    hasTranscript: false,
                    hasProtocol: false,
                    audioFiles: [],
                    engine: "Parakeet",
                    status: "transcribing"
                )
                return s
            }(),
            isSelected: true
        )
    }
    .padding()
}
```

- [ ] **Step 3: Build**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/SessionRowView.swift \
        app/MeetingTranscriber/Sources/DashboardWindow/SessionGridCardView.swift
git commit -m "feat(app): add SessionRowView, InFlightRowView, and SessionGridCardView"
```

---

## Task 5: `DetailPaneView` (metadata chips, action buttons, empty state)

**Files:**
- Create: `app/MeetingTranscriber/Sources/DashboardWindow/DetailPaneView.swift`

- [ ] **Step 1: Write `DetailPaneView.swift`**

```swift
// Sources/DashboardWindow/DetailPaneView.swift
import SwiftUI

struct DetailPaneView: View {
    /// The selected session, or nil when nothing is selected.
    let session: RecordingSession?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        if let session {
            sessionDetail(session)
        } else {
            emptyState
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack {
            Spacer()
            Image(systemName: "waveform.badge.microphone")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)
            Text("Select a recording to view details")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session detail

    @ViewBuilder
    private func sessionDetail(_ session: RecordingSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                Text(session.title.isEmpty ? "Untitled Recording" : session.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                // Metadata chips
                FlowLayout(spacing: 6) {
                    metadataChip(
                        icon: "calendar",
                        label: Self.dateFormatter.string(from: session.createdAt)
                    )
                    metadataChip(
                        icon: "clock",
                        label: durationString(session.duration)
                    )
                    if !session.appName.isEmpty {
                        metadataChip(icon: "desktopcomputer", label: session.appName)
                    }
                    metadataChip(icon: "cpu", label: session.engine.isEmpty ? "Unknown engine" : session.engine)
                    StatusChipView(status: session.status)
                }

                // Participants
                if !session.participantNames.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Participants", systemImage: "person.2")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(session.participantNames, id: \.self) { name in
                                Text(name)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Divider()

                // Action buttons
                VStack(spacing: 10) {
                    Button {
                        openTranscript(for: session)
                    } label: {
                        Label("Open Transcript", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.hasTranscript)

                    Button {
                        openProtocol(for: session)
                    } label: {
                        Label("Open Protocol", systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!session.hasProtocol)

                    Button {
                        revealInFinder(for: session)
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                // Warnings
                if !session.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Warnings", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.orange)
                        ForEach(session.warnings, id: \.self) { warning in
                            Text(warning)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Error message
                if let error = session.errorMessage, !error.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Error", systemImage: "xmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                // Transcript reader placeholder (Phase 4)
                ScrollView {
                    Text("Transcript reader — Phase 4")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(height: 200)
                .background(Color.secondary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer(minLength: 20)
            }
            .padding(20)
        }
        .frame(width: 360)
    }

    // MARK: - Helpers

    private func durationString(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func openTranscript(for session: RecordingSession) {
        let folder = URL(fileURLWithPath: session.folderPath)
        let file = folder.appendingPathComponent("transcript.md")
        NSWorkspace.shared.open(file)
    }

    private func openProtocol(for session: RecordingSession) {
        let folder = URL(fileURLWithPath: session.folderPath)
        let file = folder.appendingPathComponent("protocol.md")
        NSWorkspace.shared.open(file)
    }

    private func revealInFinder(for session: RecordingSession) {
        let folder = URL(fileURLWithPath: session.folderPath)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }

    @ViewBuilder
    private func metadataChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.08))
        .clipShape(Capsule())
    }
}

// MARK: - FlowLayout

/// Simple left-to-right wrapping layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowHeight + spacing
                totalHeight = y
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

// MARK: - Preview

#Preview("Empty state") {
    DetailPaneView(session: nil)
        .frame(width: 360, height: 600)
}
```

- [ ] **Step 2: Build**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/DetailPaneView.swift
git commit -m "feat(app): add DetailPaneView with metadata chips, action buttons, and empty state"
```

---

## Task 6: `LibraryView` (`@Query`, search filter, list/grid toggle, in-flight merge) + tests

**Files:**
- Create: `app/MeetingTranscriber/Sources/DashboardWindow/LibraryView.swift`
- Create: `app/MeetingTranscriber/Tests/DashboardWindow/LibraryViewTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/DashboardWindow/LibraryViewTests.swift
import XCTest
@testable import MeetingTranscriber

final class LibraryViewTests: XCTestCase {

    // MARK: - Search filter

    private func makeSession(title: String, appName: String, participants: [String] = [], status: String = "done") -> RecordingSession {
        RecordingSession(
            id: UUID(),
            createdAt: Date(),
            title: title,
            appName: appName,
            folderPath: "/tmp",
            duration: 300,
            participantNames: participants,
            hasTranscript: false,
            hasProtocol: false,
            audioFiles: [],
            engine: "WhisperKit",
            status: status
        )
    }

    private func applyFilter(sessions: [RecordingSession], searchText: String) -> [RecordingSession] {
        LibraryView.filterSessions(sessions, searchText: searchText)
    }

    func test_filter_emptySearch_returnsAll() {
        let sessions = [
            makeSession(title: "Alpha", appName: "Zoom"),
            makeSession(title: "Beta", appName: "Teams")
        ]
        XCTAssertEqual(applyFilter(sessions: sessions, searchText: "").count, 2)
    }

    func test_filter_matchesTitle_caseInsensitive() {
        let sessions = [
            makeSession(title: "Weekly Sync", appName: "Zoom"),
            makeSession(title: "One on One", appName: "Zoom")
        ]
        let result = applyFilter(sessions: sessions, searchText: "weekly")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Weekly Sync")
    }

    func test_filter_matchesAppName_caseInsensitive() {
        let sessions = [
            makeSession(title: "Meeting A", appName: "Zoom"),
            makeSession(title: "Meeting B", appName: "Teams")
        ]
        let result = applyFilter(sessions: sessions, searchText: "teams")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].appName, "Teams")
    }

    func test_filter_matchesParticipantName() {
        let sessions = [
            makeSession(title: "Meeting A", appName: "Zoom", participants: ["Alice", "Bob"]),
            makeSession(title: "Meeting B", appName: "Zoom", participants: ["Carol", "Dave"])
        ]
        let result = applyFilter(sessions: sessions, searchText: "alice")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Meeting A")
    }

    func test_filter_noMatch_returnsEmpty() {
        let sessions = [
            makeSession(title: "Alpha", appName: "Zoom"),
            makeSession(title: "Beta", appName: "Teams")
        ]
        XCTAssertEqual(applyFilter(sessions: sessions, searchText: "xyzzy").count, 0)
    }

    func test_filter_partialMatchTitle() {
        let sessions = [
            makeSession(title: "Q4 Quarterly Review", appName: "Zoom"),
            makeSession(title: "Sprint Planning", appName: "Zoom")
        ]
        let result = applyFilter(sessions: sessions, searchText: "quart")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Q4 Quarterly Review")
    }

    // MARK: - In-flight merge ordering

    func test_inFlightFilter_includesActiveStates() {
        let waiting = makePipelineJob(state: .waiting)
        let transcribing = makePipelineJob(state: .transcribing)
        let diarizing = makePipelineJob(state: .diarizing)
        let generatingProtocol = makePipelineJob(state: .generatingProtocol)
        let done = makePipelineJob(state: .done)
        let error = makePipelineJob(state: .error)

        let allJobs = [waiting, transcribing, diarizing, generatingProtocol, done, error]
        let inFlight = LibraryView.filterInFlightJobs(allJobs)

        XCTAssertEqual(inFlight.count, 4)
        XCTAssertTrue(inFlight.contains(where: { $0.id == waiting.id }))
        XCTAssertTrue(inFlight.contains(where: { $0.id == transcribing.id }))
        XCTAssertTrue(inFlight.contains(where: { $0.id == diarizing.id }))
        XCTAssertTrue(inFlight.contains(where: { $0.id == generatingProtocol.id }))
        XCTAssertFalse(inFlight.contains(where: { $0.id == done.id }))
        XCTAssertFalse(inFlight.contains(where: { $0.id == error.id }))
    }

    func test_inFlightFilter_speakerNamingPendingExcluded() {
        // speakerNamingPending is a pause state, not an active processing state — excluded from in-flight
        let job = makePipelineJob(state: .speakerNamingPending)
        let result = LibraryView.filterInFlightJobs([job])
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - Helpers

    private func makePipelineJob(state: JobState) -> PipelineJob {
        let job = PipelineJob(
            id: UUID(),
            meetingTitle: "Test Meeting",
            state: state,
            progress: 0.5,
            startedAt: Date()
        )
        return job
    }
}
```

- [ ] **Step 2: Run tests — they must fail (type not found)**

```bash
cd app/MeetingTranscriber && swift test --filter LibraryViewTests 2>&1 | tail -10
```

Expected: compiler error — `LibraryView` type not found.

- [ ] **Step 3: Write `LibraryView.swift`**

```swift
// Sources/DashboardWindow/LibraryView.swift
import SwiftUI
import SwiftData

struct LibraryView: View {
    // Injected from parent
    @ObservedObject var pipelineQueue: PipelineQueue

    // Binding so detail pane selection is owned by parent
    @Binding var selectedSessionID: UUID?

    // SwiftData query — most recent first
    @Query(sort: \RecordingSession.createdAt, order: .reverse)
    private var sessions: [RecordingSession]

    @State private var searchText: String = ""
    @State private var isGridLayout: Bool = false

    // MARK: - Static helpers (testable)

    static func filterSessions(_ sessions: [RecordingSession], searchText: String) -> [RecordingSession] {
        guard !searchText.isEmpty else { return sessions }
        return sessions.filter { s in
            s.title.localizedCaseInsensitiveContains(searchText)
                || s.appName.localizedCaseInsensitiveContains(searchText)
                || s.participantNames.joined().localizedCaseInsensitiveContains(searchText)
        }
    }

    static func filterInFlightJobs(_ jobs: [PipelineJob]) -> [PipelineJob] {
        let activeStates: Set<JobState> = [.waiting, .transcribing, .diarizing, .generatingProtocol]
        return jobs.filter { activeStates.contains($0.state) }
    }

    // MARK: - Computed

    private var filteredSessions: [RecordingSession] {
        Self.filterSessions(sessions, searchText: searchText)
    }

    private var inFlightJobs: [PipelineJob] {
        Self.filterInFlightJobs(pipelineQueue.jobs)
    }

    private var totalCount: Int {
        sessions.count + inFlightJobs.count
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Recordings · \(totalCount) total item\(totalCount == 1 ? "" : "s")")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                // Layout toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isGridLayout.toggle()
                    }
                } label: {
                    Image(systemName: isGridLayout ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .help(isGridLayout ? "Switch to list view" : "Switch to grid view")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                TextField("Search…", text: $searchText)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
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
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            // Content
            if isGridLayout {
                gridContent
            } else {
                listContent
            }
        }
    }

    // MARK: - List layout

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // In-flight jobs (at top, always unfiltered)
                ForEach(inFlightJobs, id: \.id) { job in
                    InFlightRowView(
                        job: job,
                        isSelected: selectedSessionID == job.id
                    )
                    .onTapGesture {
                        selectedSessionID = job.id
                    }
                    Divider().padding(.leading, 60)
                }

                // Persisted sessions (filtered by search)
                ForEach(filteredSessions, id: \.id) { session in
                    SessionRowView(
                        session: session,
                        isSelected: selectedSessionID == session.id
                    )
                    .onTapGesture {
                        selectedSessionID = session.id
                    }
                    Divider().padding(.leading, 60)
                }

                if filteredSessions.isEmpty && inFlightJobs.isEmpty {
                    emptySearchState
                }
            }
        }
    }

    // MARK: - Grid layout

    private var gridContent: some View {
        ScrollView {
            // In-flight jobs row
            if !inFlightJobs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In Progress")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(inFlightJobs, id: \.id) { job in
                                // In-flight grid card (simplified)
                                VStack(alignment: .leading, spacing: 8) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(red: 0.969, green: 0.773, blue: 0.624).opacity(0.1))
                                        Image(systemName: "waveform")
                                            .font(.system(size: 24))
                                            .foregroundStyle(Color(red: 0.969, green: 0.773, blue: 0.624).opacity(0.6))
                                    }
                                    .frame(height: 80)

                                    Text(job.meetingTitle.isEmpty ? "Recording…" : job.meetingTitle)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(2)

                                    if job.progress > 0 {
                                        ProgressView(value: job.progress)
                                            .tint(Color(red: 0.969, green: 0.773, blue: 0.624))
                                    }
                                }
                                .padding(12)
                                .frame(width: 180)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                                )
                                .onTapGesture { selectedSessionID = job.id }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 12)

                Divider().padding(.horizontal, 20).padding(.vertical, 4)
            }

            // Persisted sessions grid
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180, maximum: 200), spacing: 12)],
                spacing: 12
            ) {
                ForEach(filteredSessions, id: \.id) { session in
                    SessionGridCardView(
                        session: session,
                        isSelected: selectedSessionID == session.id
                    )
                    .onTapGesture { selectedSessionID = session.id }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if filteredSessions.isEmpty && inFlightJobs.isEmpty {
                emptySearchState
            }
        }
    }

    // MARK: - Empty state

    private var emptySearchState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            if searchText.isEmpty {
                Text("No recordings yet")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("Recorded meetings will appear here after transcription.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No results for \"\(searchText)\"")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }
}
```

- [ ] **Step 4: Run tests — they must pass**

```bash
cd app/MeetingTranscriber && swift test --filter LibraryViewTests 2>&1 | tail -20
```

Expected: `Test Suite 'LibraryViewTests' passed`

- [ ] **Step 5: Build**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/LibraryView.swift \
        app/MeetingTranscriber/Tests/DashboardWindow/LibraryViewTests.swift
git commit -m "feat(app): add LibraryView with @Query, search filter, list/grid toggle, and in-flight job merge"
```

---

## Task 7: `DashboardWindowContent` shell wiring all three panes

**Files:**
- Create: `app/MeetingTranscriber/Sources/DashboardWindow/DashboardWindowContent.swift`

- [ ] **Step 1: Write `DashboardWindowContent.swift`**

```swift
// Sources/DashboardWindow/DashboardWindowContent.swift
import SwiftUI
import SwiftData

struct DashboardWindowContent: View {
    // Injected from MeetingTranscriberApp
    @ObservedObject var pipelineQueue: PipelineQueue
    var settings: AppSettings

    // Navigation state
    @State private var selectedNav: NavItem = .library
    // Selected session drives detail pane
    @State private var selectedSessionID: UUID?

    // Fetch selected session from SwiftData context
    @Environment(\.modelContext) private var modelContext
    @Query private var allSessions: [RecordingSession]

    private var selectedSession: RecordingSession? {
        guard let id = selectedSessionID else { return nil }
        return allSessions.first(where: { $0.id == id })
    }

    // Engine badge label derived from settings
    private var engineLabel: String {
        switch settings.transcriptionEngine {
        case .whisperKit: return "WhisperKit"
        case .parakeet:   return "Parakeet TDT"
        case .qwen3:      return "Qwen3-ASR"
        }
    }

    // Storage size — computed lazily; Phase 4 can make this reactive
    private var storageLabel: String {
        let bytes = storageBytesUsed()
        return formattedBytes(bytes)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Sidebar (240px fixed)
            SidebarView(
                selectedNav: $selectedNav,
                engineLabel: engineLabel,
                storageLabel: storageLabel
            )

            // Separator
            Divider()

            // Center: Content pane (flexible)
            contentPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Separator
            Divider()

            // Right: Detail pane (360px fixed)
            DetailPaneView(session: selectedSession)
                .frame(width: 360)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    // MARK: - Content pane

    @ViewBuilder
    private var contentPane: some View {
        switch selectedNav {
        case .library:
            LibraryView(
                pipelineQueue: pipelineQueue,
                selectedSessionID: $selectedSessionID
            )
        case .dashboard:
            placeholderPane(
                icon: "square.grid.2x2",
                title: "Dashboard",
                subtitle: "Summary and analytics — coming in a future release."
            )
        case .settings:
            placeholderPane(
                icon: "gearshape",
                title: "Settings",
                subtitle: "Open the Settings window via the menu bar for now."
            )
        }
    }

    // MARK: - Placeholder

    private func placeholderPane(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Storage helpers

    private func storageBytesUsed() -> Int64 {
        let root = AppPaths.transcriberRoot
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes) + " used"
    }
}

// MARK: - Preview

#Preview {
    DashboardWindowContent(
        pipelineQueue: PipelineQueue(),
        settings: AppSettings()
    )
    .modelContainer(for: RecordingSession.self, inMemory: true)
    .frame(width: 1200, height: 700)
}
```

- [ ] **Step 2: Build**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | tail -20
```

Expected: `Build complete!`

- [ ] **Step 3: Run full test suite**

```bash
cd app/MeetingTranscriber && swift test --parallel 2>&1 | tail -30
```

Expected: all tests pass (StatusChipViewTests, LibraryViewTests, plus all pre-existing tests).

- [ ] **Step 4: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/DashboardWindowContent.swift
git commit -m "feat(app): add DashboardWindowContent wiring all three panes into window shell"
```

---

## Final verification

- [ ] **Smoke test: launch the app and open the dashboard window**

```bash
MEETINGTRANSCRIBER_DEBUG_RPC=1 ./scripts/run_app.sh &
sleep 5
cd tools/mt-cli && swift build && .build/debug/mt-cli open-settings
```

Verify:
1. The Dashboard window opens at 1200×700 centered on screen.
2. Sidebar shows "Dashboard", "Library", "Settings" items with Space Indigo background.
3. Library nav item is selected by default; content pane shows "Recordings · 0 total items" with search bar.
4. Detail pane shows the empty state message "Select a recording to view details".
5. Clicking "Dashboard" or "Settings" nav items shows their placeholder panes.

- [ ] **Run full test suite one final time**

```bash
cd app/MeetingTranscriber && swift test --parallel 2>&1 | tail -30
```

Expected: all existing + new tests pass.
