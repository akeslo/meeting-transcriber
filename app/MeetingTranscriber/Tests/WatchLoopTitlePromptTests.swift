@testable import MeetingTranscriber
import XCTest

@MainActor
final class WatchLoopTitlePromptTests: XCTestCase {

    private func makeResult() -> RecordingResult {
        RecordingResult(
            mixPath: URL(fileURLWithPath: "/tmp/mix.wav"),
            appPath: nil,
            micPath: nil,
            micDelay: 0,
            recordingStart: 0
        )
    }

    private func makeLoop(queue: PipelineQueue? = nil) -> WatchLoop {
        let detector = PowerAssertionDetector()
        detector.assertionProvider = { [:] }
        return WatchLoop(detector: detector, pipelineQueue: queue)
    }

    // MARK: - Initial state

    func testPendingTitleInitiallyNil() {
        XCTAssertNil(makeLoop().pendingTitle)
    }

    // MARK: - confirmTitle

    func testConfirmTitleClearsPendingTitle() {
        let loop = makeLoop()
        loop.pendingTitle = PendingTitleEntry(
            suggestedTitle: "Auto Title", appName: "Zoom",
            recording: makeResult(), participants: []
        )
        loop.confirmTitle("My Custom Title")
        XCTAssertNil(loop.pendingTitle)
    }

    func testConfirmTitleWithWhitespaceOnlyUsesSuggested() {
        let queue = PipelineQueue()
        let loop = makeLoop(queue: queue)
        loop.pendingTitle = PendingTitleEntry(
            suggestedTitle: "Auto Title", appName: "Zoom",
            recording: makeResult(), participants: []
        )
        loop.confirmTitle("   ")
        XCTAssertNil(loop.pendingTitle)
        XCTAssertEqual(queue.jobs.first?.meetingTitle, "Auto Title")
    }

    func testConfirmTitlePassesTrimmedTitle() {
        let queue = PipelineQueue()
        let loop = makeLoop(queue: queue)
        loop.pendingTitle = PendingTitleEntry(
            suggestedTitle: "Auto Title", appName: "Zoom",
            recording: makeResult(), participants: []
        )
        loop.confirmTitle("  My Meeting  ")
        XCTAssertEqual(queue.jobs.first?.meetingTitle, "My Meeting")
    }

    // MARK: - skipTitle

    func testSkipTitleClearsPendingTitle() {
        let loop = makeLoop()
        loop.pendingTitle = PendingTitleEntry(
            suggestedTitle: "Auto Title", appName: "Zoom",
            recording: makeResult(), participants: []
        )
        loop.skipTitle()
        XCTAssertNil(loop.pendingTitle)
    }

    func testSkipTitleUsesSuggestedTitle() {
        let queue = PipelineQueue()
        let loop = makeLoop(queue: queue)
        loop.pendingTitle = PendingTitleEntry(
            suggestedTitle: "Auto Title", appName: "Zoom",
            recording: makeResult(), participants: []
        )
        loop.skipTitle()
        XCTAssertEqual(queue.jobs.first?.meetingTitle, "Auto Title")
    }

    // MARK: - setPending auto-flush

    func testSetPendingAutoFlushesExistingEntry() {
        let queue = PipelineQueue()
        let loop = makeLoop(queue: queue)

        loop.pendingTitle = PendingTitleEntry(
            suggestedTitle: "First Meeting", appName: "Zoom",
            recording: makeResult(), participants: []
        )
        loop.setPending(
            suggestedTitle: "Second Meeting", appName: "Teams",
            recording: makeResult(), participants: []
        )

        // First entry auto-enqueued with its suggested title
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(queue.jobs.first?.meetingTitle, "First Meeting")
        // Second entry now pending
        XCTAssertEqual(loop.pendingTitle?.suggestedTitle, "Second Meeting")
    }
}
