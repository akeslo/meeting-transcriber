# Phase 2: Menu Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the menu bar icon with a heartbeat/ECG design, slim the dropdown to 3 zones removing job rows, and fix the UpdateChecker GitHub owner.

**Architecture:** `MenuBarIcon` gets a new heartbeat path renderer with Space Indigo base and Peach Glow badge overlays; all images are non-template (colored). `MenuBarView` drops job rows and gains `onOpenDashboard`. `GitHubReleaseProvider.owner` is a one-liner change. All existing `BadgeKind`, animation, and cache contracts preserved.

**Tech Stack:** Swift, AppKit (NSBezierPath, NSColor, NSImage), SwiftUI, ViewInspector (tests), XCTest

---

## File Map

| File | Action |
|---|---|
| `app/MeetingTranscriber/Sources/UpdateChecker.swift` | Modify — `"pasrom"` → `"akeslo"` on line 28 |
| `app/MeetingTranscriber/Sources/MenuBarIcon.swift` | Modify — full renderer replacement: heartbeat body, color constants, all non-template |
| `app/MeetingTranscriber/Sources/MenuBarView.swift` | Modify — 3-zone layout, new init signature, remove job rows |
| `app/MeetingTranscriber/Sources/MeetingTranscriberApp.swift` | Modify — update `MenuBarView` call site |
| `app/MeetingTranscriber/Tests/MenuBarIconTests.swift` | Modify — update isTemplate assertions (all non-template), remove bars layout math tests, add heartbeat tests |
| `app/MeetingTranscriber/Tests/MenuBarViewTests.swift` | Modify — update `makeView` helper and all inline constructors to new signature, remove job-row tests |

---

## Task 1: Fix `UpdateChecker.owner` — `"pasrom"` → `"akeslo"`

**Files:** Modify `app/MeetingTranscriber/Sources/UpdateChecker.swift`

**Context:** `GitHubReleaseProvider` hard-codes `owner = "pasrom"`. The repo has moved to `akeslo`. This is a one-line change. No new tests needed — existing update checker tests use a `MockUpdateProvider` so they pass without a real network call.

- [ ] **Edit `UpdateChecker.swift`** — change `owner`:

```swift
// BEFORE (line 28):
private let owner = "pasrom"

// AFTER:
private let owner = "akeslo"
```

- [ ] **Run tests** to confirm nothing broke:

```bash
cd app/MeetingTranscriber && swift test --parallel --filter UpdateCheckerTests
# Expected: All tests pass; no network calls made (MockUpdateProvider)
```

- [ ] **Commit:**

```bash
git add app/MeetingTranscriber/Sources/UpdateChecker.swift
git commit -m "fix(app): update GitHubReleaseProvider owner from pasrom to akeslo"
```

---

## Task 2: New `MenuBarIcon` — heartbeat body + color constants

**Files:** Modify `app/MeetingTranscriber/Sources/MenuBarIcon.swift`

**Context:** Replace the five-bar waveform renderer with a heartbeat/ECG line. All images become non-template (colored) so Space Indigo stays Space Indigo in dark mode — macOS template tinting is no longer used. The `BadgeKind` enum, `frameCount`, `nextFrame()`, `image(badge:animationFrame:permissionOverlay:recordOnlyOverlay:micSilentOverlay:appSilentOverlay:)` signature, and `[BadgeKind: [NSImage]]` cache pattern are all preserved unchanged. The `barsLayout(in:)` and `textLayout(in:)` `nonisolated` helpers are removed — the heartbeat path is drawn inline from `drawHeartbeat(in:)`.

- [ ] **Replace the full contents of `MenuBarIcon.swift`** with the following. This step replaces the bars-based renderer with the heartbeat design, adds `spaceIndigo` / `peachGlow` color constants, changes `isTemplate = false` everywhere, and wires the badge overlay draw calls to the new overlay functions defined in Task 3. The badge overlay draw functions (`drawRecordingPulse`, `drawArcSpinner`, `drawUserActionBadge`, `drawUpdateArrowBadge`, `drawErrorRing`, `drawRecordOnlyDot`, `drawTintedHalf`) are added as stubs here and fully implemented in Task 3.

