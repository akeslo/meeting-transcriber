@testable import MeetingTranscriber
import XCTest

@MainActor
final class WatchLoopAudioConfirmTests: XCTestCase {
    // MARK: - Helpers

    private func makeActiveDetector(pid: pid_t = 1234) -> PowerAssertionDetector {
        let d = PowerAssertionDetector()
        d.assertionProvider = { [pid: [["Process Name": "zoom.us", "AssertName": "zoom"]]] }
        return d
    }

    private func makeInactiveDetector() -> PowerAssertionDetector {
        let d = PowerAssertionDetector()
        d.assertionProvider = { [:] }
        return d
    }

    private func makeMeeting(pid: pid_t = 1234, audioConfirmRequired: Bool = true) -> DetectedMeeting {
        DetectedMeeting(
            pattern: .zoom,
            windowTitle: "Zoom Meeting",
            ownerName: "zoom.us",
            windowPID: pid,
            audioConfirmRequired: audioConfirmRequired,
        )
    }

    // MARK: - waitForAudioConfirm

    func testConfirmReturnsTrueWhenAudioAboveThreshold() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.appLevelDBFS = -40  // audible
        let loop = WatchLoop(
            detector: makeActiveDetector(),
            recorderFactory: { recorder },
            pollInterval: 0.05,
            audioConfirmTimeout: 60,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
        )
        let confirmed = try await loop.waitForAudioConfirm(makeMeeting(), recorder: recorder)
        XCTAssertTrue(confirmed)
    }

    func testConfirmReturnsFalseOnTimeout() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.appLevelDBFS = -120  // silent
        let loop = WatchLoop(
            detector: makeActiveDetector(),
            recorderFactory: { recorder },
            pollInterval: 0.05,
            audioConfirmTimeout: 0.1,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
        )
        let confirmed = try await loop.waitForAudioConfirm(makeMeeting(), recorder: recorder)
        XCTAssertFalse(confirmed)
    }

    func testConfirmReturnsFalseWhenMeetingGoesInactive() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.appLevelDBFS = -120
        let loop = WatchLoop(
            detector: makeInactiveDetector(),
            recorderFactory: { recorder },
            pollInterval: 0.05,
            audioConfirmTimeout: 60,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
        )
        let confirmed = try await loop.waitForAudioConfirm(makeMeeting(), recorder: recorder)
        XCTAssertFalse(confirmed)
    }

    // MARK: - handleMeeting integration

    func testHandleMeetingDiscardsWhenConfirmFails() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.mixPath = URL(fileURLWithPath: "/tmp/test.wav")
        recorder.appLevelDBFS = -120  // silent → confirm fails
        let queue = PipelineQueue()
        let loop = WatchLoop(
            detector: makeInactiveDetector(),
            recorderFactory: { recorder },
            pipelineQueue: queue,
            pollInterval: 0.05,
            audioConfirmTimeout: 0.1,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
        )
        try await loop.handleMeeting(makeMeeting())
        XCTAssertTrue(recorder.discardCalled, "discard() must be called when audio confirm fails")
        XCTAssertFalse(recorder.stopCalled, "stop() must NOT be called on discard path")
        XCTAssertEqual(queue.jobs.count, 0, "no job enqueued when audio confirm fails")
        XCTAssertNil(loop.pendingTitle)
    }

    func testHandleMeetingProceedsWhenConfirmPasses() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.mixPath = URL(fileURLWithPath: "/tmp/test.wav")
        recorder.appLevelDBFS = -40  // audible → confirm passes
        let queue = PipelineQueue()
        let loop = WatchLoop(
            detector: makeInactiveDetector(),  // inactive → waitForMeetingEnd exits via grace
            recorderFactory: { recorder },
            pipelineQueue: queue,
            pollInterval: 0.05,
            endGracePeriod: 0.1,
            audioConfirmTimeout: 60,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
        )
        try await loop.handleMeeting(makeMeeting())
        loop.skipTitle()
        XCTAssertFalse(recorder.discardCalled)
        XCTAssertTrue(recorder.stopCalled)
        XCTAssertEqual(queue.jobs.count, 1)
    }

    func testHandleMeetingSkipsConfirmWhenFlagFalse() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.mixPath = URL(fileURLWithPath: "/tmp/test.wav")
        recorder.appLevelDBFS = -120  // silent — but confirm not required
        let queue = PipelineQueue()
        let loop = WatchLoop(
            detector: makeInactiveDetector(),
            recorderFactory: { recorder },
            pipelineQueue: queue,
            pollInterval: 0.05,
            endGracePeriod: 0.1,
            audioConfirmTimeout: 0.05,  // would fire immediately if used
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
        )
        try await loop.handleMeeting(makeMeeting(audioConfirmRequired: false))
        loop.skipTitle()
        XCTAssertFalse(recorder.discardCalled, "confirm phase must be skipped when flag is false")
        XCTAssertEqual(queue.jobs.count, 1)
    }
}
