# UI/UX Redesign — Full Design Spec

**Date:** 2026-05-20  
**Approach:** SwiftData + WindowGroup (Approach A)  
**Scope:** Menu bar icons, slim dropdown, Dashboard window, Library, Meeting Detail reader, Settings restructure, output folder redesign, job history database, update checker owner change

---

## Design System

Reference: `stitch_on_device_meeting_protocoler/pro_desktop/DESIGN.md`

**Palette:**
| Token | Hex | Usage |
|---|---|---|
| Space Indigo | `#2A324B` | Sidebar bg, primary text, icon base |
| Peach Glow | `#F7C59F` | Active badges, CTAs, state overlays |
| Slate Grey | `#767B91` | Secondary text, muted labels |
| Pale Slate | `#C7CCDB` | Borders, dividers |
| Alice Blue | `#E1E5EE` | App background canvas |
| Pure White | `#FFFFFF` | Cards, content surfaces |
| Error Red | `#FF4D4D` | Error states, permission alerts |

**Typography:** Inter throughout. Hierarchy via weight + letter-spacing (not size jumps). Labels at small scale use medium/semibold.

**Shape language:** 8px default radius (`rounded-lg` = 16px for cards, `rounded-sm` = 4px for chips/tags).

**Elevation:**
- Level 0: Alice Blue canvas
- Level 1: White cards with 1px Pale Slate border
- Level 2: Popovers — 80% white + 20px backdrop blur + soft shadow
- Level 3: Modals — full white + dark overlay

---

## 1. Output Folder Restructure

**New default root:** `~/Documents/Transcriber/` (replaces flat `protocols/` folder)

**Structure:**
```
~/Documents/Transcriber/
  recordings/
    2026-05-20_143022_zoom-weekly-sync/
      audio_app.wav
      audio_mic.wav
      audio_mix.wav        (when dual-source mix exists)
      transcript.md
      protocol.md          (when LLM generation ran)
      meta.json            (replaces _meta.json sidecar)
    2026-05-19_090511_google-meet/
      ...
  library.sqlite           (SwiftData store — NOT inside a session folder)
```

**Session folder naming:** `YYYY-MM-DD_HHMMSS_<slug>` where slug = meeting title lowercased, spaces→hyphens, stripped of special chars, max 40 chars. Example: `2026-05-20_143022_zoom-weekly-sync`.

**`meta.json` schema (v2):**
```json
{
  "version": 2,
  "title": "Zoom Weekly Sync",
  "appName": "zoom.us",
  "startedAt": "2026-05-20T14:30:22Z",
  "stoppedAt": "2026-05-20T15:12:44Z",
  "participants": ["Alex Rivera", "Sam Chen"],
  "micDelaySeconds": 0.12,
  "engine": "whisperKit",
  "diarizerMode": "offlineDiarizer",
  "files": {
    "app": "audio_app.wav",
    "mic": "audio_mic.wav",
    "mix": "audio_mix.wav",
    "transcript": "transcript.md",
    "protocol": "protocol.md"
  }
}
```

**Migration:** No migration of old flat files. New structure applies to all sessions created after this release.

---

## 2. SwiftData Job History

**Model: `RecordingSession`**
```swift
@Model
final class RecordingSession {
    var id: UUID
    var createdAt: Date
    var title: String
    var appName: String
    var folderPath: String        // relative to Transcriber root
    var duration: TimeInterval
    var participantNames: [String]
    var hasTranscript: Bool
    var hasProtocol: Bool
    var audioFiles: [String]      // basenames present in folder
    var engine: String
    var status: String            // "waiting" | "transcribing" | "diarizing" | "done" | "error" | "saved"
    var errorMessage: String?
    var warnings: [String]
}
```

**Store location:** `~/Documents/Transcriber/library.sqlite`

**Write path:** `PipelineJob` → on completion/error, `PipelineQueue` writes a `RecordingSession` to the SwiftData context. Record-only mode also writes with `status = "saved"`.

**Read path:** Library view uses `@Query(sort: \.createdAt, order: .reverse)`. Dashboard Recent Activity fetches last 3.

**In-flight jobs:** `PipelineQueue.jobs` (`[PipelineJob]`) remains unchanged for active processing. The Library shows in-flight jobs by merging `@Query` results with live `pipelineQueue.jobs` — in-flight jobs appear at top with live progress.

---

## 3. Menu Bar Icon

**Design:** Heartbeat/pulse waveform in Space Indigo (`#2A324B`), rendered as SwiftUI `Canvas` → `NSImage`. Template mode **off** (colored, not adaptive).

**State badges:**

