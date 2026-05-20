import SwiftUI

struct MenuBarView: View {
    let status: TranscriberStatus?
    let isWatching: Bool
    let isModelReady: Bool
    var updateChecker: UpdateChecker?
    let onStartStop: () -> Void
    let onRecordApp: () -> Void
    let onStopManualRecording: (() -> Void)?
    let onOpenOutputFolder: () -> Void
    let onOpenDashboard: () -> Void
    let onOpenSettings: () -> Void
    let onNameSpeakers: (() -> Void)?
    let onProcessFiles: () -> Void
    let onQuit: () -> Void

    private var state: TranscriberState {
        status?.state ?? .idle
    }

    var body: some View {
        // ── Zone 1: Status ──────────────────────────────────────────────
        zone1Status

        // Model-not-ready warning sits between Zone 1 and Zone 2.
        if !isModelReady { modelNotReadyWarning }

        Divider()

        // ── Zone 2: Actions ─────────────────────────────────────────────
        zone2Actions

        Divider()

        // ── Zone 3: Quit ────────────────────────────────────────────────
        Button {
            onQuit()
        } label: {
            Text("Quit")
        }
        .keyboardShortcut("q")
    }

    // MARK: - Zone 1

    @ViewBuilder
    private var zone1Status: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Primary row: dot + state label + meeting title
            HStack(spacing: 5) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 7, height: 7)
                HStack(spacing: 4) {
                    Text(state.label)
                        .font(.headline)
                    if let title = status?.meeting?.title {
                        Text("·")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
            }

            // Secondary row: detail / elapsed
            if let detail = status?.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            }
        }
        .padding(.horizontal, 4)

        // userAction banner
        if state == .waitingForSpeakerNames || state == .waitingForSpeakerCount {
            if let onNameSpeakers {
                HStack {
                    Text("Speakers need names")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Name Now →") {
                        onNameSpeakers()
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }
        }

        // Error detail
        if let error = status?.error, state == .error {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Zone 2

    @ViewBuilder
    private var zone2Actions: some View {
        // Start / Stop Watching
        Button {
            onStartStop()
        } label: {
            if isWatching {
                Label("Stop Watching", systemImage: "stop.fill")
            } else {
                Label("Start Watching", systemImage: "play.fill")
            }
        }
        .keyboardShortcut("s")
        .disabled(!isModelReady && !isWatching)

        // Record App / Stop Recording
        if let onStopManualRecording {
            Button {
                onStopManualRecording()
            } label: {
                Label("Stop Recording", systemImage: "stop.circle.fill")
            }
            .keyboardShortcut(".")
        } else if state != .recording {
            Button {
                onRecordApp()
            } label: {
                Label("Record App...", systemImage: "record.circle")
            }
            .keyboardShortcut("r")
            .disabled(!isModelReady)
        }

        // Process Audio/Video Files
        Button {
            onProcessFiles()
        } label: {
            Label("Process Audio/Video Files...", systemImage: "doc.badge.plus")
        }
        .keyboardShortcut("p")
        .disabled(!isModelReady)

        // Open Output Folder
        Button {
            onOpenOutputFolder()
        } label: {
            Label("Open Output Folder", systemImage: "folder")
        }

        // Open Dashboard
        Button {
            onOpenDashboard()
        } label: {
            Label("Open Dashboard", systemImage: "chart.bar.doc.horizontal")
        }
        .keyboardShortcut("d")

        // Update available (Peach Glow tint, inserted above Settings)
        if let update = updateChecker?.availableUpdate {
            Button {
                NSWorkspace.shared.open(update.dmgURL ?? update.htmlURL)
            } label: {
                Label(
                    "Update Available: \(update.tagName)",
                    systemImage: "arrow.down.circle.fill",
                )
                .foregroundStyle(Color(nsColor: MenuBarIcon.peachGlow))
            }
        }

        // Settings
        Button {
            onOpenSettings()
        } label: {
            Label("Settings...", systemImage: "gear")
        }
        .keyboardShortcut(",")
    }

    // MARK: - Model-not-ready warning

    @ViewBuilder
    private var modelNotReadyWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Model not loaded")
                    .font(.caption.weight(.semibold))
                Text("Open Settings → Transcription to load.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private var statusDotColor: Color {
        switch state {
        case .recording, .transcribing, .recordingDone, .generatingProtocol,
             .waitingForSpeakerNames, .waitingForSpeakerCount, .protocolReady:
            Color(nsColor: MenuBarIcon.peachGlow)
        case .error:
            .red
        default:
            .gray
        }
    }
}
