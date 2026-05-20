@testable import MeetingTranscriber
import XCTest

@MainActor
final class MenuBarIconTests: XCTestCase {
    // MARK: - Non-template contract (all images colored, isTemplate = false)

    func testAllBadgeKindsAreNonTemplate() {
        for badge in BadgeKind.allCases {
            let image = MenuBarIcon.image(badge: badge)
            XCTAssertFalse(
                image.isTemplate,
                "Badge \(badge) must be non-template (colored design)"
            )
        }
    }

    func testAllAnimationFramesAreNonTemplate() {
        let animatedBadges: [BadgeKind] = [.recording, .transcribing, .diarizing, .processing]
        for badge in animatedBadges {
            for frame in 0 ..< MenuBarIcon.frameCount {
                let image = MenuBarIcon.image(badge: badge, animationFrame: frame)
                XCTAssertFalse(
                    image.isTemplate,
                    "\(badge) frame \(frame) must be non-template"
                )
            }
        }
    }

    func testRecordOnlyOverlayIsNonTemplate() {
        for badge in BadgeKind.allCases {
            let image = MenuBarIcon.image(badge: badge, recordOnlyOverlay: true)
            XCTAssertFalse(
                image.isTemplate,
                "record-only overlay must be non-template for \(badge)"
            )
        }
    }

    func testPermissionOverlayIsNonTemplate() {
        for badge in BadgeKind.allCases {
            let image = MenuBarIcon.image(badge: badge, animationFrame: 0, permissionOverlay: true)
            XCTAssertFalse(image.isTemplate, "permission overlay on \(badge) should be non-template")
        }
    }

    func testMicSilentOverlayIsNonTemplate() {
        for badge in BadgeKind.allCases {
            let image = MenuBarIcon.image(badge: badge, micSilentOverlay: true)
            XCTAssertFalse(image.isTemplate, "mic-silent overlay must be non-template for \(badge)")
        }
    }

    func testAppSilentOverlayIsNonTemplate() {
        for badge in BadgeKind.allCases {
            let image = MenuBarIcon.image(badge: badge, appSilentOverlay: true)
            XCTAssertFalse(image.isTemplate, "app-silent overlay must be non-template for \(badge)")
        }
    }

    // MARK: - Image size

    func testImageSizeIs18x18() {
        let image = MenuBarIcon.image(badge: .inactive)
        XCTAssertEqual(image.size.width, 18, accuracy: 0.01)
        XCTAssertEqual(image.size.height, 18, accuracy: 0.01)
    }

    func testAllBadgeKindsProduceCorrectSize() {
        for badge in BadgeKind.allCases {
            let image = MenuBarIcon.image(badge: badge)
            XCTAssertEqual(image.size.width, 18, accuracy: 0.01, "Badge \(badge) width")
            XCTAssertEqual(image.size.height, 18, accuracy: 0.01, "Badge \(badge) height")
        }
    }

    // MARK: - Animation contracts

    func testAnimatedBadgeKinds() {
        XCTAssertTrue(BadgeKind.recording.isAnimated)
        XCTAssertTrue(BadgeKind.transcribing.isAnimated)
        XCTAssertTrue(BadgeKind.diarizing.isAnimated)
        XCTAssertTrue(BadgeKind.processing.isAnimated)
        XCTAssertFalse(BadgeKind.inactive.isAnimated)
        XCTAssertFalse(BadgeKind.done.isAnimated)
        XCTAssertFalse(BadgeKind.error.isAnimated)
        XCTAssertFalse(BadgeKind.userAction.isAnimated)
        XCTAssertFalse(BadgeKind.updateAvailable.isAnimated)
    }

    func testStaticBadgesProduceIdenticalImagesAcrossFrames() {
        let staticBadges: [BadgeKind] = [.inactive, .userAction, .done, .error, .updateAvailable]
        for badge in staticBadges {
            let frame0 = MenuBarIcon.image(badge: badge, animationFrame: 0)
            let frame3 = MenuBarIcon.image(badge: badge, animationFrame: 3)
            XCTAssertEqual(
                frame0.tiffRepresentation,
                frame3.tiffRepresentation,
                "Static badge \(badge) should render identically across frames"
            )
        }
    }

    func testRecordOnlyOverlayDoesNotAnimateStaticBadges() {
        let staticBadges: [BadgeKind] = [.inactive, .userAction, .done, .error, .updateAvailable]
        for badge in staticBadges {
            let frame0 = MenuBarIcon.image(badge: badge, animationFrame: 0, recordOnlyOverlay: true)
            let frame3 = MenuBarIcon.image(badge: badge, animationFrame: 3, recordOnlyOverlay: true)
            XCTAssertEqual(
                frame0.tiffRepresentation,
                frame3.tiffRepresentation,
                "Static badge \(badge) should render identically across frames under recordOnlyOverlay"
            )
        }
    }

