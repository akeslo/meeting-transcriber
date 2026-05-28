import AVFoundation
import Combine
import CoreGraphics
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let autoWatchStart = Notification.Name("autoWatchStart")
    static let showSpeakerNaming = Notification.Name("showSpeakerNaming")
    static let showSettings = Notification.Name("showSettings")
    static let closeSettings = Notification.Name("closeSettings")
    static let showTitlePrompt = Notification.Name("showTitlePrompt")
}

/// Renders the menu-bar icon and ticks the animation frame in its own
/// view body. Keeping the timer + frame @State scoped here means the
/// surrounding `MeetingTranscriberApp` scene body never re-evaluates on
/// each tick — only this view does. Without this isolation, animating
/// badges (recording, transcribing, …) would cascade re-renders through
/// every open Window.
private struct AnimatedMenuBarIcon: View {
    let badge: BadgeKind
    let permissionOverlay: Bool
    let recordOnlyOverlay: Bool
    let micSilentOverlay: Bool
    let appSilentOverlay: Bool

    @State private var animationFrame = 0
    private let iconTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        Image(nsImage: MenuBarIcon.image(
            badge: badge,
            animationFrame: animationFrame,
            permissionOverlay: permissionOverlay,
            recordOnlyOverlay: recordOnlyOverlay,
            micSilentOverlay: micSilentOverlay,
            appSilentOverlay: appSilentOverlay,
        ))
        .onReceive(iconTimer) { _ in
            let next = MenuBarIcon.nextFrame(animationFrame, badge: badge)
            if next != animationFrame {
                animationFrame = next
            }
        }
    }
}

