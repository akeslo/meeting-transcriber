@testable import MeetingTranscriber

// swiftlint:disable file_length
import ViewInspector
import XCTest

@MainActor
// swiftlint:disable:next attributes type_body_length
final class MenuBarViewTests: XCTestCase {
    // MARK: - Helpers

    private func makeStatus(
        state: TranscriberState = .idle,
        detail: String = "",
        meeting: MeetingInfo? = nil,
        protocolPath: String? = nil,
        error: String? = nil,
    ) -> TranscriberStatus {
        TranscriberStatus(
            version: 1,
            timestamp: "2024-01-01T00:00:00",
            state: state,
            detail: detail,
            meeting: meeting,
            protocolPath: protocolPath,
            error: error,
            audioPath: nil,
            pid: nil,
        )
    }

    private func makeView(
        status: TranscriberStatus? = nil,
        isWatching: Bool = false,
        isModelReady: Bool = true,
        updateChecker: UpdateChecker? = nil,
        onNameSpeakers: (() -> Void)? = nil,
        onStopManualRecording: (() -> Void)? = nil,
    ) -> MenuBarView {
        MenuBarView(
            status: status,
            isWatching: isWatching,
            isModelReady: isModelReady,
            updateChecker: updateChecker,
            onStartStop: {},
            onRecordApp: {},
            onStopManualRecording: onStopManualRecording,
            onOpenOutputFolder: {},
            onOpenDashboard: {},
            onOpenSettings: {},
            onNameSpeakers: onNameSpeakers,
            onProcessFiles: {},
            onQuit: {},
        )
    }

    // MARK: - Start/Stop button

    func testIdleShowsStartWatching() throws {
        let sut = makeView(status: makeStatus(state: .idle), isWatching: false)
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Start Watching"))
    }

    func testWatchingShowsStopWatching() throws {
        let sut = makeView(status: makeStatus(state: .watching), isWatching: true)
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Stop Watching"))
    }

    // MARK: - Meeting info

    func testMeetingInfoShownWhenRecording() throws {
        let meeting = MeetingInfo(app: "Teams", title: "Standup", pid: 123)
        let sut = makeView(status: makeStatus(state: .recording, meeting: meeting))
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Standup"))
    }

    func testMeetingInfoHiddenWhenIdle() throws {
        let sut = makeView(status: makeStatus(state: .idle))
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Standup"))
    }

    // MARK: - Error display

    func testErrorShownWhenErrorState() throws {
        let sut = makeView(status: makeStatus(state: .error, error: "Python crashed"))
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Python crashed"))
    }

