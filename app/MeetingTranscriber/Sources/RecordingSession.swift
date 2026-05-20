// Sources/RecordingSession.swift
import Foundation
import SwiftData

/// Persisted history entry for one completed (or failed) recording session.
@Model
final class RecordingSession {
    var id: UUID
    var createdAt: Date
    var title: String
    var appName: String
    /// Path relative to `AppPaths.transcriberRoot`, e.g. "recordings/2026-05-20_143022_zoom-weekly-sync"
    var folderPath: String
    var duration: TimeInterval
    var participantNames: [String]
    var hasTranscript: Bool
    var hasProtocol: Bool
    /// Basenames of audio files present in the folder.
    var audioFiles: [String]
    var engine: String
    var status: String
    var errorMessage: String?
    var warnings: [String]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String,
        appName: String,
        folderPath: String,
        duration: TimeInterval,
        participantNames: [String] = [],
        hasTranscript: Bool = false,
        hasProtocol: Bool = false,
        audioFiles: [String] = [],
        engine: String,
        status: String,
        errorMessage: String? = nil,
        warnings: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.appName = appName
        self.folderPath = folderPath
        self.duration = duration
        self.participantNames = participantNames
        self.hasTranscript = hasTranscript
        self.hasProtocol = hasProtocol
        self.audioFiles = audioFiles
        self.engine = engine
        self.status = status
        self.errorMessage = errorMessage
        self.warnings = warnings
    }
}

/// Status string constants for `RecordingSession.status`.
enum SessionStatus {
    static let waiting = "waiting"
    static let transcribing = "transcribing"
    static let diarizing = "diarizing"
    static let generatingProtocol = "generatingProtocol"
    static let done = "done"
    static let error = "error"
    static let saved = "saved" // record-only
}