    func testRecordOnlyOverlayKeepsAnimatedBadgesAnimating() {
        let animatedBadges: [BadgeKind] = [.recording, .transcribing, .diarizing, .processing]
        for badge in animatedBadges {
            let frame0 = MenuBarIcon.image(badge: badge, animationFrame: 0, recordOnlyOverlay: true)
            let frame3 = MenuBarIcon.image(badge: badge, animationFrame: 3, recordOnlyOverlay: true)
            XCTAssertNotEqual(
                frame0.tiffRepresentation,
                frame3.tiffRepresentation,
                "Animated badge \(badge) should advance under recordOnlyOverlay"
            )
        }
    }

    func testAnimationFrameWrapsAroundFrameCount() {
        let badge = BadgeKind.recording
        let normal = MenuBarIcon.image(badge: badge, animationFrame: 2)
        let wrapped = MenuBarIcon.image(badge: badge, animationFrame: 2 + MenuBarIcon.frameCount)
        XCTAssertEqual(normal.size, wrapped.size)
        XCTAssertFalse(normal.isTemplate)
        XCTAssertFalse(wrapped.isTemplate)
    }

    func testLargeAnimationFrameDoesNotCrash() {
        for badge in BadgeKind.allCases where badge.isAnimated {
            let image = MenuBarIcon.image(badge: badge, animationFrame: 999)
            XCTAssertFalse(image.isTemplate, "Large frame index should wrap safely for \(badge)")
        }
    }

    // MARK: - Per-channel silence overlays

    func testMicAndAppSilentRenderDistinctImages() {
        let micRed = MenuBarIcon.image(badge: .recording, animationFrame: 0, micSilentOverlay: true)
        let appRed = MenuBarIcon.image(badge: .recording, animationFrame: 0, appSilentOverlay: true)
        let bothRed = MenuBarIcon.image(
            badge: .recording, animationFrame: 0, micSilentOverlay: true, appSilentOverlay: true
        )
        let normal = MenuBarIcon.image(badge: .recording, animationFrame: 0)
        XCTAssertNotEqual(micRed.tiffRepresentation, normal.tiffRepresentation)
        XCTAssertNotEqual(appRed.tiffRepresentation, normal.tiffRepresentation)
        XCTAssertNotEqual(
            micRed.tiffRepresentation, appRed.tiffRepresentation,
            "top-half and bottom-half tint must differ"
        )
        XCTAssertNotEqual(bothRed.tiffRepresentation, micRed.tiffRepresentation)
        XCTAssertNotEqual(bothRed.tiffRepresentation, appRed.tiffRepresentation)
    }

    // MARK: - Heartbeat-specific rendering tests

