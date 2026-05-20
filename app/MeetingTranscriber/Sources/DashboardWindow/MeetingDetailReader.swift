import SwiftUI
import AVFoundation

// MARK: - Tab enum

enum DetailTab: String, CaseIterable {
    case transcript = "Transcript"
    case protocol_  = "Protocol"
    case split      = "Split"
}

// MARK: - MeetingDetailReader

struct MeetingDetailReader: View {
    let session: RecordingSession

    @State private var activeTab: DetailTab = .transcript
    @State private var segments: [TranscriptSegment] = []
    @State private var protocolContent: String = ""
    @State private var selectedSegmentID: UUID?

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
                case .split:
                    splitTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            playbackBar
        }
        .task {
            loadContent()
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
                    .foregroundStyle(isActive ? spaceIndigo : Color.secondary)
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
            Text(protocolAttributedString)
                .textSelection(.enabled)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var protocolAttributedString: AttributedString {
        guard !protocolContent.isEmpty else {
            return AttributedString("No protocol generated for this session.")
        }
        guard var attributed = try? AttributedString(
            markdown: protocolContent,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return AttributedString(protocolContent)
        }
        // Tint heading/strong runs with Space Indigo
        let headingColor = Color(red: 0.082, green: 0.114, blue: 0.208)
        for run in attributed.runs {
            if let intent = run.inlinePresentationIntent,
               intent.contains(.stronglyEmphasized) {
                attributed[run.range].foregroundColor = headingColor
            }
        }
        return attributed
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
                Text(protocolAttributedString)
                    .textSelection(.enabled)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Playback bar

    private var playbackBar: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .imageScale(.large)
                    .foregroundStyle(spaceIndigo)
            }
            .buttonStyle(.plain)
            .disabled(player == nil)
            .keyboardShortcut(" ", modifiers: [])

            Slider(value: $playbackPosition, in: 0...max(duration, 1)) { editing in
                if !editing, let player {
                    player.currentTime = playbackPosition
                }
            }
            .disabled(player == nil)

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
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private func loadContent() {
        let folder = URL(fileURLWithPath: session.folderPath)
        let transcriptURL = folder.appendingPathComponent(RecordingFileSuffix.transcript)
        if let raw = try? String(contentsOf: transcriptURL, encoding: .utf8) {
            segments = TranscriptParser.parse(markdown: raw)
        }
        let protocolURL = folder.appendingPathComponent(RecordingFileSuffix.protocol_)
        protocolContent = (try? String(contentsOf: protocolURL, encoding: .utf8)) ?? ""
    }

    private func loadAudio() {
        let mixURL = URL(fileURLWithPath: session.folderPath)
            .appendingPathComponent(RecordingFileSuffix.mix)
        guard let p = try? AVAudioPlayer(contentsOf: mixURL) else { return }
        p.prepareToPlay()
        player = p
        duration = p.duration
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
                    .foregroundStyle(spaceIndigo)
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
