import SwiftUI

struct SessionGridCardView: View {
    let session: RecordingSession
    let isSelected: Bool
    let onDelete: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private var durationString: String {
        let total = Int(session.duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))

                HStack(alignment: .center, spacing: 2) {
                    ForEach(Array(waveformHeights.enumerated()), id: \.offset) { _, height in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 3, height: CGFloat(height))
                    }
                }
                .blur(radius: 1)

                Image(systemName: "waveform")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary.opacity(0.4))
            }
            .frame(height: 80)

            Text(session.title.isEmpty ? "Untitled Recording" : session.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack {
                Text(Self.dateFormatter.string(from: session.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Text(durationString)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            StatusChipView(status: session.status)
        }
        .padding(12)
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected
                    ? Color.accentColor.opacity(0.08)
                    : Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.12),
                    lineWidth: 1
                )
        )
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    }

    private var waveformHeights: [Int] {
        let seed = session.id.uuidString.utf8.reduce(0) { $0 &+ Int($1) }
        return (0..<28).map { i in
            abs((seed &+ i * 17) % 40) + 8
        }
    }
}
