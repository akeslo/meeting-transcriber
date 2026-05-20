import Foundation

struct WatchedWebsite: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var urlPattern: String
    var enabled: Bool

    init(id: UUID = UUID(), name: String, urlPattern: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.urlPattern = urlPattern
        self.enabled = enabled
    }
}
