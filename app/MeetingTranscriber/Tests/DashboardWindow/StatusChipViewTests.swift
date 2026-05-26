import XCTest
@testable import MeetingTranscriber

@MainActor
final class StatusChipViewTests: XCTestCase {

    func test_chipColor_done_isGreen() {
        XCTAssertEqual(StatusChipView.chipColor(for: "done"), StatusChipView.ChipColor.green)
    }

    func test_chipColor_saved_isSlateGrey() {
        XCTAssertEqual(StatusChipView.chipColor(for: "saved"), StatusChipView.ChipColor.slateGrey)
    }

    func test_chipColor_transcribing_isPeachGlow() {
        XCTAssertEqual(StatusChipView.chipColor(for: "transcribing"), StatusChipView.ChipColor.peachGlow)
    }

    func test_chipColor_diarizing_isPeachGlow() {
        XCTAssertEqual(StatusChipView.chipColor(for: "diarizing"), StatusChipView.ChipColor.peachGlow)
    }

    func test_chipColor_waiting_isPeachGlow() {
        XCTAssertEqual(StatusChipView.chipColor(for: "waiting"), StatusChipView.ChipColor.peachGlow)
    }

    func test_chipColor_generatingProtocol_isPeachGlow() {
        XCTAssertEqual(StatusChipView.chipColor(for: "generatingProtocol"), StatusChipView.ChipColor.peachGlow)
    }

    func test_chipColor_error_isRed() {
        XCTAssertEqual(StatusChipView.chipColor(for: "error"), StatusChipView.ChipColor.red)
    }

    func test_chipColor_unknown_isSlateGrey() {
        XCTAssertEqual(StatusChipView.chipColor(for: "someUnknownStatus"), StatusChipView.ChipColor.slateGrey)
    }

    func test_chipLabel_done() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "done"), "Transcribed")
    }

    func test_chipLabel_transcribing() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "transcribing"), "Transcribing")
    }

    func test_chipLabel_diarizing() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "diarizing"), "Diarizing")
    }

    func test_chipLabel_waiting() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "waiting"), "Waiting")
    }

    func test_chipLabel_generatingProtocol() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "generatingProtocol"), "Summarizing")
    }

    func test_chipLabel_error() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "error"), "Error")
    }

    func test_chipLabel_saved() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "saved"), "Saved")
    }

    func test_chipLabel_unknown_capitalizesFirst() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "pending"), "Pending")
    }

    func test_chipLabel_summarized_isSingleWord() {
        XCTAssertEqual(StatusChipView.chipLabel(for: "summarized"), "Summarized")
        // Ensure no spaces that would force wrap in narrow containers
        XCTAssertFalse(StatusChipView.chipLabel(for: "summarized").contains(" "))
    }
}
