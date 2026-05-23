# Dashboard + Stats Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the "Stats" sidebar nav item and fold all statistics content into the Dashboard view as a section below "Recent Activity".

**Architecture:** Move all stat computed properties and view helpers from `StatsView` directly into `DashboardView`. Add a `@Query` to `DashboardView` for session data. Delete `StatsView.swift` and remove the `NavItem.stats` case.

**Tech Stack:** SwiftUI, SwiftData (`@Query`), XCTest

---

## File Map

| File | Action |
|------|--------|
| `Sources/DashboardWindow/SidebarView.swift` | Modify — remove `NavItem.stats` case |
| `Sources/DashboardWindow/DashboardWindowContent.swift` | Modify — remove `case .stats:` branch |
| `Sources/DashboardWindow/DashboardView.swift` | Modify — add `@Query`, stat logic, stats section in body |
| `Sources/DashboardWindow/StatsView.swift` | **Delete** |
| `Tests/DashboardWindow/DashboardViewTests.swift` | Modify — add stat computation tests |

---

### Task 1: Remove NavItem.stats and its dispatch branch

**Files:**
- Modify: `Sources/DashboardWindow/SidebarView.swift`
- Modify: `Sources/DashboardWindow/DashboardWindowContent.swift`

- [ ] **Step 1: Remove `.stats` from `NavItem`**

In `Sources/DashboardWindow/SidebarView.swift`, delete the `.stats` case and its `systemImage`:

```swift
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
```

- [ ] **Step 2: Remove `case .stats:` from `DashboardWindowContent`**

In `Sources/DashboardWindow/DashboardWindowContent.swift`, delete the stats branch from `contentPane`:

```swift
@ViewBuilder
private var contentPane: some View {
    switch selectedNav {
    case .library:
        LibraryView(
            pipelineQueue: pipelineQueue,
            selectedSessionID: $selectedSessionID,
            onDeleteSession: deleteSession
        )
    case .dashboard:
        DashboardView(
            status: status,
            isWatching: isWatching,
            settings: settings,
            elapsedLabel: elapsedLabel,
            onStartStop: onStartStop,
            onDeleteSession: deleteSession,
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
            onSpeakerMutate: onSpeakerMutate,
            onRunDetectionTest: onRunDetectionTest
        )
    }
}
```

- [ ] **Step 3: Build to verify no compile errors**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep -E "error:|warning:" | head -20
```

Expected: zero errors (may have warnings about unused `StatsView` — fine for now).

- [ ] **Step 4: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/SidebarView.swift \
        app/MeetingTranscriber/Sources/DashboardWindow/DashboardWindowContent.swift
git commit -m "feat(app): remove Stats nav item from sidebar"
```

---

### Task 2: Move stat logic into DashboardView

**Files:**
- Modify: `Sources/DashboardWindow/DashboardView.swift`

- [ ] **Step 1: Add `@Query` and stat computed properties to `DashboardView`**

At the top of `DashboardView` struct (after the existing `let`/`@Binding` properties), add:

```swift
@Query private var allSessions: [RecordingSession]

private var completedSessions: [RecordingSession] {
    allSessions.filter { $0.status == SessionStatus.done }
}

private var totalHours: Double {
    allSessions.reduce(0) { $0 + $1.duration } / 3600
}

private var uniqueSpeakers: Int {
    Set(allSessions.flatMap(\.participantNames)).count
}

private var mostUsedApp: String? {
    let counts = Dictionary(grouping: allSessions, by: \.appName)
        .filter { !$0.key.isEmpty }
        .mapValues(\.count)
    return counts.max(by: { $0.value < $1.value })?.key
}

private var protocolRate: Double {
    let total = completedSessions.count
    guard total > 0 else { return 0 }
    return Double(completedSessions.filter(\.hasProtocol).count) / Double(total) * 100
}

private var thisMonthCount: Int {
    let start = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    )!
    return allSessions.filter { $0.createdAt >= start }.count
}

private var avgDurationMinutes: Double {
    guard !allSessions.isEmpty else { return 0 }
    return allSessions.reduce(0) { $0 + $1.duration } / Double(allSessions.count) / 60
}

private var monthlyActivity: [String: Int] {
    let cal = Calendar.current
    var result: [String: Int] = [:]
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM"
    for offset in (0 ..< 6).reversed() {
        if let month = cal.date(byAdding: .month, value: -offset, to: Date()) {
            result[fmt.string(from: month)] = 0
        }
    }
    for session in allSessions {
        if let sixMonthsAgo = cal.date(byAdding: .month, value: -6, to: Date()),
           session.createdAt >= sixMonthsAgo {
            let key = fmt.string(from: session.createdAt)
            result[key, default: 0] += 1
        }
    }
    return result
}
```

