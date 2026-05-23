import Foundation

struct TranscriptSegment: Identifiable {
    let id: UUID
    let speaker: String
    let timestamp: TimeInterval
    let body: String
}

enum TranscriptParser {
    static func parse(markdown: String) -> [TranscriptSegment] {
        // Matches: **Speaker Name** [HH:MM:SS] or **Speaker Name** [MM:SS]
        let headerPattern = #/^\*\*(.+?)\*\*\s+\[(\d+):(\d{2})(?::(\d{2}))?\]/#
        let lines = markdown.components(separatedBy: "\n")
        var segments: [TranscriptSegment] = []
        var currentSpeaker: String?
        var currentTimestamp: TimeInterval = 0
        var bodyLines: [String] = []

        func flush() {
            guard let speaker = currentSpeaker else { return }
            let body = bodyLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard !body.isEmpty else { return }
            segments.append(TranscriptSegment(
                id: UUID(),
                speaker: speaker,
                timestamp: currentTimestamp,
                body: body
            ))
        }

        for line in lines {
            if let m = line.firstMatch(of: headerPattern) {
                flush()
                bodyLines = []
                currentSpeaker = String(m.1)
                let a = TimeInterval(m.2)!
                let b = TimeInterval(m.3)!
                if let dStr = m.4, let d = TimeInterval(dStr) {
                    currentTimestamp = a * 3600 + b * 60 + d
                } else {
                    currentTimestamp = a * 60 + b
                }
            } else if currentSpeaker != nil {
                bodyLines.append(line)
            }
        }
        flush()
        return segments
    }

    // Also supports inline format: [MM:SS] Speaker: text
    static func parseInline(markdown: String) -> [TranscriptSegment] {
        let pattern = #/^\[(\d+):(\d{2})(?::(\d{2}))?\] (.+?): (.+)/#
        return markdown.components(separatedBy: "\n").compactMap { line -> TranscriptSegment? in
            guard let m = line.firstMatch(of: pattern) else { return nil }
            let a = TimeInterval(m.1)!
            let b = TimeInterval(m.2)!
            let timestamp: TimeInterval
            if let cStr = m.3, let c = TimeInterval(cStr) {
                timestamp = a * 3600 + b * 60 + c
            } else {
                timestamp = a * 60 + b
            }
            return TranscriptSegment(
                id: UUID(),
                speaker: String(m.4),
                timestamp: timestamp,
                body: String(m.5)
            )
        }
    }
}
