# Feature Gaps Implementation Design
**Date:** 2026-05-23

## Context

23 feature gaps identified across 6 subsystems. Working-tree already has: tags/folders, editable title, Claude model picker, schema migration, browser-audio-only tab detection. This spec covers the remaining 22.

---

## Group F — Pipeline & Monitoring

### F1 · Dock badge during processing (#22)
Set `NSApp.dockTile.badgeLabel` to job count when pipeline is busy; clear when idle.  
Where: `AppState` observer on `pipelineQueue.jobs` count.  
**Complexity:** Low

### F2 · LLM retry with backoff (#29)
Wrap `generate()` in both `ClaudeCLIProtocolGenerator` and `OpenAIProtocolGenerator` with up to 3 retries, exponential backoff (2s, 4s, 8s), retry only on transient errors (timeout, network).  
**Complexity:** Low

### F3 · Retry UI for failed jobs (#24)
"Retry" button in `DetailPaneView` for sessions with `status == .error`. Re-enqueues a new `PipelineJob` from the session's existing audio files.  
**Complexity:** Low

### F4 · Job queue pause/cancel (#23)
Add "Cancel" button to in-flight job rows in `LibraryView`. Cancellable via `PipelineJob.cancel()` (already has `isCancelled`). Show estimated remaining: "~2 min" based on audio duration / historical speed.  
**Complexity:** Medium

### F5 · Bulk export (#4)
Export sheet: user picks sessions (multi-select via checkbox overlay on grid), chooses format (Markdown / Plain Text / JSON), destination folder. Loop writes files with pattern `{date}-{title}-{type}.{ext}`.  
**Complexity:** Medium

---

## Group E — Detection & Audio

### E1 · Regex URL patterns (#17)
Add `useRegex: Bool` to `WatchedWebsite`. When true, match via `NSRegularExpression` instead of `contains`. Expose toggle in watched-websites editor row.  
**Complexity:** Low

### E2 · Detection dry-run (#18)
"Test Now" button in General settings (watched apps / websites section). Runs one poll cycle across all detectors; shows a sheet listing which detector fired (or "nothing detected").  
**Complexity:** Low

### E3 · Test mic button (#19)
In `AudioSettingsView`, add a "Test Microphone" button that starts a 3-second AVAudioEngine capture and displays a live dBFS level bar. Shows "OK" / "Silent" / "Too Loud" after.  
**Complexity:** Medium

### E4 · VAD presets (#20)
Add `VadPreset` enum (`.quiet`, `.balanced`, `.aggressive`) to `AppSettings`. Each maps to a threshold and minimum-silence-duration. Picker in Audio Settings replaces the manual threshold slider (or sits above it as an override).  
**Complexity:** Low

---

## Group A — Library & Search

### A1 · Date-range filter (#6)
Two `DatePicker` fields in the library filter row (start / end). Wired into `filterSessions`.  
**Complexity:** Low

### A2 · Sort options (#8)
Sort picker: Newest, Oldest, Longest, Shortest, Title A–Z, Status. Implemented as a `@State var sortOrder` enum in `LibraryView`, applied after filter.  
**Complexity:** Low

### A3 · Aggregate stats panel (#25)
Stats card in the dashboard sidebar or as a dedicated `NavItem.stats` pane: total sessions, total recorded hours, unique speakers, most-used app, protocol generation rate, storage used.  
Pulls from `@Query` on `RecordingSession`.  
**Complexity:** Medium

### A4 · Full-text transcript search (#5)
"Search in transcripts" toggle in library search bar. When enabled, `filterSessions` additionally scans each session's `_transcript.txt` file for the search query (background task, results streamed in). No index — grep-style scan.  
**Complexity:** Medium (file I/O, background actor, debounce)

---

## Group B — Protocol & Output

### B1 · Inline prompt editor (#9)
Replace the "Edit in Finder" button in `OutputSettingsView` with a modal sheet containing a `TextEditor` bound to the prompt file content. Auto-saves on close.  
**Complexity:** Low

### B2 · Protocol templates (#11)
Add `[ProtocolTemplate]` to `AppSettings` (name + promptBody). Picker above the custom prompt editor. Selecting a built-in template populates the prompt. User can save current prompt as a named template.  
Built-in templates: "Meeting Notes", "Technical Review", "Client Call", "1:1".  
**Complexity:** Medium

