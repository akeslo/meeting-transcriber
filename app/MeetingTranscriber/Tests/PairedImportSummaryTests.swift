@testable import MeetingTranscriber
import XCTest

final class PairedImportSummaryTests: XCTestCase {
    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    private func audioURL(stem: String, suffix: String) -> URL {
        url("\(stem)_\(suffix)")
    }

    func testEmptySelectionShowsBlank() {
        XCTAssertEqual(PairedImportSummary.text(forSelectedURLs: []), " ")
    }

    func testSinglePairWithMixAnchorIs1Transcript() {
        let text = PairedImportSummary.text(forSelectedURLs: [
            audioURL(stem: "meeting", suffix: RecordingFileSuffix.app),
            audioURL(stem: "meeting", suffix: RecordingFileSuffix.mic),
            audioURL(stem: "meeting", suffix: RecordingFileSuffix.mix),
        ])
        XCTAssertEqual(text, "1 paired recording → 1 transcript")
    }

    func testTwoPairsArePluralized() {
        let text = PairedImportSummary.text(forSelectedURLs: [
            audioURL(stem: "a", suffix: RecordingFileSuffix.app),
            audioURL(stem: "a", suffix: RecordingFileSuffix.mic),
            audioURL(stem: "a", suffix: RecordingFileSuffix.mix),
            audioURL(stem: "b", suffix: RecordingFileSuffix.app),
            audioURL(stem: "b", suffix: RecordingFileSuffix.mic),
            audioURL(stem: "b", suffix: RecordingFileSuffix.mix),
        ])
        XCTAssertEqual(text, "2 paired recordings → 2 transcripts")
    }

    func testMixedPairAndSingleton() {
        let text = PairedImportSummary.text(forSelectedURLs: [
            audioURL(stem: "meeting", suffix: RecordingFileSuffix.app),
            audioURL(stem: "meeting", suffix: RecordingFileSuffix.mic),
            audioURL(stem: "meeting", suffix: RecordingFileSuffix.mix),
            url("podcast.mp3"),
        ])
        XCTAssertEqual(text, "1 paired recording + 1 single file → 2 transcripts")
    }

    func testAppPlusMicWithoutMixIsOnePairedRecording() {
        // app+mic without mix is paired — synthesizer creates the mix on enqueue.
        let text = PairedImportSummary.text(forSelectedURLs: [
            audioURL(stem: "meeting", suffix: RecordingFileSuffix.app),
            audioURL(stem: "meeting", suffix: RecordingFileSuffix.mic),
        ])
        XCTAssertEqual(text, "1 paired recording → 1 transcript")
    }

    func testOnlySingletons() {
        let text = PairedImportSummary.text(forSelectedURLs: [
            url("one.mp3"),
            url("two.m4a"),
        ])
        XCTAssertEqual(text, "2 single files → 2 transcripts")
    }

    func testLoneAppFallsBackAndIsCountedAsSingle() {
        let text = PairedImportSummary.text(forSelectedURLs: [
            url("orphan_app.wav"),
        ])
        XCTAssertEqual(text, "1 single file → 1 transcript")
    }
}
