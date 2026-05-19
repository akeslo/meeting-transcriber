import AVFoundation
import SwiftUI

struct MenuBarView: View {
    let status: TranscriberStatus?
    let isWatching: Bool
    let pipelineQueue: PipelineQueue
    var updateChecker: UpdateChecker?
    let currentMicUID: String
    var isRPCActive: Bool = false
    var protocolProviderIsNone: Bool = false
    let onSelectMic: (String) -> Void
    let onStartStop: () -> Void
    let onRecordApp: () -> Void
    let onRecordWindow: () -> Void
    let onStopManualRecording: (() -> Void)?
    let onStopAutoRecording: (() -> Void)?
    let onOpenLastProtocol: () -> Void
    let onOpenProtocol: (URL) -> Void
    let onOpenProtocolsFolder: () -> Void
    let onOpenSettings: () -> Void
    let onNameSpeakers: (() -> Void)?
    let onProcessFiles: () -> Void
    let onDismissJob: (UUID) -> Void
    let onQuit: () -> Void

    @State private var audioInputDevices: [(uid: String, name: String, channels: UInt32)] = []

    private var state: TranscriberState {
        status?.state ?? .idle
    }

    private var currentMicName: String {
        if currentMicUID.isEmpty { return "System Default" }
        return audioInputDevices.first { $0.uid == currentMicUID }?.name ?? "Unknown"
    }

