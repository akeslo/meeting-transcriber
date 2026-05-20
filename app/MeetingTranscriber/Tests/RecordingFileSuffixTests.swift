import XCTest
@testable import MeetingTranscriber

final class RecordingFileSuffixTests: XCTestCase {

    func test_audioConstants() {
        XCTAssertEqual(RecordingFileSuffix.mix, "audio_mix.wav")
        XCTAssertEqual(RecordingFileSuffix.app, "audio_app.wav")
        XCTAssertEqual(RecordingFileSuffix.mic, "audio_mic.wav")
    }

    func test_documentConstants() {
        XCTAssertEqual(RecordingFileSuffix.transcript, "transcript.md")
        XCTAssertEqual(RecordingFileSuffix.protocol_, "protocol.md")
    }

    func test_stripSuffix_audioMix() {
        let result = RecordingFileSuffix.stripSuffix(from: "audio_mix.wav")
        XCTAssertEqual(result?.stem, "")
        XCTAssertEqual(result?.suffix, "audio_mix.wav")
    }

    func test_stripSuffix_unknown() {
        XCTAssertNil(RecordingFileSuffix.stripSuffix(from: "something_else.wav"))
    }
}
