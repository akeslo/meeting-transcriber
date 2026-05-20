import XCTest
@testable import MeetingTranscriber

final class TranscriptParserTests: XCTestCase {

    func test_singleSegment_parsedCorrectly() {
        let md = """
        **Alice** [00:01:30]
        Hello there, this is Alice speaking.
        """
        let segments = TranscriptParser.parse(markdown: md)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].speaker, "Alice")
        XCTAssertEqual(segments[0].timestamp, 90)
        XCTAssertEqual(segments[0].body, "Hello there, this is Alice speaking.")
    }

    func test_twoSegments_parsedInOrder() {
        let md = """
        **Alice** [00:00:05]
        First utterance.

        **Bob** [00:01:10]
        Second utterance.
        """
        let segments = TranscriptParser.parse(markdown: md)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].speaker, "Alice")
        XCTAssertEqual(segments[0].timestamp, 5)
        XCTAssertEqual(segments[1].speaker, "Bob")
        XCTAssertEqual(segments[1].timestamp, 70)
    }

    func test_hoursInTimestamp_parsedCorrectly() {
        let md = """
        **Charlie** [01:02:03]
        Body text.
        """
        let segments = TranscriptParser.parse(markdown: md)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].timestamp, 3723)
    }

    func test_multiLineBody_joinedWithNewline() {
        let md = """
        **Alice** [00:00:00]
        Line one.
        Line two.
        Line three.
        """
        let segments = TranscriptParser.parse(markdown: md)
        XCTAssertEqual(segments.count, 1)
        XCTAssertTrue(segments[0].body.contains("Line one."))
        XCTAssertTrue(segments[0].body.contains("Line two."))
        XCTAssertTrue(segments[0].body.contains("Line three."))
    }

    func test_headerWithNoBody_isDropped() {
        let md = """
        **Alice** [00:00:00]

        **Bob** [00:00:10]
        Real content here.
        """
        let segments = TranscriptParser.parse(markdown: md)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].speaker, "Bob")
    }

    func test_emptyString_returnsEmpty() {
        XCTAssertTrue(TranscriptParser.parse(markdown: "").isEmpty)
    }

    func test_noSpeakerHeaders_returnsEmpty() {
        let md = """
        Just some random text.
        No speaker headers here.
        """
        XCTAssertTrue(TranscriptParser.parse(markdown: md).isEmpty)
    }

    func test_speakerNameWithSpaces_parsedCorrectly() {
        let md = """
        **John Doe** [00:00:42]
        Content.
        """
        let segments = TranscriptParser.parse(markdown: md)
        XCTAssertEqual(segments[0].speaker, "John Doe")
    }

    func test_allSegmentsHaveUniqueIDs() {
        let md = """
        **A** [00:00:01]
        Body A.

        **B** [00:00:02]
        Body B.

        **C** [00:00:03]
        Body C.
        """
        let segments = TranscriptParser.parse(markdown: md)
        let ids = Set(segments.map(\.id))
        XCTAssertEqual(ids.count, segments.count)
    }
}
