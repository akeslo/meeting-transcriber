@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import os.log

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "MeetingDetector")

/// Polls window list to detect active meeting windows.
///
/// Uses CGWindowListCopyWindowInfo to read on-screen windows.
/// Requires Screen Recording permission.
@Observable
class MeetingDetector: MeetingDetecting {
    private let patterns: [AppMeetingPattern]
    private let confirmationCount: Int
    private var consecutiveHits: [String: Int] = [:]
    private var cooldownUntil: [String: Date] = [:]
    private let cooldownDuration: TimeInterval = 5 // brief cooldown to avoid re-detecting the same meeting

    /// Pre-compiled regex for each pattern to avoid re-compilation on every poll.
    private let compiledMeetingPatterns: [String: [NSRegularExpression]]
    private let compiledIdlePatterns: [String: [NSRegularExpression]]
    private let compiledTitleCleanupPatterns: [String: [NSRegularExpression]]

    /// Closure that provides the window list. Defaults to CGWindowListCopyWindowInfo.
    /// Override in tests to inject mock window data.
    var windowListProvider: () -> [[String: Any]] = MeetingDetector.systemWindowList

    init(patterns: [AppMeetingPattern], confirmationCount: Int = 2) {
        self.patterns = patterns
        self.confirmationCount = confirmationCount

        var meeting: [String: [NSRegularExpression]] = [:]
        var idle: [String: [NSRegularExpression]] = [:]
        var cleanup: [String: [NSRegularExpression]] = [:]
        for p in patterns {
            meeting[p.appName] = p.meetingPatterns.compactMap { pattern in
                do {
                    return try NSRegularExpression(pattern: pattern)
                } catch {
                    logger.error("Invalid meeting regex for \(p.appName): \(pattern) — \(error.localizedDescription)")
                    return nil
                }
            }
            idle[p.appName] = p.idlePatterns.compactMap { pattern in
                do {
                    return try NSRegularExpression(pattern: pattern)
                } catch {
                    logger.error("Invalid idle regex for \(p.appName): \(pattern) — \(error.localizedDescription)")
                    return nil
                }
            }
            cleanup[p.appName] = p.titleCleanupPatterns.compactMap { pattern in
                do {
                    return try NSRegularExpression(pattern: pattern)
                } catch {
                    logger.error("Invalid title cleanup regex for \(p.appName): \(pattern) — \(error.localizedDescription)")
                    return nil
                }
            }
        }
        self.compiledMeetingPatterns = meeting
        self.compiledIdlePatterns = idle
        self.compiledTitleCleanupPatterns = cleanup
    }

    /// Single poll: check all windows against all patterns.
    ///
    /// Returns a `DetectedMeeting` only after `confirmationCount` consecutive
    /// positive detections for the same app.
    func checkOnce() -> DetectedMeeting? {
        let windows = windowListProvider()
        let patternCount = self.patterns.count
        logger.debug("[detect] poll: windows=\(windows.count, privacy: .public) patterns=\(patternCount, privacy: .public)")
        var hitsThisRound: Set<String> = []
        // Track first matching window per pattern for returning DetectedMeeting
        var firstMatch: [String: (title: String, window: [String: Any])] = [:]

        for window in windows {
            for pattern in patterns {
                // Skip apps in cooldown (just handled a meeting)
                if let until = cooldownUntil[pattern.appName], Date() < until {
                    continue
                }
                // Only count each pattern once per poll (prevents over-counting
                // when multiple windows match the same app)
                guard !hitsThisRound.contains(pattern.appName) else { continue }

                if let title = matchWindow(window, pattern: pattern) {
                    hitsThisRound.insert(pattern.appName)
                    firstMatch[pattern.appName] = (title, window)
                    consecutiveHits[pattern.appName, default: 0] += 1
                }
            }
        }

        // Check if any pattern reached confirmation threshold
        for (appName, hits) in consecutiveHits {
            if hits >= confirmationCount, let match = firstMatch[appName],
               let pattern = patterns.first(where: { $0.appName == appName }) {
                let pid = match.window["kCGWindowOwnerPID"] as? Int32 ?? 0

                // Reset counter before returning so a re-detection after the
                // meeting ends requires a fresh run of consecutive hits.
                consecutiveHits[appName] = 0

                return DetectedMeeting(
                    pattern: pattern,
                    windowTitle: match.title,
                    ownerName: match.window["kCGWindowOwnerName"] as? String ?? "",
                    windowPID: pid,
                )
            }
        }

        // Reset counters for apps that had no hit this round
        for appName in consecutiveHits.keys where !hitsThisRound.contains(appName) {
            consecutiveHits[appName] = 0
        }

        return nil
    }

    /// Check if a previously detected meeting is still active.
    func isMeetingActive(_ meeting: DetectedMeeting) -> Bool {
        let windows = windowListProvider()
        for window in windows where matchWindow(window, pattern: meeting.pattern) != nil {
            return true
        }
        return false
    }

