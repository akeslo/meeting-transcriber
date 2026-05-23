import SwiftData
import SwiftUI

struct StatsView: View {
    @Query private var sessions: [RecordingSession]

    private var completedSessions: [RecordingSession] {
        sessions.filter { $0.status == SessionStatus.done }
    }

    private var totalHours: Double {
        sessions.reduce(0) { $0 + $1.duration } / 3600
    }

    private var uniqueSpeakers: Int {
        Set(sessions.flatMap(\.participantNames)).count
    }

    private var mostUsedApp: String? {
        let counts = Dictionary(grouping: sessions, by: \.appName)
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
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
        return sessions.filter { $0.createdAt >= start }.count
    }

    private var avgDurationMinutes: Double {
        guard !sessions.isEmpty else { return 0 }
        return sessions.reduce(0) { $0 + $1.duration } / Double(sessions.count) / 60
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Statistics")
                    .font(.system(size: 20, weight: .bold))
                    .padding(.top, 4)

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
                        value: "\(sessions.count)",
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
                            subtitle: "\(sessions.filter { $0.appName == app }.count) recordings"
                        )
                    }
                    statCard(
                        icon: "checkmark.circle",
                        title: "Completed",
                        value: "\(completedSessions.count)",
                        subtitle: "\(sessions.filter { $0.status == SessionStatus.error }.count) errors"
                    )
                }

                if !sessions.isEmpty {
                    activitySection
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Activity by month

    private var activitySection: some View {
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
        for session in sessions {
            if let sixMonthsAgo = cal.date(byAdding: .month, value: -6, to: Date()),
               session.createdAt >= sixMonthsAgo {
                let key = fmt.string(from: session.createdAt)
                result[key, default: 0] += 1
            }
        }
        return result
    }

    // MARK: - Card

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
}
