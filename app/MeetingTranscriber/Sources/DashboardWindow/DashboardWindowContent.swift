import os.log
import SwiftData
import SwiftUI

private let dashboardLogger = Logger(subsystem: AppPaths.logSubsystem, category: "DashboardWindow")

struct DashboardWindowContent: View {
    var pipelineQueue: PipelineQueue
    var settings: AppSettings
    var status: TranscriberStatus?
    var isWatching: Bool
    var onStartStop: () -> Void
    var whisperKitEngine: WhisperKitEngine
    var parakeetEngine: ParakeetEngine
    var qwen3Engine: (any TranscribingEngine)?
    var updateChecker: UpdateChecker?
    var recognitionStatsLog: RecognitionStatsLog
    var enrollmentDiarizerFactory: (() -> any DiarizationProvider)?
    var namingDialogActive: Bool
    var pipelineBusy: Bool
    var onSpeakerMutate: (() -> Void)?
    var onRunDetectionTest: (() -> String)? = nil

    @State private var selectedNav: NavItem = .library
    @State private var selectedSessionID: UUID?
    @State private var storageLabel: String = "—"
    @State private var elapsedLabel: String = "—"

    @Environment(\.modelContext) private var modelContext
    @Query private var allSessions: [RecordingSession]

    private var selectedSession: RecordingSession? {
        guard let id = selectedSessionID else { return nil }
        return allSessions.first(where: { $0.id == id })
    }

    private var selectedJob: PipelineJob? {
        guard let id = selectedSessionID, selectedSession == nil else { return nil }
        return pipelineQueue.jobs.first(where: { $0.id == id })
    }

    private var engineLabel: String {
        switch settings.transcriptionEngine {
        case .whisperKit: return "WhisperKit"
        case .parakeet:   return "Parakeet TDT"
        case .qwen3:      return "Qwen3-ASR"
        }
    }

    private func deleteSession(_ session: RecordingSession) {
        if selectedSessionID == session.id {
            selectedSessionID = nil
        }
        if !session.folderPath.isEmpty {
            let fullURL = settings.effectiveOutputDir.appendingPathComponent(session.folderPath)
            if FileManager.default.fileExists(atPath: fullURL.path) {
                NSWorkspace.shared.recycle([fullURL]) { _, error in
                    if let error {
                        dashboardLogger.error("Trash failed '\(fullURL.path)': \(error)")
                    }
                }
            }
        }
        modelContext.delete(session)
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                selectedNav: $selectedNav,
                engineLabel: engineLabel,
                storageLabel: storageLabel
            )

            Divider()

            contentPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            DetailPaneView(
                session: selectedSession,
                job: selectedJob,
                settings: settings,
                onRetry: { session in
                    pipelineQueue.retrySession(session, outputDir: settings.effectiveOutputDir)
                }
            )
            .frame(width: 360)
        }
        .frame(minWidth: 900, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            selectedNav = .settings
        }
        .onAppear {
            pipelineQueue.modelContext = modelContext
        }
        .task {
            let root = AppPaths.transcriberRoot
            let bytes = await Task.detached(priority: .utility) {
                Self.bytesUsed(at: root)
            }.value
            storageLabel = formattedBytes(bytes)
        }
    }

    // MARK: - Content pane

    @ViewBuilder
    private var contentPane: some View {
        switch selectedNav {
        case .library:
            LibraryView(
                pipelineQueue: pipelineQueue,
                selectedSessionID: $selectedSessionID,
                onDeleteSession: deleteSession
            )
        case .dashboard:
            DashboardView(
                status: status,
                isWatching: isWatching,
                settings: settings,
                elapsedLabel: elapsedLabel,
                onStartStop: onStartStop,
                onDeleteSession: deleteSession,
                selectedNav: $selectedNav,
                selectedSessionID: $selectedSessionID
            )
        case .stats:
            StatsView()
        case .settings:
            SettingsContentView(
                settings: settings,
                whisperKitEngine: whisperKitEngine,
                parakeetEngine: parakeetEngine,
                qwen3Engine: qwen3Engine,
                updateChecker: updateChecker,
                recognitionStatsLog: recognitionStatsLog,
                enrollmentDiarizerFactory: enrollmentDiarizerFactory,
                namingDialogActive: namingDialogActive,
                pipelineBusy: pipelineBusy,
                onSpeakerMutate: onSpeakerMutate,
                onRunDetectionTest: onRunDetectionTest
            )
        }
    }

    // MARK: - Placeholder

    private func placeholderPane(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Storage helpers

    nonisolated private static func bytesUsed(at root: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes) + " used"
    }
}