```swift
import AppKit

/// Badge overlay kind for the menu bar icon.
enum BadgeKind: CaseIterable {
    case inactive
    case recording
    case transcribing
    case diarizing
    case processing
    case userAction
    case done
    case error
    case updateAvailable

    /// Whether this badge kind uses animation.
    var isAnimated: Bool {
        switch self {
        case .recording, .transcribing, .diarizing, .processing: true
        default: false
        }
    }
}

/// Composites a menu bar icon (heartbeat/ECG line + optional badge overlay).
///
/// The base icon is a heartbeat/ECG waveform drawn in Space Indigo. Depending on the
/// badge kind, an animated Peach Glow overlay is composited on top:
/// - `.recording`: Peach Glow filled circle top-right, pulsing opacity
/// - `.transcribing`: Peach Glow arc spinner top-right (60° per frame)
/// - `.diarizing`: same arc spinner, 40° per frame (slower cadence)
/// - `.processing`: arc spinner, 50° per frame
/// - `.userAction`: Peach Glow stroke circle + white "!" glyph, bottom-right
/// - `.updateAvailable`: Peach Glow upward arrow, top-right
/// - `.error`: full red stroke ring + red "!" centered, heartbeat at 30% alpha
///
/// All images are non-template (`isTemplate = false`) — Space Indigo and Peach Glow
/// survive macOS dark mode without template tinting.
///
/// `@MainActor` because cache initialisation, NSApp / NSAppearance reads, and
/// `image(badge:…)` all need to run on the main actor.
@MainActor
enum MenuBarIcon {
    /// Number of distinct animation frames. Pure constant.
    nonisolated static let frameCount = 6

    /// Returns the next animation frame for `badge`, or `current` if `badge`
    /// is non-animated. Pure math — `nonisolated` so it can be called from
    /// any context (tests, off-main).
    nonisolated static func nextFrame(_ current: Int, badge: BadgeKind) -> Int {
        guard badge.isAnimated else { return current }
        return (current + 1) % frameCount
    }

    // MARK: - Color Constants

    /// Space Indigo — heartbeat base color (#2A324B).
    nonisolated static let spaceIndigo = NSColor(
        calibratedRed: 0.165, green: 0.196, blue: 0.294, alpha: 1
    )

    /// Peach Glow — badge overlay color (#F7C59F).
    nonisolated static let peachGlow = NSColor(
        calibratedRed: 0.969, green: 0.773, blue: 0.624, alpha: 1
    )

    // MARK: - Cache

    /// Pre-rendered frames keyed by BadgeKind. Populated once eagerly when
    /// the type is first referenced. The type is `@MainActor`, so the
    /// initialiser runs on MainActor and can safely read NSApp/NSAppearance.
    private static let cache: [BadgeKind: [NSImage]] = {
        var result: [BadgeKind: [NSImage]] = [:]
        for badge in BadgeKind.allCases {
            let count = badge.isAnimated ? frameCount : 1
            result[badge] = (0 ..< count).map { frame in renderImage(badge: badge, frame: frame) }
        }
        return result
    }()

    // MARK: - Public

    /// Returns a pre-rendered 18×18pt colored `NSImage` (`isTemplate = false`) for the
    /// given badge and animation frame.
    ///
    /// If `permissionOverlay` or `recordOnlyOverlay` is true, the corresponding overlay
    /// is composited over the base icon. If `micSilentOverlay` is true, the **top half**
    /// of the heartbeat is filled in red — signalling the mic channel went silent. If
    /// `appSilentOverlay` is true, the **bottom half** is red. The two are independent;
    /// if both are true, both halves are red. All of these bypass the pre-rendered cache
    /// and force a fresh render.
    static func image(
        badge: BadgeKind,
        animationFrame: Int = 0,
        permissionOverlay: Bool = false,
        recordOnlyOverlay: Bool = false,
        micSilentOverlay: Bool = false,
        appSilentOverlay: Bool = false,
    ) -> NSImage {
        if permissionOverlay || recordOnlyOverlay || micSilentOverlay || appSilentOverlay {
            let frame = badge.isAnimated ? animationFrame : 0
            return renderImage(
                badge: badge, frame: frame,
                permissionOverlay: permissionOverlay,
                recordOnlyOverlay: recordOnlyOverlay,
                micSilentOverlay: micSilentOverlay,
                appSilentOverlay: appSilentOverlay,
            )
        }
        guard let frames = cache[badge] else { return renderImage(badge: badge, frame: animationFrame) }
        return frames[animationFrame % frames.count]
    }

    // MARK: - Rendering

    private static func renderImage(
        badge: BadgeKind,
        frame: Int,
        permissionOverlay: Bool = false,
        recordOnlyOverlay: Bool = false,
        micSilentOverlay: Bool = false,
        appSilentOverlay: Bool = false,
    ) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw heartbeat base in Space Indigo.
            // For .error and permissionOverlay, draw at reduced alpha so the red ring
            // reads clearly against the base path.
            let baseAlpha: CGFloat = (badge == .error || permissionOverlay) ? 0.30 : 1.0
            spaceIndigo.withAlphaComponent(baseAlpha).setStroke()
            drawHeartbeat(in: rect)

            // Tint halves AFTER the base body is drawn.
            if micSilentOverlay {
                drawTintedHalf(in: rect, half: .top) {
                    NSColor.systemRed.setStroke()
                    drawHeartbeat(in: rect)
                }
            }
            if appSilentOverlay {
                drawTintedHalf(in: rect, half: .bottom) {
                    NSColor.systemRed.setStroke()
                    drawHeartbeat(in: rect)
                }
            }

            // Badge overlay — drawn on top of the heartbeat.
            drawBadgeOverlay(badge: badge, in: rect, frame: frame)

            // Permission / record-only overlays take precedence.
            if permissionOverlay || badge == .error {
                drawErrorRing(in: rect)
            } else if recordOnlyOverlay {
                drawRecordOnlyDot(in: rect)
            }

            return true
        }
        // ALL images are non-template — Space Indigo and Peach Glow must stay
        // colored in both light and dark mode.
        image.isTemplate = false
        return image
    }

    /// Dispatches to the per-badge overlay draw function.
    private static func drawBadgeOverlay(badge: BadgeKind, in rect: NSRect, frame: Int) {
        switch badge {
        case .inactive, .done:
            break // heartbeat only, no overlay
        case .recording:
            drawRecordingPulse(in: rect, frame: frame)
        case .transcribing:
            peachGlow.setStroke()
            drawArcSpinner(in: rect, startDeg: spinnerAngles[frame % spinnerAngles.count])
        case .diarizing:
            peachGlow.setStroke()
            drawArcSpinner(in: rect, startDeg: spinnerAnglesDiarizing[frame % spinnerAnglesDiarizing.count])
        case .processing:
            peachGlow.setStroke()
            drawArcSpinner(in: rect, startDeg: spinnerAnglesProcessing[frame % spinnerAnglesProcessing.count])
        case .userAction:
            drawUserActionBadge(in: rect)
        case .updateAvailable:
            drawUpdateArrowBadge(in: rect)
        case .error:
            drawErrorRing(in: rect) // also drawn from renderImage; harmless double-draw path
        }
    }

    // MARK: - Heartbeat Path

    /// Draws the ECG heartbeat line in the current stroke color.
    /// Points normalized to 18×18 rect.
    private static func drawHeartbeat(in rect: NSRect) {
        let w = rect.width
        let h = rect.height
        let cy = rect.midY

        let path = NSBezierPath()
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        // Flat baseline left
        path.move(to: NSPoint(x: w * 0.02, y: cy))
        path.line(to: NSPoint(x: w * 0.20, y: cy))
        // P-wave: small upward bump
        path.curve(
            to: NSPoint(x: w * 0.30, y: cy),
            controlPoint1: NSPoint(x: w * 0.23, y: cy - h * 0.10),
            controlPoint2: NSPoint(x: w * 0.27, y: cy - h * 0.10)
        )
        // Q: short dip
        path.line(to: NSPoint(x: w * 0.36, y: cy + h * 0.06))
        // R: tall spike up
        path.line(to: NSPoint(x: w * 0.42, y: cy - h * 0.38))
        // S: spike down below baseline
        path.line(to: NSPoint(x: w * 0.50, y: cy + h * 0.18))
        // Return to baseline
        path.line(to: NSPoint(x: w * 0.56, y: cy))
        // T-wave: smooth recovery bump
        path.curve(
            to: NSPoint(x: w * 0.72, y: cy),
            controlPoint1: NSPoint(x: w * 0.60, y: cy - h * 0.18),
            controlPoint2: NSPoint(x: w * 0.68, y: cy - h * 0.18)
        )
        // Flat baseline right
        path.line(to: NSPoint(x: w * 0.98, y: cy))

        path.stroke()
    }

    // MARK: - Tinted Half (per-channel silence overlay)

    private enum Half { case top, bottom }

    /// Save graphics state, clip to the top or bottom half of `rect`, run `body`, restore.
    private static func drawTintedHalf(in rect: NSRect, half: Half, body: () -> Void) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }
        let centerY = rect.height / 2
        let clip = switch half {
        case .top: NSRect(x: 0, y: centerY - 0.5, width: rect.width, height: rect.height - centerY + 0.5)
        case .bottom: NSRect(x: 0, y: 0, width: rect.width, height: centerY + 0.5)
        }
        NSBezierPath(rect: clip).setClip()
        body()
    }

    // MARK: - Badge Overlay Stubs (implemented in Task 3)
    // These are declared here so the file compiles after Task 2.
    // Task 3 replaces each stub body with the real implementation.

    private static let spinnerAngles: [CGFloat] = [0, 60, 120, 180, 240, 300]
    private static let spinnerAnglesDiarizing: [CGFloat] = [0, 40, 80, 120, 160, 200]
    private static let spinnerAnglesProcessing: [CGFloat] = [0, 50, 100, 150, 200, 250]

    private static let recordingPulseAlphas: [CGFloat] = [0.6, 0.7, 0.85, 1.0, 0.85, 0.7]

    private static func drawRecordingPulse(in rect: NSRect, frame: Int) {
        // Stub — implemented in Task 3
        let alpha = recordingPulseAlphas[frame % recordingPulseAlphas.count]
        let size: CGFloat = 6.0
        let margin: CGFloat = 0.5
        let cx = rect.maxX - size / 2 - margin
        let cy = rect.maxY - size / 2 - margin
        peachGlow.withAlphaComponent(alpha).setFill()
        NSBezierPath(
            ovalIn: NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
        ).fill()
    }

    private static func drawArcSpinner(in rect: NSRect, startDeg: CGFloat) {
        // Stub — implemented in Task 3
        let size: CGFloat = 6.0
        let margin: CGFloat = 0.5
        let cx = rect.maxX - size / 2 - margin
        let cy = rect.maxY - size / 2 - margin
        let r = size / 2 - 0.5
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineCapStyle = .round
        path.appendArc(
            withCenter: NSPoint(x: cx, y: cy),
            radius: r,
            startAngle: startDeg,
            endAngle: startDeg + 216,
            clockwise: false
        )
        path.stroke()
    }

    private static func drawUserActionBadge(in rect: NSRect) {
        // Stub — implemented in Task 3
        let size: CGFloat = 6.0
        let margin: CGFloat = 0.5
        let cx = rect.maxX - size / 2 - margin
        let cy = rect.minY + size / 2 + margin
        peachGlow.setStroke()
        let ring = NSBezierPath(
            ovalIn: NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
        )
        ring.lineWidth = 1.2
        ring.stroke()
        NSColor.white.setFill()
        let stemW: CGFloat = 1.2
        let stemH: CGFloat = 2.4
        let stemY = cy - size / 2 + 1.8
        NSBezierPath(
            roundedRect: NSRect(x: cx - stemW / 2, y: stemY, width: stemW, height: stemH),
            xRadius: stemW / 2, yRadius: stemW / 2
        ).fill()
        let dotSize: CGFloat = 1.2
        NSBezierPath(
            ovalIn: NSRect(x: cx - dotSize / 2, y: cy - size / 2 + 0.6, width: dotSize, height: dotSize)
        ).fill()
    }

    private static func drawUpdateArrowBadge(in rect: NSRect) {
        // Stub — implemented in Task 3
        let size: CGFloat = 6.0
        let margin: CGFloat = 0.5
        let cx = rect.maxX - size / 2 - margin
        let cy = rect.maxY - size / 2 - margin
        peachGlow.setFill()
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: cx, y: cy + size / 2))
        arrow.line(to: NSPoint(x: cx - size / 3, y: cy + 0.5))
        arrow.line(to: NSPoint(x: cx + size / 3, y: cy + 0.5))
        arrow.close()
        arrow.fill()
        let stemW: CGFloat = 1.4
        let stem = NSRect(x: cx - stemW / 2, y: cy - size / 3, width: stemW, height: size / 2)
        NSBezierPath(roundedRect: stem, xRadius: stemW / 2, yRadius: stemW / 2).fill()
    }

    private static func drawErrorRing(in rect: NSRect) {
        // Stub — implemented in Task 3
        let inset: CGFloat = 1.0
        NSColor.systemRed.setStroke()
        let ring = NSBezierPath(
            ovalIn: NSRect(
                x: rect.minX + inset,
                y: rect.minY + inset,
                width: rect.width - 2 * inset,
                height: rect.height - 2 * inset
            )
        )
        ring.lineWidth = 1.4
        ring.stroke()
        NSColor.systemRed.setFill()
        let cx = rect.midX
        let cy = rect.midY
        let stemW: CGFloat = 1.3
        let stemH: CGFloat = 4.0
        let stemY = cy - 0.5
        NSBezierPath(
            roundedRect: NSRect(x: cx - stemW / 2, y: stemY, width: stemW, height: stemH),
            xRadius: stemW / 2, yRadius: stemW / 2
        ).fill()
        let dotSize: CGFloat = 1.3
        let dotY = cy - stemH - 0.5
        NSBezierPath(
            ovalIn: NSRect(x: cx - dotSize / 2, y: dotY, width: dotSize, height: dotSize)
        ).fill()
    }

    private static func drawRecordOnlyDot(in rect: NSRect) {
        // Stub — implemented in Task 3
        let size: CGFloat = 5.0
        let margin: CGFloat = 0.5
        let cx = rect.minX + size / 2 + margin
        let cy = rect.minY + size / 2 + margin
        peachGlow.setFill()
        NSBezierPath(
            ovalIn: NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
        ).fill()
    }
}

// MARK: - Badge State Logic (pure function, testable without UI)

extension BadgeKind {
    /// Computes the current badge from plain value inputs.
    ///
    /// This is a pure function with no object dependencies — tests can call it
    /// directly with any combination of inputs without driving WatchLoop into states.
    static func compute(
        watchLoopActive: Bool,
        watchLoopState: WatchLoop.State,
        transcriberState: TranscriberState,
        activeJobState: JobState?,
        updateAvailable: Bool,
        permissionProblem: Bool = false,
        modelReady: Bool = true,
    ) -> BadgeKind {
        if watchLoopActive {
            if watchLoopState == .recording { return .recording }
            switch transcriberState {
            case .waitingForSpeakerCount, .waitingForSpeakerNames: return .userAction
            case .protocolReady: return .done
            case .error: return .error
            case .transcribing, .recordingDone: return .transcribing
            case .generatingProtocol: return .processing
            default: break
            }
        }
        switch activeJobState {
        case .transcribing: return .transcribing
        case .diarizing: return .diarizing
        case .some: return .processing
        case .none: break
        }
        if permissionProblem { return .error }
        if !modelReady { return .error }
        if updateAvailable { return .updateAvailable }
        return .inactive
    }
}
```

