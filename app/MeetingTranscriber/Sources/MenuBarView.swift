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
    var micDeviceName: String = ""
    var appSourceName: String = ""
    /// Called at ~10 Hz to get (micDBFS, appDBFS). Closure avoids stale Double snapshots.
    var levelSource: (() -> (mic: Double, app: Double))? = nil

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
                Text((status?.meeting?.title).map { "\(state.label) · \($0)" } ?? state.label)
                    .font(.headline)
                    .lineLimit(1)
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

        if state == .recording {
            AudioLevelsView(
                appSourceName: appSourceName,
                micDeviceName: micDeviceName,
                levelSource: levelSource
            )
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
        Button { onOpenSettings() } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Model not loaded")
                        .font(.caption.weight(.semibold))
                    Text("Open Settings → Transcription to load.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
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

// MARK: - Self-updating audio level rows

/// Polls its own timer so level bars stay live regardless of Scene-body observation cadence.
private struct AudioLevelsView: View {
    let appSourceName: String
    let micDeviceName: String
    let levelSource: (() -> (mic: Double, app: Double))?

    @State private var micLevel: Double = -120
    @State private var appLevel: Double = -120
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()
            HStack(alignment: .top, spacing: 10) {
                if !appSourceName.isEmpty {
                    levelRow(label: appSourceName, icon: "desktopcomputer", level: appLevel)
                }
                if !appSourceName.isEmpty { Divider().frame(height: 28) }
                levelRow(
                    label: micDeviceName.isEmpty ? "Microphone" : micDeviceName,
                    icon: "mic.fill",
                    level: micLevel
                )
            }
            .padding(.vertical, 4)
            Divider()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .onReceive(timer) { _ in
            if let levels = levelSource?() {
                micLevel = levels.mic
                appLevel = levels.app
            }
        }
    }

    private func levelRow(label: String, icon: String, level: Double) -> some View {
        let fraction = max(0, min(1, (level + 60) / 60))
        let color: Color = level > -6 ? .red : level > -20 ? .yellow : .green
        let dbText = level <= -119 ? "—" : "\(Int(level)) dB"
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(dbText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(color.opacity(level <= -119 ? 0.4 : 0.9))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .green.opacity(0.9), location: 0),
                                    .init(color: .green.opacity(0.9), location: 0.55),
                                    .init(color: .yellow.opacity(0.9), location: 0.75),
                                    .init(color: .red.opacity(0.9), location: 1.0),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing,
                            )
                        )
                        .frame(width: geo.size.width * fraction)
                        .animation(.linear(duration: 0.08), value: fraction)
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
    }
}
