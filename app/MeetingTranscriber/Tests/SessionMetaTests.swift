import XCTest
@testable import MeetingTranscriber

final class SessionMetaTests: XCTestCase {

    func test_encodeDecodeRoundtrip() throws {
        let meta = SessionMeta(
            title: "Zoom Weekly",
            appName: "zoom.us",
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            stoppedAt: Date(timeIntervalSince1970: 1_002_500),
            participants: ["Alice", "Bob"],
            micDelaySeconds: 0.12,
            engine: "whisperKit",
            diarizerMode: "offlineDiarizer",
            files: SessionMeta.FileRefs(
                app: "audio_app.wav", mic: "audio_mic.wav",
                mix: "audio_mix.wav", transcript: "transcript.md", protocol_: "protocol.md"
            )
        )
        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(SessionMeta.self, from: data)
        XCTAssertEqual(decoded.version, SessionMeta.currentVersion)
        XCTAssertEqual(decoded.title, "Zoom Weekly")
        XCTAssertEqual(decoded.participants, ["Alice", "Bob"])
        XCTAssertEqual(decoded.files.app, "audio_app.wav")
        XCTAssertEqual(decoded.files.protocol_, "protocol.md")
        XCTAssertEqual(decoded.duration, 2500, accuracy: 0.001)
    }

    func test_writeAndRead() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let meta = SessionMeta(
            title: "Test Meeting", appName: "Test.app",
            startedAt: Date(timeIntervalSince1970: 0),
            stoppedAt: Date(timeIntervalSince1970: 100),
            participants: [],
            micDelaySeconds: 0,
            engine: "parakeet",
            diarizerMode: "sortformer",
            files: SessionMeta.FileRefs(app: nil, mic: nil, mix: "audio_mix.wav", transcript: "transcript.md", protocol_: nil)
        )
        try meta.write(to: dir)
        let url = dir.appendingPathComponent("meta.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let decoded = try SessionMeta.read(from: dir)
        XCTAssertEqual(decoded.title, "Test Meeting")
    }
}