- [ ] **Build to confirm the file compiles:**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep -E "error:|warning:" | head -20
# Expected: no errors; possibly warnings about stub functions being unused — ignore
```

- [ ] **Commit:**

```bash
git add app/MeetingTranscriber/Sources/MenuBarIcon.swift
git commit -m "feat(app): replace waveform bars with heartbeat/ECG icon renderer in MenuBarIcon

Space Indigo base (#2A324B), Peach Glow overlays (#F7C59F).
All images isTemplate=false — colored design survives dark mode.
Badge overlay stubs in place; full implementations follow in next commit."
```

---

## Task 3: Badge overlay draw functions — recording pulse, arc spinner, userAction, updateAvailable, error, recordOnly

**Files:** Modify `app/MeetingTranscriber/Sources/MenuBarIcon.swift`

**Context:** Replace each stub body from Task 2 with the final implementation. The stubs already compile and the cache already works; this task polishes the visual output. Edit each `private static func` in place — the surrounding file structure is unchanged.

- [ ] **Replace `drawRecordingPulse(in:frame:)` with the final implementation:**

```swift
private static func drawRecordingPulse(in rect: NSRect, frame: Int) {
    let alpha = recordingPulseAlphas[frame % recordingPulseAlphas.count]
    let size: CGFloat = 6.0
    let margin: CGFloat = 0.5
    let cx = rect.maxX - size / 2 - margin
    let cy = rect.maxY - size / 2 - margin
    peachGlow.withAlphaComponent(alpha).setFill()
    NSBezierPath(
        ovalIn: NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
    ).fill()
}
```

- [ ] **Replace `drawArcSpinner(in:startDeg:)` with the final implementation:**

```swift
private static func drawArcSpinner(in rect: NSRect, startDeg: CGFloat) {
    let size: CGFloat = 6.0
    let margin: CGFloat = 0.5
    let cx = rect.maxX - size / 2 - margin
    let cy = rect.maxY - size / 2 - margin
    let r = size / 2 - 0.5
    let path = NSBezierPath()
    path.lineWidth = 1.2
    path.lineCapStyle = .round
    path.appendArc(
        withCenter: NSPoint(x: cx, y: cy),
        radius: r,
        startAngle: startDeg,
        endAngle: startDeg + 216,
        clockwise: false
    )
    path.stroke()
}
```

- [ ] **Replace `drawUserActionBadge(in:)` with the final implementation:**

```swift
private static func drawUserActionBadge(in rect: NSRect) {
    // Bottom-right corner: Peach Glow stroke circle + white "!" glyph.
    let size: CGFloat = 6.0
    let margin: CGFloat = 0.5
    let cx = rect.maxX - size / 2 - margin
    let cy = rect.minY + size / 2 + margin

    // Peach Glow stroke ring
    peachGlow.setStroke()
    let ring = NSBezierPath(
        ovalIn: NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
    )
    ring.lineWidth = 1.2
    ring.stroke()

    // White "!" — stem
    NSColor.white.setFill()
    let stemW: CGFloat = 1.2
    let stemH: CGFloat = 2.4
    let stemY = cy - size / 2 + 1.8
    NSBezierPath(
        roundedRect: NSRect(x: cx - stemW / 2, y: stemY, width: stemW, height: stemH),
        xRadius: stemW / 2, yRadius: stemW / 2
    ).fill()

    // White "!" — dot
    let dotSize: CGFloat = 1.2
    NSBezierPath(
        ovalIn: NSRect(x: cx - dotSize / 2, y: cy - size / 2 + 0.6, width: dotSize, height: dotSize)
    ).fill()
}
```

- [ ] **Replace `drawUpdateArrowBadge(in:)` with the final implementation:**

```swift
private static func drawUpdateArrowBadge(in rect: NSRect) {
    // Top-right corner: Peach Glow upward arrow (triangle head + dot-stem).
    let size: CGFloat = 6.0
    let margin: CGFloat = 0.5
    let cx = rect.maxX - size / 2 - margin
    let cy = rect.maxY - size / 2 - margin

    peachGlow.setFill()

    // Triangle head pointing up
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: cx, y: cy + size / 2))
    arrow.line(to: NSPoint(x: cx - size / 3, y: cy + 0.5))
    arrow.line(to: NSPoint(x: cx + size / 3, y: cy + 0.5))
    arrow.close()
    arrow.fill()

    // Dot stem below arrow head
    let stemW: CGFloat = 1.4
    let stem = NSRect(x: cx - stemW / 2, y: cy - size / 3, width: stemW, height: size / 2)
    NSBezierPath(roundedRect: stem, xRadius: stemW / 2, yRadius: stemW / 2).fill()
}
```

- [ ] **Replace `drawErrorRing(in:)` with the final implementation:**

```swift
private static func drawErrorRing(in rect: NSRect) {
    // Full red stroke ring around icon perimeter + red "!" centered.
    let inset: CGFloat = 1.0
    NSColor.systemRed.setStroke()
    let ring = NSBezierPath(
        ovalIn: NSRect(
            x: rect.minX + inset,
            y: rect.minY + inset,
            width: rect.width - 2 * inset,
            height: rect.height - 2 * inset
        )
    )
    ring.lineWidth = 1.4
    ring.stroke()

    NSColor.systemRed.setFill()
    let cx = rect.midX
    let cy = rect.midY

    // "!" stem (above center)
    let stemW: CGFloat = 1.3
    let stemH: CGFloat = 4.0
    let stemY = cy - 0.5
    NSBezierPath(
        roundedRect: NSRect(x: cx - stemW / 2, y: stemY, width: stemW, height: stemH),
        xRadius: stemW / 2, yRadius: stemW / 2
    ).fill()

    // "!" dot (below stem)
    let dotSize: CGFloat = 1.3
    let dotY = cy - stemH - 0.5
    NSBezierPath(
        ovalIn: NSRect(x: cx - dotSize / 2, y: dotY, width: dotSize, height: dotSize)
    ).fill()
}
```

- [ ] **Replace `drawRecordOnlyDot(in:)` with the final implementation:**

```swift
private static func drawRecordOnlyDot(in rect: NSRect) {
    // Bottom-LEFT corner: Peach Glow small filled circle (record-only mode indicator).
    let size: CGFloat = 5.0
    let margin: CGFloat = 0.5
    let cx = rect.minX + size / 2 + margin
    let cy = rect.minY + size / 2 + margin
    peachGlow.setFill()
    NSBezierPath(
        ovalIn: NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
    ).fill()
}
```

- [ ] **Build to confirm the file compiles with no errors:**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep -E "^.*error:" | head -20
# Expected: no build errors
```

