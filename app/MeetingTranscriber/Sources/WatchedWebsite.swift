import Foundation

struct WatchedWebsite: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var urlPattern: String
    var enabled: Bool
    var recordMic: Bool

    init(id: UUID = UUID(), name: String, urlPattern: String, enabled: Bool = true, recordMic: Bool = false) {
        self.id = id
        self.name = name
        self.urlPattern = urlPattern
        self.enabled = enabled
        self.recordMic = recordMic
    }
}
