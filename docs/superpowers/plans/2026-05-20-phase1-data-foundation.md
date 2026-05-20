# Phase 1: Data Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the output folder to per-session directories, introduce a SwiftData job history store (`RecordingSession`), and wire `PipelineQueue`/`WatchLoop` to write the new structure on job completion.

**Architecture:** New pure-function `SessionFolder` enum handles folder naming. `RecordingSession` is the SwiftData model written at job completion/error/record-only. `PipelineQueue` and `WatchLoop` are updated to write all outputs into `<root>/recordings/<session-folder>/`. `RecordingFileSuffix` gains `transcript` and `protocol` constants. `AppPaths` gains `transcriberRoot` and `libraryStore`.

**Tech Stack:** Swift, SwiftData (macOS 14+), XCTest

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/SessionFolder.swift` | Pure slug + folder naming logic |
| Create | `Sources/RecordingSession.swift` | SwiftData `@Model` for job history |
| Create | `Sources/SessionMeta.swift` | v2 `meta.json` Codable writer (replaces `RecordingSidecar`) |
| Modify | `Sources/AppPaths.swift` | Add `transcriberRoot`, `libraryStore`, `defaultRecordingsDir` |
| Modify | `Sources/RecordingFileSuffix.swift` | Add `transcript = "transcript.md"`, `protocol = "protocol.md"`, rename audio constants |
| Modify | `Sources/PipelineQueue.swift` | Write all outputs to per-session folder; write `RecordingSession` on done/error |
| Modify | `Sources/WatchLoop.swift` | Record-only uses session folder + `SessionMeta` instead of `RecordingSidecar` |
| Modify | `Sources/AppSettings.swift` | `effectiveOutputDir` default → `AppPaths.transcriberRoot` |
| Create | `Tests/SessionFolderTests.swift` | Tests for slug and folder naming |
| Create | `Tests/SessionMetaTests.swift` | Tests for v2 JSON encode/decode |
| Create | `Tests/RecordingFileSuffixTests.swift` | Tests for updated suffix constants |

---

## Task 1: `SessionFolder` — slug and folder naming

**Files:**
- Create: `app/MeetingTranscriber/Sources/SessionFolder.swift`
- Create: `app/MeetingTranscriber/Tests/SessionFolderTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/SessionFolderTests.swift
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
        // Folder name is local-time formatted; just verify structure
        let name = SessionFolder.folderName(date: date, title: "Zoom Weekly")
        XCTAssertTrue(name.hasSuffix("_zoom-weekly"), "got: \(name)")
        let parts = name.components(separatedBy: "_")
        XCTAssertEqual(parts.count, 3) // date_time_slug
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd app/MeetingTranscriber && swift test --filter SessionFolderTests 2>&1 | grep -E "error|FAILED|passed"
```

Expected: compile error — `SessionFolder` not found.

- [ ] **Step 3: Implement `SessionFolder`**

```swift
// Sources/SessionFolder.swift
import Foundation

/// Pure functions for per-session folder naming.
enum SessionFolder {

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Lowercased, hyphenated slug from a meeting title, max 40 chars.
    static func slug(from title: String) -> String {
        guard !title.isEmpty else { return "untitled" }
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-"))
        let raw = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let cleaned = raw.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : Character("-") }
        let collapsed = String(cleaned)
            .components(separatedBy: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return String(collapsed.prefix(40))
            .trimmingCharacters(in: .init(charactersIn: "-"))
    }

    /// Folder name: `YYYY-MM-DD_HHmmss_<slug>`.
    static func folderName(date: Date, title: String) -> String {
        "\(formatter.string(from: date))_\(slug(from: title))"
    }