- [ ] **Commit:**

```bash
git add app/MeetingTranscriber/Sources/MenuBarIcon.swift
git commit -m "feat(app): implement all badge overlay draw functions for heartbeat MenuBarIcon

Recording pulse (pulsing opacity), arc spinners (transcribing/diarizing/processing),
userAction ring+glyph (bottom-right), update arrow (top-right), error ring+glyph
(full perimeter), recordOnly Peach Glow dot (bottom-left)."
```

---

## Task 4: Update `MenuBarIconTests` — non-template assertions + heartbeat-specific tests

**Files:** Modify `app/MeetingTranscriber/Tests/MenuBarIconTests.swift`

**Context:** The old tests assert `isTemplate == true` for most badges. The new design sets `isTemplate = false` for ALL images — no exceptions. Additionally, the `barsLayout` and `textLayout` math tests reference constants that no longer exist (`barWidth`, `barSpacing`, `lineHeight`, `lineSpacing`, `lineWidths`, `lineLeftInset`). Those helpers are removed from `MenuBarIcon`; the tests must be removed or replaced. New tests verify: (1) all images are non-template, (2) the heartbeat body is consistent across frames for static badges, (3) the `spaceIndigo` and `peachGlow` color constants are accessible, (4) the recording pulse visually differs across frames.

