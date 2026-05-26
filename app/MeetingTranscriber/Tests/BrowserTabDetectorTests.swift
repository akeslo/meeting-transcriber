@testable import MeetingTranscriber
import XCTest

final class BrowserTabDetectorTests: XCTestCase {
    private func makeSite(
        name: String = "Meet",
        pattern: String = "meet.google.com",
        recordMic: Bool = false,
    ) -> WatchedWebsite {
        WatchedWebsite(name: name, urlPattern: pattern, recordMic: recordMic)
    }

    private func makeDetector(
        sites: [WatchedWebsite],
        confirmationCount: Int = 1,
    ) -> BrowserTabDetector {
        BrowserTabDetector(websitesProvider: { sites }, confirmationCount: confirmationCount)
    }

    private func tabInfo(url: String = "https://meet.google.com/abc") -> BrowserTabDetector.TabInfo {
        BrowserTabDetector.TabInfo(processName: "Chrome", pid: 1234, url: url)
    }

    // MARK: - Audio flags on detected meeting

    func testAudioConfirmRequiredIsTrue() {
        let detector = makeDetector(sites: [makeSite()])
        detector.tabURLProvider = { [self.tabInfo()] }
        let meeting = detector.checkOnce()
        XCTAssertTrue(meeting?.audioConfirmRequired == true)
    }

    func testAudioSilenceStopEnabledIsTrue() {
        let detector = makeDetector(sites: [makeSite()])
        detector.tabURLProvider = { [self.tabInfo()] }
        let meeting = detector.checkOnce()
        XCTAssertTrue(meeting?.audioSilenceStopEnabled == true)
    }

    // MARK: - noMicOverride wiring

    func testNoMicOverrideTrueWhenRecordMicFalse() {
        let detector = makeDetector(sites: [makeSite(recordMic: false)])
        detector.tabURLProvider = { [self.tabInfo()] }
        XCTAssertEqual(detector.checkOnce()?.noMicOverride, true)
    }

    func testNoMicOverrideFalseWhenRecordMicTrue() {
        let detector = makeDetector(sites: [makeSite(recordMic: true)])
        detector.tabURLProvider = { [self.tabInfo()] }
        XCTAssertEqual(detector.checkOnce()?.noMicOverride, false)
    }

    // MARK: - confirmationCount respected

    func testNilBeforeConfirmationCountMet() {
        let detector = makeDetector(sites: [makeSite()], confirmationCount: 2)
        detector.tabURLProvider = { [self.tabInfo()] }
        XCTAssertNil(detector.checkOnce(), "confirmationCount=2 requires two consecutive hits")
    }

    func testMeetingReturnedAfterConfirmationCountMet() {
        let detector = makeDetector(sites: [makeSite()], confirmationCount: 2)
        detector.tabURLProvider = { [self.tabInfo()] }
        _ = detector.checkOnce()
        XCTAssertNotNil(detector.checkOnce())
    }
}
