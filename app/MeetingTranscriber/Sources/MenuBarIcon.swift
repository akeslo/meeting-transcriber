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
    /// of the heartbeat is tinted red — signalling the mic channel went silent. If
    /// `appSilentOverlay` is true, the **bottom half** is red. All of these bypass the
    /// pre-rendered cache and force a fresh render.
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
        guard let frames = cache[badge] else { return renderImage(badge: badge, frame: animationFrame % frameCount) }
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
        case .inactive, .done, .error:
            break // heartbeat only; .error ring is drawn by renderImage unconditionally
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
        NSBezierPath(rect: clip).addClip()
        body()
    }

    // MARK: - Badge Overlays

    private static let spinnerAngles: [CGFloat] = [0, 60, 120, 180, 240, 300]
    private static let spinnerAnglesDiarizing: [CGFloat] = [0, 40, 80, 120, 160, 200]
    private static let spinnerAnglesProcessing: [CGFloat] = [0, 50, 100, 150, 200, 250]

    private static let recordingPulseAlphas: [CGFloat] = [0.6, 0.7, 0.85, 1.0, 0.85, 0.7]

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
        let dotY = cy - stemH - 1.5
        NSBezierPath(
            ovalIn: NSRect(x: cx - dotSize / 2, y: dotY, width: dotSize, height: dotSize)
        ).fill()
    }

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