    /// Full URL for a session folder inside `root/recordings/`.
    static func sessionURL(root: URL, date: Date, title: String) -> URL {
        root
            .appendingPathComponent("recordings")
            .appendingPathComponent(folderName(date: date, title: title))
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd app/MeetingTranscriber && swift test --filter SessionFolderTests 2>&1 | grep -E "error|FAILED|passed"
```

Expected: `Test Suite 'SessionFolderTests' passed`

- [ ] **Step 5: Commit**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber
git add app/MeetingTranscriber/Sources/SessionFolder.swift app/MeetingTranscriber/Tests/SessionFolderTests.swift
git commit -m "feat(app): add SessionFolder for per-session folder naming"
```

---

## Task 2: Update `RecordingFileSuffix`

**Files:**
- Modify: `app/MeetingTranscriber/Sources/RecordingFileSuffix.swift`
- Create: `app/MeetingTranscriber/Tests/RecordingFileSuffixTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/RecordingFileSuffixTests.swift
import XCTest
@testable import MeetingTranscriber

final class RecordingFileSuffixTests: XCTestCase {

    func test_audioConstants() {
        XCTAssertEqual(RecordingFileSuffix.mix, "audio_mix.wav")
        XCTAssertEqual(RecordingFileSuffix.app, "audio_app.wav")
        XCTAssertEqual(RecordingFileSuffix.mic, "audio_mic.wav")
    }

    func test_documentConstants() {
        XCTAssertEqual(RecordingFileSuffix.transcript, "transcript.md")
        XCTAssertEqual(RecordingFileSuffix.protocol_, "protocol.md")
    }

    func test_stripSuffix_audioMix() {
        let result = RecordingFileSuffix.stripSuffix(from: "audio_mix.wav")
        XCTAssertEqual(result?.stem, "")
        XCTAssertEqual(result?.suffix, "audio_mix.wav")
    }

    func test_stripSuffix_unknown() {
        XCTAssertNil(RecordingFileSuffix.stripSuffix(from: "something_else.wav"))
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd app/MeetingTranscriber && swift test --filter RecordingFileSuffixTests 2>&1 | grep -E "error|FAILED|passed"
```

Expected: compile errors — missing constants.

- [ ] **Step 3: Update `RecordingFileSuffix`**

Replace the full content of `Sources/RecordingFileSuffix.swift`:

```swift
import Foundation

/// Filename constants for all files produced in a session folder.
enum RecordingFileSuffix {
    // Audio files
    static let mix = "audio_mix.wav"
    static let app = "audio_app.wav"
    static let mic = "audio_mic.wav"

    // Document files
    static let transcript = "transcript.md"
    static let protocol_ = "protocol.md"

    static let allAudio: [String] = [mix, app, mic]

    /// Strip a known audio suffix from a filename, returning (stem, suffix).
    /// Returns nil if filename doesn't match any known audio suffix.
    static func stripSuffix(from filename: String) -> (stem: String, suffix: String)? {
        for suffix in allAudio where filename == suffix || filename.hasSuffix("_\(suffix)") {
            // For bare filenames like "audio_mix.wav" the stem is empty.
            if filename == suffix { return ("", suffix) }
            return (String(filename.dropLast(suffix.count + 1)), suffix)
        }
        return nil
    }
}
```

- [ ] **Step 4: Fix compile errors from suffix constant renames**

Search for old suffix references and update:

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber
grep -rn '"_mix\.wav"\|"_app\.wav"\|"_mic\.wav"\|RecordingFileSuffix\.mix\b\|RecordingFileSuffix\.app\b\|RecordingFileSuffix\.mic\b' app/MeetingTranscriber/Sources/ --include="*.swift"
```

For each hit, the value is now `"audio_mix.wav"` / `"audio_app.wav"` / `"audio_mic.wav"` — the `RecordingFileSuffix.*` constant references are fine as-is (they now hold the new values). Only hardcoded string literals like `"_mix.wav"` need updating to `RecordingFileSuffix.mix`.

- [ ] **Step 5: Run tests**

```bash
cd app/MeetingTranscriber && swift test --filter RecordingFileSuffixTests 2>&1 | grep -E "error|FAILED|passed"
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber
git add app/MeetingTranscriber/Sources/RecordingFileSuffix.swift app/MeetingTranscriber/Tests/RecordingFileSuffixTests.swift
git commit -m "feat(app): rename audio file constants and add transcript/protocol suffixes"
```

---

## Task 3: Update `AppPaths` with new root paths

**Files:**
- Modify: `app/MeetingTranscriber/Sources/AppPaths.swift`

No new tests needed — `AppPaths` constants are path computations only; integration tested by Tasks 5+.

- [ ] **Step 1: Add constants to `AppPaths`**

Add after the existing `downloadsProtocolsDir` block:

```swift
/// New default output root: `~/Documents/Transcriber/`
static let transcriberRoot: URL = {
    guard let docs = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask).first
    else { return downloadsProtocolsDir }
    return docs.appendingPathComponent("Transcriber")
}()

/// Per-session recordings directory under the new root.
static let defaultRecordingsDir: URL = transcriberRoot.appendingPathComponent("recordings")

/// SwiftData library store location.
static let libraryStore: URL = transcriberRoot.appendingPathComponent("library.sqlite")
```

- [ ] **Step 2: Build check**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber
git add app/MeetingTranscriber/Sources/AppPaths.swift
git commit -m "feat(app): add transcriberRoot, defaultRecordingsDir, libraryStore to AppPaths"
```

---

## Task 4: Update `AppSettings` default output dir

**Files:**
- Modify: `app/MeetingTranscriber/Sources/AppSettings.swift`

- [ ] **Step 1: Update `effectiveOutputDir` default**

Find the `effectiveOutputDir` computed property and change the fallback:

```swift
var effectiveOutputDir: URL {
    customOutputDir ?? AppPaths.transcriberRoot
}
```

- [ ] **Step 2: Build check**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber
git add app/MeetingTranscriber/Sources/AppSettings.swift
git commit -m "feat(app): default output dir to ~/Documents/Transcriber/"
```

---

## Task 5: `RecordingSession` SwiftData model

**Files:**
- Create: `app/MeetingTranscriber/Sources/RecordingSession.swift`

SwiftData models are tested via integration in `PipelineQueue` (Task 6). Add a unit test for the `SessionStatus` helper.

- [ ] **Step 1: Write `RecordingSession`**

```swift
// Sources/RecordingSession.swift
import Foundation
import SwiftData

/// Persisted history entry for one completed (or failed) recording session.
@Model
final class RecordingSession {
    var id: UUID
    var createdAt: Date
    var title: String
    var appName: String
    /// Path relative to `AppPaths.transcriberRoot`, e.g. "recordings/2026-05-20_143022_zoom-weekly-sync"
    var folderPath: String
    var duration: TimeInterval
    var participantNames: [String]
    var hasTranscript: Bool
    var hasProtocol: Bool
    /// Basenames of audio files present in the folder.
    var audioFiles: [String]
    var engine: String
    var status: String
    var errorMessage: String?
    var warnings: [String]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String,
        appName: String,
        folderPath: String,
        duration: TimeInterval,
        participantNames: [String] = [],
        hasTranscript: Bool = false,
        hasProtocol: Bool = false,
        audioFiles: [String] = [],
        engine: String,
        status: String,
        errorMessage: String? = nil,
        warnings: [String] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.appName = appName
        self.folderPath = folderPath
        self.duration = duration
        self.participantNames = participantNames
        self.hasTranscript = hasTranscript
        self.hasProtocol = hasProtocol
        self.audioFiles = audioFiles
        self.engine = engine
        self.status = status
        self.errorMessage = errorMessage
        self.warnings = warnings
    }
}