    var body: some View {
        // Status header
        VStack(alignment: .leading, spacing: 2) {
            Label(state.label, systemImage: state.icon)
                .font(.headline)

            if let detail = status?.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isRPCActive {
                Label("RPC Active", systemImage: "network")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Debug RPC server is running on localhost:9876")
            }
        }
        .padding(.horizontal, 4)
        .onAppear { audioInputDevices = MicRecorder.listDevices() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)) { _ in
            audioInputDevices = MicRecorder.listDevices()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)) { _ in
            audioInputDevices = MicRecorder.listDevices()
        }

        // Meeting info
        if let meeting = status?.meeting {
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(meeting.app)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }

        // Error info
        if let error = status?.error, state == .error {
            Divider()
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 4)
        }

        Divider()

        // Start/Stop Watching
        Button {
            onStartStop()
        } label: {
            if isWatching {
                Label("Stop Watching", systemImage: "stop.fill")
            } else {
                Label("Start Watching", systemImage: "play.fill")
            }
        }
        .keyboardShortcut("s", modifiers: .command)

        if let onStopManualRecording {
            Button {
                onStopManualRecording()
            } label: {
                Label("Stop Recording", systemImage: "stop.circle.fill")
            }
            .keyboardShortcut(".")
        } else if state == .recording, let onStopAutoRecording {
            Button {
                onStopAutoRecording()
            } label: {
                Label("Stop Recording (keep watching)", systemImage: "stop.circle")
            }
            .keyboardShortcut(".")
        } else if state != .recording {
            Divider()
            Button {
                onRecordWindow()
            } label: {
                Label("Record Window...", systemImage: "macwindow.badge.plus")
            }
            .keyboardShortcut("r")
            .help(isWatching ? "Stops auto-watching and starts manual recording" : "")
            Button {
                onRecordApp()
            } label: {
                Label("Record App...", systemImage: "record.circle")
            }
            .help(isWatching ? "Stops auto-watching and starts manual recording" : "")
        }

        if let onNameSpeakers {
            Button {
                onNameSpeakers()
            } label: {
                Label("Name Speakers...", systemImage: "person.2.fill")
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        Button {
            onProcessFiles()
        } label: {
            Label("Process Audio/Video Files...", systemImage: "doc.badge.plus")
        }
        .keyboardShortcut("p")

        // Processing queue
        if !pipelineQueue.jobs.isEmpty {
            Divider()
            Label("Processing", systemImage: "gearshape.2.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(pipelineQueue.jobs) { job in
                jobRow(job)
            }
        }

        Divider()

        openLastItem

        Button {
            onOpenProtocolsFolder()
        } label: {
            Label("Open Protocols Folder", systemImage: "folder")
        }

        if let update = updateChecker?.availableUpdate {
            Divider()
            Button {
                NSWorkspace.shared.open(update.dmgURL ?? update.htmlURL)
            } label: {
                Label(
                    "Update Available: \(update.tagName)",
                    systemImage: "arrow.down.circle.fill",
                )
            }
        }

        Divider()

        Menu {
            Button {
                onSelectMic("")
            } label: {
                if currentMicUID.isEmpty {
                    Label("System Default", systemImage: "checkmark")
                } else {
                    Text("System Default")
                }
            }
            if !audioInputDevices.isEmpty {
                Divider()
                ForEach(audioInputDevices, id: \.uid) { device in
                    Button {
                        onSelectMic(device.uid)
                    } label: {
                        if currentMicUID == device.uid {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            }
        } label: {
            Label(currentMicName, systemImage: "mic")
        }
        .accessibilityLabel("Microphone: \(currentMicName)")

        Divider()

        Button {
            onOpenSettings()
        } label: {
            Label("Settings...", systemImage: "gear")
        }
        .keyboardShortcut(",")

        Divider()

        Button {
            onQuit()
        } label: {
            Label("Quit", systemImage: "power")
        }
        .keyboardShortcut("q")
    }

    // MARK: - Helpers

    @ViewBuilder
    private var openLastItem: some View {
        let latestDoneJob = pipelineQueue.jobs.last { $0.state == .done }
        let latestJobTranscriptPath = latestDoneJob?.transcriptPath
        let latestJobProtocolPath = latestDoneJob?.protocolPath
        let hasTranscriptOnly = latestJobTranscriptPath != nil && latestJobProtocolPath == nil
        if hasTranscriptOnly, let transcriptPath = latestJobTranscriptPath {
            Button {
                onOpenProtocol(transcriptPath)
            } label: {
                Label("Open Last Transcript", systemImage: "doc.text")
            }
            .keyboardShortcut("o")
        } else if !protocolProviderIsNone {
            Button {
                onOpenLastProtocol()
            } label: {
                Label("Open Last Protocol", systemImage: "doc.text")
            }
            .keyboardShortcut("o")
            .disabled(latestJobProtocolPath == nil && latestJobTranscriptPath == nil)
        }
    }

    private func jobRow(_ job: PipelineJob) -> some View {
        HStack {
            Circle()
                .fill(jobColor(job))
                .frame(width: 8, height: 8)
                .accessibilityLabel("Status: \(job.state.label)")
            VStack(alignment: .leading) {
                Text(job.meetingTitle)
                    .font(.caption)
                jobStateLabel(job)
            }
            Spacer()
            if job.state == .done, let path = job.protocolPath ?? job.transcriptPath {
                Button("Open") { onOpenProtocol(path) }
                    .font(.caption2)
                    .accessibilityLabel("Open protocol for \(job.meetingTitle)")
                    .accessibilityHint("Opens the protocol or transcript file in Finder")
            }
            if job.state == .speakerNamingPending {
                Button("Name Speakers") { onNameSpeakers?() }
                    .font(.caption2)
                    .accessibilityLabel("Name speakers for \(job.meetingTitle)")
                    .accessibilityHint("Opens the speaker naming dialog for this meeting")
            }
            if job.state == .waiting || job.state == .transcribing
                || job.state == .diarizing || job.state == .generatingProtocol {
                Button("Cancel") { pipelineQueue.cancelJob(id: job.id) }
                    .font(.caption2)
                    .accessibilityLabel("Cancel processing \(job.meetingTitle)")
                    .accessibilityHint("Stops processing and removes this job from the queue")
            }
            if job.state == .done || job.state == .error || job.state == .speakerNamingPending {
                Button("Dismiss") { onDismissJob(job.id) }
                    .font(.caption2)
                    .accessibilityLabel("Dismiss \(job.meetingTitle)")
                    .accessibilityHint("Removes this job from the list")
            }
        }
        .padding(.horizontal, 4)
    }

    private func jobStateLabel(_ job: PipelineJob) -> some View {
        Group {
            if [.transcribing, .diarizing, .generatingProtocol].contains(job.state) {
                Text("\(job.state.label) \(formattedElapsed(pipelineQueue.activeJobElapsed))")
                    .foregroundStyle(.secondary)
            } else if job.state == .error, let msg = job.error {
                Text(msg)
                    .foregroundStyle(.red)
            } else if job.state == .done, !job.warnings.isEmpty {
                Text(job.warnings.joined(separator: "; "))
                    .foregroundStyle(.orange)
            } else {
                Text(job.state.label)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
    }

    private func formattedElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total < 60 {
            return "\(total)s"
        }
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private func jobColor(_ job: PipelineJob) -> Color {
        switch job.state {
        case .waiting: .gray
        case .transcribing: .blue
        case .diarizing: .purple
        case .generatingProtocol: .orange
        case .speakerNamingPending: .purple
        case .done: job.warnings.isEmpty ? .green : .yellow
        case .error: .red
        }
    }
}
