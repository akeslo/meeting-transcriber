import AppKit
import SwiftUI

struct DetailPaneView: View {
    let session: RecordingSession?
    let job: PipelineJob?
    let settings: AppSettings
    var onRetry: ((RecordingSession) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var activeDetailTab: DetailTab = .protocol_
    @State private var titleDraft: String = ""
    @State private var folderDraft: String = ""
    @State private var tagDraft: String = ""
    @State private var showFileManager = false
    @State private var showDatePicker = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        if let session {
            sessionDetail(session)
                .task(id: session.id) {
                    titleDraft = session.title
                    folderDraft = session.folderGroup
                    activeDetailTab = .protocol_
                }
        } else if let job {
            jobDetail(job)
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
        VStack(spacing: 0) {
            // ── Metadata header ──────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {

                // Editable title
                TextField("Title", text: $titleDraft)
                    .font(.system(size: 15, weight: .semibold))
                    .textFieldStyle(.plain)
                    .onSubmit { commitTitle(session) }

                // Metadata chips
                FlowLayout(spacing: 5) {
                    // Tappable date → DatePicker popover
                    Button {
                        showDatePicker.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar").font(.system(size: 10))
                            Text(Self.dateFormatter.string(from: session.createdAt))
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showDatePicker) {
                        VStack(spacing: 0) {
                            DatePicker(
                                "Recording Date",
                                selection: Binding(
                                    get: { session.createdAt },
                                    set: { newDate in
                                        session.createdAt = newDate
                                        try? modelContext.save()
                                    }
                                ),
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.graphical)
                            .padding()
                        }
                        .frame(width: 300)
                    }

                    metadataChip(icon: "clock", label: durationString(session.duration))
                    if !session.appName.isEmpty {
                        metadataChip(icon: "desktopcomputer", label: session.appName)
                    }
                    StatusChipView(status: session.displayStatus)
                }

                // Folder assignment
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("No folder", text: $folderDraft)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        .foregroundStyle(folderDraft.isEmpty ? .secondary : .primary)
                        .onSubmit { commitFolder(session) }
                }

                // Tags
                tagsSection(session)

                Divider()

                // Action buttons
                HStack(spacing: 8) {
                    Spacer()

                    if session.status == SessionStatus.error, let onRetry {
                        Button {
                            onRetry(session)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .help("Retry transcription")
                    }

                    Button {
                        showFileManager.toggle()
                    } label: {
                        Image(systemName: showFileManager ? "doc.badge.minus" : "doc.badge.ellipsis")
                    }
                    .buttonStyle(.bordered)
                    .help("Manage files")

                    Button {
                        revealInFinder(for: session)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .help("Show in Finder")
                }

                // File manager (delete individual files)
                if showFileManager {
                    fileManagerSection(session)
                }

                if !session.warnings.isEmpty {
                    ForEach(session.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }

                if let error = session.errorMessage, !error.isEmpty {
                    Label(error, systemImage: "xmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            MeetingDetailReader(session: session, settings: settings, activeTab: $activeDetailTab)
                .id(session.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Tags section

    @ViewBuilder
    private func tagsSection(_ session: RecordingSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !session.tags.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(session.tags, id: \.self) { tag in
                        tagChip(tag) {
                            removeTag(tag, from: session)
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Add tag…", text: $tagDraft)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .onSubmit { addTag(to: session) }
            }
        }
    }

    @ViewBuilder
    private func tagChip(_ tag: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Text(tag)
                .font(.system(size: 11))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - File manager section

    @ViewBuilder
    private func fileManagerSection(_ session: RecordingSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Files")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            let folder = settings.effectiveOutputDir.appendingPathComponent(session.folderPath)

            // Audio files
            ForEach(session.audioFiles, id: \.self) { filename in
                fileRow(
                    name: filename,
                    systemImage: "waveform",
                    folder: folder
                ) {
                    deleteFile(filename: filename, folder: folder, session: session, type: .audio)
                }
            }

            // Transcript
            if session.hasTranscript {
                fileRow(
                    name: RecordingFileSuffix.transcript,
                    systemImage: "doc.text",
                    folder: folder
                ) {
                    deleteFile(
                        filename: RecordingFileSuffix.transcript,
                        folder: folder,
                        session: session,
                        type: .transcript
                    )
                }
            }

            // Summary (protocol)
            if session.hasProtocol {
                fileRow(
                    name: RecordingFileSuffix.protocol_,
                    systemImage: "doc.richtext",
                    folder: folder
                ) {
                    deleteFile(
                        filename: RecordingFileSuffix.protocol_,
                        folder: folder,
                        session: session,
                        type: .summary
                    )
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func fileRow(
        name: String,
        systemImage: String,
        folder: URL,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(name)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func durationString(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func revealInFinder(for session: RecordingSession) {
        let folder = settings.effectiveOutputDir.appendingPathComponent(session.folderPath)
        NSWorkspace.shared.open(folder)
    }

    // MARK: - Commit actions

    private func commitTitle(_ session: RecordingSession) {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != session.title else { return }
        session.title = trimmed
        try? modelContext.save()
        let dir = settings.effectiveOutputDir.appendingPathComponent(session.folderPath)
        try? SessionMeta.updateFields(in: dir, title: trimmed)
    }

    private func commitFolder(_ session: RecordingSession) {
        let trimmed = folderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != session.folderGroup else { return }
        session.folderGroup = trimmed
        try? modelContext.save()
        let dir = settings.effectiveOutputDir.appendingPathComponent(session.folderPath)
        try? SessionMeta.updateFields(in: dir, folderGroup: trimmed)
    }

    private func addTag(to session: RecordingSession) {
        let trimmed = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !session.tags.contains(trimmed) else {
            tagDraft = ""
            return
        }
        session.tags.append(trimmed)
        tagDraft = ""
        try? modelContext.save()
        let dir = settings.effectiveOutputDir.appendingPathComponent(session.folderPath)
        try? SessionMeta.updateFields(in: dir, tags: session.tags)
    }

    private func removeTag(_ tag: String, from session: RecordingSession) {
        session.tags.removeAll { $0 == tag }
        try? modelContext.save()
        let dir = settings.effectiveOutputDir.appendingPathComponent(session.folderPath)
        try? SessionMeta.updateFields(in: dir, tags: session.tags)
    }

    private enum FileType { case audio, transcript, summary }

    private func deleteFile(filename: String, folder: URL, session: RecordingSession, type: FileType) {
        let url = folder.appendingPathComponent(filename)
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        switch type {
        case .audio:
            session.audioFiles.removeAll { $0 == filename }
            try? SessionMeta.updateFields(in: folder, removeFileKey: audioMetaKey(for: filename))
        case .transcript:
            session.hasTranscript = false
            try? SessionMeta.updateFields(in: folder, removeFileKey: "transcript")
        case .summary:
            session.hasProtocol = false
            try? SessionMeta.updateFields(in: folder, removeFileKey: "protocol")
        }
        try? modelContext.save()
    }

    private func audioMetaKey(for filename: String) -> String {
        if filename == RecordingFileSuffix.app { return "app" }
        if filename == RecordingFileSuffix.mic { return "mic" }
        return "mix"
    }

    // MARK: - Job detail

    private func jobDetail(_ job: PipelineJob) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(job.meetingTitle.isEmpty ? "Processing…" : job.meetingTitle)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(3)
            StatusChipView(status: job.state.rawValue)
            if job.progress > 0 {
                ProgressView(value: job.progress)
            }
            Text("This recording is being processed. Details will appear when complete.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
