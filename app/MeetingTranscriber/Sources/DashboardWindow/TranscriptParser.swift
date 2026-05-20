import Foundation

struct TranscriptSegment: Identifiable {
    let id: UUID
    let speaker: String
    let timestamp: TimeInterval
    let body: String
}

enum TranscriptParser {
    static func parse(markdown: String) -> [TranscriptSegment] {
        let pattern = #/^\*\*(.+?)\*\* \[(\d{2}):(\d{2}):(\d{2})\]/#

        var segments: [TranscriptSegment] = []
        let lines = markdown.components(separatedBy: "\n")

        var currentSpeaker: String?
        var currentTimestamp: TimeInterval?
        var bodyLines: [String] = []

        func flush() {
            guard let speaker = currentSpeaker, let ts = currentTimestamp else { return }
            let body = bodyLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }
            segments.append(TranscriptSegment(id: UUID(), speaker: speaker, timestamp: ts, body: body))
        }

        for line in lines {
            if let match = line.firstMatch(of: pattern) {
                flush()
                currentSpeaker = String(match.1)
                let h = TimeInterval(match.2)!
                let m = TimeInterval(match.3)!
                let s = TimeInterval(match.4)!
                currentTimestamp = h * 3600 + m * 60 + s
                bodyLines = []
            } else {
                bodyLines.append(line)
            }
        }
        flush()
        return segments
    }
}
