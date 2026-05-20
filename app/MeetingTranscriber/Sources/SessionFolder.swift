import Foundation

/// Pure functions for per-session folder naming.
enum SessionFolder {

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    /// Lowercased, hyphenated slug from a meeting title, max 40 chars.
    static func slug(from title: String) -> String {
        guard !title.isEmpty else { return "untitled" }
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-"))
        let raw = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let cleaned = raw.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : Character("-") }
        let collapsed = String(cleaned)
            .components(separatedBy: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let result = String(collapsed.prefix(40))
            .trimmingCharacters(in: .init(charactersIn: "-"))
        return result.isEmpty ? "untitled" : result
    }

    /// Folder name: `YYYY-MM-DD_HHmmss_<slug>`.
    static func folderName(date: Date, title: String) -> String {
        "\(formatter.string(from: date))_\(slug(from: title))"
    }

    /// Full URL for a session folder inside `root/recordings/`.
    static func sessionURL(root: URL, date: Date, title: String) -> URL {
        root
            .appendingPathComponent("recordings")
            .appendingPathComponent(folderName(date: date, title: title))
    }
}
