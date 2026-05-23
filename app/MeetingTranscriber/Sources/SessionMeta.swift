import Foundation

/// v2 session metadata file (`meta.json`) written inside each session folder.
struct SessionMeta: Codable {
    static let currentVersion = 2
    static let filename = "meta.json"

    let version: Int
    let title: String
    let appName: String
    let startedAt: Date
    let stoppedAt: Date
    let participants: [String]
    let micDelaySeconds: Double
    let engine: String
    let diarizerMode: String
    let files: FileRefs

    /// Duration in seconds derived from start/stop.
    var duration: TimeInterval { stoppedAt.timeIntervalSince(startedAt) }

    struct FileRefs: Codable {
        let app: String?
        let mic: String?
        let mix: String?
        let transcript: String?
        let protocol_: String?

        enum CodingKeys: String, CodingKey {
            case app, mic, mix, transcript
            case protocol_ = "protocol"
        }
    }

    init(
        title: String,
        appName: String,
        startedAt: Date,
        stoppedAt: Date,
        participants: [String],
        micDelaySeconds: Double,
        engine: String,
        diarizerMode: String,
        files: FileRefs
    ) {
        self.version = Self.currentVersion
        self.title = title
        self.appName = appName
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.participants = participants
        self.micDelaySeconds = micDelaySeconds
        self.engine = engine
        self.diarizerMode = diarizerMode
        self.files = files
    }

    /// Write `meta.json` into `dir`.
    func write(to dir: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: dir.appendingPathComponent(Self.filename), options: .atomic)
    }

    /// Read `meta.json` from `dir`.
    static func read(from dir: URL) throws -> SessionMeta {
        let data = try Data(contentsOf: dir.appendingPathComponent(filename))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionMeta.self, from: data)
    }

    /// Patch arbitrary top-level keys in `meta.json` without a full round-trip decode.
    /// Safe against unknown fields — edits only the provided keys.
    static func updateFields(
        in dir: URL,
        title: String? = nil,
        tags: [String]? = nil,
        folderGroup: String? = nil,
        removeFileKey: String? = nil
    ) throws {
        let url = dir.appendingPathComponent(filename)
        guard var dict = try JSONSerialization.jsonObject(
            with: Data(contentsOf: url)
        ) as? [String: Any] else { return }
        if let t = title { dict["title"] = t }
        if let t = tags { dict["tags"] = t }
        if let f = folderGroup { dict["folderGroup"] = f }
        if let key = removeFileKey {
            if var files = dict["files"] as? [String: Any] {
                files.removeValue(forKey: key)
                dict["files"] = files
            }
        }
        let data = try JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }
}
