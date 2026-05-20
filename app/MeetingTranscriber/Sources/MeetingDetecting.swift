import CoreGraphics
import Foundation

/// Represents a detected active meeting.
struct DetectedMeeting: Equatable {
    let pattern: AppMeetingPattern
    let windowTitle: String
    let ownerName: String
    let windowPID: pid_t
    let detectedAt: Date
    /// When non-nil, overrides WatchLoop's global `noMic` setting for this recording.
    let noMicOverride: Bool?

    init(
        pattern: AppMeetingPattern,
        windowTitle: String,
        ownerName: String,
        windowPID: pid_t,
        detectedAt: Date = Date(),
        noMicOverride: Bool? = nil,
    ) {
        self.pattern = pattern
        self.windowTitle = windowTitle
        self.ownerName = ownerName
        self.windowPID = windowPID
        self.detectedAt = detectedAt
        self.noMicOverride = noMicOverride
    }
}

/// Protocol for meeting detection strategies.
protocol MeetingDetecting {
    /// Single poll: check for active meetings. Returns a meeting after confirmation threshold.
    func checkOnce() -> DetectedMeeting?

    /// Check if a previously detected meeting is still active.
    func isMeetingActive(_ meeting: DetectedMeeting) -> Bool

    /// Reset confirmation counters and start cooldown for the given app.
    func reset(appName: String?)
}

extension MeetingDetecting {
    // swiftlint:disable:next unused_declaration
    func reset() {
        reset(appName: nil)
    }
}
