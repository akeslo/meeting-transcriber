import Foundation

struct WatchedWebsite: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var urlPattern: String
    var enabled: Bool
    var recordMic: Bool
    var useRegex: Bool

    init(
        id: UUID = UUID(),
        name: String,
        urlPattern: String,
        enabled: Bool = true,
        recordMic: Bool = false,
        useRegex: Bool = false
    ) {
        self.id = id
        self.name = name
        self.urlPattern = urlPattern
        self.enabled = enabled
        self.recordMic = recordMic
        self.useRegex = useRegex
    }

    /// Returns true if `url` matches this site's pattern (substring or regex).
    func matches(url: String) -> Bool {
        guard enabled else { return false }
        if useRegex {
            guard let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) else { return false }
            return regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
        }
        return url.contains(urlPattern)
    }
}