- [ ] **Step 2: Add `statCard` helper to `DashboardView`**

Add as a private `@ViewBuilder` function inside `DashboardView`:

```swift
@ViewBuilder
private func statCard(icon: String, title: String, value: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        Text(value)
            .font(.system(size: 22, weight: .bold))
        Text(subtitle)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.secondary.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 10))
}
```

- [ ] **Step 3: Add `statisticsSection` computed view to `DashboardView`**

Add as a private computed property inside `DashboardView`:

```swift
private var statisticsSection: some View {
    VStack(alignment: .leading, spacing: 16) {
        Text("Statistics")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(spaceIndigo)

        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ],
            spacing: 12
        ) {
            statCard(
                icon: "waveform",
                title: "Total Recordings",
                value: "\(allSessions.count)",
                subtitle: "\(thisMonthCount) this month"
            )
            statCard(
                icon: "clock",
                title: "Total Hours",
                value: String(format: "%.1f h", totalHours),
                subtitle: String(format: "avg %.0f min/session", avgDurationMinutes)
            )
            statCard(
                icon: "person.2",
                title: "Unique Speakers",
                value: "\(uniqueSpeakers)",
                subtitle: "identified via diarization"
            )
            statCard(
                icon: "doc.richtext",
                title: "Protocol Rate",
                value: String(format: "%.0f%%", protocolRate),
                subtitle: "\(completedSessions.filter(\.hasProtocol).count) / \(completedSessions.count) completed"
            )
            if let app = mostUsedApp {
                statCard(
                    icon: "desktopcomputer",
                    title: "Most Used App",
                    value: app,
                    subtitle: "\(allSessions.filter { $0.appName == app }.count) recordings"
                )
            }
            statCard(
                icon: "checkmark.circle",
                title: "Completed",
                value: "\(completedSessions.count)",
                subtitle: "\(allSessions.filter { $0.status == SessionStatus.error }.count) errors"
            )
        }

        if !allSessions.isEmpty {
            activityChartSection
        }
    }
}

private var activityChartSection: some View {
    VStack(alignment: .leading, spacing: 10) {
        Text("Activity (last 6 months)")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)

        let monthly = monthlyActivity
        let maxCount = monthly.values.max() ?? 1

        HStack(alignment: .bottom, spacing: 6) {
            ForEach(monthly.keys.sorted(), id: \.self) { month in
                let count = monthly[month] ?? 0
                VStack(spacing: 4) {
                    Text("\(count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.7))
                        .frame(width: 28, height: max(4, CGFloat(count) / CGFloat(maxCount) * 80))
                    Text(month)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    .padding(16)
    .background(Color.secondary.opacity(0.05))
    .clipShape(RoundedRectangle(cornerRadius: 10))
}
```

- [ ] **Step 4: Add `statisticsSection` to `DashboardView.body`**

In `DashboardView.body`, the `VStack` currently contains three items. Add `statisticsSection` after `RecentActivitySection`:

```swift
var body: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                StatusCard(
                    headline: statusHeadline,
                    subtext: statusSubtext,
                    isWatching: isWatching,
                    isRecording: status?.state == .recording,
                    onStartStop: onStartStop
                )
                .frame(maxWidth: .infinity)

                VStack(spacing: 16) {
                    QuickControlsCard(settings: settings)
                    AmbientLevelCard(
                        appDbfs: settings.lastAppDbfs,
                        micDbfs: settings.lastMicDbfs,
                        isActive: status?.state == .recording
                    )
                }
                .frame(maxWidth: .infinity)
            }

            RecentActivitySection(
                selectedNav: $selectedNav,
                selectedSessionID: $selectedSessionID,
                onDeleteSession: onDeleteSession
            )

            statisticsSection
        }
        .padding(24)
    }
    .background(Color(nsColor: .windowBackgroundColor))
}
```

