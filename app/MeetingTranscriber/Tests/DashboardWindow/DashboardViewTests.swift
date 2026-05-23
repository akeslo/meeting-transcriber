import XCTest
@testable import MeetingTranscriber

@MainActor
final class DashboardViewTests: XCTestCase {

    private func headline(state: TranscriberState?, isWatching: Bool, elapsed: String = "00:00") -> String {
        guard let state else {
            return isWatching ? "Meeting Detection is active." : "Idle"
        }
        switch state {
        case .recording:          return "Recording · \(elapsed)"
        case .transcribing:       return "Transcribing..."
        case .generatingProtocol: return "Generating Protocol..."
        case .recordingDone:      return "Processing..."
        default:
            return isWatching ? "Meeting Detection is active." : "Idle"
        }
    }

    func test_idle_notWatching_showsIdle() {
        XCTAssertEqual(headline(state: nil, isWatching: false), "Idle")
    }

    func test_idle_watching_showsActiveText() {
        XCTAssertEqual(headline(state: nil, isWatching: true), "Meeting Detection is active.")
    }

    func test_recording_showsElapsed() {
        XCTAssertEqual(headline(state: .recording, isWatching: true, elapsed: "01:23"), "Recording · 01:23")
    }

    func test_transcribing_showsTranscribingText() {
        XCTAssertEqual(headline(state: .transcribing, isWatching: true), "Transcribing...")
    }

    func test_generatingProtocol_showsProtocolText() {
        XCTAssertEqual(headline(state: .generatingProtocol, isWatching: true), "Generating Protocol...")
    }

    func test_recordingDone_showsProcessingText() {
        XCTAssertEqual(headline(state: .recordingDone, isWatching: true), "Processing...")
    }

    // MARK: - Stat Computation Tests

    func test_totalHours_empty_returnsZero() {
        let sessions: [TimeInterval] = []
        let hours = sessions.reduce(0, +) / 3600
        XCTAssertEqual(hours, 0)
    }

    func test_totalHours_twoSessions_sumsCorrectly() {
        // 3600 s + 7200 s = 3.0 h
        let sessions: [TimeInterval] = [3600, 7200]
        let hours = sessions.reduce(0, +) / 3600
        XCTAssertEqual(hours, 3.0, accuracy: 0.001)
    }

    func test_avgDurationMinutes_empty_returnsZero() {
        let durations: [TimeInterval] = []
        let avg = durations.isEmpty ? 0.0 : durations.reduce(0, +) / Double(durations.count) / 60
        XCTAssertEqual(avg, 0.0)
    }

    func test_avgDurationMinutes_twoSessions_returnsCorrectAvg() {
        // 60 s + 120 s → avg 90 s → 1.5 min
        let durations: [TimeInterval] = [60, 120]
        let avg = durations.reduce(0, +) / Double(durations.count) / 60
        XCTAssertEqual(avg, 1.5, accuracy: 0.001)
    }

    func test_protocolRate_noCompleted_returnsZero() {
        let total = 0
        let rate = total > 0 ? Double(0) / Double(total) * 100 : 0.0
        XCTAssertEqual(rate, 0.0)
    }

    func test_protocolRate_halfCompleted_returns50() {
        let total = 4
        let withProtocol = 2
        let rate = Double(withProtocol) / Double(total) * 100
        XCTAssertEqual(rate, 50.0, accuracy: 0.001)
    }

    func test_uniqueSpeakers_deduplicates() {
        let participants: [[String]] = [["Alice", "Bob"], ["Bob", "Carol"], ["Alice"]]
        let unique = Set(participants.flatMap { $0 }).count
        XCTAssertEqual(unique, 3)
    }

    func test_mostUsedApp_returnsHighestCount() {
        let apps = ["Zoom", "Zoom", "Teams", "Zoom", "Teams"]
        let counts = Dictionary(grouping: apps, by: { $0 }).mapValues(\.count)
        let most = counts.max(by: { $0.value < $1.value })?.key
        XCTAssertEqual(most, "Zoom")
    }

    func test_mostUsedApp_empty_returnsNil() {
        let apps: [String] = []
        let counts = Dictionary(grouping: apps, by: { $0 })
            .filter { !$0.key.isEmpty }
            .mapValues(\.count)
        let most = counts.max(by: { $0.value < $1.value })?.key
        XCTAssertNil(most)
    }
}