    /// Reset confirmation counters and start cooldown for the given app.
    func reset(appName: String? = nil) {
        consecutiveHits.removeAll()
        if let appName {
            cooldownUntil[appName] = Date().addingTimeInterval(cooldownDuration)
        }
    }

    // MARK: - Private

    /// Match a window dict against a meeting pattern. Returns the title if matched.
    ///
    /// The ownerName check is the primary spoofing defence for browser patterns
    /// like `teamsBrowser`: a crafted page title can match the meeting regex but
    /// it can only reach the regex check if the OS-reported `kCGWindowOwnerName`
    /// is one of the expected browser process names listed in `pattern.ownerNames`.
    private func matchWindow(_ window: [String: Any], pattern: AppMeetingPattern) -> String? {
        // Always verify the OS-reported ownerName is in the allowed list before
        // matching the window title.  This prevents a web page whose title ends
        // with " | Microsoft Teams" from being treated as a real Teams meeting.
        guard let owner = window["kCGWindowOwnerName"] as? String else {
            return nil
        }
        guard pattern.ownerNames.contains(owner) else {
            logger.debug("[detect] owner-mismatch: owner=\(owner, privacy: .public) expected=\(pattern.ownerNames.joined(separator: "|"), privacy: .public)")
            return nil
        }

        let rawTitle = window["kCGWindowName"] as? String ?? ""
        let title: String
        if rawTitle.isEmpty {
            // Some browsers (e.g. Dia) don't expose kCGWindowName — fall back to AX focused window title.
            if let pid = window["kCGWindowOwnerPID"] as? Int32,
               let axTitle = MeetingDetector.axWindowTitle(pid: pid),
               !axTitle.isEmpty {
                logger.debug("[detect] ax-title-fallback: owner=\(owner, privacy: .public) title=\(axTitle, privacy: .public)")
                title = axTitle
            } else {
                logger.debug("[detect] empty-title: owner=\(owner, privacy: .public) pattern=\(pattern.appName, privacy: .public)")
                return nil
            }
        } else {
            title = rawTitle
        }

        // Check minimum size
        if let bounds = window["kCGWindowBounds"] as? [String: Any] {
            let width = bounds["Width"] as? CGFloat ?? 0
            let height = bounds["Height"] as? CGFloat ?? 0
            if width < pattern.minWindowWidth || height < pattern.minWindowHeight {
                logger.debug("[detect] too-small: owner=\(owner, privacy: .public) size=\(width, privacy: .public)x\(height, privacy: .public) min=\(pattern.minWindowWidth, privacy: .public)x\(pattern.minWindowHeight, privacy: .public)")
                return nil
            }
        }

        // Skip idle patterns (pre-compiled)
        let range = NSRange(title.startIndex..., in: title)
        if let idleRegexes = compiledIdlePatterns[pattern.appName] {
            for regex in idleRegexes where regex.firstMatch(in: title, range: range) != nil {
                logger.debug("[detect] idle-match: title=\(title, privacy: .public) pattern=\(pattern.appName, privacy: .public)")
                return nil
            }
        }

        // Match meeting patterns (pre-compiled)
        if let meetingRegexes = compiledMeetingPatterns[pattern.appName] {
            for regex in meetingRegexes where regex.firstMatch(in: title, range: range) != nil {
                let cleaned = cleanTitle(title, pattern: pattern)
                logger.debug("[detect] meeting-match: title=\(title, privacy: .public) cleaned=\(cleaned, privacy: .public) pattern=\(pattern.appName, privacy: .public)")
                return cleaned
            }
        }

        return nil
    }

    private func cleanTitle(_ title: String, pattern: AppMeetingPattern) -> String {
        guard let regexes = compiledTitleCleanupPatterns[pattern.appName], !regexes.isEmpty else {
            return title
        }
        var result = title
        for regex in regexes {
            let r = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: r, withTemplate: "")
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    /// Read the focused window title for a process via AX API.
    /// Returns nil if AX isn't available or the process has no focused window.
    static func axWindowTitle(pid: Int32) -> String? {
        let app = AXUIElementCreateApplication(pid_t(pid))
        var focusedWindow: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
              let focusedWindowObj = focusedWindow,
              CFGetTypeID(focusedWindowObj as CFTypeRef) == AXUIElementGetTypeID()
        else { return nil }
        // Safe: type ID confirmed above
        let window = focusedWindowObj as! AXUIElement // swiftlint:disable:this force_cast
        var titleVal: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleVal) == .success,
              let title = titleVal as? String else { return nil }
        return title
    }

    /// Default window list provider using CGWindowListCopyWindowInfo.
    static func systemWindowList() -> [[String: Any]] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID,
        ) as? [[String: Any]] else {
            return []
        }
        return windowList
    }
}
