import AppKit
import SwiftUI

/// Shows an NSAlert with a text field, calls `completion` with trimmed non-empty result.
@MainActor
func promptText(
    title: String,
    message: String,
    placeholder: String,
    initial: String,
    completion: @escaping (String) -> Void
) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    field.stringValue = initial
    field.placeholderString = placeholder
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    if alert.runModal() == .alertFirstButtonReturn {
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        completion(trimmed)
    }
}

struct SessionRowView: View {
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
        .contextMenu {
            // Rename
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

            // Add Tag
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

            // Folder submenu
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
    var onCancel: (() -> Void)? = nil

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

    @ViewBuilder private var baseRow: some View {
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

    var body: some View {
        if let onCancel {
            baseRow.contextMenu {
                Button(role: .destructive, action: onCancel) {
                    Label("Cancel", systemImage: "xmark.circle")
                }
            }
        } else {
            baseRow
        }
    }
}
