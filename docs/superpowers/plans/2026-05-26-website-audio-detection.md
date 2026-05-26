# Website Audio Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate website-detected meetings on audio activity (no recording until browser audio appears) and stop recording when audio stays silent for `asymmetricSilenceWarningSeconds`.

**Architecture:** Two new `DetectedMeeting` flags (`audioConfirmRequired`, `audioSilenceStopEnabled`) opt browser-tab meetings into (1) a `waitForAudioConfirm` phase in `WatchLoop.handleMeeting` that discards if no audio within 60s, and (2) an `AudioSilencePolicy` pure type driving a silence-stop check in `waitForMeetingEnd`. All app-detected meetings leave both flags `false` — zero behaviour change.

**Tech Stack:** Swift 6, XCTest, SPM. No new dependencies. Uses existing `TestClock`/`MockRecorder` test infrastructure.

---

## Pre-existing test failures

`WatchLoopTitlePromptTests.swift` has unrelated compile errors before this change. Run `swift test --filter <SuiteName>` to target specific suites and avoid them.

## File Map

**New:**
- `Sources/AudioSilencePolicy.swift` — pure silence-stop state machine
- `Tests/AudioSilencePolicyTests.swift` — unit tests for AudioSilencePolicy
- `Tests/BrowserTabDetectorTests.swift` — unit tests for BrowserTabDetector audio flags
- `Tests/WatchLoopAudioConfirmTests.swift` — tests for audio-confirm phase

**Modified:**
- `Sources/MeetingDetecting.swift` — add `audioConfirmRequired`, `audioSilenceStopEnabled` to `DetectedMeeting`
- `Sources/DualSourceRecorder.swift` — add `discard()` to `RecordingProvider` protocol and implement in `DualSourceRecorder`
- `Sources/BrowserTabDetector.swift` — set both new flags on returned `DetectedMeeting`
- `Sources/WatchLoop.swift` — add `audioConfirmTimeout`/`silenceStopSecondsProvider` params, `waitForAudioConfirm`, update `handleMeeting` and `waitForMeetingEnd`
- `Sources/AppState.swift` — wire `silenceStopSecondsProvider` closure
- `Tests/TestHelpers.swift` — add `discardCalled: Bool` and `discard()` to `MockRecorder`

---

### Task 1: Add `discard()` to `RecordingProvider`, implement in `DualSourceRecorder` and `MockRecorder`

**Files:**
- Modify: `Sources/DualSourceRecorder.swift`
- Modify: `Tests/TestHelpers.swift`

- [ ] **Step 1: Add `discard()` to the `RecordingProvider` protocol**

In `Sources/DualSourceRecorder.swift`, find `protocol RecordingProvider` and add after `func stop() throws -> RecordingResult`:

```swift
/// Stop capture and delete all temp files without producing a `RecordingResult`.
/// Called when audio-confirm fails and the partial recording should be discarded.
func discard()
```

Then in the `extension RecordingProvider` block (the one with `appLevelDBFS`/`micLevelDBFS` defaults), add:

```swift
func discard() {}
```

- [ ] **Step 2: Implement `discard()` in `DualSourceRecorder`**

In `Sources/DualSourceRecorder.swift`, add the following method inside `class DualSourceRecorder`, after the `stop()` method:

```swift
func discard() {
    guard isRecording else { return }
    guard #available(macOS 14.2, *) else {
        isRecording = false
        startTimestamp = nil
        return
    }
    isRecording = false
    startTimestamp = nil
    guard let session = captureSession else { return }
    let result = session.stop()
    captureSession = nil
    try? FileManager.default.removeItem(at: result.appAudioFileURL)
    if let micURL = result.micAudioFileURL {
        try? FileManager.default.removeItem(at: micURL)
    }
    logger.info("Recording discarded — temp files removed")
}
```

- [ ] **Step 3: Add `discardCalled` and `discard()` to `MockRecorder` in `Tests/TestHelpers.swift`**

Find `class MockRecorder: RecordingProvider` and add:

```swift
var discardCalled = false
```

