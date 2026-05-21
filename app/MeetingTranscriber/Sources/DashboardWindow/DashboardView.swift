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
    @Binding var selectedNav: NavItem
    @Binding var selectedSessionID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    StatusCard(
                        headline: statusHeadline,
                        subtext: statusSubtext,
                        isWatching: isWatching,
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
                    selectedSessionID: $selectedSessionID
                )
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
        .environment(\.colorScheme, .light)
    }
}

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
                            SessionRowView(session: session, isSelected: false)
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