/// Status string constants for `RecordingSession.status`.
enum SessionStatus {
    static let waiting = "waiting"
    static let transcribing = "transcribing"
    static let diarizing = "diarizing"
    static let generatingProtocol = "generatingProtocol"
    static let done = "done"
    static let error = "error"
    static let saved = "saved" // record-only
}
```

- [ ] **Step 2: Add SwiftData import to `Package.swift`**

SwiftData is a system framework on macOS 14+ — no `Package.swift` change needed. Just verify the target's minimum deployment version is already `macOS(.v14)`.

```bash
grep -n "macOS" app/MeetingTranscriber/Package.swift | head -5
```

Expected: a line like `.macOS(.v14)` or `.macOS("14.2")`.

- [ ] **Step 3: Build check**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber
git add app/MeetingTranscriber/Sources/RecordingSession.swift
git commit -m "feat(app): add RecordingSession SwiftData model and SessionStatus constants"
```

---

## Task 6: `SessionMeta` — v2 `meta.json` writer

**Files:**
- Create: `app/MeetingTranscriber/Sources/SessionMeta.swift`
- Create: `app/MeetingTranscriber/Tests/SessionMetaTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/SessionMetaTests.swift
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
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd app/MeetingTranscriber && swift test --filter SessionMetaTests 2>&1 | grep -E "error:|FAILED|passed"
```