| `BadgeKind` | Overlay |
|---|---|
| `inactive` | None |
| `recording` | Peach Glow filled circle, top-right, pulsing opacity |
| `transcribing` | Peach Glow arc spinner, top-right |
| `diarizing` | Peach Glow arc spinner, top-right, slower cadence |
| `processing` | Peach Glow arc spinner, top-right |
| `userAction` | Peach Glow ring + `!` glyph, bottom-right |
| `updateAvailable` | Peach Glow arrow-up with dot stem, top-right |
| `error` | Full red circle ring around icon, red `!` centered, waveform at 30% opacity |
| `mic_silent` overlay | Gray mic outline + red diagonal slash over waveform |
| `recordOnly` overlay | Peach Glow small filled dot, bottom-left |

**Implementation:** Replaces existing `MenuBarIcon` draw methods. Same `cache: [BadgeKind: [NSImage]]` pattern. Animation cadence logic unchanged (`nextFrame`).

---

## 4. Slim Dropdown

Replaces current `MenuBarView`. Three zones separated by single dividers.

**Zone 1 — Status:**
```
● Recording · Zoom Weekly Sync
  00:42 elapsed
```
- Icon color matches `BadgeKind` accent (Peach Glow when active, red when error)
- State label + meeting title on one line
- Detail (elapsed / progress % / error message) on second line, secondary color
- When `userAction`: banner row "Speakers need names" + "Name Now →" button → opens Dashboard

**Zone 2 — Actions:**
```
▶ Start Watching          ⌘S
⏺ Record App…             ⌘R
📂 Process Files…         ⌘P
📁 Open Output Folder
⊞ Open Dashboard          ⌘D   ← new
⚙ Settings…               ⌘,
```
- `Record App…` swaps to `Stop Recording ⌘.` when manual recording active
- `Start Watching` disabled + tooltip "Model loading…" when `!isModelReady`
- Model not ready: inline warning row between Zone 1 and actions (no separate banner divider)
- Update available: inserted above Settings row with Peach Glow tint

**Zone 3 — Quit:**
```
Quit                       ⌘Q
```

**Removed from dropdown:** Pipeline job rows, Open Last Protocol button (both live in Dashboard).

---

## 5. Main Window — Shell

**Window type:** SwiftUI `WindowGroup(id: "dashboard")`. Standard macOS window (not NSPanel). Appears in Dock + app switcher. Remembers position via `defaultPosition` + `windowResizability`. Min size: 900×600.

**Opening:** `⌘D` from dropdown, "Open Dashboard" menu item, or clicking status banner in dropdown.

**Three-pane layout:**
```
┌──────────────┬─────────────────────┬──────────────────────┐
│  Sidebar     │  Content / List     │  Detail / Reader     │
│  240px fixed │  flex               │  360px fixed         │
└──────────────┴─────────────────────┴──────────────────────┘
```

**Sidebar — Space Indigo background:**
- Top: app icon + "Transcriber" wordmark
- Nav items: Dashboard, Library, Settings (routes content pane)
- Active state: Peach Glow 3px left-pill + Alice Blue row tint
- Bottom: engine badge (e.g. "WhisperKit Large-v3"), storage used (`~/Documents/Transcriber/` size)

---

## 6. Dashboard View

Shown when "Dashboard" selected in sidebar. Content pane only (no detail pane).

**Layout (two columns):**

**Left — Status card:**
- Headline: "Meeting Detection is active." / "Idle" / "Recording · 00:42"
- Subtext reflects `WatchLoop` phase
- Primary CTA button: "Start Watching" / "Stop Watching" (matches dropdown)
- Audio source rows: "App Audio Tap · Dia" + checkmark / "Built-in Mic" + checkmark — live from `DualSourceRecorder` state

**Right — two stacked cards:**
- Quick Controls card: three toggles — VAD (`AppSettings.vadEnabled`), Diarizer mode (`AppSettings.diarizerMode`, Offline↔Sortformer), Record-only (`AppSettings.recordOnly`)
- Ambient Level card: dual RMS bar meters (App / Mic channels) updated from `ChannelHealthMonitor` dBFS feed via 500ms timer during recording; static "–" when idle

**Bottom — Recent Activity:**
- Section header "Recent Activity" + "View All Library →" link
- Last 3 `RecordingSession` rows (same chip/status style as Library)
- Tapping a row selects it in Library + opens detail pane

---

## 7. Library View

Shown when "Library" selected in sidebar. Content pane = list. Detail pane = session reader.

**Content pane:**
- Header: "Recordings · N total items"
- Search bar (filters title, appName, participantNames)
- List/Grid toggle (List default)
- `@Query` sorted by `createdAt` descending, in-flight `PipelineJob` entries merged at top

**List row (48px):**
```
[app icon]  Meeting Title                    Oct 24  42:15  ● DONE
            Zoom · Speaker 1, Speaker 2
```
Status chip colors: DONE=green, PROCESSING=Peach Glow, ERROR=red, SAVED=Slate Grey

**Grid card (when toggled):** ~180px wide card, thumbnail (blurred waveform placeholder), title, date, status chip.

