import Foundation

/// Chains multiple MeetingDetecting instances, polling all of them every cycle
/// so each detector's internal consecutive-hit counters stay up to date.
/// Returns the first match found (priority order matches the array order).
final class CompositeDetector: MeetingDetecting {
    private let detectors: [any MeetingDetecting]

    init(_ detectors: [any MeetingDetecting]) {
        self.detectors = detectors
    }

    func checkOnce() -> DetectedMeeting? {
        var first: DetectedMeeting?
        for d in detectors {
            if let m = d.checkOnce(), first == nil {
                first = m
            }
        }
        return first
    }

    func isMeetingActive(_ meeting: DetectedMeeting) -> Bool {
        detectors.contains { $0.isMeetingActive(meeting) }
    }

    func reset(appName: String? = nil) {
        detectors.forEach { $0.reset(appName: appName) }
    }
}