Expected: compile error — `SessionMeta` not found.

- [ ] **Step 3: Implement `SessionMeta`**

```swift
// Sources/SessionMeta.swift
import Foundation

/// v2 session metadata file (`meta.json`) written inside each session folder.
struct SessionMeta: Codable {
    static let currentVersion = 2
    static let filename = "meta.json"

    let version: Int
    let title: String
    let appName: String
    let startedAt: Date
    let stoppedAt: Date
    let participants: [String]
    let micDelaySeconds: Double
    let engine: String
    let diarizerMode: String
    let files: FileRefs

    /// Duration in seconds derived from start/stop.
    var duration: TimeInterval { stoppedAt.timeIntervalSince(startedAt) }

    struct FileRefs: Codable {
        let app: String?
        let mic: String?
        let mix: String?
        let transcript: String?
        let protocol_: String?

        enum CodingKeys: String, CodingKey {
            case app, mic, mix, transcript
            case protocol_ = "protocol"
        }
    }

    init(
        title: String,
        appName: String,
        startedAt: Date,
        stoppedAt: Date,
        participants: [String],
        micDelaySeconds: Double,
        engine: String,
        diarizerMode: String,
        files: FileRefs
    ) {
        self.version = Self.currentVersion
        self.title = title
        self.appName = appName
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.participants = participants
        self.micDelaySeconds = micDelaySeconds
        self.engine = engine
        self.diarizerMode = diarizerMode
        self.files = files
    }

    /// Write `meta.json` into `dir`.
    func write(to dir: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: dir.appendingPathComponent(Self.filename), options: .atomic)
    }

    /// Read `meta.json` from `dir`.
    static func read(from dir: URL) throws -> SessionMeta {
        let data = try Data(contentsOf: dir.appendingPathComponent(filename))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionMeta.self, from: data)
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd app/MeetingTranscriber && swift test --filter SessionMetaTests 2>&1 | grep -E "error:|FAILED|passed"
```

Expected: `Test Suite 'SessionMetaTests' passed`

- [ ] **Step 5: Commit**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber
git add app/MeetingTranscriber/Sources/SessionMeta.swift app/MeetingTranscriber/Tests/SessionMetaTests.swift
git commit -m "feat(app): add SessionMeta v2 meta.json writer/reader"
```

---

## Task 7: Wire `PipelineQueue` to per-session folders + write `RecordingSession`

**Files:**
- Modify: `app/MeetingTranscriber/Sources/PipelineQueue.swift`

This is the largest task. The changes:
1. `PipelineQueue` receives an optional `modelContext: ModelContext?` for writing `RecordingSession` entries.
2. When a job finishes (done, error, record-only), create a session folder under `outputDir/recordings/<SessionFolder.folderName>` and write all outputs there.
3. Write `meta.json` via `SessionMeta.write(to:)`.
4. Write `RecordingSession` to the SwiftData context.

- [ ] **Step 1: Add `modelContext` property to `PipelineQueue`**

Find the `PipelineQueue` class declaration. Add:

```swift
import SwiftData

// Inside PipelineQueue class body:
var modelContext: ModelContext?
```

- [ ] **Step 2: Add `sessionFolderURL` helper to `PipelineQueue`**

Add this private helper:

```swift
private func sessionFolderURL(title: String, startedAt: Date, outputDir: URL) -> URL {
    SessionFolder.sessionURL(root: outputDir, date: startedAt, title: title)
}
```

- [ ] **Step 3: Update the transcript + audio save block**

Find the block in `PipelineQueue` that currently does:
```swift
let protocolsDir = outputDir.appendingPathComponent("protocols")
let txtPath = try ProtocolGenerator.saveTranscript(finalTranscript, title: title, dir: protocolsDir)
```

Replace that section (transcript save + audio copy + 16k persist) with:

```swift
// Create per-session folder
let sessionStart = jobs.first(where: { $0.id == jobID })?.startedAt ?? Date()
let sessionDir = sessionFolderURL(title: title, startedAt: sessionStart, outputDir: outputDir)
try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

