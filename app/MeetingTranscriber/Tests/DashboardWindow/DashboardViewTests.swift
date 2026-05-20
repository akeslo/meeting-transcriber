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
}