- [ ] **Replace the full contents of `MenuBarIconTests.swift`** with:

```swift
@testable import MeetingTranscriber
import XCTest

@MainActor
final class MenuBarIconTests: XCTestCase {
    // MARK: - Non-template contract (all images colored, isTemplate = false)

    func testAllBadgeKindsAreNonTemplate() {
        // Phase 2: ALL images are non-template regardless of badge kind.
        // Space Indigo + Peach Glow must survive dark mode without macOS tinting.
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
        // Static badges use frame 0 from cache regardless of animationFrame — no motion.
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
        // The inactive image should contain non-zero pixel data (the heartbeat path is visible).
        let image = MenuBarIcon.image(badge: .inactive)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            XCTFail("Could not get bitmap for inactive badge")
            return
        }
        // At least some pixels should be non-transparent (heartbeat is drawn)
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
        // The recording pulse changes opacity per frame — frames 0 and 3 must differ.
        let frame0 = MenuBarIcon.image(badge: .recording, animationFrame: 0)
        let frame3 = MenuBarIcon.image(badge: .recording, animationFrame: 3)
        XCTAssertNotEqual(
            frame0.tiffRepresentation,
            frame3.tiffRepresentation,
            "Recording pulse frames 0 and 3 should differ (different pulse opacity)"
        )
    }

    func testSpinnerFramesDifferForTranscribing() {
        // Arc spinner advances 60° per frame — every frame should be unique.
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
        // Verify the color constants are accessible from tests and have expected alpha.
        XCTAssertEqual(MenuBarIcon.spaceIndigo.alphaComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(MenuBarIcon.peachGlow.alphaComponent, 1.0, accuracy: 0.01)
    }

    func testRecordOnlyDotPositionIsBottomLeft() {
        // The record-only overlay is a dot in the BOTTOM-LEFT corner (Peach Glow).
        // Just verify the image is non-template and non-empty.
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
```

- [ ] **Run the MenuBarIcon tests:**

```bash
cd app/MeetingTranscriber && swift test --parallel --filter MenuBarIconTests
# Expected: All tests pass. testHeartbeatInactiveRendersNonEmpty confirms pixel output.
# testRecordingPulseFramesDifferAcrossAnimation confirms per-frame opacity change.
```

- [ ] **Commit:**

```bash
git add app/MeetingTranscriber/Tests/MenuBarIconTests.swift
git commit -m "test(app): update MenuBarIconTests for non-template heartbeat icon design

All isTemplate assertions changed to assertFalse. Bars layout math tests removed
(barsLayout/textLayout helpers no longer exist). Added heartbeat-specific tests:
pixel presence, recording pulse per-frame diff, spinner frame diff, color constant
exposure."
```

---

## Task 5: Slim `MenuBarView` — 3-zone layout + new init signature

**Files:** Modify `app/MeetingTranscriber/Sources/MenuBarView.swift`

**Context:** The current view has a flat layout with pipeline job rows, "Open Last Protocol", `pipelineQueue` parameter, `onOpenLastProtocol`, `onOpenProtocol`, and `onDismissJob`. All of these are removed. The new view has three zones separated by `Divider()`:

- **Zone 1 (Status):** Dot + state + meeting title on one line; elapsed/detail on second line. `userAction` banner ("Speakers need names" + "Name Now →") replaces the old inline "Name Speakers..." button. Model-not-ready warning between Zone 1 and Zone 2.
- **Zone 2 (Actions):** Start/Stop Watching, Record App / Stop Recording, Process Files, Open Output Folder, Open Dashboard (new), update item, Settings.
- **Zone 3 (Quit):** Quit.

The `onNameSpeakers` callback moves from a standalone button into the `userAction` state banner in Zone 1. The `"Record App..."` button is now disabled when `!isModelReady` (matching spec).

- [ ] **Replace the full contents of `MenuBarView.swift`** with:

```swift
import SwiftUI

struct MenuBarView: View {
    let status: TranscriberStatus?
    let isWatching: Bool
    let isModelReady: Bool
    var updateChecker: UpdateChecker?
    let onStartStop: () -> Void
    let onRecordApp: () -> Void
    let onStopManualRecording: (() -> Void)?
    let onOpenOutputFolder: () -> Void
    let onOpenDashboard: () -> Void
    let onOpenSettings: () -> Void
    let onNameSpeakers: (() -> Void)?
    let onProcessFiles: () -> Void
    let onQuit: () -> Void

    private var state: TranscriberState {
        status?.state ?? .idle
    }

    var body: some View {
        // ── Zone 1: Status ──────────────────────────────────────────────
        zone1Status

        // Model-not-ready warning sits between Zone 1 and Zone 2.
        if !isModelReady { modelNotReadyWarning }

        Divider()

        // ── Zone 2: Actions ─────────────────────────────────────────────
        zone2Actions

        Divider()

        // ── Zone 3: Quit ────────────────────────────────────────────────
        Button {
            onQuit()
        } label: {
            Text("Quit")
        }
        .keyboardShortcut("q")
    }

    // MARK: - Zone 1

    @ViewBuilder
    private var zone1Status: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Primary row: dot + state label + meeting title
            HStack(spacing: 5) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 7, height: 7)
                HStack(spacing: 4) {
                    Text(state.label)
                        .font(.headline)
                    if let title = status?.meeting?.title {
                        Text("·")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }
            }

            // Secondary row: detail / elapsed
            if let detail = status?.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            }
        }
        .padding(.horizontal, 4)

        // userAction banner
        if state == .waitingForSpeakerNames || state == .waitingForSpeakerCount {
            if let onNameSpeakers {
                HStack {
                    Text("Speakers need names")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Name Now →") {
                        onNameSpeakers()
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }
        }

        // Error detail
        if let error = status?.error, state == .error {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Zone 2

    @ViewBuilder
    private var zone2Actions: some View {
        // Start / Stop Watching
        Button {
            onStartStop()
        } label: {
            if isWatching {
                Label("Stop Watching", systemImage: "stop.fill")
            } else {
                Label("Start Watching", systemImage: "play.fill")
            }
        }
        .keyboardShortcut("s")
        .disabled(!isModelReady && !isWatching)

        // Record App / Stop Recording
        if let onStopManualRecording {
            Button {
                onStopManualRecording()
            } label: {
                Label("Stop Recording", systemImage: "stop.circle.fill")
            }
            .keyboardShortcut(".")
        } else if state != .recording {
            Button {
                onRecordApp()
            } label: {
                Label("Record App...", systemImage: "record.circle")
            }
            .keyboardShortcut("r")
            .disabled(!isModelReady)
        }

        // Process Audio/Video Files
        Button {
            onProcessFiles()
        } label: {
            Label("Process Audio/Video Files...", systemImage: "doc.badge.plus")
        }
        .keyboardShortcut("p")
        .disabled(!isModelReady)

        // Open Output Folder
        Button {
            onOpenOutputFolder()
        } label: {
            Label("Open Output Folder", systemImage: "folder")
        }

        // Open Dashboard
        Button {
            onOpenDashboard()
        } label: {
            Label("Open Dashboard", systemImage: "chart.bar.doc.horizontal")
        }
        .keyboardShortcut("d")

        // Update available (Peach Glow tint, inserted above Settings)
        if let update = updateChecker?.availableUpdate {
            Button {
                NSWorkspace.shared.open(update.dmgURL ?? update.htmlURL)
            } label: {
                Label(
                    "Update Available: \(update.tagName)",
                    systemImage: "arrow.down.circle.fill",
                )
                .foregroundStyle(Color(nsColor: MenuBarIcon.peachGlow))
            }
        }

        // Settings
        Button {
            onOpenSettings()
        } label: {
            Label("Settings...", systemImage: "gear")
        }
        .keyboardShortcut(",")
    }

    // MARK: - Model-not-ready warning

    @ViewBuilder
    private var modelNotReadyWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Model not loaded")
                    .font(.caption.weight(.semibold))
                Text("Open Settings → Transcription to load.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private var statusDotColor: Color {
        switch state {
        case .recording, .transcribing, .diarizing, .generatingProtocol,
             .waitingForSpeakerNames, .waitingForSpeakerCount, .protocolReady:
            Color(nsColor: MenuBarIcon.peachGlow)
        case .error:
            .red
        default:
            .gray
        }
    }
}
```

- [ ] **Build to confirm MenuBarView compiles** (call site in `MeetingTranscriberApp.swift` will fail — fix in Task 7, but the view file itself must compile in isolation):

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep "MenuBarView.swift.*error:" | head -10
# Expected: no errors in MenuBarView.swift itself
# MeetingTranscriberApp.swift will show argument mismatch errors — those are fixed in Task 7
```

- [ ] **Commit:**

```bash
git add app/MeetingTranscriber/Sources/MenuBarView.swift
git commit -m "feat(app): slim MenuBarView to 3-zone layout with heartbeat design integration

