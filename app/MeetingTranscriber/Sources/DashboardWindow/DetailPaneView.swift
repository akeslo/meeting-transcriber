import AppKit
import SwiftUI

struct DetailPaneView: View {
    let session: RecordingSession?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        if let session {
            sessionDetail(session)
        } else {
            emptyState
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack {
            Spacer()
            Image(systemName: "waveform.badge.microphone")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 12)
            Text("Select a recording to view details")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session detail

    @ViewBuilder
    private func sessionDetail(_ session: RecordingSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(session.title.isEmpty ? "Untitled Recording" : session.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                FlowLayout(spacing: 6) {
                    metadataChip(
                        icon: "calendar",
                        label: Self.dateFormatter.string(from: session.createdAt)
                    )
                    metadataChip(
                        icon: "clock",
                        label: durationString(session.duration)
                    )
                    if !session.appName.isEmpty {
                        metadataChip(icon: "desktopcomputer", label: session.appName)
                    }
                    metadataChip(icon: "cpu", label: session.engine.isEmpty ? "Unknown engine" : session.engine)
                    StatusChipView(status: session.status)
                }

                if !session.participantNames.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Participants", systemImage: "person.2")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(session.participantNames, id: \.self) { name in
                                Text(name)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Divider()

                VStack(spacing: 10) {
                    Button {
                        openTranscript(for: session)
                    } label: {
                        Label("Open Transcript", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.hasTranscript)

                    Button {
                        openProtocol(for: session)
                    } label: {
                        Label("Open Protocol", systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!session.hasProtocol)

                    Button {
                        revealInFinder(for: session)
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if !session.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Warnings", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.orange)
                        ForEach(session.warnings, id: \.self) { warning in
                            Text(warning)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = session.errorMessage, !error.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Error", systemImage: "xmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView {
                    Text("Transcript reader — Phase 4")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(height: 200)
                .background(Color.secondary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer(minLength: 20)
            }
            .padding(20)
        }
        .frame(width: 360)
    }

    // MARK: - Helpers

    private func durationString(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func openTranscript(for session: RecordingSession) {
        let folder = URL(fileURLWithPath: session.folderPath)
        NSWorkspace.shared.open(folder.appendingPathComponent("transcript.md"))
    }

    private func openProtocol(for session: RecordingSession) {
        let folder = URL(fileURLWithPath: session.folderPath)
        NSWorkspace.shared.open(folder.appendingPathComponent("protocol.md"))
    }

    private func revealInFinder(for session: RecordingSession) {
        let folder = URL(fileURLWithPath: session.folderPath)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }

    @ViewBuilder
    private func metadataChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.08))
        .clipShape(Capsule())
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                totalHeight = y
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
