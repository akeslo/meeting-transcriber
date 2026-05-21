import CoreGraphics

/// Pattern definition for detecting active meetings via window titles.
struct AppMeetingPattern: Equatable {
    let appName: String
    let ownerNames: [String]
    let meetingPatterns: [String]
    let idlePatterns: [String]
    let minWindowWidth: CGFloat
    let minWindowHeight: CGFloat

    init(
        appName: String,
        ownerNames: [String],
        meetingPatterns: [String],
        idlePatterns: [String] = [],
        minWindowWidth: CGFloat = 200,
        minWindowHeight: CGFloat = 200,
    ) {
        self.appName = appName
        self.ownerNames = ownerNames
        self.meetingPatterns = meetingPatterns
        self.idlePatterns = idlePatterns
        self.minWindowWidth = minWindowWidth
        self.minWindowHeight = minWindowHeight
    }
}

extension AppMeetingPattern {
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

    static let teams = AppMeetingPattern(
        appName: "Microsoft Teams",
        ownerNames: ["Microsoft Teams", "Microsoft Teams (work or school)"],
        meetingPatterns: [
            #".+\s*\|\s*Microsoft Teams$"#,
            #"^Meeting\s"#,
        ],
        idlePatterns: [
            #"^Microsoft Teams$"#,
            #"^Chat\s*\|"#,
        ],
    )

    static let webex = AppMeetingPattern(
        appName: "Webex",
        ownerNames: ["Cisco Webex Meetings", "Webex"],
        meetingPatterns: [
            #"Webex Meeting"#,
            #".+\s*-\s*Webex$"#,
            #"Personal Room"#,
        ],
        idlePatterns: [
            #"^Webex$"#,
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

    static let all: [AppMeetingPattern] = [zoom, teams, webex, simulator]

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