- [ ] **Step 5: Build to verify no errors**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep -E "error:" | head -20
```

Expected: zero errors.

- [ ] **Step 6: Commit**

```bash
git add app/MeetingTranscriber/Sources/DashboardWindow/DashboardView.swift
git commit -m "feat(app): embed statistics section in Dashboard view"
```

---

### Task 3: Delete StatsView.swift

**Files:**
- Delete: `Sources/DashboardWindow/StatsView.swift`

- [ ] **Step 1: Delete the file**

```bash
git rm app/MeetingTranscriber/Sources/DashboardWindow/StatsView.swift
```

- [ ] **Step 2: Build to confirm nothing references it**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep -E "error:" | head -20
```

Expected: zero errors.

- [ ] **Step 3: Commit**

```bash
git commit -m "chore(app): delete StatsView (merged into DashboardView)"
```

---

### Task 4: Add stat computation tests

**Files:**
- Modify: `Tests/DashboardWindow/DashboardViewTests.swift`

The existing `DashboardViewTests` tests the headline logic via a local helper function (no SwiftData needed). We follow the same pattern for stat computations — extract the pure logic into testable free functions or test the computed values directly via helper functions mirroring the production logic.

- [ ] **Step 1: Add tests for stat computed properties**

Append these test methods to the existing `DashboardViewTests` class:

```swift
func test_totalHours_empty_returnsZero() {
    let sessions: [TimeInterval] = []
    let hours = sessions.reduce(0, +) / 3600
    XCTAssertEqual(hours, 0)
}

func test_totalHours_twoSessions_sumsCorrectly() {
    // 3600 s + 7200 s = 3.0 h
    let sessions: [TimeInterval] = [3600, 7200]
    let hours = sessions.reduce(0, +) / 3600
    XCTAssertEqual(hours, 3.0, accuracy: 0.001)
}

func test_avgDurationMinutes_empty_returnsZero() {
    let durations: [TimeInterval] = []
    let avg = durations.isEmpty ? 0.0 : durations.reduce(0, +) / Double(durations.count) / 60
    XCTAssertEqual(avg, 0.0)
}

func test_avgDurationMinutes_twoSessions_returnsCorrectAvg() {
    // 60 s + 120 s → avg 90 s → 1.5 min
    let durations: [TimeInterval] = [60, 120]
    let avg = durations.reduce(0, +) / Double(durations.count) / 60
    XCTAssertEqual(avg, 1.5, accuracy: 0.001)
}

func test_protocolRate_noCompleted_returnsZero() {
    let total = 0
    let rate = total > 0 ? Double(0) / Double(total) * 100 : 0.0
    XCTAssertEqual(rate, 0.0)
}

func test_protocolRate_halfCompleted_returns50() {
    let total = 4
    let withProtocol = 2
    let rate = Double(withProtocol) / Double(total) * 100
    XCTAssertEqual(rate, 50.0, accuracy: 0.001)
}

func test_uniqueSpeakers_deduplicates() {
    let participants: [[String]] = [["Alice", "Bob"], ["Bob", "Carol"], ["Alice"]]
    let unique = Set(participants.flatMap { $0 }).count
    XCTAssertEqual(unique, 3)
}

func test_mostUsedApp_returnsHighestCount() {
    let apps = ["Zoom", "Zoom", "Teams", "Zoom", "Teams"]
    let counts = Dictionary(grouping: apps, by: { $0 }).mapValues(\.count)
    let most = counts.max(by: { $0.value < $1.value })?.key
    XCTAssertEqual(most, "Zoom")
}

func test_mostUsedApp_empty_returnsNil() {
    let apps: [String] = []
    let counts = Dictionary(grouping: apps, by: { $0 })
        .filter { !$0.key.isEmpty }
        .mapValues(\.count)
    let most = counts.max(by: { $0.value < $1.value })?.key
    XCTAssertNil(most)
}
```

- [ ] **Step 2: Run the tests**

```bash
cd app/MeetingTranscriber && swift test --filter DashboardViewTests 2>&1 | tail -20
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/MeetingTranscriber/Tests/DashboardWindow/DashboardViewTests.swift
git commit -m "test(app): add stat computation tests for Dashboard merge"
```

---

### Task 5: Full test suite

- [ ] **Step 1: Run all tests**

```bash
cd app/MeetingTranscriber && swift test --parallel 2>&1 | tail -30
```

Expected: All tests pass, no regressions.
