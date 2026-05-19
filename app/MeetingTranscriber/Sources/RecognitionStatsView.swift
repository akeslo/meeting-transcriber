import AppKit
import SwiftUI

/// Surfaces aggregate counts from `recognition_log.jsonl` so the user can
/// verify whether `SpeakerMatcher` quality drifts over time. The JSONL file
/// remains the source of truth; this view is read-only.
struct RecognitionStatsView: View {
    @State private var aggregate: RecognitionStats.Aggregate?
    @State private var windowDays: WindowChoice = .thirty
    @State private var isReloading = false

    private let log: RecognitionStatsLog

    init(log: RecognitionStatsLog) {
        self.log = log
    }

    enum WindowChoice: Int, CaseIterable, Identifiable {
        case seven = 7, thirty = 30, ninety = 90
        var id: Int {
            rawValue
        }

        var label: String {
            "Last \(rawValue) days"
        }
    }

    var body: some View {
        Section("Recognition Stats") {
            Picker("Window", selection: $windowDays) {
                ForEach(WindowChoice.allCases) { choice in
                    Text(choice.label)
                        .tag(choice)
                        .accessibilityLabel(choice.label)
                }
            }
            .pickerStyle(.segmented)

            if let aggregate {
                if aggregate.total > 0 {
                    statsBody(aggregate)
                } else {
                    Text("No data yet — confirm a meeting to start collecting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView("Loading stats...").frame(maxWidth: .infinity, alignment: .center)
            }

            HStack {
                Button("Open Log Folder") {
                    let logPath = RecognitionStatsLog.defaultPath
                    if FileManager.default.fileExists(atPath: logPath.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([logPath])
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([logPath.deletingLastPathComponent()])
                    }
                }
                Spacer()
                Button {
                    Task {
                        isReloading = true
                        await reload()
                        isReloading = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isReloading {
                            ProgressView().controlSize(.small)
                        }
                        Text("Reload")
                    }
                }
                .disabled(isReloading)
            }
        }
        .task(id: windowDays) { await reload() }
    }

    @ViewBuilder
    private func statsBody(_ agg: RecognitionStats.Aggregate) -> some View {
        LabeledContent("Total confirmations", value: "\(agg.total)")
        statRow(.accepted, count: agg.counts[.accepted] ?? 0, total: agg.total)
        statRow(.corrected, count: agg.counts[.corrected] ?? 0, total: agg.total)
        statRow(.added, count: agg.counts[.added] ?? 0, total: agg.total)
        statRow(.skipped, count: agg.counts[.skipped] ?? 0, total: agg.total)
        statRow(.dismissed, count: agg.counts[.dismissed] ?? 0, total: agg.total)
    }

    private func statRow(_ action: RecognitionAction, count: Int, total: Int) -> some View {
        let pct = Int((Double(count) / Double(total) * 100).rounded())
        return LabeledContent(action.rawValue.capitalized) {
            HStack(spacing: 8) {
                Text("\(count)")
                pctLabel(pct)
                progressBar(count: count, total: total)
            }
        }
    }

    private func pctLabel(_ pct: Int) -> some View {
        Text("(\(pct)%)")
            .foregroundStyle(.secondary)
            .font(.caption)
    }

    private func progressBar(count: Int, total: Int) -> some View {
        return ProgressView(value: Double(count), total: Double(total))
            .frame(width: 80)
            .accessibilityLabel("\(count) of \(total)")
    }

    private func reload() async {
        let now = Date()
        let interval = TimeInterval(windowDays.rawValue * 86400)
        let events = await log.loadRecent(within: interval, now: now)
        aggregate = RecognitionStats.aggregate(
            events: events,
            from: now.addingTimeInterval(-interval),
            to: now,
        )
    }
}