**Detail pane (right):**
When session selected:
- Title + metadata chips (date, duration, app, engine)
- Action buttons: "Open Transcript" (external), "Download WAV"
- Reader area (see Section 8)

When nothing selected: centered empty state ("Select a recording to view details")

---

## 8. Meeting Detail Reader

Embedded in detail pane. Three tabs: **Transcript · Protocol · Split**

**Transcript tab:**
- Speaker segments: Space Indigo bold speaker name label + timestamp (hover to show)
- Body text: system body font, dark on white
- Peach Glow highlight on selected/active segment
- Scrollable, no editing

**Protocol tab:**
- Rendered Markdown via `AttributedString(markdown:)` in a `ScrollView`
- Headings in Space Indigo, body in `on-surface`, code blocks with Alice Blue bg

**Split tab:**
- Transcript left / Protocol right, 50/50
- Synchronized scroll: selecting a speaker segment in Transcript highlights nearest protocol section by timestamp proximity

**Playback bar (all tabs):**
- Plays `audio_mix.wav` from session folder via `AVAudioPlayer`
- Play/Pause, scrub slider, elapsed/total time
- During playback: transcript auto-scrolls to segment matching current timestamp

---

## 9. Settings View

Accessed via sidebar "Settings" nav item. Replaces current tabbed `SettingsView` floating window. Rendered in the content pane (full width, no detail pane).

Single scrollable column of **collapsible card sections**. Each section: icon + title header + collapse chevron. Default: all expanded.

**Section order:**

### ⬡ Detection & Patterns
- Window Title Matching: editable pattern list (`MeetingPatterns`) with add/delete rows
- Browser URL Patterns: `WatchedWebsite` chip list with enable toggle + mic toggle per site
- Power Assertions toggle

### 🎙 Audio & Capture
- Microphone device picker
- VAD toggle + sensitivity slider
- Grace period slider (min 1s)
- Max recording duration picker

### ⚡ Transcription Engine
- Visual card picker: WhisperKit · Parakeet TDT · Qwen3-ASR
- Each card shows: name, tag (INDUSTRY STANDARD / OPTIMIZED SPEED / MULTILINGUAL), model size, speed rating
- Per-engine options appear below selected card: language picker, model variant, custom vocab path
- Qwen3 card disabled + "Requires macOS 15+" badge when on macOS <15

### 👥 Speakers & Diarization
- Diarizer mode toggle (OfflineDiarizer / Sortformer)
- Mic speaker name field
- Known Voices list (inline rename/delete/merge)
- Voice enrollment button

### 📄 Output & Protocol
- Output folder picker (security-scoped bookmark)
- LLM provider card picker: Claude CLI · OpenAI-compatible · None
- Protocol language text field
- Custom prompt editor (expandable textarea)

### 🔧 Advanced
- Record-only mode toggle (with banner explaining recordings-only behavior)
- Debug RPC Server toggle (`#if !APPSTORE`)
- Verbose audio logging toggle
- Permissions health rows (mic, screen recording — `PermissionRow` components)
- Export Diagnostics button
- About section: app version + build, engine versions
- Update checker: checks `akeslo/meeting-transcriber` GitHub releases (replaces `pasrom/meeting-transcriber`)
- "Check for Updates" button

**`recordOnlyDisabled()` modifier** still dims Transcription Engine, Speakers & Diarization, and Output & Protocol sections when record-only is active.

---

## 10. Update Checker Change

`UpdateChecker.owner` changes from `"pasrom"` → `"akeslo"`. Repo stays `"meeting-transcriber"`. Settings Advanced section links to `https://github.com/akeslo/meeting-transcriber/releases`.

---

## Implementation Phases

**Phase 1 — Data foundation**
- New output folder structure + session folder naming
- `meta.json` v2 writer (replacing `RecordingSidecar`)
- `RecordingSession` SwiftData model + store at `~/Documents/Transcriber/library.sqlite`
- `PipelineQueue` writes `RecordingSession` on job completion/error/record-only
- `RecordingFileSuffix` updated to `transcript.md`, `protocol.md`, `audio_app.wav` etc.

**Phase 2 — Menu bar**
- New `MenuBarIcon` Canvas renderer (heartbeat design, all badge states)
- Slim `MenuBarView` (3-zone layout, job rows removed)
- `UpdateChecker` owner → `akeslo`

**Phase 3 — Window shell + Library**
- `WindowGroup(id: "dashboard")` + sidebar nav
- Library list/grid view with `@Query` + in-flight merge
- Detail pane shell + metadata header + action buttons

**Phase 4 — Dashboard + Meeting Detail + Settings**
- Dashboard status card + quick controls + ambient level meters + recent activity
- Meeting Detail reader (Transcript / Protocol / Split tabs + playback bar)
- Settings restructured to collapsible card sections
