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
    var levelSource: (() -> (mic: Double, app: Double))? = nil

    private var state: TranscriberState { status?.state ?? .idle }
    private var isRecording: Bool { state == .recording }
    private var isManualRecording: Bool { onStopManualRecording != nil }

    var body: some View {
        VStack(spacing: 0) {
            statusCard
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)

            primaryActionButton
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            if !isModelReady {
                modelNotReadyBanner
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            if (state == .waitingForSpeakerNames || state == .waitingForSpeakerCount),
               let cb = onNameSpeakers {
                speakersBanner(action: cb)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            Divider()

            actionRows

            Divider()

            MenuActionRow(icon: "power", label: "Quit", action: onQuit)
                .keyboardShortcut("q")
        }
        .frame(width: 300)
    }

    // MARK: - Status card

    @ViewBuilder
    private var statusCard: some View {
        Group {
            if isRecording {
                recordingCard
            } else if state == .watching {
                watchingCard
            } else {
                defaultCard
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    // Recording: waveform + title row
    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text(statusLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            WaveformBarsView(levelSource: levelSource)
                .frame(height: 60)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
    }

    // Watching: radar pulse centred in card
    private var watchingCard: some View {
        VStack(spacing: 10) {
            RadarPulseView(color: Color(nsColor: MenuBarIcon.peachGlow))
                .frame(width: 56, height: 56)
                .padding(.top, 16)
            Text("Watching for Meetings")
                .font(.system(size: 13, weight: .semibold))
            if let detail = status?.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }

    // All other states: icon + label centred
    private var defaultCard: some View {
        VStack(spacing: 6) {
            Image(systemName: state.icon)
                .font(.system(size: 22))
                .foregroundStyle(statusDotColor)
                .padding(.top, 14)
            Text(statusLabel)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if let error = status?.error, state == .error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            } else if let detail = status?.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 14)
    }

    private var statusLabel: String {
        if let title = status?.meeting?.title, !title.isEmpty {
            return "\(state.label) · \(title)"
        }
        return state.label
    }

    // MARK: - Primary action

    @ViewBuilder
    private var primaryActionButton: some View {
        if let onStop = onStopManualRecording {
            PrimaryActionRow(icon: "stop.fill", label: "Stop Recording", color: .red, action: onStop)
                .keyboardShortcut(".")
        } else if isWatching {
            PrimaryActionRow(icon: "stop.circle", label: "Stop Watching", color: .orange, action: onStartStop)
                .keyboardShortcut("s")
        } else {
            PrimaryActionRow(
                icon: "play.fill", label: "Start Watching", color: .accentColor,
                action: onStartStop, disabled: !isModelReady
            )
            .keyboardShortcut("s")
        }
    }

    // MARK: - Action rows

    @ViewBuilder
    private var actionRows: some View {
        VStack(spacing: 0) {
            if !isRecording && !isManualRecording {
                MenuActionRow(icon: "record.circle", label: "Record App\u{2026}", action: onRecordApp, disabled: !isModelReady)
                    .keyboardShortcut("r")
                Divider().padding(.leading, 52)
            }
            MenuActionRow(icon: "folder", label: "Process Files", action: onProcessFiles, disabled: !isModelReady)
                .keyboardShortcut("p")
            Divider().padding(.leading, 52)
            MenuActionRow(icon: "arrow.up.forward.square", label: "Output Folder", action: onOpenOutputFolder)
            Divider().padding(.leading, 52)
            MenuActionRow(icon: "gauge.medium", label: "Dashboard", action: onOpenDashboard)
                .keyboardShortcut("d")
            Divider().padding(.leading, 52)
            MenuActionRow(icon: "gearshape", label: "Settings", action: onOpenSettings)
                .keyboardShortcut(",")
            if let update = updateChecker?.availableUpdate {
                Divider().padding(.leading, 52)
                MenuActionRow(
                    icon: "arrow.down.circle.fill",
                    label: "Update: \(update.tagName)",
                    tint: Color(nsColor: MenuBarIcon.peachGlow),
                    action: { NSWorkspace.shared.open(update.dmgURL ?? update.htmlURL) }
                )
            }
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var modelNotReadyBanner: some View {
        Button { onOpenSettings() } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Model not loaded")
                        .font(.caption.weight(.semibold))
                    Text("Open Settings → Transcription to load.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func speakersBanner(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                Text("Speakers need names")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Name Now \u{2192}")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var statusDotColor: Color {
        switch state {
        case .recording, .transcribing, .recordingDone, .generatingProtocol,
             .waitingForSpeakerNames, .waitingForSpeakerCount, .protocolReady:
            Color(nsColor: MenuBarIcon.peachGlow)
        case .error: .red
        default: .gray
        }
    }
}

// MARK: - PrimaryActionRow

private struct PrimaryActionRow: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    var disabled: Bool = false

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(isHovered ? 0.22 : 0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(color.opacity(disabled ? 0.4 : 1))
                }
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color.opacity(disabled ? 0.4 : 1))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(isHovered ? 0.15 : 0.09))
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { isHovered = $0 }
    }
}

// MARK: - MenuActionRow

private struct MenuActionRow: View {
    let icon: String
    let label: String
    var tint: Color = .primary
    let action: () -> Void
    var disabled: Bool = false

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .frame(width: 24)
                    .foregroundStyle(tint == .primary ? Color.primary.opacity(disabled ? 0.35 : 0.8) : tint)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(tint == .primary ? Color.primary.opacity(disabled ? 0.35 : 1) : tint)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(isHovered && !disabled ? Color.primary.opacity(0.07) : Color.clear)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { isHovered = $0 }
    }
}

// MARK: - WaveformBarsView

private struct WaveformBarsView: View {
    var levelSource: (() -> (mic: Double, app: Double))?

    @State private var phase: Double = 0
    @State private var smoothedAmp: Double = 0.15

    private let barCount = 36
    private static let offsets: [Double] = {
        (0..<36).map { i in Double(i) * (Double.pi * 2 / 36) * 1.618 }
    }()
    private var offsets: [Double] { Self.offsets }
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let bw = max(1, (geo.size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(0..<barCount, id: \.self) { i in
                    let h = barHeight(i: i, maxH: geo.size.height)
                    RoundedRectangle(cornerRadius: min(bw / 2, 2.5))
                        .fill(Color.green.opacity(0.9))
                        .frame(width: bw, height: h)
                        .animation(.linear(duration: 0.05), value: h)
                }
            }
        }
        .onReceive(timer) { _ in
            phase += 0.12
            if let levels = levelSource?() {
                let norm = max(0.08, min(1, (max(levels.mic, levels.app) + 60) / 60))
                smoothedAmp = smoothedAmp * 0.8 + norm * 0.2
            }
        }
    }

    private func barHeight(i: Int, maxH: CGFloat) -> CGFloat {
        let pos = Double(i) / Double(barCount - 1)
        let env = pow(sin(.pi * pos), 0.6)
        let w1 = (sin(phase * 2.0 + offsets[i]) + 1) / 2
        let w2 = (sin(phase * 1.3 + offsets[i] * 0.7) + 1) / 2 * 0.35
        return max(2, env * (0.65 * w1 + 0.35 * w2) * smoothedAmp * maxH)
    }
}

// MARK: - RadarPulseView

private struct RadarPulseView: View {
    var color: Color = .accentColor

    // 3 rings staggered by 1/3 of the cycle
    @State private var scales: [CGFloat] = [0.2, 0.2, 0.2]
    @State private var opacities: [Double] = [0.7, 0.7, 0.7]

    private let duration: Double = 2.2
    private let ringCount = 3

    var body: some View {
        ZStack {
            ForEach(0..<ringCount, id: \.self) { i in
                Circle()
                    .stroke(color.opacity(opacities[i]), lineWidth: 1.5)
                    .scaleEffect(scales[i])
            }
            // Centre dot
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear { animate() }
    }

    private func animate() {
        for i in 0..<ringCount {
            let delay = duration / Double(ringCount) * Double(i)
            withAnimation(
                .easeOut(duration: duration)
                .repeatForever(autoreverses: false)
                .delay(delay)
            ) {
                scales[i] = 1.0
                opacities[i] = 0.0
            }
        }
    }
}
