import Foundation

enum AudioSilencePolicy {
    static func step(
        enabled: Bool,
        audioSilent: Bool,
        silenceStart: Date?,
        silenceStopSeconds: TimeInterval,
        now: Date,
    ) -> (stop: Bool, newSilenceStart: Date?) {
        guard enabled, silenceStopSeconds > 0 else {
            return (stop: false, newSilenceStart: nil)
        }
        guard audioSilent else {
            return (stop: false, newSilenceStart: nil)
        }
        let start = silenceStart ?? now
        return (stop: now.timeIntervalSince(start) >= silenceStopSeconds, newSilenceStart: start)
    }
}