// Save transcript as transcript.md
let txtURL = sessionDir.appendingPathComponent(RecordingFileSuffix.transcript)
try finalTranscript.write(to: txtURL, atomically: true, encoding: .utf8)
if let idx = jobs.firstIndex(where: { $0.id == jobID }) {
    jobs[idx].transcriptPath = txtURL
    jobs[idx].namingSlug = SessionFolder.slug(from: title)
}
logger.info("[\(shortID, privacy: .public)] transcript_saved path=\(txtURL.lastPathComponent, privacy: .public)")

// Copy/move audio into session folder
var audioFiles: [String] = []
if let mixPath {
    let dest = sessionDir.appendingPathComponent(RecordingFileSuffix.mix)
    try? FileManager.default.moveItem(at: mixPath, to: dest)
    audioFiles.append(RecordingFileSuffix.mix)
}
if let appPath {
    let dest = sessionDir.appendingPathComponent(RecordingFileSuffix.app)
    try? FileManager.default.moveItem(at: appPath, to: dest)
    audioFiles.append(RecordingFileSuffix.app)
}
if let micPath {
    let dest = sessionDir.appendingPathComponent(RecordingFileSuffix.mic)
    try? FileManager.default.moveItem(at: micPath, to: dest)
    audioFiles.append(RecordingFileSuffix.mic)
}

// Move 16kHz audio for re-diarization
for (src, dst) in [
    ("mix_16k.wav", "audio_mix_16k.wav"),
    ("app_16k.wav", "audio_app_16k.wav"),
    ("mic_16k.wav", "audio_mic_16k.wav"),
] {
    try? FileManager.default.moveItem(
        at: workDir.appendingPathComponent(src),
        to: sessionDir.appendingPathComponent(dst)
    )
}
```

- [ ] **Step 4: Update `generateProtocol` to save into session folder**

`generateProtocol` currently receives `protocolsDir`. Change its signature to accept the session folder URL:

Find: `func generateProtocol(jobID: UUID, transcript: String, title: String, protocolsDir: URL)`
Change parameter to `sessionDir: URL`.

Inside, replace:
```swift
let mdPath = try ProtocolGenerator.saveProtocol(fullMD, title: title, dir: protocolsDir)
```
With:
```swift
let mdPath = sessionDir.appendingPathComponent(RecordingFileSuffix.protocol_)
try fullMD.write(to: mdPath, atomically: true, encoding: .utf8)
```

Update all call sites to pass `sessionDir` instead of `protocolsDir`. There are two: main pipeline and `reapplySpeakerNames`.

- [ ] **Step 5: Write `RecordingSession` on job done/error**

Add a helper:

```swift
private func writeRecordingSession(
    job: PipelineJob,
    sessionDir: URL,
    outputDir: URL,
    audioFiles: [String],
    status: String,
    engine: String
) {
    guard let ctx = modelContext else { return }
    let relPath = sessionDir.path
        .replacingOccurrences(of: outputDir.path + "/", with: "")
    let duration = job.startedAt.map { Date().timeIntervalSince($0) } ?? 0
    let session = RecordingSession(
        title: job.meetingTitle,
        appName: job.appName,
        folderPath: relPath,
        duration: duration,
        participantNames: job.participants,
        hasTranscript: job.transcriptPath != nil,
        hasProtocol: job.protocolPath != nil,
        audioFiles: audioFiles,
        engine: engine,
        status: status,
        errorMessage: job.error,
        warnings: job.warnings
    )
    ctx.insert(session)
    try? ctx.save()
}
```

Call this after `updateJobState(id: jobID, to: .done)` and after `updateJobState(id: jobID, to: .error, ...)`.

- [ ] **Step 6: Build and run full test suite**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep -E "error:|Build complete"
swift test --parallel 2>&1 | tail -5
```

Expected: `Build complete!` and tests pass (or only pre-existing failures).