@main
struct MeetingTranscriberApp: App {
    @State private var appState = AppState(notifier: NotificationManager.shared)
    private let modelContainer: ModelContainer = {
        // Migrate library.sqlite from old Documents location before opening the store.
        AppPaths.migrateIfNeeded()
        let config = ModelConfiguration(url: AppPaths.libraryStore)
        do {
            return try ModelContainer(for: RecordingSession.self, configurations: config)
        } catch {
            // Schema changed — delete old store and recreate (sessions will be re-imported from disk).
            let storeURL = AppPaths.libraryStore
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: RecordingSession.self, configurations: config)
        }
    }()
    @Environment(\.openWindow)
    private var openWindow

    init() {
        NotificationManager.shared.setUp()
        DualSourceRecorder.cleanupTempFiles()
        let suppressAutoWatch = ProcessInfo.processInfo.environment["MEETINGTRANSCRIBER_DEBUG_SUPPRESS_AUTOWATCH"] == "1"
        // Auto-watch: schedule on main run loop after app finishes launching.
        // E2E drivers that force channel-health flags via env var also set
        // `MEETINGTRANSCRIBER_DEBUG_SUPPRESS_AUTOWATCH=1` so a +3 s
        // `toggleWatching` doesn't reset the forced flag through the
        // normal `stopChannelHealthMonitoring()` path.
        if (CommandLine.arguments.contains("--auto-watch")
            || UserDefaults.standard.bool(forKey: "autoWatch"))
            && !suppressAutoWatch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                NotificationCenter.default.post(name: .autoWatchStart, object: nil)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                status: appState.currentStatus,
                isWatching: appState.isWatching,
                isModelReady: appState.isModelReady,
                updateChecker: appState.updateChecker,
                onStartStop: appState.toggleWatching,
                onRecordApp: { bringWindowToFront(id: "record-app") },
                onStopManualRecording: appState.watchLoop?.isManualRecording == true ? {
                    appState.stopManualRecording()
                } : nil,
                onOpenOutputFolder: openOutputFolder,
                onOpenDashboard: {
                    openWindow(id: "dashboard")
                    bringWindowToFront(id: "dashboard")
                },
                onOpenSettings: {
                    openWindow(id: "dashboard")
                    bringWindowToFront(id: "dashboard")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .showSettings, object: nil)
                    }
                },
                onNameSpeakers: appState.pipelineQueue.pendingSpeakerNamingJobs.isEmpty ? nil : {
                    bringWindowToFront(id: "speaker-naming")
                },
                onProcessFiles: processAudioFiles,
                onQuit: quit,
                micDeviceName: appState.settings.micName,
                appSourceName: appState.currentStatus?.meeting?.app ?? "",
                levelSource: { (mic: appState.micLevelDBFS, app: appState.appLevelDBFS) },
            )
        } label: { // swiftlint:disable:this closure_body_length
            Label {
                Text(appState.currentStateLabel)
            } icon: {
                AnimatedMenuBarIcon(
                    badge: appState.currentBadge,
                    permissionOverlay: appState.permissionHealth?.isHealthy == false,
                    recordOnlyOverlay: appState.settings.recordOnly,
                    // `recordingSilentActive` paints both halves; OR'd in here so
                    // MenuBarIcon only needs the two per-channel overlay inputs.
                    micSilentOverlay: appState.micSilentActive || appState.recordingSilentActive,
                    appSilentOverlay: appState.appSilentActive || appState.recordingSilentActive,
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .autoWatchStart)) { _ in
                if !appState.isWatching {
                    appState.toggleWatching()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSpeakerNaming)) { _ in
                bringWindowToFront(id: "speaker-naming")
            }
            .onReceive(NotificationCenter.default.publisher(for: .showTitlePrompt)) { _ in
                openWindow(id: "title-prompt")
                bringWindowToFront(id: "title-prompt")
            }
            .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
                openWindow(id: "dashboard")
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeSettings)) { _ in
                closeWindow(id: "dashboard")
            }
            .task {
                appState.modelContext = modelContainer.mainContext
            }
            .task {
                guard appState.settings.preloadModelOnStartup else { return }
                appState.syncLanguageSettings()
                await appState.activeTranscriptionEngine.loadModel()
            }
            .task {
                appState.updateChecker.startPeriodicChecks(settings: appState.settings)
            }
            .task {
                await appState.checkPermissions()
            }
            .task {
                let screenOK = CGPreflightScreenCaptureAccess()
                let micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                if !screenOK || !micOK {
                    openWindow(id: "onboarding")
                    bringWindowToFront(id: "onboarding")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                // Re-check permissions when the user returns to the app (e.g. from System
                // Settings after toggling a permission). Debounced so rapid Cmd-Tab cycles
                // don't repeatedly churn the mic HAL via the 500 ms probe.
                Task { @MainActor in
                    await appState.checkPermissions(minimumInterval: 3)
                }
            }
        }

        Window("Set Up Permissions", id: "onboarding") {
            PermissionsOnboardingView {
                closeWindow(id: "onboarding")
            }
        }
        .windowResizability(.contentSize)

        Window("Name Speakers", id: "speaker-naming") {
            speakerNamingContent
                .onAppear {
                    // Close restored window if no naming data available (macOS state restoration)
                    if appState.pipelineQueue.pendingSpeakerNamingJobs.isEmpty {
                        closeWindow(id: "speaker-naming")
                    }
                }
                // Auto-close when the pending list drains. Covers RPC-driven
                // skip (`POST /action/skipNaming`), where the data layer
                // transitions but the UI callback never fires.
                .onChange(of: appState.pipelineQueue.pendingSpeakerNamingJobs.isEmpty) { _, isEmpty in
                    if isEmpty {
                        closeWindow(id: "speaker-naming")
                    }
                }
        }
        .windowResizability(.contentSize)

        Window("Record App", id: "record-app") {
            AppPickerView(
                onStartRecording: { pid, appName, title in
                    appState.startManualRecording(pid: pid, appName: appName, title: title)
                    closeWindow(id: "record-app")
                },
                onCancel: { closeWindow(id: "record-app") },
            )
        }
        .windowResizability(.contentSize)

        Window("Name this Recording", id: "title-prompt") {
            TitlePromptView(
                watchLoop: appState.watchLoop,
                namedPrompts: appState.settings.namedPrompts,
                defaultPromptID: appState.settings.defaultPromptID
            )
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 130)

        Window("Dashboard", id: "dashboard") {
            DashboardWindowContent(
                pipelineQueue: appState.pipelineQueue,
                settings: appState.settings,
                status: appState.currentStatus,
                isWatching: appState.isWatching,
                onStartStop: { appState.toggleWatching() },
                whisperKitEngine: appState.whisperKit,
                parakeetEngine: appState.parakeetEngine,
                qwen3Engine: {
                    if #available(macOS 15, *) {
                        return appState.qwen3Engine
                    }
                    return nil
                }(),
                updateChecker: appState.updateChecker,
                recognitionStatsLog: appState.pipelineQueue.recognitionStatsLog ?? RecognitionStatsLog(),
                enrollmentDiarizerFactory: { FluidDiarizer(mode: appState.settings.diarizerMode) },
                namingDialogActive: appState.pipelineQueue.pendingSpeakerNaming != nil,
                pipelineBusy: appState.pipelineQueue.isProcessing,
                onSpeakerMutate: appState.pipelineQueue.refreshKnownSpeakerNames,
                onRunDetectionTest: appState.runDetectionTest,
                onRerunSession: { session, promptText in
                    appState.rerunProtocolOnly(session: session, promptText: promptText)
                }
            )
            .environment(\.appState, appState)
            .modelContainer(modelContainer)
            .onAppear { NSApp.setActivationPolicy(.regular) }
            .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 1200, height: 700)
        .defaultPosition(.center)
    }

    // MARK: - Speaker Naming Window

    @ViewBuilder private var speakerNamingContent: some View {
        if let data = appState.pipelineQueue.speakerNamingData(
            forJobID: appState.selectedNamingJobID,
        ) {
            VStack(spacing: 0) {
                speakerNamingPicker
                speakerNamingForm(data: data)
            }
        } else {
            Text("No speaker data available.")
                .padding()
        }
    }

    @ViewBuilder private var speakerNamingPicker: some View {
        if appState.pipelineQueue.pendingSpeakerNamingJobs.count > 1 {
            Picker("Meeting", selection: Binding(
                get: {
                    appState.selectedNamingJobID
                        ?? appState.pipelineQueue.pendingSpeakerNamingJobs.first?.id
                },
                set: { appState.selectedNamingJobID = $0 },
            )) {
                ForEach(appState.pipelineQueue.pendingSpeakerNamingJobs) { job in
                    Text(job.meetingTitle).tag(Optional(job.id))
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private func speakerNamingForm(
        data: PipelineQueue.SpeakerNamingData,
    ) -> some View {
        SpeakerNamingView(
            data: data,
            knownSpeakerNames: appState.pipelineQueue.knownSpeakerNames,
        ) { result in
            appState.pipelineQueue.completeSpeakerNaming(jobID: data.jobID, result: result)
            if appState.pipelineQueue.pendingSpeakerNamingJobs.isEmpty {
                closeWindow(id: "speaker-naming")
            } else {
                appState.selectedNamingJobID =
                    appState.pipelineQueue.pendingSpeakerNamingJobs.first?.id
            }
        }
    }

    // MARK: - UI Actions

    private func processAudioFiles() {
        let panel = NSOpenPanel()
        panel.title = "Select Audio or Video Files"
        var types: [UTType] = [
            .wav, .mp3, .aiff, .mpeg4Audio,
            .mpeg4Movie, .quickTimeMovie,
        ] + [UTType("public.flac")].compactMap(\.self)
        if FFmpegHelper.isAvailable {
            types += FFmpegHelper.ffmpegOnlyTypes
        }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        let pairingDelegate = PairedImportPanelDelegate()
        panel.delegate = pairingDelegate
        panel.accessoryView = pairingDelegate.accessoryView
        panel.isAccessoryViewDisclosed = true

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        appState.enqueueFiles(panel.urls)
    }

    private func bringWindowToFront(id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
        // Ensure the window is brought to front even if already open
        DispatchQueue.main.async {
            for window in NSApp.windows where window.identifier?.rawValue == id {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func closeWindow(id: String) {
        for window in NSApp.windows where window.identifier?.rawValue == id {
            window.close()
        }
    }

    private func openOutputFolder() {
        let dir = appState.settings.effectiveOutputDir
        let accessing = dir.startAccessingSecurityScopedResource()
        defer { if accessing { dir.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    private func quit() {
        appState.watchLoop?.stop()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Pure Helpers (testable without @main)

    /// Whether auto-watch should be enabled based on CLI flags or user settings.
    static func shouldAutoWatch(
        commandLineArgs: [String] = CommandLine.arguments,
        autoWatchSetting: Bool = UserDefaults.standard.bool(forKey: "autoWatch"),
    ) -> Bool {
        commandLineArgs.contains("--auto-watch") || autoWatchSetting
    }

    /// Returns the protocol path from the last completed job, if any.
    static func lastCompletedProtocolPath(completedJobs: [PipelineJob]) -> URL? {
        completedJobs.last?.protocolPath
    }
}