Add the method inside the class body:

```swift
func discard() {
    discardCalled = true
}
```

- [ ] **Step 4: Build**

```bash
swift build
```
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/DualSourceRecorder.swift Tests/TestHelpers.swift
git commit -m "feat: add discard() to RecordingProvider for audio-confirm abort path"
```

---

### Task 2: Add `audioConfirmRequired`/`audioSilenceStopEnabled` to `DetectedMeeting` and update `BrowserTabDetector`

**Files:**
- Modify: `Sources/MeetingDetecting.swift`
- Modify: `Sources/BrowserTabDetector.swift`
- Create: `Tests/BrowserTabDetectorTests.swift`

- [ ] **Step 1: Add two fields to `DetectedMeeting`**

In `Sources/MeetingDetecting.swift`, find `struct DetectedMeeting` and add after `let noMicOverride: Bool?`:

```swift
/// When true, WatchLoop runs an audio-confirm phase after starting the recorder.
/// Set by BrowserTabDetector; false for all app-based detectors.
let audioConfirmRequired: Bool
/// When true, waitForMeetingEnd also stops when audio is silent for
/// silenceStopSecondsProvider() seconds. Set by BrowserTabDetector.
let audioSilenceStopEnabled: Bool
```

- [ ] **Step 2: Update the `DetectedMeeting` initializer to include both new fields with defaults**

Replace the existing `init(` with:

```swift
init(
    pattern: AppMeetingPattern,
    windowTitle: String,
    ownerName: String,
    windowPID: pid_t,
    detectedAt: Date = Date(),
    noMicOverride: Bool? = nil,
    audioConfirmRequired: Bool = false,
    audioSilenceStopEnabled: Bool = false,
) {
    self.pattern = pattern
    self.windowTitle = windowTitle
    self.ownerName = ownerName
    self.windowPID = windowPID
    self.detectedAt = detectedAt
    self.noMicOverride = noMicOverride
    self.audioConfirmRequired = audioConfirmRequired
    self.audioSilenceStopEnabled = audioSilenceStopEnabled
}
```

- [ ] **Step 3: Build — all existing call sites compile via defaults**

```bash
swift build
```
Expected: `Build complete!`

- [ ] **Step 4: Update `BrowserTabDetector` to set both new flags**

In `Sources/BrowserTabDetector.swift`, find `return DetectedMeeting(` inside `checkOnce()` and add the two new arguments:

```swift
return DetectedMeeting(
    pattern: pattern,
    windowTitle: site.name,
    ownerName: match.processName,
    windowPID: match.pid,
    noMicOverride: !site.recordMic,
    audioConfirmRequired: true,
    audioSilenceStopEnabled: true,
)
```

- [ ] **Step 5: Write `Tests/BrowserTabDetectorTests.swift`**

Create the file:

```swift
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
```

- [ ] **Step 6: Run `BrowserTabDetectorTests`**

```bash
swift test --filter BrowserTabDetectorTests
```
Expected: 6 tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/MeetingDetecting.swift Sources/BrowserTabDetector.swift Tests/BrowserTabDetectorTests.swift
git commit -m "feat: add audioConfirmRequired/audioSilenceStopEnabled to DetectedMeeting"
```

---

### Task 3: `AudioSilencePolicy` pure type

**Files:**
- Create: `Sources/AudioSilencePolicy.swift`
- Create: `Tests/AudioSilencePolicyTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/AudioSilencePolicyTests.swift`:

```swift
@testable import MeetingTranscriber
import XCTest

final class AudioSilencePolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testDisabledNeverStops() {
        let r = AudioSilencePolicy.step(
            enabled: false, audioSilent: true,
            silenceStart: t0, silenceStopSeconds: 1, now: t0.addingTimeInterval(10),
        )
        XCTAssertFalse(r.stop)
    }

    func testZeroSecondsNeverStops() {
        let r = AudioSilencePolicy.step(
            enabled: true, audioSilent: true,
            silenceStart: t0, silenceStopSeconds: 0, now: t0.addingTimeInterval(10),
        )
        XCTAssertFalse(r.stop)
    }

    func testAudioNotSilentClearsTimer() {
        let r = AudioSilencePolicy.step(
            enabled: true, audioSilent: false,
            silenceStart: t0, silenceStopSeconds: 10, now: t0.addingTimeInterval(5),
        )
        XCTAssertFalse(r.stop)
        XCTAssertNil(r.newSilenceStart)
    }

    func testSilenceBelowThresholdContinues() {
        let r = AudioSilencePolicy.step(
            enabled: true, audioSilent: true,
            silenceStart: t0, silenceStopSeconds: 10, now: t0.addingTimeInterval(5),
        )
        XCTAssertFalse(r.stop)
        XCTAssertEqual(r.newSilenceStart, t0)
    }

    func testSilenceAtExactThresholdStops() {
        let r = AudioSilencePolicy.step(
            enabled: true, audioSilent: true,
            silenceStart: t0, silenceStopSeconds: 10, now: t0.addingTimeInterval(10),
        )
        XCTAssertTrue(r.stop)
    }

    func testSilenceExceedsThresholdStops() {
        let r = AudioSilencePolicy.step(
            enabled: true, audioSilent: true,
            silenceStart: t0, silenceStopSeconds: 10, now: t0.addingTimeInterval(15),
        )
        XCTAssertTrue(r.stop)
    }

    func testNilSilenceStartInitialisedToNow() {
        let now = t0.addingTimeInterval(5)
        let r = AudioSilencePolicy.step(
            enabled: true, audioSilent: true,
            silenceStart: nil, silenceStopSeconds: 10, now: now,
        )
        XCTAssertFalse(r.stop)
        XCTAssertEqual(r.newSilenceStart, now)
    }

    func testAudioReturnResetsTimerAndPreventsStop() {
        // 5s of silence accumulates
        let r1 = AudioSilencePolicy.step(
            enabled: true, audioSilent: true,
            silenceStart: nil, silenceStopSeconds: 10, now: t0.addingTimeInterval(5),
        )
        XCTAssertNotNil(r1.newSilenceStart)

        // Audio returns — timer resets to nil
        let r2 = AudioSilencePolicy.step(
            enabled: true, audioSilent: false,
            silenceStart: r1.newSilenceStart, silenceStopSeconds: 10, now: t0.addingTimeInterval(9),
        )
        XCTAssertNil(r2.newSilenceStart)
        XCTAssertFalse(r2.stop)

        // Silence starts again from t0+9; 9s later (t0+18) is only 9s of new silence → no stop
        let r3 = AudioSilencePolicy.step(
            enabled: true, audioSilent: true,
            silenceStart: r2.newSilenceStart, silenceStopSeconds: 10, now: t0.addingTimeInterval(18),
        )
        XCTAssertFalse(r3.stop, "fresh silence epoch started at t0+9; only 9s elapsed, not 10")
    }
}
```

- [ ] **Step 2: Run to verify compile failure**

```bash
swift test --filter AudioSilencePolicyTests 2>&1 | head -5
```
Expected: compile error — `AudioSilencePolicy` not defined.

- [ ] **Step 3: Implement `AudioSilencePolicy`**

Create `Sources/AudioSilencePolicy.swift`:

```swift
import Foundation

/// Pure decision logic for audio-silence-based recording stop.
/// Separated from `WatchLoopEndPolicy` so the two stop conditions
/// (meeting gone vs. audio silent) are independently testable.
enum AudioSilencePolicy {
    /// Advance the silence-stop state machine one tick.
    ///
    /// - Parameters:
    ///   - enabled: When false, always returns `(false, nil)`.
    ///   - audioSilent: Whether the required channels are all below -60 dBFS.
    ///   - silenceStart: When the current silence episode began, or `nil`.
    ///   - silenceStopSeconds: Seconds of continuous silence before stop. `0` disables.
    ///   - now: Current clock time.
    /// - Returns: `stop` = true when the episode exceeds `silenceStopSeconds`.
    ///   `newSilenceStart` is the value the caller should carry into the next tick.
    static func step(
        enabled: Bool,
        audioSilent: Bool,
        silenceStart: Date?,
        silenceStopSeconds: TimeInterval,
        now: Date,
    ) -> (stop: Bool, newSilenceStart: Date?) {
        guard enabled, silenceStopSeconds > 0 else {
            return (stop: false, newSilenceStart: nil)
        }
        guard audioSilent else {
            return (stop: false, newSilenceStart: nil)
        }
        let start = silenceStart ?? now
        return (stop: now.timeIntervalSince(start) >= silenceStopSeconds, newSilenceStart: start)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter AudioSilencePolicyTests
```
Expected: 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AudioSilencePolicy.swift Tests/AudioSilencePolicyTests.swift
git commit -m "feat: add AudioSilencePolicy pure type for silence-stop logic"
```

---

### Task 4: Add `waitForAudioConfirm` to `WatchLoop`

**Files:**
- Modify: `Sources/WatchLoop.swift`
- Create: `Tests/WatchLoopAudioConfirmTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/WatchLoopAudioConfirmTests.swift`:

```swift
@testable import MeetingTranscriber
import XCTest

@MainActor
final class WatchLoopAudioConfirmTests: XCTestCase {
    // MARK: - Helpers

    private func makeActiveDetector(pid: pid_t = 1234) -> PowerAssertionDetector {
        let d = PowerAssertionDetector()
        d.assertionProvider = { [pid: [["Process Name": "zoom.us", "AssertName": "zoom"]]] }
        return d
    }

    private func makeInactiveDetector() -> PowerAssertionDetector {
        let d = PowerAssertionDetector()
        d.assertionProvider = { [:] }
        return d
    }

    private func makeMeeting(pid: pid_t = 1234, audioConfirmRequired: Bool = true) -> DetectedMeeting {
        DetectedMeeting(
            pattern: .zoom,
            windowTitle: "Zoom Meeting",
            ownerName: "zoom.us",
            windowPID: pid,
            audioConfirmRequired: audioConfirmRequired,
        )
    }

    // MARK: - waitForAudioConfirm

    func testConfirmReturnsTrueWhenAudioAboveThreshold() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.appLevelDBFS = -40  // audible
        let loop = WatchLoop(
            detector: makeActiveDetector(),
            recorderFactory: { recorder },
            pollInterval: 0.05,
            audioConfirmTimeout: 60,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
        )
        let confirmed = try await loop.waitForAudioConfirm(makeMeeting(), recorder: recorder)
        XCTAssertTrue(confirmed)
    }

    func testConfirmReturnsFalseOnTimeout() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.appLevelDBFS = -120  // silent
        let loop = WatchLoop(
            detector: makeActiveDetector(),
            recorderFactory: { recorder },
            pollInterval: 0.05,
            audioConfirmTimeout: 0.1,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
        )
        let confirmed = try await loop.waitForAudioConfirm(makeMeeting(), recorder: recorder)
        XCTAssertFalse(confirmed)
    }

    func testConfirmReturnsFalseWhenMeetingGoesInactive() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.appLevelDBFS = -120
        let loop = WatchLoop(
            detector: makeInactiveDetector(),
            recorderFactory: { recorder },
            pollInterval: 0.05,
            audioConfirmTimeout: 60,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
        )
        let confirmed = try await loop.waitForAudioConfirm(makeMeeting(), recorder: recorder)
        XCTAssertFalse(confirmed)
    }

    // MARK: - handleMeeting integration

    func testHandleMeetingDiscardsWhenConfirmFails() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.mixPath = URL(fileURLWithPath: "/tmp/test.wav")
        recorder.appLevelDBFS = -120  // silent → confirm fails
        let queue = PipelineQueue()
        let loop = WatchLoop(
            detector: makeInactiveDetector(),
            recorderFactory: { recorder },
            pipelineQueue: queue,
            pollInterval: 0.05,
            audioConfirmTimeout: 0.1,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
        )
        try await loop.handleMeeting(makeMeeting())
        XCTAssertTrue(recorder.discardCalled, "discard() must be called when audio confirm fails")
        XCTAssertFalse(recorder.stopCalled, "stop() must NOT be called on discard path")
        XCTAssertEqual(queue.jobs.count, 0, "no job enqueued when audio confirm fails")
        XCTAssertNil(loop.pendingTitle)
    }

    func testHandleMeetingProceedsWhenConfirmPasses() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.mixPath = URL(fileURLWithPath: "/tmp/test.wav")
        recorder.appLevelDBFS = -40  // audible → confirm passes
        let queue = PipelineQueue()
        let loop = WatchLoop(
            detector: makeInactiveDetector(),  // inactive → waitForMeetingEnd exits via grace
            recorderFactory: { recorder },
            pipelineQueue: queue,
            pollInterval: 0.05,
            endGracePeriod: 0.1,
            audioConfirmTimeout: 60,
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
        )
        try await loop.handleMeeting(makeMeeting())
        loop.skipTitle()
        XCTAssertFalse(recorder.discardCalled)
        XCTAssertTrue(recorder.stopCalled)
        XCTAssertEqual(queue.jobs.count, 1)
    }

    func testHandleMeetingSkipsConfirmWhenFlagFalse() async throws {
        let clock = TestClock()
        let recorder = MockRecorder()
        recorder.mixPath = URL(fileURLWithPath: "/tmp/test.wav")
        recorder.appLevelDBFS = -120  // silent — but confirm not required
        let queue = PipelineQueue()
        let loop = WatchLoop(
            detector: makeInactiveDetector(),
            recorderFactory: { recorder },
            pipelineQueue: queue,
            pollInterval: 0.05,
            endGracePeriod: 0.1,
            audioConfirmTimeout: 0.05,  // would fire immediately if used
            nowProvider: { clock.now },
            sleepProvider: { await clock.sleep(for: $0) },
        )
        try await loop.handleMeeting(makeMeeting(audioConfirmRequired: false))
        loop.skipTitle()
        XCTAssertFalse(recorder.discardCalled, "confirm phase must be skipped when flag is false")
        XCTAssertEqual(queue.jobs.count, 1)
    }
}
```

- [ ] **Step 2: Run to verify compile failure**

```bash
swift test --filter WatchLoopAudioConfirmTests 2>&1 | head -5
```
Expected: compile error — `audioConfirmTimeout` param and `waitForAudioConfirm` not defined.

- [ ] **Step 3: Add `audioConfirmTimeout` and `silenceStopSecondsProvider` stored properties to `WatchLoop`**

In `Sources/WatchLoop.swift`, add two properties in the stored-properties section after `pidAliveCheck`:

```swift
let audioConfirmTimeout: TimeInterval
/// Returns the silence-stop duration for audio-gated meetings.
/// Populated by AppState from `settings.asymmetricSilenceWarningSeconds`.
let silenceStopSecondsProvider: () -> TimeInterval
```

In `init(...)`, add after the `pidAliveCheck` parameter:

```swift
audioConfirmTimeout: TimeInterval = 60,
silenceStopSecondsProvider: @escaping () -> TimeInterval = { 0 },
```

In the `init` body, add:

```swift
self.audioConfirmTimeout = audioConfirmTimeout
self.silenceStopSecondsProvider = silenceStopSecondsProvider
```

- [ ] **Step 4: Add `waitForAudioConfirm` method**

In `Sources/WatchLoop.swift`, add the following after the closing brace of `waitForMeetingEnd`:

```swift
/// Audio-confirm phase for website-detected meetings.
///
/// Returns `true` as soon as `recorder.appLevelDBFS` exceeds -60 dBFS.
/// Returns `false` on timeout, tab-closed, or task cancellation.
func waitForAudioConfirm(_ meeting: DetectedMeeting, recorder: any RecordingProvider) async throws -> Bool {
    let deadline = nowProvider().addingTimeInterval(audioConfirmTimeout)
    while !Task.isCancelled {
        if recorder.appLevelDBFS > -60 {
            logger.info("audio_confirm_success meeting=\(meeting.pattern.appName, privacy: .public)")
            return true
        }
        if !detector.isMeetingActive(meeting) {
            logger.info("audio_confirm_tab_closed meeting=\(meeting.pattern.appName, privacy: .public)")
            return false
        }
        if nowProvider() >= deadline {
            logger.info("audio_confirm_timeout meeting=\(meeting.pattern.appName, privacy: .public) timeout=\(self.audioConfirmTimeout)")
            return false
        }
        try await sleepProvider(pollInterval)
    }
    return false
}
```

- [ ] **Step 5: Update `handleMeeting` to call the confirm phase**

In `Sources/WatchLoop.swift`, in `handleMeeting`, find `defer { activeRecorder = nil }` and add immediately after it:

```swift
// Audio-confirm phase: abort and discard if no browser audio within timeout
if meeting.audioConfirmRequired {
    let confirmed = try await waitForAudioConfirm(meeting, recorder: recorder)
    if !confirmed {
        recorder.discard()
        return
    }
}
```

- [ ] **Step 6: Run the new tests**

```bash
swift test --filter WatchLoopAudioConfirmTests
```
Expected: All 5 tests pass.

- [ ] **Step 7: Run existing WatchLoop suites for regressions**

```bash
swift test --filter "WatchLoopTests|WatchLoopMonitorTests|WatchLoopStateTests|WatchLoopEndPolicyTests|WatchLoopTimingTests"
```
Expected: All pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/WatchLoop.swift Tests/WatchLoopAudioConfirmTests.swift
git commit -m "feat: add audio-confirm phase to WatchLoop for website meetings"
```

