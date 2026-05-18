import Foundation

/// A user-configured website/browser-tab pattern for meeting detection.
struct WebsiteWatchEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var titleContains: String
    var enabled: Bool

    init(id: UUID = UUID(), name: String, titleContains: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.titleContains = titleContains
        self.enabled = enabled
    }

    static let defaults: [WebsiteWatchEntry] = [
        WebsiteWatchEntry(name: "Microsoft Teams", titleContains: "Microsoft Teams", enabled: true),
        WebsiteWatchEntry(name: "YouTube", titleContains: "YouTube", enabled: false),
    ]
}
