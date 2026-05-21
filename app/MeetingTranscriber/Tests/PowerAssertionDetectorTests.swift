@testable import MeetingTranscriber
import XCTest

// MARK: - Test Helpers

private func makeAssertionDict(
    pid: Int32,
    processName: String,
    assertName: String,
    assertType: String = "PreventUserIdleDisplaySleep",
) -> [Int32: [[String: Any]]] {
    [
        pid: [
            [
                "Process Name": processName,
                "AssertName": assertName,
                "AssertType": assertType,
                "AssertPID": pid,
                "AssertLevel": 255,
            ],
        ],
    ]
}

private func makeDetector(confirmationCount: Int = 1) -> PowerAssertionDetector {
    let detector = PowerAssertionDetector(confirmationCount: confirmationCount)
    detector.windowListProvider = { [] } // no real windows in unit tests
    return detector
}

// MARK: - Detection Tests

final class PowerAssertionDetectorTests: XCTestCase {
    func testNoAssertionsReturnsNil() {
        let detector = makeDetector()
        detector.assertionProvider = { [:] }
        XCTAssertNil(detector.checkOnce())
    }

    func testDetectsZoomViaZoomusProcess() {
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 1438,
                processName: "zoom.us",
                assertName: "Zoom video call active",
            )
        }
        let result = detector.checkOnce()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.pattern.appName, "Zoom")
        XCTAssertEqual(result?.windowTitle, "Zoom video call active")
        XCTAssertEqual(result?.ownerName, "zoom.us")
        XCTAssertEqual(result?.windowPID, 1438)
    }

    func testDetectsZoomViaCptHostProcess() {
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 1234,
                processName: "CptHost",
                assertName: "Zoom video call active",
            )
        }
        XCTAssertNotNil(detector.checkOnce())
    }

    func testDetectsZoomViaAnyAssertName() {
        // Zoom has no keyword filter — any assertion from a Zoom process triggers detection
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 5678,
                processName: "zoom.us",
                assertName: "PreventUserIdleDisplaySleep",
            )
        }
        let result = detector.checkOnce()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.pattern.appName, "Zoom")
    }

    func testIgnoresUnknownVideoWakeLock() {
        // Generic "Video Wake Lock" from an unlisted app must NOT trigger detection
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 4211,
                processName: "SomeVideoApp",
                assertName: "Video Wake Lock",
            )
        }
        XCTAssertNil(detector.checkOnce())
    }

    func testDetectsZoomCall() {
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 2345,
                processName: "zoom.us",
                assertName: "Zoom Video Communication",
            )
        }
        let result = detector.checkOnce()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.pattern.appName, "Zoom")
    }

    func testDetectsSimulatorMeeting() {
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 3456,
                processName: "meeting-simulator",
                assertName: "simulator meeting",
            )
        }
        let result = detector.checkOnce()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.pattern.appName, "MeetingSimulator")
    }

    func testSimulatorRequiresKeyword() {
        // Simulator has a keyword filter — other assertNames must not trigger detection
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 3457,
                processName: "meeting-simulator",
                assertName: "PreventUserIdleDisplaySleep",
            )
        }
        XCTAssertNil(detector.checkOnce())
    }

    // MARK: - Ignore Non-Meeting Assertions

    func testIgnoresSafariAssertion() {
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 9999,
                processName: "Safari",
                assertName: "Playing video",
            )
        }
        XCTAssertNil(detector.checkOnce())
    }

    func testIgnoresSpotifyAssertion() {
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 8888,
                processName: "Spotify",
                assertName: "Spotify is playing",
            )
        }
        XCTAssertNil(detector.checkOnce())
    }

    func testIgnoresUnknownProcess() {
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 7777,
                processName: "SomeRandomApp",
                assertName: "call in progress",
            )
        }
        XCTAssertNil(detector.checkOnce())
    }

    func testSimulatorIgnoresNonMeetingAssertName() {
        // "meeting-simulator" process with a non-meeting assertName must not trigger detection
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 1234,
                processName: "meeting-simulator",
                assertName: "downloading update",
            )
        }
        XCTAssertNil(detector.checkOnce())
    }

    // MARK: - Confirmation Threshold

    func testConfirmationThreshold() {
        let detector = makeDetector(confirmationCount: 3)
        let assertions = makeAssertionDict(
            pid: 1234,
            processName: "zoom.us",
            assertName: "Zoom video call active",
        )
        detector.assertionProvider = { assertions }

        XCTAssertNil(detector.checkOnce()) // count=1
        XCTAssertNil(detector.checkOnce()) // count=2
        XCTAssertNotNil(detector.checkOnce()) // count=3
    }

    func testCounterResetsWhenAssertionDisappears() {
        let detector = makeDetector(confirmationCount: 3)
        let assertions = makeAssertionDict(
            pid: 1234,
            processName: "zoom.us",
            assertName: "Zoom video call active",
        )

        detector.assertionProvider = { assertions }
        XCTAssertNil(detector.checkOnce()) // count=1

        // Assertion disappears
        detector.assertionProvider = { [:] }
        XCTAssertNil(detector.checkOnce()) // resets

        // Needs full count again
        detector.assertionProvider = { assertions }
        XCTAssertNil(detector.checkOnce()) // count=1
        XCTAssertNil(detector.checkOnce()) // count=2
        XCTAssertNotNil(detector.checkOnce()) // count=3
    }

    // MARK: - Cooldown

    func testCooldownPreventsRedetection() {
        let detector = makeDetector()
        let assertions = makeAssertionDict(
            pid: 1234,
            processName: "zoom.us",
            assertName: "Zoom video call active",
        )
        detector.assertionProvider = { assertions }

        XCTAssertNotNil(detector.checkOnce())
        detector.reset(appName: "Zoom")
        XCTAssertNil(detector.checkOnce())
    }

    func testCooldownDoesNotAffectOtherApps() {
        let detector = makeDetector()

        // Detect Zoom
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 1234,
                processName: "zoom.us",
                assertName: "Zoom video call active",
            )
        }
        XCTAssertNotNil(detector.checkOnce())
        detector.reset(appName: "Zoom")

        // Simulator should still work
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 2345,
                processName: "meeting-simulator",
                assertName: "simulator meeting",
            )
        }
        let result = detector.checkOnce()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.pattern.appName, "MeetingSimulator")
    }

    // MARK: - isMeetingActive

    func testIsMeetingActiveTrue() throws {
        let detector = makeDetector()
        let assertions = makeAssertionDict(
            pid: 1234,
            processName: "zoom.us",
            assertName: "Zoom video call active",
        )
        detector.assertionProvider = { assertions }
        let meeting = try XCTUnwrap(detector.checkOnce())

        XCTAssertTrue(detector.isMeetingActive(meeting))
    }

    func testIsMeetingActiveFalse() throws {
        let detector = makeDetector()
        let assertions = makeAssertionDict(
            pid: 1234,
            processName: "zoom.us",
            assertName: "Zoom video call active",
        )
        detector.assertionProvider = { assertions }
        let meeting = try XCTUnwrap(detector.checkOnce())

        detector.assertionProvider = { [:] }
        XCTAssertFalse(detector.isMeetingActive(meeting))
    }

    // MARK: - Keyword Case Insensitivity

    func testKeywordMatchIsCaseInsensitive() {
        // The Simulator pattern uses "simulator meeting" keyword — verify case-insensitive match
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 1234,
                processName: "meeting-simulator",
                assertName: "SIMULATOR MEETING ACTIVE",
            )
        }
        XCTAssertNotNil(detector.checkOnce())
    }

    // MARK: - Window Title Lookup

    func testWindowTitleUsedWhenFound() {
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 1438,
                processName: "zoom.us",
                assertName: "Zoom video call active",
            )
        }
        detector.windowListProvider = {
            [[
                "kCGWindowOwnerName": "zoom.us",
                "kCGWindowName": "Sprint Review - Zoom",
                "kCGWindowOwnerPID": Int32(1438),
            ]]
        }
        let result = detector.checkOnce()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.windowTitle, "Sprint Review - Zoom")
    }

    func testAssertionNameUsedWhenNoWindowFound() {
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 1438,
                processName: "zoom.us",
                assertName: "Zoom video call active",
            )
        }
        // No matching windows
        detector.windowListProvider = { [] }
        let result = detector.checkOnce()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.windowTitle, "Zoom video call active")
    }

    func testWindowTitleSkipsEmptyAndAppNameOnly() {
        let detector = makeDetector()
        detector.assertionProvider = {
            makeAssertionDict(
                pid: 1438,
                processName: "zoom.us",
                assertName: "Zoom video call active",
            )
        }
        detector.windowListProvider = {
            [
                // Empty title — should be skipped
                [
                    "kCGWindowOwnerName": "zoom.us",
                    "kCGWindowName": "",
                    "kCGWindowOwnerPID": Int32(1438),
                ],
                // Title equals app name — should be skipped (appName is "Zoom" for the zoom pattern)
                [
                    "kCGWindowOwnerName": "zoom.us",
                    "kCGWindowName": "Zoom",
                    "kCGWindowOwnerPID": Int32(1438),
                ],
                // Real meeting title
                [
                    "kCGWindowOwnerName": "zoom.us",
                    "kCGWindowName": "Daily Standup - Zoom",
                    "kCGWindowOwnerPID": Int32(1438),
                ],
            ]
        }
        let result = detector.checkOnce()
        XCTAssertEqual(result?.windowTitle, "Daily Standup - Zoom")
    }

    // MARK: - Reset Without App Name

    func testResetWithoutAppNameNoCooldown() {
        let detector = makeDetector()
        let assertions = makeAssertionDict(
            pid: 1234,
            processName: "zoom.us",
            assertName: "Zoom video call active",
        )
        detector.assertionProvider = { assertions }

        XCTAssertNotNil(detector.checkOnce())
        detector.reset()
        XCTAssertNotNil(detector.checkOnce())
    }
}
