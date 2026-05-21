import Foundation
import os.log

/// Centralized path constants and logger subsystem for the app.
enum AppPaths {
    /// Logger subsystem for all os.log loggers.
    static let logSubsystem = "com.meetingtranscriber"

    /// App data directory: `~/Library/Application Support/MeetingTranscriber/`
    /// In sandbox, this automatically resolves to the container path.
    /// Falls back to `~/.MeetingTranscriber/` if Application Support is unavailable.
    static let dataDir: URL = {
        if let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport.appendingPathComponent("MeetingTranscriber")
        }
        Logger(subsystem: logSubsystem, category: "AppPaths")
            .error("Application Support directory unavailable — falling back to home directory")
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".MeetingTranscriber")
    }()

    /// IPC directory: under `dataDir` for sandbox compatibility.
    static let ipcDir = dataDir.appendingPathComponent("ipc")

    /// Recordings directory.
    static let recordingsDir = dataDir.appendingPathComponent("recordings")

    /// Protocols output directory (legacy, inside Application Support).
    static let protocolsDir = dataDir.appendingPathComponent("protocols")

    /// Default protocols output in Downloads: `~/Downloads/MeetingTranscriber/`
    /// In sandbox, `FileManager.urls(for: .downloadsDirectory)` resolves to the container-granted path.
    static let downloadsProtocolsDir: URL = {
        guard let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
        else {
            return protocolsDir
        }
        return downloads.appendingPathComponent("MeetingTranscriber")
    }()

    /// New default output root: `~/Documents/Transcriber/`
    static let transcriberRoot: URL = {
        guard let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first
        else { return downloadsProtocolsDir }
        return docs.appendingPathComponent("Transcriber")
    }()

    /// Per-session recordings directory under the new root.
    static let defaultRecordingsDir: URL = transcriberRoot.appendingPathComponent("recordings")

    /// SwiftData library store location (internal app data — Application Support, not Documents).
    static let libraryStore: URL = dataDir.appendingPathComponent("library.sqlite")

    /// Speaker voice profiles DB.
    static let speakersDB = dataDir.appendingPathComponent("speakers.json")

    /// Custom protocol prompt file.
    static let customPromptFile = dataDir.appendingPathComponent("protocol_prompt.md")

    /// Legacy IPC directory (`~/.meeting-transcriber/`) used before sandbox migration.
    private static let legacyIpcDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".meeting-transcriber")

    private static let logger = Logger(subsystem: logSubsystem, category: "AppPaths")

    /// Migrate IPC files from `~/.meeting-transcriber/` to `dataDir/ipc/`.
    /// Also migrates library.sqlite from ~/Documents/Transcriber/ to dataDir if needed.
    /// Safe to call multiple times — copyItem fails gracefully if destination exists.
    static func migrateIfNeeded() {
        let fm = FileManager.default

        // Migrate library.sqlite from old Documents location to Application Support.
        let oldLibraryStore = transcriberRoot.appendingPathComponent("library.sqlite")
        if fm.fileExists(atPath: oldLibraryStore.path),
           !fm.fileExists(atPath: libraryStore.path) {
            try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
            do {
                try fm.moveItem(at: oldLibraryStore, to: libraryStore)
                logger.info("Migrated library.sqlite from Documents to Application Support")
            } catch {
                logger.error("Failed to migrate library.sqlite: \(error.localizedDescription)")
            }
        }

        guard fm.fileExists(atPath: legacyIpcDir.path) else { return }

        let filesToMigrate = [
            "processed_recordings.json",
            "pipeline_queue.json",
            "pipeline_log.jsonl",
        ]

        try? fm.createDirectory(at: ipcDir, withIntermediateDirectories: true)

        for name in filesToMigrate {
            let src = legacyIpcDir.appendingPathComponent(name)
            let dst = ipcDir.appendingPathComponent(name)
            do {
                try fm.copyItem(at: src, to: dst)
                logger.info("Migrated \(name) from legacy IPC directory")
            } catch CocoaError.fileWriteFileExists {
                // Already migrated — expected on subsequent launches
            } catch CocoaError.fileReadNoSuchFile {
                // Source doesn't exist — skip
            } catch {
                logger.error("Failed to migrate \(name): \(error.localizedDescription)")
            }
        }
    }
}
