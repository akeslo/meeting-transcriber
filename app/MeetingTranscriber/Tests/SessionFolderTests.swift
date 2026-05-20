import XCTest
@testable import MeetingTranscriber

final class SessionFolderTests: XCTestCase {

    func test_slug_lowercasesAndHyphenates() {
        XCTAssertEqual(SessionFolder.slug(from: "Zoom Weekly Sync"), "zoom-weekly-sync")
    }

    func test_slug_removesSpecialChars() {
        XCTAssertEqual(SessionFolder.slug(from: "Q4 Review! (Corp)"), "q4-review-corp")
    }

    func test_slug_truncatesAt40() {
        let long = "This Is A Very Long Meeting Title That Exceeds Forty Characters For Sure"
        XCTAssertTrue(SessionFolder.slug(from: long).count <= 40)
    }

    func test_slug_emptyTitle() {
        XCTAssertEqual(SessionFolder.slug(from: ""), "untitled")
    }

    func test_slug_collapsesMultipleHyphens() {
        XCTAssertEqual(SessionFolder.slug(from: "Hello -- World"), "hello-world")
    }

    func test_folderName_format() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 20
        comps.hour = 14; comps.minute = 30; comps.second = 22
        let date = cal.date(from: comps)!
        let name = SessionFolder.folderName(date: date, title: "Zoom Weekly")
        XCTAssertTrue(name.hasSuffix("_zoom-weekly"), "got: \(name)")
        let parts = name.components(separatedBy: "_")
        XCTAssertEqual(parts.count, 3) // date_time_slug
    }
}
