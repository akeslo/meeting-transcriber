import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "BrowserTabDetector")

/// Detects active browser tab sessions by matching open tab URLs against
/// user-configured WatchedWebsite patterns.
///
/// Reads tab URLs via AppleScript from any running browser that supports it.
/// Chrome-style AppleScript (used by Chrome, Brave, Arc, Edge, DIA, etc.)
/// iterates all tabs across all windows. Safari uses the same approach with
/// its own dictionary.
class BrowserTabDetector: MeetingDetecting {
    struct BrowserDef {
        let processName: String
        let scriptAppName: String
        let chromiumStyle: Bool
    }

    static let knownBrowsers: [BrowserDef] = [
        BrowserDef(processName: "Safari", scriptAppName: "Safari", chromiumStyle: false),
        BrowserDef(processName: "Google Chrome", scriptAppName: "Google Chrome", chromiumStyle: true),
        BrowserDef(processName: "Chromium", scriptAppName: "Chromium", chromiumStyle: true),
        BrowserDef(processName: "Brave Browser", scriptAppName: "Brave Browser", chromiumStyle: true),
        BrowserDef(processName: "Arc", scriptAppName: "Arc", chromiumStyle: true),
        BrowserDef(processName: "Microsoft Edge", scriptAppName: "Microsoft Edge", chromiumStyle: true),
        BrowserDef(processName: "Dia", scriptAppName: "Dia", chromiumStyle: true),
        BrowserDef(processName: "Orion", scriptAppName: "Orion", chromiumStyle: false),
        BrowserDef(processName: "Vivaldi", scriptAppName: "Vivaldi", chromiumStyle: true),
        BrowserDef(processName: "Opera", scriptAppName: "Opera", chromiumStyle: true),
    ]

    private let websitesProvider: () -> [WatchedWebsite]
    private let confirmationCount: Int
    private var consecutiveHits: [UUID: Int] = [:]
    private var lastMatch: [UUID: (processName: String, pid: pid_t)] = [:]

    /// Override in tests to inject mock tab data.
    var tabURLProvider: () -> [TabInfo] = { [] }

    init(
        websitesProvider: @escaping () -> [WatchedWebsite],
        confirmationCount: Int = 2,
    ) {
        self.websitesProvider = websitesProvider
        self.confirmationCount = confirmationCount
        tabURLProvider = { [weak self] in self?.systemTabURLs() ?? [] }
    }

    func checkOnce() -> DetectedMeeting? {
        let allSites = websitesProvider()
        let sites = allSites.filter { $0.enabled }
        let disabled = allSites.filter { !$0.enabled }.map { $0.name }

        if sites.isEmpty {
            if !disabled.isEmpty {
                logger.info("browser_poll skipped — all sites disabled: \(disabled.joined(separator: ", "))")
            }
            return nil
        }

        let tabs = tabURLProvider()
        logger.info("browser_poll sites=\(sites.map { $0.name }.joined(separator: ",")) tabs=\(tabs.count)")

        var hitsThisRound: Set<UUID> = []

        for site in sites {
            for tab in tabs {
                if tab.url.lowercased().contains(site.urlPattern.lowercased()) {
                    logger.info("browser_match site=\(site.name) url=\(tab.url) browser=\(tab.processName) hits=\(self.consecutiveHits[site.id, default: 0] + 1)/\(self.confirmationCount)")
                    hitsThisRound.insert(site.id)
                    lastMatch[site.id] = (tab.processName, tab.pid)
                    consecutiveHits[site.id, default: 0] += 1
                    break
                }
            }
        }

        if hitsThisRound.isEmpty {
            logger.info("browser_poll no_match — patterns: \(sites.map { "\($0.name)=\($0.urlPattern)" }.joined(separator: ","))")
        }

        for (id, hits) in consecutiveHits {
            if hits >= confirmationCount,
               hitsThisRound.contains(id),
               let site = sites.first(where: { $0.id == id }),
               let match = lastMatch[id] {
                logger.info("browser_detected site=\(site.name) browser=\(match.processName)")
                let pattern = AppMeetingPattern(
                    appName: site.name,
                    ownerNames: [match.processName],
                    meetingPatterns: [],
                )
                return DetectedMeeting(
                    pattern: pattern,
                    windowTitle: site.name,
                    ownerName: match.processName,
                    windowPID: match.pid,
                )
            }
        }

        for site in sites where !hitsThisRound.contains(site.id) {
            consecutiveHits[site.id] = 0
        }

        return nil
    }

    func isMeetingActive(_ meeting: DetectedMeeting) -> Bool {
        guard let site = websitesProvider().first(where: { $0.name == meeting.pattern.appName }),
              site.enabled else { return false }
        let lower = site.urlPattern.lowercased()
        return tabURLProvider().contains { $0.url.lowercased().contains(lower) }
    }

    func reset(appName: String? = nil) {
        consecutiveHits.removeAll()
        lastMatch.removeAll()
    }

    // MARK: - Tab info

    struct TabInfo {
        let processName: String
        let pid: pid_t
        let url: String
    }

    // MARK: - System tab reading

    private func systemTabURLs() -> [TabInfo] {
        var results: [TabInfo] = []
        let running = NSWorkspace.shared.runningApplications

        for browser in Self.knownBrowsers {
            guard let app = running.first(where: { $0.localizedName == browser.processName }) else {
                continue
            }
            let pid = app.processIdentifier
            let script = browser.chromiumStyle
                ? chromiumScript(for: browser.scriptAppName)
                : safariScript(for: browser.scriptAppName)
            let urls = runAppleScript(script)
            logger.info("browser_fetch browser=\(browser.processName) tabs=\(urls.count)")
            results.append(contentsOf: urls.map { TabInfo(processName: browser.processName, pid: pid, url: $0) })
        }
        return results
    }

    // MARK: - AppleScript

    private func chromiumScript(for appName: String) -> String {
        """
        tell application "\(appName)"
            set allURLs to {}
            repeat with w in every window
                try
                    repeat with t in every tab of w
                        try
                            set end of allURLs to URL of t
                        end try
                    end repeat
                end try
            end repeat
            return allURLs
        end tell
        """
    }

    private func safariScript(for appName: String) -> String {
        """
        tell application "\(appName)"
            set allURLs to {}
            repeat with w in every window
                try
                    repeat with t in every tab of w
                        try
                            set end of allURLs to URL of t
                        end try
                    end repeat
                end try
            end repeat
            return allURLs
        end tell
        """
    }

    private func runAppleScript(_ source: String) -> [String] {
        var errorDict: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return [] }
        let result = script.executeAndReturnError(&errorDict)
        if let err = errorDict {
            logger.info("applescript_failed: \(err)")
            return []
        }
        return extractStrings(from: result)
    }

    private func extractStrings(from descriptor: NSAppleEventDescriptor) -> [String] {
        let count = descriptor.numberOfItems
        if count > 0 {
            return (1 ... count).compactMap { descriptor.atIndex($0)?.stringValue }
        }
        if let s = descriptor.stringValue, !s.isEmpty {
            return [s]
        }
        return []
    }
}
