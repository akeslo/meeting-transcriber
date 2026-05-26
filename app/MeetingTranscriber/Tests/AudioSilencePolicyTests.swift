@testable import MeetingTranscriber
import XCTest

final class AudioSilencePolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testDisabledNeverStops() {
        let r = AudioSilencePolicy.step(
            enabled: false, audioSilent: true,
            silenceStart: t0, silenceStopSeconds: 1, now: t0.addingTimeInterval(10),
        )
        XCTAssertFalse(r.stop)
    }

    func testZeroSecondsNeverStops() {
        let r = AudioSilencePolicy.step(
            enabled: true, audioSilent: true,
            silenceStart: t0, silenceStopSeconds: 0, now: t0.addingTimeInterval(10),
        )
        XCTAssertFalse(r.stop)
    }

    func testAudioNotSilentClearsTimer() {
        let r = AudioSilencePolicy.step(
            enabled: true, audioSilent: false,
            silenceStart: t0, silenceStopSeconds: 10, now: t0.addingTimeInterval(5),
        )
        XCTAssertFalse(r.stop)
        XCTAssertNil(r.newSilenceStart)
    }

    func testSilenceBelowThresholdContinues() {
        let r = AudioSilencePolicy.step(
            enabled: true, audioSilent: true,
            silenceStart: t0, silenceStopSeconds: 10, now: t0.addingTimeInterval(5),
        )
        XCTAssertFalse(r.stop)
        XCTAssertEqual(r.newSilenceStart, t0)
    }

    func testSilenceAtExactThresholdStops() {
        let r = AudioSilencePolicy.step(
            enabled: true, audioSilent: true,
            silenceStart: t0, silenceStopSeconds: 10, now: t0.addingTimeInterval(10),
        )
        XCTAssertTrue(r.stop)
    }

    func testSilenceExceedsThresholdStops() {
        let r = AudioSilencePolicy.step(
            enabled: true, audioSilent: true,
            silenceStart: t0, silenceStopSeconds: 10, now: t0.addingTimeInterval(15),
        )
        XCTAssertTrue(r.stop)
    }

    func testNilSilenceStartInitialisedToNow() {
        let now = t0.addingTimeInterval(5)
        let r = AudioSilencePolicy.step(
            enabled: true, audioSilent: true,
            silenceStart: nil, silenceStopSeconds: 10, now: now,
        )
        XCTAssertFalse(r.stop)
        XCTAssertEqual(r.newSilenceStart, now)
    }

    func testAudioReturnResetsTimerAndPreventsStop() {
        // 5s of silence accumulates
        let r1 = AudioSilencePolicy.step(
            enabled: true, audioSilent: true,
            silenceStart: nil, silenceStopSeconds: 10, now: t0.addingTimeInterval(5),
        )
        XCTAssertNotNil(r1.newSilenceStart)

        // Audio returns — timer resets to nil
        let r2 = AudioSilencePolicy.step(
            enabled: true, audioSilent: false,
            silenceStart: r1.newSilenceStart, silenceStopSeconds: 10, now: t0.addingTimeInterval(9),
        )
        XCTAssertNil(r2.newSilenceStart)
        XCTAssertFalse(r2.stop)

        // Silence starts again from t0+9; 9s later (t0+18) is only 9s of new silence → no stop
        let r3 = AudioSilencePolicy.step(
            enabled: true, audioSilent: true,
            silenceStart: r2.newSilenceStart, silenceStopSeconds: 10, now: t0.addingTimeInterval(18),
        )
        XCTAssertFalse(r3.stop, "fresh silence epoch started at t0+9; only 9s elapsed, not 10")
    }
}
