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
            Image(systemName: iconName(for: session.appName))
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title.isEmpty ? "Untitled Recording" : session.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(dateString)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(durationString)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)

            StatusChipView(status: session.status)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    private func iconName(for appName: String) -> String {
        let lower = appName.lowercased()
        if lower.contains("zoom")  { return "video" }
        if lower.contains("teams") { return "video.fill" }
        if lower.contains("meet")  { return "person.2.wave.2" }
        if lower.contains("webex") { return "network" }
        if lower.contains("slack") { return "bubble.left.and.bubble.right" }
        return "mic"
    }
}

// MARK: - InFlightRowView

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

                if let startedAt = job.startedAt {
                    Text(Self.dateFormatter.string(from: startedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

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