---

### Task 5: Silence-stop in `waitForMeetingEnd`

**Files:**
- Modify: `Sources/WatchLoop.swift`
- Modify: `Tests/WatchLoopTimingTests.swift`

- [ ] **Step 1: Write failing tests**

In `Tests/WatchLoopTimingTests.swift`, add the following tests inside the `WatchLoopTimingTests` class after the existing tests:

```swift
// MARK: - Silence-stop

func testWaitForMeetingEndStopsOnAppAudioSilence_noMicRecording() async throws {
    // Meeting stays "active" via IOKit assertion, but silence-stop fires first.
    let detector = PowerAssertionDetector()
    detector.assertionProvider = {
        [1234: [["Process Name": "zoom.us", "AssertName": "Zoom video call active"]]]
    }
    let clock = TestClock()
    let recorder = MockRecorder()
    recorder.appLevelDBFS = -120  // silent
    let loop = WatchLoop(
        detector: detector,
        recorderFactory: { recorder },
        pollInterval: 0.05,
        maxDuration: 100,
        audioConfirmTimeout: 60,
        silenceStopSecondsProvider: { 0.15 },
        nowProvider: { clock.now },
        sleepProvider: { await clock.sleep(for: $0) },
    )
    let meeting = DetectedMeeting(
        pattern: .zoom,
        windowTitle: "Zoom Meeting",
        ownerName: "zoom.us",
        windowPID: 1234,
        noMicOverride: true,            // app audio only
        audioSilenceStopEnabled: true,
    )
    loop.activeRecorder = recorder
    let virtualStart = clock.now
    try await loop.waitForMeetingEnd(meeting)
    let elapsed = clock.now.timeIntervalSince(virtualStart)
    XCTAssertGreaterThanOrEqual(elapsed, 0.15, "should wait at least silenceStopSeconds")
    XCTAssertLessThan(elapsed, 100, "should stop before maxDuration")
}

func testWaitForMeetingEndStopsWhenBothChannelsSilent_micEnabled() async throws {
    let detector = PowerAssertionDetector()
    detector.assertionProvider = {
        [1234: [["Process Name": "zoom.us", "AssertName": "Zoom video call active"]]]
    }
    let clock = TestClock()
    let recorder = MockRecorder()
    recorder.appLevelDBFS = -120
    recorder.micLevelDBFS = -120
    let loop = WatchLoop(
        detector: detector,
        recorderFactory: { recorder },
        pollInterval: 0.05,
        maxDuration: 100,
        audioConfirmTimeout: 60,
        silenceStopSecondsProvider: { 0.15 },
        nowProvider: { clock.now },
        sleepProvider: { await clock.sleep(for: $0) },
    )
    let meeting = DetectedMeeting(
        pattern: .zoom,
        windowTitle: "Zoom Meeting",
        ownerName: "zoom.us",
        windowPID: 1234,
        noMicOverride: false,           // both channels required
        audioSilenceStopEnabled: true,
    )
    loop.activeRecorder = recorder
    let virtualStart = clock.now
    try await loop.waitForMeetingEnd(meeting)
    XCTAssertGreaterThanOrEqual(
        clock.now.timeIntervalSince(virtualStart), 0.15,
    )
}

func testSilenceStopDoesNotFireWhenOnlyOneChannelSilent_micEnabled() async throws {
    // App silent, mic audible, noMicOverride=false → both needed → should NOT silence-stop.
    // Meeting immediately inactive → exits via grace period instead.
    let detector = PowerAssertionDetector()
    detector.assertionProvider = { [:] }  // inactive → grace fires
    let clock = TestClock()
    let recorder = MockRecorder()
    recorder.appLevelDBFS = -120
    recorder.micLevelDBFS = -40   // audible mic
    let loop = WatchLoop(
        detector: detector,
        recorderFactory: { recorder },
        pollInterval: 0.05,
        endGracePeriod: 0.1,
        maxDuration: 100,
        audioConfirmTimeout: 60,
        silenceStopSecondsProvider: { 999 },  // very long — must not fire
        nowProvider: { clock.now },
        sleepProvider: { await clock.sleep(for: $0) },
    )
    let meeting = DetectedMeeting(
        pattern: .zoom,
        windowTitle: "Zoom Meeting",
        ownerName: "zoom.us",
        windowPID: 1234,
        noMicOverride: false,
        audioSilenceStopEnabled: true,
    )
    loop.activeRecorder = recorder
    let virtualStart = clock.now
    try await loop.waitForMeetingEnd(meeting)
    let elapsed = clock.now.timeIntervalSince(virtualStart)
    XCTAssertLessThan(elapsed, 1, "should stop via grace (0.1s), not silence-stop (999s)")
}

func testSilenceStopDisabledWhenFlagFalse() async throws {
    // audioSilenceStopEnabled=false → silence is ignored; stops via grace
    let detector = PowerAssertionDetector()
    detector.assertionProvider = { [:] }
    let clock = TestClock()
    let recorder = MockRecorder()
    recorder.appLevelDBFS = -120
    let loop = WatchLoop(
        detector: detector,
        recorderFactory: { recorder },
        pollInterval: 0.05,
        endGracePeriod: 0.1,
        maxDuration: 100,
        audioConfirmTimeout: 60,
        silenceStopSecondsProvider: { 0.01 },  // would fire instantly if enabled
        nowProvider: { clock.now },
        sleepProvider: { await clock.sleep(for: $0) },
    )
    let meeting = DetectedMeeting(
        pattern: .zoom,
        windowTitle: "Zoom Meeting",
        ownerName: "zoom.us",
        windowPID: 1234,
        audioSilenceStopEnabled: false,  // disabled
    )
    loop.activeRecorder = recorder
    try await loop.waitForMeetingEnd(meeting)
    XCTAssert(true, "completed without error")
}
```

