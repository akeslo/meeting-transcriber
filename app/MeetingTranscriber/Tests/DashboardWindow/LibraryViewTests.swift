import XCTest
@testable import MeetingTranscriber

@MainActor
final class LibraryViewTests: XCTestCase {

    // MARK: - Search filter

    private func makeSession(title: String, appName: String, participants: [String] = [], status: String = "done") -> RecordingSession {
        RecordingSession(
            id: UUID(),
            createdAt: Date(),
            title: title,
            appName: appName,
            folderPath: "/tmp",
            duration: 300,
            participantNames: participants,
            hasTranscript: false,
            hasProtocol: false,
            audioFiles: [],
            engine: "WhisperKit",
            status: status
        )
    }

    private func applyFilter(sessions: [RecordingSession], searchText: String) -> [RecordingSession] {
        LibraryView.filterSessions(sessions, searchText: searchText)
    }

    func test_filter_emptySearch_returnsAll() {
        let sessions = [
            makeSession(title: "Alpha", appName: "Zoom"),
            makeSession(title: "Beta", appName: "Teams"),
        ]
        XCTAssertEqual(applyFilter(sessions: sessions, searchText: "").count, 2)
    }

    func test_filter_matchesTitle_caseInsensitive() {
        let sessions = [
            makeSession(title: "Weekly Sync", appName: "Zoom"),
            makeSession(title: "One on One", appName: "Zoom"),
        ]
        let result = applyFilter(sessions: sessions, searchText: "weekly")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Weekly Sync")
    }

    func test_filter_matchesAppName_caseInsensitive() {
        let sessions = [
            makeSession(title: "Meeting A", appName: "Zoom"),
            makeSession(title: "Meeting B", appName: "Teams"),
        ]
        let result = applyFilter(sessions: sessions, searchText: "teams")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].appName, "Teams")
    }

    func test_filter_matchesParticipantName() {
        let sessions = [
            makeSession(title: "Meeting A", appName: "Zoom", participants: ["Alice", "Bob"]),
            makeSession(title: "Meeting B", appName: "Zoom", participants: ["Carol", "Dave"]),
        ]
        let result = applyFilter(sessions: sessions, searchText: "alice")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Meeting A")
    }

    func test_filter_noMatch_returnsEmpty() {
        let sessions = [
            makeSession(title: "Alpha", appName: "Zoom"),
            makeSession(title: "Beta", appName: "Teams"),
        ]
        XCTAssertEqual(applyFilter(sessions: sessions, searchText: "xyzzy").count, 0)
    }

    func test_filter_partialMatchTitle() {
        let sessions = [
            makeSession(title: "Q4 Quarterly Review", appName: "Zoom"),
            makeSession(title: "Sprint Planning", appName: "Zoom"),
        ]
        let result = applyFilter(sessions: sessions, searchText: "quart")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Q4 Quarterly Review")
    }

    // MARK: - In-flight filter

    func test_inFlightFilter_includesActiveStates() {
        let waiting = makePipelineJob(state: .waiting)
        let transcribing = makePipelineJob(state: .transcribing)
        let diarizing = makePipelineJob(state: .diarizing)
        let generatingProtocol = makePipelineJob(state: .generatingProtocol)
        let done = makePipelineJob(state: .done)
        let error = makePipelineJob(state: .error)

        let allJobs = [waiting, transcribing, diarizing, generatingProtocol, done, error]
        let inFlight = LibraryView.filterInFlightJobs(allJobs)

        XCTAssertEqual(inFlight.count, 4)
        XCTAssertTrue(inFlight.contains(where: { $0.id == waiting.id }))
        XCTAssertTrue(inFlight.contains(where: { $0.id == transcribing.id }))
        XCTAssertTrue(inFlight.contains(where: { $0.id == diarizing.id }))
        XCTAssertTrue(inFlight.contains(where: { $0.id == generatingProtocol.id }))
        XCTAssertFalse(inFlight.contains(where: { $0.id == done.id }))
        XCTAssertFalse(inFlight.contains(where: { $0.id == error.id }))
    }

    func test_inFlightFilter_speakerNamingPendingExcluded() {
        let job = makePipelineJob(state: .speakerNamingPending)
        let result = LibraryView.filterInFlightJobs([job])
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - Helpers

    private func makePipelineJob(state: JobState) -> PipelineJob {
        PipelineJob(
            id: UUID(),
            meetingTitle: "Test Meeting",
            state: state,
            progress: 0.5,
            startedAt: Date()
        )
    }
}