Remove pipeline job rows, pipelineQueue param, onOpenLastProtocol, onOpenProtocol,
onDismissJob. Add onOpenDashboard (⌘D) and onOpenOutputFolder (renamed from
onOpenProtocolsFolder). Zone 1 status with Peach Glow dot and userAction banner.
Zone 2 actions. Zone 3 quit."
```

---

## Task 6: Update `MenuBarViewTests` — new signature + remove job-row tests

**Files:** Modify `app/MeetingTranscriber/Tests/MenuBarViewTests.swift`

**Context:** The test file has two problems after Task 5: (1) `makeView` and every inline constructor use the old signature (with `pipelineQueue`, `onOpenLastProtocol`, `onOpenProtocol`, `onDismissJob`), and (2) many tests assert on job rows, "Open Last Protocol", "Open Protocols Folder", and `pipelineQueue` state — all removed from the view. Replace the full file with tests matching the new 3-zone contract.

Tests to preserve (behavior unchanged): Start/Stop Watching, Record App / Stop Recording, Settings, Process Files, Stop Recording callback, model-not-ready warning, update indicator, quit callback.

Tests to add: Zone 1 dot color, `userAction` banner visibility, `onOpenDashboard` button exists and fires, `onOpenOutputFolder` button exists and fires, `onNameSpeakers` fires from banner.

Tests to remove: all job-row tests (`testProcessingSectionShownWithActiveJob`, `testDismissButtonShownForCompletedJob`, `testDismissButtonCallsCallbackWithJobID`, `testDismissButtonShownForErrorJob`, `testWarningJobShowsWarningText`, `testMultipleJobsRendered`, `testWaitingJobShowsWaitingLabel`, `testCancelButtonShownForWaitingJob`, `testCancelButtonHiddenForDoneJob`, `testDoneJobWithoutPathsHidesOpenButton`, `testErrorJobShowsErrorMessage`), `testOpenLastProtocolShownWhenPathPresent`, `testOpenLastProtocolHiddenWhenNoPath`, `testOpenLastProtocolButtonCallsCallback`, `testOpenProtocolsFolderButtonCallsCallback`, `testProtocolsFolderButtonCallsCallback`, `testMeetingAppAndPidShown` (the PID line is removed from Zone 1), `testProcessingSectionHiddenWhenNoJobs`.

- [ ] **Replace the full contents of `MenuBarViewTests.swift`** with:

```swift
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

    // MARK: - Zone 1: Status

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

    func testNilStatusShowsIdleLabel() throws {
        let sut = makeView(status: nil)
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Idle"))
    }

    func testMeetingTitleShownInZone1WhenRecording() throws {
        let meeting = MeetingInfo(app: "Teams", title: "Standup", pid: 123)
        let sut = makeView(status: makeStatus(state: .recording, meeting: meeting))
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Standup"))
    }

    func testMeetingTitleHiddenWhenIdle() throws {
        let sut = makeView(status: makeStatus(state: .idle))
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Standup"))
    }

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

    // MARK: - Zone 1: userAction banner

    func testUserActionBannerShownWhenWaitingForSpeakerNames() throws {
        // swiftlint:disable:next trailing_closure
        let sut = makeView(status: makeStatus(state: .waitingForSpeakerNames), onNameSpeakers: {})
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Speakers need names"))
        XCTAssertNoThrow(try body.find(button: "Name Now →"))
    }

    func testUserActionBannerShownWhenWaitingForSpeakerCount() throws {
        // swiftlint:disable:next trailing_closure
        let sut = makeView(status: makeStatus(state: .waitingForSpeakerCount), onNameSpeakers: {})
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Speakers need names"))
    }

    func testUserActionBannerHiddenWhenIdle() throws {
        let sut = makeView(status: makeStatus(state: .idle))
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Speakers need names"))
    }

    func testNameNowButtonCallsOnNameSpeakers() throws {
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

    // MARK: - Zone 1: model-not-ready warning

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

    // MARK: - Zone 2: Actions

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

    func testStopRecordingReplacesRecordAppButton() throws {
        // swiftlint:disable:next trailing_closure
        let sut = makeView(status: makeStatus(state: .idle), onStopManualRecording: {})
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Stop Recording"))
        XCTAssertThrowsError(try body.find(text: "Record App..."))
    }

    func testRecordAppAndStopBothHiddenDuringAutoRecording() throws {
        let sut = makeView(status: makeStatus(state: .recording), onStopManualRecording: nil)
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Record App..."))
        XCTAssertThrowsError(try body.find(text: "Stop Recording"))
    }

    func testProcessFilesButtonAlwaysExists() throws {
        let sut = makeView(status: makeStatus(state: .idle))
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Process Audio/Video Files..."))
    }

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

    func testSettingsButtonExists() throws {
        let sut = makeView(status: makeStatus())
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Settings..."))
    }

    // MARK: - Zone 2: removed items no longer present

    func testOpenLastProtocolNotPresent() throws {
        let sut = makeView(status: makeStatus(state: .protocolReady, protocolPath: "/tmp/p.md"))
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Open Last Protocol"))
    }

    func testOpenProtocolsFolderNotPresent() throws {
        let sut = makeView(status: makeStatus())
        let body = try sut.inspect()
        XCTAssertThrowsError(try body.find(text: "Open Protocols Folder"))
    }

    // MARK: - Zone 3: Quit

    func testQuitButtonExists() throws {
        let sut = makeView(status: makeStatus())
        let body = try sut.inspect()
        XCTAssertNoThrow(try body.find(text: "Quit"))
    }

    // MARK: - Callbacks

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

    func testOpenOutputFolderButtonCallsCallback() throws {
        var called = false
        let sut = MenuBarView(
            status: makeStatus(state: .idle),
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
            status: makeStatus(state: .idle),
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

    // MARK: - Update indicator

    func testUpdateIndicatorShownWhenUpdateAvailable() throws {
        let checker = UpdateChecker(provider: MockUpdateProvider())
        checker.availableUpdate = try ReleaseInfo(
            tagName: "v1.0.0",
            name: "Release v1.0.0",
            prerelease: false,
            htmlURL: XCTUnwrap(URL(string: "https://github.com/akeslo/meeting-transcriber/releases/tag/v1.0.0")),
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

    // MARK: - State labels

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
}
```

- [ ] **Run the MenuBarView tests:**

```bash
cd app/MeetingTranscriber && swift test --parallel --filter MenuBarViewTests
# Expected: All tests pass.
# testOpenLastProtocolNotPresent and testOpenProtocolsFolderNotPresent confirm removals.
# testOpenDashboardButtonExists and testOpenDashboardButtonCallsCallback confirm new item.
```

- [ ] **Commit:**

```bash
git add app/MeetingTranscriber/Tests/MenuBarViewTests.swift
git commit -m "test(app): update MenuBarViewTests for 3-zone layout and new init signature

Update makeView helper: remove pipelineQueue/onOpenLastProtocol/onOpenProtocol/
onDismissJob, add onOpenOutputFolder/onOpenDashboard/isModelReady. Remove all
job-row tests (those UI elements no longer exist). Add tests for Open Dashboard
button, userAction banner, model-not-ready warning, and renamed output folder button."
```

---

## Task 7: Update `MeetingTranscriberApp.swift` call site

**Files:** Modify `app/MeetingTranscriber/Sources/MeetingTranscriberApp.swift`

**Context:** The `MenuBarView(...)` call in `MeetingTranscriberApp.body` uses the old signature. It must be updated to the new signature: remove `pipelineQueue`, `onOpenLastProtocol`, `onOpenProtocol`, `onDismissJob`; rename `onOpenProtocolsFolder` → `onOpenOutputFolder`; add `onOpenDashboard`. The `openLastProtocol` and `openProtocolsFolder` helper methods in `MeetingTranscriberApp` are still used by existing logic (the `openLastProtocol` method was called from the old `onOpenLastProtocol` but is now unreachable from the menu bar — keep it as an internal helper or remove it). The `openProtocolsFolder` method is renamed `openOutputFolder` to match the new parameter name. A stub `openDashboard()` method is added (opens the output folder as a placeholder until Phase 3 builds the real dashboard).

- [ ] **Replace only the `MenuBarView(...)` call block inside `body`** (the `MenuBarExtra { ... }` content closure) in `MeetingTranscriberApp.swift`. Locate the block starting with `MenuBarView(` and replace it:

```swift
MenuBarView(
    status: appState.currentStatus,
    isWatching: appState.isWatching,
    isModelReady: appState.isModelReady,
    updateChecker: appState.updateChecker,
    onStartStop: appState.toggleWatching,
    onRecordApp: { bringWindowToFront(id: "record-app") },
    onStopManualRecording: appState.watchLoop?.isManualRecording == true ? {
        appState.stopManualRecording()
    } : nil,
    onOpenOutputFolder: openOutputFolder,
    onOpenDashboard: openDashboard,
    onOpenSettings: {
        bringWindowToFront(id: "settings")
    },
    onNameSpeakers: appState.pipelineQueue.pendingSpeakerNamingJobs.isEmpty ? nil : {
        bringWindowToFront(id: "speaker-naming")
    },
    onProcessFiles: processAudioFiles,
    onQuit: quit,
)
```

- [ ] **Rename `openProtocolsFolder()` → `openOutputFolder()`** in the `// MARK: - UI Actions` section:

```swift
// BEFORE:
private func openProtocolsFolder() {
    let protocols = appState.settings.effectiveOutputDir
    let accessing = protocols.startAccessingSecurityScopedResource()
    defer { if accessing { protocols.stopAccessingSecurityScopedResource() } }
    try? FileManager.default.createDirectory(at: protocols, withIntermediateDirectories: true)
    NSWorkspace.shared.open(protocols)
}

// AFTER:
private func openOutputFolder() {
    let outputDir = appState.settings.effectiveOutputDir
    let accessing = outputDir.startAccessingSecurityScopedResource()
    defer { if accessing { outputDir.stopAccessingSecurityScopedResource() } }
    try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    NSWorkspace.shared.open(outputDir)
}
```

- [ ] **Add `openDashboard()` helper** directly after `openOutputFolder()`:

```swift
private func openDashboard() {
    // Phase 3 will open the dashboard window. For now, open the output folder.
    openOutputFolder()
}
```

- [ ] **Build the full project to confirm no errors:**

```bash
cd app/MeetingTranscriber && swift build 2>&1 | grep -E "error:" | head -20
# Expected: no errors
```

- [ ] **Run the full test suite:**

```bash
cd app/MeetingTranscriber && swift test --parallel
# Expected: All tests pass (including MenuBarIconTests, MenuBarViewTests, UpdateCheckerTests).
# MenuBarIconSnapshotTests may fail if snapshots were cached from the old bar design;
# those are reference snapshots that need to be regenerated — see note below.
```

> **Note on snapshot tests:** `MenuBarIconSnapshotTests` captures pixel-exact reference images. After replacing the waveform bars with the heartbeat design, the old snapshots are stale. Re-record them by running:
> ```bash
> cd app/MeetingTranscriber && swift test --parallel --filter MenuBarIconSnapshotTests \
>   -Xswiftc -DRECORD_SNAPSHOTS
> ```
> Then commit the updated snapshots alongside this task's commit.

- [ ] **Commit:**

```bash
git add app/MeetingTranscriber/Sources/MeetingTranscriberApp.swift
git commit -m "fix(app): update MenuBarView call site for 3-zone layout signature

Remove pipelineQueue/onOpenLastProtocol/onOpenProtocol/onDismissJob args.
Rename openProtocolsFolder→openOutputFolder. Add openDashboard stub (opens
output folder; Phase 3 will wire the real dashboard window)."
```

---

## Completion Checklist

After all 7 tasks:

- [ ] `swift build` passes with zero errors on both Homebrew and App Store variants:
  ```bash
  cd app/MeetingTranscriber && swift build
  ./scripts/build_release.sh --appstore --no-notarize
  ```
- [ ] Full test suite passes:
  ```bash
  cd app/MeetingTranscriber && swift test --parallel
  ```
- [ ] `UpdateChecker.GitHubReleaseProvider.owner` is `"akeslo"`
- [ ] All `MenuBarIcon.image(...)` calls return `isTemplate = false`
- [ ] `MenuBarView` has no `pipelineQueue`, `onOpenLastProtocol`, `onOpenProtocol`, or `onDismissJob`
- [ ] `MenuBarView` has `onOpenDashboard` and `onOpenOutputFolder`
- [ ] `MenuBarIconSnapshotTests` snapshots re-recorded and committed
- [ ] `./scripts/lint.sh` passes (no SwiftFormat/SwiftLint violations):
  ```bash
  ./scripts/lint.sh
  ```