### B3 · Action-item extraction (#10)
Enhance the default prompt to explicitly request a `## Action Items` section with owner + deadline columns. Add a dedicated "Action Items" tab in `MeetingDetailReader` that parses that section and renders a checklist.  
**Complexity:** Medium

### B4 · Transcript anonymization (#28)
Toggle in Output Settings: "Anonymize transcript before sending to LLM". When on, replaces known speaker names in the transcript with `[Speaker A]`, `[Speaker B]` before the LLM call. Uses the speaker name list from the session.  
**Complexity:** Medium

---

## Group C — Speaker Management

### C1 · Speaker confidence display (#14)
In `KnownVoicesView`, show per-speaker match statistics: recognition count, average cosine similarity. Expose from `SpeakerMatcher`'s existing `RecognitionStats`.  
**Complexity:** Low

### C2 · Batch speaker naming (#13)
Replace the per-speaker modal naming flow with a table sheet: rows are detected speakers, columns are audio snippet (play button) and name text field. "Confirm All" commits. Shown after diarization, before protocol generation.  
**Complexity:** High

### C3 · Participant pre-seeding (#15)
In `WatchedWebsite` and the "Apps to Watch" list, add an "Expected Participants" text field (comma-separated). Before diarization, pre-populate the speaker name candidates with these names so the matcher has anchors.  
**Complexity:** High

---

## Group D — Recording & Sessions

### D1 · Meeting start-time edit (#30)
In `DetailPaneView` header, make `createdAt` editable: click timestamp → `DatePicker` popover. Writes back to `RecordingSession.createdAt` and `SessionMeta`.  
**Complexity:** Low

### D2 · Live timestamped notes (#12)
While a recording is active (status `.recording`), show a "Notes" text area in the menu bar dropdown. Each note saves with a timestamp offset from `recordingStart`. Stored in `PipelineJob.notes: [TimestampedNote]`. Surfaced in a "Notes" tab in `MeetingDetailReader`.  
**Complexity:** Medium

### D3 · Pause/resume recording (#21)
Add `pause()` / `resume()` to `AudioCaptureSession` (AudioTapLib). Insert silence-gap markers in the output WAV or produce segment files. Add pause button to menu bar dropdown active-recording row.  
**Complexity:** High — deferred to follow-up spec (requires AudioTapLib state machine changes).

---

## Implementation Order

1. **Phase 1 — Quick wins** (F1, F2, F3, E1, E2, E4, A1, A2, B1, C1, D1): ~1 day
2. **Phase 2 — Medium** (F4, F5, E3, A3, A4, B2, B3, B4, D2): ~2 days  
3. **Phase 3 — Complex** (C2, C3): follow-up after user review
4. **Deferred** (D3 pause/resume): separate spec

---

## Files Touched

| File | Changes |
|------|---------|
| `AppSettings.swift` | VadPreset, ProtocolTemplate[], anonymization toggle |
| `AppState.swift` | Dock badge observer |
| `LibraryView.swift` | Date filter, sort picker, full-text search toggle |
| `DetailPaneView.swift` | Retry button, start-time edit |
| `MeetingDetailReader.swift` | Action items tab, Notes tab |
| `SessionRowView.swift` | Bulk-select checkbox |
| `OutputSettingsView.swift` | Inline prompt editor, template picker, anonymization |
| `AudioSettingsView.swift` | Test mic, VAD presets |
| `GeneralSettingsView.swift` | Detection dry-run, regex URL toggle |
| `WatchedWebsite.swift` | useRegex field, expectedParticipants |
| `BrowserTabDetector.swift` | Regex matching |
| `ClaudeCLIProtocolGenerator.swift` | Retry logic, anonymization |
| `OpenAIProtocolGenerator.swift` | Retry logic, anonymization |
| `KnownVoicesView.swift` | Confidence stats display |
| `PipelineQueue.swift` | Cancel support, modelContext |
| New: `StatsView.swift` | Aggregate stats panel |
| New: `BulkExportSheet.swift` | Export UI |
| New: `PromptEditorSheet.swift` | Inline prompt editor |
| New: `MicTestView.swift` | Mic level preview |
