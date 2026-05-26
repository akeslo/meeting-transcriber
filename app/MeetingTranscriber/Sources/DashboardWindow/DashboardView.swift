import SwiftData
import SwiftUI

// MARK: - Design tokens (module-private)

private let spaceIndigo  = Color(red: 0.082, green: 0.114, blue: 0.208)
private let peachGlow    = Color(red: 0.969, green: 0.773, blue: 0.624)
private let aliceBlue    = Color(red: 0.882, green: 0.898, blue: 0.933)
private let paleSlate    = Color(red: 0.878, green: 0.898, blue: 0.941)
private let cardBg       = Color.white

struct DashboardView: View {
    let status: TranscriberStatus?
    let isWatching: Bool
    @Bindable var settings: AppSettings
    let elapsedLabel: String
    let onStartStop: () -> Void
    let onDeleteSession: (RecordingSession) -> Void
    @Binding var selectedNav: NavItem
    @Binding var selectedSessionID: UUID?

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

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
        .environment(\.colorScheme, .light)
    }

    // MARK: - Stat helpers

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

    // MARK: - Headline logic (internal for testability)

    var statusHeadline: String {
        guard let state = status?.state else {
            return isWatching ? "Meeting Detection is active." : "Idle"
        }
        switch state {
        case .recording:          return "Recording · \(elapsedLabel)"
        case .transcribing:       return "Transcribing..."
        case .generatingProtocol: return "Generating Protocol..."
        case .recordingDone:      return "Processing..."
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
        case .recordingDone:      return "Identifying speakers..."
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
    let isRecording: Bool
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

            if isRecording {
                VStack(alignment: .leading, spacing: 8) {
                    AudioSourceRow(label: "App Audio Tap", active: true)
                    AudioSourceRow(label: "Built-in Mic", active: true)
                }
            }

            Spacer(minLength: 0)

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
        .environment(\.colorScheme, .light)
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
            set: { settings.diarizerMode = $0 ? .sortformer : .offline }
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

            Toggle("Sortformer (Overlap-aware)", isOn: sortformerBinding)
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
        .environment(\.colorScheme, .light)
    }
}

// MARK: - RecentActivitySection

private struct RecentActivitySection: View {
    @Binding var selectedNav: NavItem
    @Binding var selectedSessionID: UUID?
    let onDeleteSession: (RecordingSession) -> Void

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
                            SessionRowView(session: session, isSelected: false, onDelete: { onDeleteSession(session) })
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
                .environment(\.colorScheme, .light)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(paleSlate, lineWidth: 1)
                )
            }
        }
    }
}
