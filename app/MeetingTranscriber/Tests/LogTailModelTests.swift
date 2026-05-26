import XCTest
@testable import MeetingTranscriber

@MainActor
final class LogTailModelTests: XCTestCase {

    func test_parse_extractsTimestamp() {
        let raw = "May 26 12:34:56 host MeetingTranscriber(WatchLoop)[123] <Notice>: hello"
        let line = LogLine.parse(raw: raw)
        XCTAssertEqual(line.timestamp, "May 26 12:34:56")
    }

    func test_parse_extractsCategory() {
        let raw = "May 26 12:34:56 host MeetingTranscriber(PipelineQueue)[123] <Notice>: msg"
        let line = LogLine.parse(raw: raw)
        XCTAssertEqual(line.category, "PipelineQueue")
    }

    func test_parse_extractsMessage() {
        let raw = "May 26 12:34:56 host MeetingTranscriber(WatchLoop)[123] <Notice>: job done"
        let line = LogLine.parse(raw: raw)
        XCTAssertEqual(line.message, "job done")
    }

    func test_parse_unparseable_returnsRawAsMessage() {
        let raw = "not a syslog line at all"
        let line = LogLine.parse(raw: raw)
        XCTAssertEqual(line.raw, raw)
        XCTAssertEqual(line.category, "")
        XCTAssertEqual(line.message, raw)
    }

    func test_parse_emptyCategoryWhenNoParens() {
        let raw = "May 26 12:34:56 host MeetingTranscriber[123] <Notice>: no category"
        let line = LogLine.parse(raw: raw)
        XCTAssertEqual(line.category, "")
    }

    // MARK: - LogTailModel ring buffer

    func test_ringBuffer_dropsOldestWhenExceedingMax() {
        let model = LogTailModel()
        let lines = (0 ..< (LogTailModel.maxLines + 10)).map { i in
            LogLine(id: UUID(), raw: "line \(i)", timestamp: "", category: "", message: "line \(i)")
        }
        model.appendForTesting(lines)
        XCTAssertEqual(model.lines.count, LogTailModel.maxLines)
        XCTAssertEqual(model.lines.first?.message, "line 10")
    }

    func test_categories_deduplicatedInInsertionOrder() {
        let model = LogTailModel()
        let a = LogLine(id: UUID(), raw: "", timestamp: "", category: "Alpha", message: "")
        let b = LogLine(id: UUID(), raw: "", timestamp: "", category: "Beta", message: "")
        let c = LogLine(id: UUID(), raw: "", timestamp: "", category: "Alpha", message: "")
        model.appendForTesting([a, b, c])
        XCTAssertEqual(model.categories, ["Alpha", "Beta"])
    }
}