    func testErrorHiddenWhenNotErrorState() throws {
        let sut = makeView(status: makeStatus(state: .recording, error: "stale error"))
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "stale error"))
    }

    // MARK: - Name Speakers button

    func testNameSpeakersButtonShownWhenWaiting() throws {
        // swiftlint:disable:next trailing_closure
        let sut = makeView(status: makeStatus(state: .waitingForSpeakerNames), onNameSpeakers: {})
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Name Now →"))
    }

    func testNameSpeakersButtonHiddenWhenIdle() throws {
        let sut = makeView(status: makeStatus(state: .idle))
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Name Now →"))
    }

    func testNameSpeakersButtonCallsCallback() throws {
        var called = false
        let sut = MenuBarView(
            status: makeStatus(state: .waitingForSpeakerNames),
            isWatching: false,
            isModelReady: true,
            updateChecker: nil,
            onStartStop: {},
            onRecordApp: {},
            onStopManualRecording: nil,
            onOpenOutputFolder: {},
            onOpenDashboard: {},
            onOpenSettings: {},
            onNameSpeakers: { called = true },
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        try body.find(button: "Name Now →").tap()
        XCTAssertTrue(called)
    }

    // MARK: - Detail text

    func testDetailShownWhenNonEmpty() throws {
        let sut = makeView(status: makeStatus(state: .watching, detail: "Checking Teams..."))
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Checking Teams..."))
    }

    func testDetailHiddenWhenEmpty() throws {
        let sut = makeView(status: makeStatus(state: .watching, detail: ""))
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Checking Teams..."))
    }

    // MARK: - Static buttons always present

    func testSettingsButtonExists() throws {
        let sut = makeView(status: makeStatus())
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Settings..."))
    }

    func testQuitButtonExists() throws {
        let sut = makeView(status: makeStatus())
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Quit"))
    }

    // MARK: - Button tap callbacks

    func testStartStopButtonCallsCallback() throws {
        var called = false
        let sut = MenuBarView(
            status: makeStatus(state: .idle),
            isWatching: false,
            isModelReady: true,
            updateChecker: nil,
            onStartStop: { called = true },
            onRecordApp: {},
            onStopManualRecording: nil,
            onOpenOutputFolder: {},
            onOpenDashboard: {},
            onOpenSettings: {},
            onNameSpeakers: nil,
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        try body.find(button: "Start Watching").tap()
        XCTAssertTrue(called)
    }

    func testQuitButtonCallsCallback() throws {
        var called = false
        let sut = MenuBarView(
            status: makeStatus(state: .idle),
            isWatching: false,
            isModelReady: true,
            updateChecker: nil,
            onStartStop: {},
            onRecordApp: {},
            onStopManualRecording: nil,
            onOpenOutputFolder: {},
            onOpenDashboard: {},
            onOpenSettings: {},
            onNameSpeakers: nil,
            onProcessFiles: {},
            onQuit: { called = true },
        )
        let body = try sut.inspect()
        try body.find(button: "Quit").tap()
        XCTAssertTrue(called)
    }

    func testSettingsButtonCallsCallback() throws {
        var called = false
        let sut = MenuBarView(
            status: makeStatus(state: .idle),
            isWatching: false,
            isModelReady: true,
            updateChecker: nil,
            onStartStop: {},
            onRecordApp: {},
            onStopManualRecording: nil,
            onOpenOutputFolder: {},
            onOpenDashboard: {},
            onOpenSettings: { called = true },
            onNameSpeakers: nil,
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        try body.find(button: "Settings...").tap()
        XCTAssertTrue(called)
    }

    // MARK: - State label

    func testNilStatusShowsIdleLabel() throws {
        let sut = makeView(status: nil)
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Idle"))
    }

    func testMeetingTitleShownWhenRecording() throws {
        let meeting = MeetingInfo(app: "Zoom", title: "Retro", pid: 456)
        let sut = makeView(status: makeStatus(state: .recording, meeting: meeting))
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Retro"), "Meeting title should appear in Zone 1")
    }

    // MARK: - Record App button

    func testRecordAppButtonExistsWhenIdle() throws {
        let sut = makeView(status: makeStatus(state: .idle))
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Record App..."))
    }

    func testRecordAppButtonHiddenDuringRecording() throws {
        let sut = makeView(status: makeStatus(state: .recording))
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Record App..."))
    }

    func testRecordAppButtonCallsCallback() throws {
        var called = false
        let sut = MenuBarView(
            status: makeStatus(state: .idle),
            isWatching: false,
            isModelReady: true,
            updateChecker: nil,
            onStartStop: {},
            onRecordApp: { called = true },
            onStopManualRecording: nil,
            onOpenOutputFolder: {},
            onOpenDashboard: {},
            onOpenSettings: {},
            onNameSpeakers: nil,
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        try body.find(button: "Record App...").tap()
        XCTAssertTrue(called)
    }

    // MARK: - Stop Recording button (manual)

    func testStopRecordingButtonVisibleDuringManualRecording() throws {
        // swiftlint:disable:next trailing_closure
        let sut = makeView(status: makeStatus(state: .recording), onStopManualRecording: {})
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Stop Recording"))
    }

    func testStopRecordingButtonHiddenWhenNoManualRecording() throws {
        let sut = makeView(status: makeStatus(state: .recording))
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Stop Recording"))
    }

    func testStopRecordingButtonCallsCallback() throws {
        var called = false
        let sut = MenuBarView(
            status: makeStatus(state: .recording),
            isWatching: false,
            isModelReady: true,
            updateChecker: nil,
            onStartStop: {},
            onRecordApp: {},
            onStopManualRecording: { called = true },
            onOpenOutputFolder: {},
            onOpenDashboard: {},
            onOpenSettings: {},
            onNameSpeakers: nil,
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        try body.find(button: "Stop Recording").tap()
        XCTAssertTrue(called)
    }

    // MARK: - Update indicator

    func testUpdateIndicatorShownWhenUpdateAvailable() throws {
        let checker = UpdateChecker(provider: MockUpdateProvider())
        checker.availableUpdate = try ReleaseInfo(
            tagName: "v1.0.0",
            name: "Release v1.0.0",
            prerelease: false,
            htmlURL: XCTUnwrap(URL(string: "https://github.com/pasrom/meeting-transcriber/releases/tag/v1.0.0")),
            dmgURL: URL(string: "https://example.com/app.dmg"),
        )

        let sut = makeView(status: makeStatus(), updateChecker: checker)
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Update Available: v1.0.0"))
    }

    func testUpdateIndicatorHiddenWhenNoUpdate() throws {
        let checker = UpdateChecker(provider: MockUpdateProvider())

        let sut = makeView(status: makeStatus(), updateChecker: checker)
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Update Available:"))
    }

    func testUpdateIndicatorHiddenWhenNoChecker() throws {
        let sut = makeView(status: makeStatus())
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Update Available:"))
    }

    // MARK: - Process Files button

    func testProcessFilesButtonAlwaysExists() throws {
        let sut = makeView(status: makeStatus(state: .idle))
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Process Audio/Video Files..."))
    }

    func testProcessFilesButtonCallsCallback() throws {
        var called = false
        let sut = MenuBarView(
            status: makeStatus(),
            isWatching: false,
            isModelReady: true,
            updateChecker: nil,
            onStartStop: {},
            onRecordApp: {},
            onStopManualRecording: nil,
            onOpenOutputFolder: {},
            onOpenDashboard: {},
            onOpenSettings: {},
            onNameSpeakers: nil,
            onProcessFiles: { called = true },
            onQuit: {},
        )
        let body = try sut.inspect()
        try body.find(button: "Process Audio/Video Files...").tap()
        XCTAssertTrue(called)
    }

    // MARK: - Record/Stop button mutual exclusion

    func testRecordAppAndStopBothHiddenDuringAutoRecording() throws {
        let sut = makeView(status: makeStatus(state: .recording), onStopManualRecording: nil)
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Record App..."))
        XCTAssertThrowsError(try body.find(text: "Stop Recording"))
    }

    func testStopRecordingReplacesRecordAppButton() throws {
        // swiftlint:disable:next trailing_closure
        let sut = makeView(status: makeStatus(state: .idle), onStopManualRecording: {})
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Stop Recording"))
        XCTAssertThrowsError(try body.find(text: "Record App..."))
    }

    // MARK: - All state labels shown

    func testAllTranscriberStateLabelsRendered() throws {
        let states: [TranscriberState] = [
            .idle, .watching, .recording, .transcribing,
            .generatingProtocol, .protocolReady, .error,
        ]
        for state in states {
            let sut = makeView(status: makeStatus(state: state))
            let body = try sut.inspect()
            XCTAssertNoThrow(
                try body.find(text: state.label),
                "State label '\(state.label)' not found for \(state)",
            )
        }
    }

    // MARK: - Open Output Folder + Dashboard

    func testOpenOutputFolderButtonExists() throws {
        let sut = makeView(status: makeStatus())
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Open Output Folder"))
    }

    func testOpenDashboardButtonExists() throws {
        let sut = makeView(status: makeStatus())
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Open Dashboard"))
    }

    func testOpenOutputFolderButtonCallsCallback() throws {
        var called = false
        let sut = MenuBarView(
            status: makeStatus(),
            isWatching: false,
            isModelReady: true,
            updateChecker: nil,
            onStartStop: {},
            onRecordApp: {},
            onStopManualRecording: nil,
            onOpenOutputFolder: { called = true },
            onOpenDashboard: {},
            onOpenSettings: {},
            onNameSpeakers: nil,
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        try body.find(button: "Open Output Folder").tap()
        XCTAssertTrue(called)
    }

    func testOpenDashboardButtonCallsCallback() throws {
        var called = false
        let sut = MenuBarView(
            status: makeStatus(),
            isWatching: false,
            isModelReady: true,
            updateChecker: nil,
            onStartStop: {},
            onRecordApp: {},
            onStopManualRecording: nil,
            onOpenOutputFolder: {},
            onOpenDashboard: { called = true },
            onOpenSettings: {},
            onNameSpeakers: nil,
            onProcessFiles: {},
            onQuit: {},
        )
        let body = try sut.inspect()
        try body.find(button: "Open Dashboard").tap()
        XCTAssertTrue(called)
    }

    // MARK: - Model-not-ready warning

    func testModelNotReadyWarningShownWhenNotReady() throws {
        let sut = makeView(status: makeStatus(), isModelReady: false)
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Model not loaded"))
    }

    func testModelNotReadyWarningHiddenWhenReady() throws {
        let sut = makeView(status: makeStatus(), isModelReady: true)
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Model not loaded"))
    }

    // MARK: - User-action banner

    func testUserActionBannerShownWhenWaitingForSpeakerNames() throws {
        // swiftlint:disable:next trailing_closure
        let sut = makeView(status: makeStatus(state: .waitingForSpeakerNames), onNameSpeakers: {})
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Speakers need names"))
        XCTAssertNoThrow(try body.find(text: "Name Now →"))
    }

    func testUserActionBannerShownWhenWaitingForSpeakerCount() throws {
        // swiftlint:disable:next trailing_closure
        let sut = makeView(status: makeStatus(state: .waitingForSpeakerCount), onNameSpeakers: {})
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Speakers need names"))
    }

    func testUserActionBannerHiddenWhenNoCallback() throws {
        let sut = makeView(status: makeStatus(state: .waitingForSpeakerNames), onNameSpeakers: nil)
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Speakers need names"))
    }
}
