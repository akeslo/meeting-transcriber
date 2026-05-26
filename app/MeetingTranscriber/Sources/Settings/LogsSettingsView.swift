import Foundation
import SwiftUI

// MARK: - LogLine

struct LogLine: Identifiable, Sendable {
    let id: UUID
    let raw: String
    let timestamp: String
    let category: String
    let message: String

    private static let categoryRegex =
        try? NSRegularExpression(pattern: #"\((\w[\w\s]*)\)\[\d"#)
    private static let messageRegex =
        try? NSRegularExpression(pattern: #"<\w+>: (.+)$"#, options: .dotMatchesLineSeparators)

    static func parse(raw: String) -> LogLine {
        let ts = raw.count >= 15 ? String(raw.prefix(15)) : ""

        var category = ""
        if let m = categoryRegex?.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let r = Range(m.range(at: 1), in: raw) {
            category = String(raw[r])
        }

        var message = raw
        if let m = messageRegex?.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let r = Range(m.range(at: 1), in: raw) {
            message = String(raw[r])
        }

        return LogLine(id: UUID(), raw: raw, timestamp: ts, category: category, message: message)
    }
}

// MARK: - LogTailModel

@Observable
@MainActor
final class LogTailModel {
    private(set) var lines: [LogLine] = []
    private(set) var categories: [String] = []

    private var fileOffset: UInt64 = 0
    private var pollTask: Task<Void, Never>?

    static let maxLines = 2000
    private static let initialReadBytes: UInt64 = 65536  // ~500 syslog lines

    func start(logDirectory: URL) {
        stop()
        let url = logDirectory.appendingPathComponent(
            PersistentDiagnosticLog.logFileName(for: Date())
        )
        loadInitial(from: url)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.pollNewLines(from: url)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func loadInitial(from url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let readFrom = size > Self.initialReadBytes ? size - Self.initialReadBytes : 0
        try? handle.seek(toOffset: readFrom)
        let data = handle.readDataToEndOfFile()
        fileOffset = size
        let text = String(data: data, encoding: .utf8) ?? ""
        let parsed = text.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .suffix(500)
            .map { LogLine.parse(raw: $0) }
        lines = Array(parsed)
        updateCategories(from: lines)
    }

    private func pollNewLines(from url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: fileOffset)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }
        fileOffset += UInt64(data.count)
        let text = String(data: data, encoding: .utf8) ?? ""
        let newLines = text.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .map { LogLine.parse(raw: $0) }
        guard !newLines.isEmpty else { return }
        lines.append(contentsOf: newLines)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
        updateCategories(from: newLines)
    }

    private func updateCategories(from newLines: [LogLine]) {
        for line in newLines {
            let cat = line.category.isEmpty ? "Other" : line.category
            if !categories.contains(cat) {
                categories.append(cat)
            }
        }
    }

    /// Test seam: inject pre-built lines directly, bypassing file IO.
    func appendForTesting(_ newLines: [LogLine]) {
        lines.append(contentsOf: newLines)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
        updateCategories(from: newLines)
    }
}