- [ ] **Step 2: Run to verify failure**

```bash
swift test --filter WatchLoopTimingTests 2>&1 | grep "error:\|failed" | head -5
```
Expected: compile errors — `activeRecorder` setter not accessible (it is `private(set)`), `silenceStopSecondsProvider` not in init.

- [ ] **Step 3: Make `activeRecorder` writable (remove `private(set)`)**

In `Sources/WatchLoop.swift`, find:

```swift
private(set) var activeRecorder: (any RecordingProvider)?
```

Replace with:

```swift
var activeRecorder: (any RecordingProvider)?
```

`AppState` reads `watchLoop?.activeRecorder` at line 622 — this change is backward-compatible. `WatchLoop` internal writes continue working as before.

- [ ] **Step 4: Update `waitForMeetingEnd` to call `AudioSilencePolicy`**

In `Sources/WatchLoop.swift`, replace the entire body of `waitForMeetingEnd` with:

```swift
func waitForMeetingEnd(_ meeting: DetectedMeeting) async throws {
    var graceStart: Date?
    var silenceStart: Date?
    let startTime = nowProvider()
    let config = WatchLoopEndConfig(
        maxDuration: maxDuration,
        endGracePeriod: endGracePeriod,
    )

    while !Task.isCancelled {
        let decision = WatchLoopEndPolicy.step(
            config: config,
            now: nowProvider(),
            startTime: startTime,
            graceStart: graceStart,
            meetingActive: detector.isMeetingActive(meeting),
        )
        switch decision {
        case .stopMaxDurationExceeded:
            logger.info("Max recording duration reached (\(Int(self.maxDuration))s)")
            return

        case .stopGraceExpired:
            return

        case let .continuePolling(newGraceStart):
            graceStart = newGraceStart
        }

        if meeting.audioSilenceStopEnabled {
            let rec = activeRecorder
            let appSilent = (rec?.appLevelDBFS ?? -120) <= -60
            let micSilent = (rec?.micLevelDBFS ?? -120) <= -60
            let audioSilent = meeting.noMicOverride == true ? appSilent : (appSilent && micSilent)
            let result = AudioSilencePolicy.step(
                enabled: true,
                audioSilent: audioSilent,
                silenceStart: silenceStart,
                silenceStopSeconds: silenceStopSecondsProvider(),
                now: nowProvider(),
            )
            silenceStart = result.newSilenceStart
            if result.stop {
                logger.info("audio_silence_stop meeting=\(meeting.pattern.appName, privacy: .public)")
                return
            }
        }

        try await sleepProvider(pollInterval)
    }
}
```

