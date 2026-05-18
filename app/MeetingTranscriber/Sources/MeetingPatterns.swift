import CoreGraphics
import Foundation

/// Pattern definition for detecting active meetings via window titles.
struct AppMeetingPattern: Equatable {
    let appName: String
    let ownerNames: [String]
    let meetingPatterns: [String]
    let idlePatterns: [String]
    /// Regex patterns applied in sequence to clean the raw window title before use as meeting name.
    let titleCleanupPatterns: [String]
    let minWindowWidth: CGFloat
    let minWindowHeight: CGFloat

    init(
        appName: String,
        ownerNames: [String],
        meetingPatterns: [String],
        idlePatterns: [String] = [],
        titleCleanupPatterns: [String] = [],
        minWindowWidth: CGFloat = 200,
        minWindowHeight: CGFloat = 200,
    ) {
        self.appName = appName
        self.ownerNames = ownerNames
        self.meetingPatterns = meetingPatterns
        self.idlePatterns = idlePatterns
        self.titleCleanupPatterns = titleCleanupPatterns
        self.minWindowWidth = minWindowWidth
        self.minWindowHeight = minWindowHeight
    }
}

extension AppMeetingPattern {
    static let teams = AppMeetingPattern(
        appName: "Microsoft Teams",
        ownerNames: ["Microsoft Teams", "Microsoft Teams (work or school)"],
        meetingPatterns: [
            #".+\s+\|\s+Microsoft Teams"#,
        ],
        idlePatterns: [
            #"^Microsoft Teams$"#,
            #"^Microsoft Teams \(work or school\)$"#,
            #"^Chat \|"#,
            #"^Activity \|"#,
            #"^Calendar \|"#,
            #"^Teams \|"#,
            #"^Files \|"#,
            #"^Assignments \|"#,
            #"^Settings \|"#,
            #"^Calls \|"#,
            #"^People \|"#,
            #"^Notifications \|"#,
        ],
        titleCleanupPatterns: [
            #"^\(\d+\)\s+"#,                                           // strip "(4) " notification count
            #"\s*\|\s*Microsoft Teams(?:\s+\(work or school\))?$"#,   // strip " | Microsoft Teams" suffix
        ],
    )

    static let zoom = AppMeetingPattern(
        appName: "Zoom",
        ownerNames: ["zoom.us"],
        meetingPatterns: [
            #"^Zoom Meeting$"#,
            #"^Zoom Webinar$"#,
            #".+\s*-\s*Zoom$"#,
        ],
        idlePatterns: [
            #"^Zoom$"#,
            #"^Zoom Workplace$"#,
            #"^Home$"#,
        ],
    )

    static let webex = AppMeetingPattern(
        appName: "Webex",
        ownerNames: ["Webex", "Cisco Webex Meetings"],
        meetingPatterns: [
            #".+\s*-\s*Webex$"#,
            #"^Meeting \|"#,
            #".+'s Personal Room"#,
        ],
        idlePatterns: [
            #"^Webex$"#,
            #"^Cisco Webex Meetings$"#,
        ],
    )

    /// Debug simulator for testing the full pipeline without a real meeting app.
    /// Run: cd tools/meeting-simulator && swift run
    static let simulator = AppMeetingPattern(
        appName: "MeetingSimulator",
        ownerNames: ["meeting-simulator"],
        meetingPatterns: [
            #"Simulator Meeting"#,
        ],
        minWindowWidth: 100,
        minWindowHeight: 100,
    )

    static let teamsBrowser = AppMeetingPattern(
        appName: "Microsoft Teams (Web)",
        ownerNames: browserOwnerNames,
        meetingPatterns: [
            #".+\s+\|\s+Microsoft Teams"#,
        ],
        idlePatterns: [
            #"^Microsoft Teams$"#,
            #"^Microsoft Teams - Microsoft Edge$"#,
            #"^Microsoft Teams - Google Chrome$"#,
        ],
        titleCleanupPatterns: [
            #"^\(\d+\)\s+"#,                          // strip "(4) " notification count
            #"\s*\|\s*Microsoft Teams$"#,             // strip " | Microsoft Teams" suffix
        ],
        minWindowWidth: 400,
        minWindowHeight: 300,
    )

    static let youtube = AppMeetingPattern(
        appName: "YouTube",
        ownerNames: browserOwnerNames,
        meetingPatterns: [
            #".+ - YouTube$"#,
            #".+ - YouTube — .+"#,   // browser-name suffix variant (em dash)
            #".+ - YouTube - .+"#,   // browser-name suffix variant (hyphen)
        ],
        idlePatterns: [
            #"^YouTube$"#,
            #"^YouTube Studio"#,
            #"^YouTube Music"#,
            #"^YouTube TV"#,
        ],
        minWindowWidth: 400,
        minWindowHeight: 300,
    )

    /// Browser process names checked for website patterns.
    static let browserOwnerNames = [
        "Google Chrome", "Microsoft Edge", "Safari",
        "Firefox", "Arc", "Brave Browser",
        "Dia", "Opera", "Vivaldi", "Orion",
    ]

    /// Build an `AppMeetingPattern` from a user-configured `WebsiteWatchEntry`.
    /// Matches any browser window whose title contains `entry.titleContains`,
    /// skips when the title is exactly the site name, and strips the suffix to
    /// produce a clean meeting name.
    static func pattern(for entry: WebsiteWatchEntry) -> AppMeetingPattern {
        let escaped = NSRegularExpression.escapedPattern(for: entry.titleContains)
        return AppMeetingPattern(
            appName: entry.name,
            ownerNames: browserOwnerNames,
            meetingPatterns: [escaped],
            idlePatterns: ["^\(escaped)$"],
            titleCleanupPatterns: [
                #"^\(\d+\)\s+"#,
                "\\s*[|\\-]\\s*\(escaped).*$",
            ],
            minWindowWidth: 400,
            minWindowHeight: 300,
        )
    }

    static let all: [AppMeetingPattern] = [teams, zoom, webex, simulator]

    static let byName: [String: AppMeetingPattern] = {
        var dict: [String: AppMeetingPattern] = [:]
        for p in all {
            dict[p.appName.lowercased()] = p
        }
        return dict
    }()

    /// Lookup pattern by app name (case-insensitive).
    static func forAppName(_ name: String) -> AppMeetingPattern? {
        byName[name.lowercased()]
    }
}