    func testHeartbeatInactiveRendersNonEmpty() {
        let image = MenuBarIcon.image(badge: .inactive)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            XCTFail("Could not get bitmap for inactive badge")
            return
        }
        var hasOpaquePx = false
        outer: for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                let color = bitmap.colorAt(x: x, y: y)
                if (color?.alphaComponent ?? 0) > 0.05 {
                    hasOpaquePx = true
                    break outer
                }
            }
        }
        XCTAssertTrue(hasOpaquePx, "Inactive heartbeat icon must contain visible pixels")
    }

    func testRecordingPulseFramesDifferAcrossAnimation() {
        let frame0 = MenuBarIcon.image(badge: .recording, animationFrame: 0)
        let frame3 = MenuBarIcon.image(badge: .recording, animationFrame: 3)
        XCTAssertNotEqual(
            frame0.tiffRepresentation,
            frame3.tiffRepresentation,
            "Recording pulse frames 0 and 3 should differ (different pulse opacity)"
        )
    }

    func testSpinnerFramesDifferForTranscribing() {
        let f0 = MenuBarIcon.image(badge: .transcribing, animationFrame: 0)
        let f1 = MenuBarIcon.image(badge: .transcribing, animationFrame: 1)
        XCTAssertNotEqual(
            f0.tiffRepresentation,
            f1.tiffRepresentation,
            "Transcribing spinner frames 0 and 1 should differ"
        )
    }

    func testSpinnerFramesDifferForDiarizing() {
        let f0 = MenuBarIcon.image(badge: .diarizing, animationFrame: 0)
        let f2 = MenuBarIcon.image(badge: .diarizing, animationFrame: 2)
        XCTAssertNotEqual(
            f0.tiffRepresentation,
            f2.tiffRepresentation,
            "Diarizing spinner frames 0 and 2 should differ"
        )
    }

    func testSpinnerFramesDifferForProcessing() {
        let f0 = MenuBarIcon.image(badge: .processing, animationFrame: 0)
        let f1 = MenuBarIcon.image(badge: .processing, animationFrame: 1)
        XCTAssertNotEqual(
            f0.tiffRepresentation,
            f1.tiffRepresentation,
            "Processing spinner frames 0 and 1 should differ"
        )
    }

    func testErrorBadgeIsNonTemplate() {
        let image = MenuBarIcon.image(badge: .error)
        XCTAssertFalse(image.isTemplate, ".error badge must be non-template (red ring visible)")
    }

    func testColorConstantsExposed() {
        XCTAssertEqual(MenuBarIcon.spaceIndigo.alphaComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(MenuBarIcon.peachGlow.alphaComponent, 1.0, accuracy: 0.01)
    }

    func testRecordOnlyDotPositionIsBottomLeft() {
        let image = MenuBarIcon.image(badge: .inactive, recordOnlyOverlay: true)
        XCTAssertFalse(image.isTemplate)
        XCTAssertNotNil(image.tiffRepresentation)
    }

    func testPermissionOverlayDefaultsToFalse() {
        let withoutParam = MenuBarIcon.image(badge: .recording, animationFrame: 0)
        let explicitFalse = MenuBarIcon.image(badge: .recording, animationFrame: 0, permissionOverlay: false)
        XCTAssertEqual(withoutParam.tiffRepresentation, explicitFalse.tiffRepresentation)
    }

    // MARK: - BadgeKind.compute() — unchanged logic, preserved tests

    func testCompute_watchLoopRecording_returnsRecording() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .recording,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .recording)
    }

    func testCompute_watchLoopRecording_priorityOverTranscriberState() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .recording,
            transcriberState: .transcribing,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .recording)
    }

    func testCompute_waitingForSpeakerCount_returnsUserAction() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .waitingForSpeakerCount,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .userAction)
    }

    func testCompute_waitingForSpeakerNames_returnsUserAction() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .waitingForSpeakerNames,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .userAction)
    }

    func testCompute_protocolReady_returnsDone() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .protocolReady,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .done)
    }

    func testCompute_transcriberError_returnsError() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .error,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .error)
    }

    func testCompute_transcriberTranscribing_returnsTranscribing() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .transcribing,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .transcribing)
    }

    func testCompute_recordingDone_returnsTranscribing() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .recordingDone,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .transcribing)
    }

    func testCompute_generatingProtocol_returnsProcessing() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .generatingProtocol,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .processing)
    }

    func testCompute_activeJobTranscribing_returnsTranscribing() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .transcribing,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .transcribing)
    }

    func testCompute_activeJobDiarizing_returnsDiarizing() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .diarizing,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .diarizing)
    }

    func testCompute_activeJobGeneratingProtocol_returnsProcessing() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .generatingProtocol,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .processing)
    }

    func testCompute_activeJobWaiting_returnsProcessing() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .waiting,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .processing)
    }

    func testCompute_activeJobDone_returnsProcessing() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .done,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .processing)
    }

    func testCompute_activeJobError_returnsProcessing() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .error,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .processing)
    }

    func testCompute_updateAvailable_returnsUpdateAvailable() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: true,
        )
        XCTAssertEqual(result, .updateAvailable)
    }

    func testCompute_allIdle_returnsInactive() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .inactive)
    }

    func testCompute_watchLoopActiveIdleTranscriber_returnsInactive() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .inactive)
    }

    func testCompute_activeJob_priorityOverUpdateAvailable() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: .transcribing,
            updateAvailable: true,
        )
        XCTAssertEqual(result, .transcribing)
    }

    func testCompute_watchLoopRecording_priorityOverActiveJobAndUpdate() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .recording,
            transcriberState: .idle,
            activeJobState: .transcribing,
            updateAvailable: true,
        )
        XCTAssertEqual(result, .recording)
    }

    func testCompute_watchLoopActiveWatchingState_fallsThroughToInactive() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .watching,
            transcriberState: .watching,
            activeJobState: nil,
            updateAvailable: false,
        )
        XCTAssertEqual(result, .inactive)
    }

    func testCompute_permissionBroken_returnsError() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: false,
            permissionProblem: true,
        )
        XCTAssertEqual(result, .error)
    }

    func testCompute_recordingOverridesPermissionProblem() {
        let result = BadgeKind.compute(
            watchLoopActive: true,
            watchLoopState: .recording,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: false,
            permissionProblem: true,
        )
        XCTAssertEqual(result, .recording)
    }

    func testCompute_permissionProblemOverridesUpdate() {
        let result = BadgeKind.compute(
            watchLoopActive: false,
            watchLoopState: .idle,
            transcriberState: .idle,
            activeJobState: nil,
            updateAvailable: true,
            permissionProblem: true,
        )
        XCTAssertEqual(result, .error)
    }
}