- [ ] **Step 7: Commit**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber
git add app/MeetingTranscriber/Sources/PipelineQueue.swift
git commit -m "feat(app): write outputs to per-session folders and persist RecordingSession"
```

---

## Task 8: Update `WatchLoop` record-only to use session folders + `SessionMeta`

**Files:**
- Modify: `app/MeetingTranscriber/Sources/WatchLoop.swift`

- [ ] **Step 1: Replace `RecordingSidecar` with `SessionMeta` in `writeRecordOnlySidecar`**

Find `writeRecordOnlySidecar`. Replace the inner do/catch block:

```swift
do {
    let destination = recordOnlyDestination()
    let accessing = destination.scope.startAccessingSecurityScopedResource()
    defer { if accessing { destination.scope.stopAccessingSecurityScopedResource() } }

    // Create per-session folder inside the record-only destination
    let sessionDir = SessionFolder.sessionURL(
        root: destination.scope,
        date: startedAt,
        title: title
    )
    try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

    let movedMix = try Self.move(recording.mixPath, into: sessionDir)
    let movedApp = try recording.appPath.map { try Self.move($0, into: sessionDir) }
    let movedMic = try recording.micPath.map { try Self.move($0, into: sessionDir) }

    let meta = SessionMeta(
        title: title,
        appName: appName,
        startedAt: startedAt,
        stoppedAt: stoppedAt,
        participants: participants,
        micDelaySeconds: recording.micDelay,
        engine: "record-only",
        diarizerMode: "none",
        files: SessionMeta.FileRefs(
            app: movedApp?.lastPathComponent,
            mic: movedMic?.lastPathComponent,
            mix: movedMix.lastPathComponent,
            transcript: nil,
            protocol_: nil
        )
    )
    try meta.write(to: sessionDir)
    logger.info("Record-only: wrote session folder \(sessionDir.lastPathComponent) for \(title)")
} catch {
    // ... (keep existing error handler unchanged)
}
```

- [ ] **Step 2: Remove `RecordingSidecar` import / usage**

Check if `RecordingSidecar` is used anywhere else:

```bash
grep -rn "RecordingSidecar" /Users/akeslo/Scrypting/meeting-transcriber/app/MeetingTranscriber/Sources/
```

If only in `WatchLoop.swift`, remove the usage. `RecordingSidecar.swift` can be kept for now (backward compat with existing `.local/` notes) but is no longer called in production code.

- [ ] **Step 3: Build check**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep -E "error:|Build complete"
```

Expected: `Build complete!`

- [ ] **Step 4: Run full test suite**

```bash
cd app/MeetingTranscriber && swift test --parallel 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber
git add app/MeetingTranscriber/Sources/WatchLoop.swift
git commit -m "feat(app): record-only uses session folders and SessionMeta v2"
```

---

## Task 9: `PipelineJob` — add `startedAt` field

The `writeRecordingSession` helper in Task 7 uses `job.startedAt`. Add this field if not present.

- [ ] **Step 1: Check if `startedAt` exists**

```bash
grep -n "startedAt\|recordingStart" app/MeetingTranscriber/Sources/PipelineJob.swift | head -10
```

- [ ] **Step 2: Add if missing**

If `startedAt: Date?` is not present in `PipelineJob`, add it:

```swift
// In PipelineJob struct/class body:
var startedAt: Date? = nil
```

Set it in `PipelineQueue` when the job transitions to `.transcribing`:
```swift
if let idx = jobs.firstIndex(where: { $0.id == jobID }) {
    jobs[idx].startedAt = Date()
}
```

- [ ] **Step 3: Build and test**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep -E "error:|Build complete"
swift test --parallel 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
cd /Users/akeslo/Scrypting/meeting-transcriber
git add app/MeetingTranscriber/Sources/PipelineJob.swift
git commit -m "feat(app): add startedAt to PipelineJob for session duration tracking"
```

---

## Phase 1 Complete — Verification

- [ ] **Run full test suite one final time**

```bash
cd app/MeetingTranscriber && swift test --parallel 2>&1 | tail -10
```

- [ ] **Smoke test: launch app and trigger a recording**

```bash
./scripts/run_app.sh --build-only
```

Then manually trigger a recording. Verify:
1. `~/Documents/Transcriber/recordings/` contains a dated session folder
2. Folder contains `audio_mix.wav` (or `audio_app.wav`/`audio_mic.wav`), `transcript.md`, `protocol.md`, `meta.json`
3. `meta.json` has `"version": 2`
