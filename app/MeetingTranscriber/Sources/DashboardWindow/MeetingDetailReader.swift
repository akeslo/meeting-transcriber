import SwiftUI
import AVFoundation

// MARK: - Tab enum

enum DetailTab: String, CaseIterable, Identifiable {
    case transcript   = "Transcript"
    case protocol_    = "Summary"
    case actionItems  = "Actions"
    case split        = "Split"

    var id: String { rawValue }
}

// MARK: - MeetingDetailReader

struct MeetingDetailReader: View {
    let session: RecordingSession
    let settings: AppSettings

    @Binding var activeTab: DetailTab
    @State private var segments: [TranscriptSegment] = []
    @State private var protocolContent: String = ""
    @State private var selectedSegmentID: UUID?
    @State private var checkedActionItems: Set<Int> = []

    @State private var player: AVAudioPlayer?
    @State private var isPlaying: Bool = false
    @State private var playbackPosition: TimeInterval = 0
    @State private var duration: TimeInterval = 0

    private let playbackTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private let spaceIndigo = Color(red: 0.082, green: 0.114, blue: 0.208)
    private let peachGlow   = Color(red: 0.969, green: 0.773, blue: 0.624)

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            Divider()

            Group {
                switch activeTab {
                case .transcript:
                    transcriptTab
                case .protocol_:
                    protocolTab
                case .actionItems:
                    actionItemsTab
                case .split:
                    splitTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            playbackBar
        }
        .task {
            await loadContent()
            loadAudio()
        }
        .onReceive(playbackTimer) { _ in
            guard isPlaying, let player else { return }
            playbackPosition = player.currentTime
            if !player.isPlaying {
                isPlaying = false
            }
            autoScrollToCurrentSegment()
        }
        .onDisappear {
            player?.stop()
            player = nil
            isPlaying = false
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.rawValue) { tab in
                tabButton(tab)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func tabButton(_ tab: DetailTab) -> some View {
        let isActive = tab == activeTab
        Button {
            activeTab = tab
        } label: {
            VStack(spacing: 6) {
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary)
                    .padding(.horizontal, 4)

                Rectangle()
                    .fill(isActive ? peachGlow : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 24)
    }

    // MARK: - Transcript tab

    private var transcriptTab: some View {
        ScrollViewReader { proxy in
            List(segments) { segment in
                TranscriptSegmentView(segment: segment, isSelected: segment.id == selectedSegmentID)
                    .id(segment.id)
                    .listRowBackground(segment.id == selectedSegmentID
                        ? Color(red: 0.882, green: 0.898, blue: 0.933)
                        : Color.clear)
                    .onTapGesture {
                        selectedSegmentID = segment.id
                        if let player {
                            player.currentTime = segment.timestamp
                            playbackPosition = segment.timestamp
                        }
                    }
            }
            .listStyle(.plain)
            .onChange(of: selectedSegmentID) { _, newID in
                if let id = newID {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    // MARK: - Protocol tab

    private var protocolTab: some View {
        ScrollView {
            if protocolContent.isEmpty {
                Text("No summary generated for this session.")
                    .foregroundStyle(.secondary)
                    .padding(20)
            } else {
                MarkdownView(content: protocolContent)
                    .padding(20)
            }
        }
    }

    // MARK: - Action items tab

    private var actionItemsTab: some View {
        let items = Self.extractActionItems(from: protocolContent)
        return ScrollView {
            if items.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 40)
                    Image(systemName: "checkmark.square")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text(protocolContent.isEmpty ? "No summary generated yet." : "No action items found in this summary.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("\(items.count) action item\(items.count == 1 ? "" : "s")")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            let text = items.enumerated().map { i, item in
                                let prefix = checkedActionItems.contains(i) ? "- [x] " : "- [ ] "
                                return prefix + item
                            }.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        } label: {
                            Label("Copy All", systemImage: "doc.on.doc")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                    .padding(.bottom, 10)

                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        let isChecked = checkedActionItems.contains(idx)
                        Button {
                            if isChecked {
                                checkedActionItems.remove(idx)
                            } else {
                                checkedActionItems.insert(idx)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 15))
                                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                                    .padding(.top, 1)
                                Text(item)
                                    .font(.system(size: 13))
                                    .foregroundStyle(isChecked ? Color.secondary : Color.primary)
                                    .strikethrough(isChecked)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Copy to clipboard")
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .padding(20)
            }
        }
    }

    static func extractActionItems(from text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var items: [String] = []
        let taskHeadings: Set<String> = ["## Tasks", "## Aufgaben", "## Tâches", "## Tareas", "## Compiti"]
        var inTasksSection = false
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Track section entry/exit via heading depth
            if trimmed.hasPrefix("## ") {
                inTasksSection = taskHeadings.contains(trimmed)
            } else if trimmed.hasPrefix("# ") {
                inTasksSection = false
            }
            if trimmed.hasPrefix("- [ ]") {
                items.append(String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("* [ ]") {
                items.append(String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            } else if inTasksSection,
                      trimmed.hasPrefix("|"),
                      trimmed.range(of: "^[|]\\s*([^|]+)\\s*[|]", options: .regularExpression) != nil {
                let cell = trimmed.components(separatedBy: "|").dropFirst().first ?? ""
                let clean = cell.trimmingCharacters(in: .whitespaces)
                let headerPrefixes = ["Task", "Aufgabe", "Tâche", "Tarea", "Compito", "---", "Beschreibung"]
                if !clean.isEmpty, !headerPrefixes.contains(where: { clean.hasPrefix($0) }) {
                    items.append(clean)
                }
            }
        }
        return items
    }

    // MARK: - Split tab

    private var splitTab: some View {
        HStack(spacing: 0) {
            List(segments) { segment in
                TranscriptSegmentView(segment: segment, isSelected: segment.id == selectedSegmentID)
                    .id(segment.id)
                    .listRowBackground(segment.id == selectedSegmentID
                        ? Color(red: 0.882, green: 0.898, blue: 0.933)
                        : Color.clear)
                    .onTapGesture { selectedSegmentID = segment.id }
            }
            .listStyle(.plain)
            .frame(maxWidth: .infinity)

            Divider()

            ScrollView {
                MarkdownView(content: protocolContent)
                    .padding(20)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Playback bar

    private var playbackBar: some View {
        Group {
            if let player {
                HStack(spacing: 12) {
                    Button {
                        togglePlayback()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .imageScale(.large)
                            .foregroundStyle(spaceIndigo)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(" ", modifiers: [])

                    Slider(value: $playbackPosition, in: 0...max(duration, 1)) { editing in
                        if !editing {
                            player.currentTime = playbackPosition
                        }
                    }

                    Text(timeLabel(playbackPosition))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 42, alignment: .trailing)

                    Text("/")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)

                    Text(timeLabel(duration))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 42, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            } else {
                Text("No audio available")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private func loadContent() async {
        let folder = settings.effectiveOutputDir.appendingPathComponent(session.folderPath)
        let transcriptURL = folder.appendingPathComponent(RecordingFileSuffix.transcript)
        let protocolURL   = folder.appendingPathComponent(RecordingFileSuffix.protocol_)

        let (rawTranscript, rawProtocol) = await Task.detached(priority: .userInitiated) {
            let t = try? String(contentsOf: transcriptURL, encoding: .utf8)
            let p = try? String(contentsOf: protocolURL, encoding: .utf8)
            return (t, p)
        }.value

        if let rawTranscript {
            segments = TranscriptParser.parse(markdown: rawTranscript)
        }
        protocolContent = rawProtocol ?? ""
    }

    private func loadAudio() {
        let base = settings.effectiveOutputDir.appendingPathComponent(session.folderPath)
        for filename in [RecordingFileSuffix.mix, RecordingFileSuffix.app, RecordingFileSuffix.mic] {
            guard session.audioFiles.contains(filename) else { continue }
            guard let p = try? AVAudioPlayer(contentsOf: base.appendingPathComponent(filename)) else { continue }
            p.prepareToPlay()
            player = p
            duration = p.duration
            return
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func autoScrollToCurrentSegment() {
        guard isPlaying, !segments.isEmpty else { return }
        let match = segments.last(where: { $0.timestamp <= playbackPosition })
        if let match, match.id != selectedSegmentID {
            selectedSegmentID = match.id
        }
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - TranscriptSegmentView

struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    let isSelected: Bool

    private let spaceIndigo = Color(red: 0.082, green: 0.114, blue: 0.208)

    private var timestampLabel: String {
        let s = Int(segment.timestamp)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(segment.speaker)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                Text(timestampLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
            Text(segment.body)
                .font(.body)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}

// MARK: - MeetingDetailReaderSheet

struct MeetingDetailReaderSheet: View {
    let session: RecordingSession
    let settings: AppSettings
    let initialTab: DetailTab

    @State private var activeTab: DetailTab
    @Environment(\.dismiss) private var dismiss

    init(session: RecordingSession, settings: AppSettings, initialTab: DetailTab) {
        self.session = session
        self.settings = settings
        self.initialTab = initialTab
        _activeTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(session.title.isEmpty ? "Untitled Recording" : session.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            MeetingDetailReader(session: session, settings: settings, activeTab: $activeTab)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
