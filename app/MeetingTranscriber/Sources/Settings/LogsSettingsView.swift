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
        let ts = raw.count >= 19 ? String(raw.prefix(19)) : ""

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
        lines = Array(parsed.reversed())
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
        lines.insert(contentsOf: newLines.reversed(), at: 0)
        if lines.count > Self.maxLines {
            lines.removeLast(lines.count - Self.maxLines)
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
        lines.insert(contentsOf: newLines.reversed(), at: 0)
        if lines.count > Self.maxLines {
            lines.removeLast(lines.count - Self.maxLines)
        }
        updateCategories(from: newLines)
    }
}

// MARK: - LogLineRow

private struct LogLineRow: View {
    let line: LogLine

    private var categoryColor: Color {
        guard !line.category.isEmpty else { return .secondary }
        let hash = abs(line.category.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if !line.timestamp.isEmpty {
                Text(line.timestamp)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                    .lineLimit(1)
            }
            if !line.category.isEmpty {
                Text(line.category)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(categoryColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(categoryColor.opacity(0.12))
                    .clipShape(Capsule())
                    .frame(width: 90, alignment: .leading)
                    .lineLimit(1)
            } else {
                Color.clear.frame(width: 90, height: 1)
            }
            Text(line.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}

// MARK: - LogsSettingsView

struct LogsSettingsView: View {
    @State private var model = LogTailModel()
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    private var visibleLines: [LogLine] {
        model.lines.filter { line in
            let catOK: Bool = {
                guard let sel = selectedCategory else { return true }
                let cat = line.category.isEmpty ? "Other" : line.category
                return cat == sel
            }()
            let searchOK = searchText.isEmpty
                || line.raw.localizedCaseInsensitiveContains(searchText)
            return catOK && searchOK
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbarRow
            if !model.categories.isEmpty {
                categoryChipsRow
            }
            Divider()
            logArea
        }
        .onAppear {
            model.start(logDirectory: PersistentDiagnosticLog.logDirectory)
        }
        .onDisappear {
            model.stop()
        }
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField("Filter…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            Button {
                let text = visibleLines.map(\.raw).joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy filtered log lines to clipboard")

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Category chips

    private var categoryChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(label: "All", isActive: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(model.categories, id: \.self) { cat in
                    categoryChip(label: cat, isActive: selectedCategory == cat) {
                        selectedCategory = selectedCategory == cat ? nil : cat
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func categoryChip(
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isActive
                        ? Color.accentColor.opacity(0.12)
                        : Color.secondary.opacity(0.08)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log area

    @ViewBuilder
    private var logArea: some View {
        if model.lines.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "scroll")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("No log entries yet")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleLines) { line in
                        LogLineRow(line: line)
                    }
                }
            }
        }
    }
}
