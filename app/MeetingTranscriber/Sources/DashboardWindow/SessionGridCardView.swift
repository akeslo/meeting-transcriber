import AppKit
import SwiftUI

struct SessionGridCardView: View {
    let session: RecordingSession
    let isSelected: Bool
    let onDelete: () -> Void
    var allTags: [String] = []
    var allFolders: [String] = []
    var onRename: ((String) -> Void)? = nil
    var onAddTag: ((String) -> Void)? = nil
    var onSetFolder: ((String) -> Void)? = nil

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

            StatusChipView(status: session.displayStatus)
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
            if let onRename {
                Button {
                    promptText(
                        title: "Rename Recording",
                        message: "Enter a new name:",
                        placeholder: session.title,
                        initial: session.title
                    ) { onRename($0) }
                } label: {
                    Label("Rename…", systemImage: "pencil")
                }
            }

            if let onAddTag {
                Button {
                    promptText(
                        title: "Add Tag",
                        message: "Enter a tag name:",
                        placeholder: "tag name",
                        initial: ""
                    ) { onAddTag($0) }
                } label: {
                    Label("Add Tag…", systemImage: "tag")
                }
            }

            if let onSetFolder {
                Menu {
                    if !session.folderGroup.isEmpty {
                        Button {
                            onSetFolder("")
                        } label: {
                            Label("Remove from Folder", systemImage: "folder.badge.minus")
                        }
                        Divider()
                    }
                    ForEach(allFolders.filter { $0 != session.folderGroup }, id: \.self) { folder in
                        Button(folder) { onSetFolder(folder) }
                    }
                    Button {
                        promptText(
                            title: "New Folder",
                            message: "Enter folder name:",
                            placeholder: "folder name",
                            initial: ""
                        ) { onSetFolder($0) }
                    } label: {
                        Label("New Folder…", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("Move to Folder", systemImage: "folder")
                }
            }

            Divider()

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