- [ ] **Step 5: Run the new silence-stop tests**

```bash
swift test --filter WatchLoopTimingTests
```
Expected: All tests pass, including the 4 new silence-stop tests.

- [ ] **Step 6: Run full WatchLoop suite**

```bash
swift test --filter "WatchLoopTests|WatchLoopMonitorTests|WatchLoopStateTests|WatchLoopEndPolicyTests|WatchLoopTimingTests|WatchLoopAudioConfirmTests"
```
Expected: All pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/WatchLoop.swift Tests/WatchLoopTimingTests.swift
git commit -m "feat: add silence-stop to waitForMeetingEnd via AudioSilencePolicy"
```

---

### Task 6: Wire `AppState`

**Files:**
- Modify: `Sources/AppState.swift`

- [ ] **Step 1: Find the `WatchLoop(` construction in `AppState`**

In `Sources/AppState.swift`, search for `let loop = WatchLoop(` (around line 413). The call currently ends with:

```swift
notifier: notifier,
)
```

- [ ] **Step 2: Add `silenceStopSecondsProvider`**

Replace:

```swift
notifier: notifier,
)
```

With:

```swift
notifier: notifier,
silenceStopSecondsProvider: { [settings] in settings.asymmetricSilenceWarningSeconds },
)
```

- [ ] **Step 3: Build**

```bash
swift build
```
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/AppState.swift
git commit -m "feat: wire silenceStopSecondsProvider from settings into WatchLoop"
```

---

### Task 7: Final verification

- [ ] **Step 1: Run all owned test suites**

```bash
swift test --filter "AudioSilencePolicyTests|BrowserTabDetectorTests|WatchLoopAudioConfirmTests|WatchLoopTimingTests|WatchLoopTests|WatchLoopMonitorTests|WatchLoopStateTests|WatchLoopEndPolicyTests"
```
Expected: All pass.

- [ ] **Step 2: Full build**

```bash
swift build
```
Expected: `Build complete!`
