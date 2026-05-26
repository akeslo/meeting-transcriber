import SwiftUI

/// Block-level markdown renderer. Handles headings, bullets, numbered lists,
/// bold/italic inline formatting, horizontal rules, tables, and paragraphs.
/// Timestamp lines (`[MM:SS] Speaker: ...`) are kept as individual blocks
/// rather than merged into a single paragraph.
struct MarkdownView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    // MARK: - Block types

    private enum Block {
        case h1(String)
        case h2(String)
        case h3(String)
        case bullet(String)
        case numbered(String)
        case rule
        case paragraph(String)
        case table([[String]])   // rows of parsed cells; first row is header
        case spacer
    }

    // MARK: - Parser

    private var blocks: [Block] {
        var result: [Block] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if case .spacer? = result.last { /* deduplicate */ } else {
                    result.append(.spacer)
                }
            } else if trimmed.hasPrefix("### ") {
                result.append(.h3(String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                result.append(.h2(String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                result.append(.h1(String(trimmed.dropFirst(2))))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                result.append(.rule)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                result.append(.bullet(String(trimmed.dropFirst(2))))
            } else if isNumberedListItem(trimmed) {
                result.append(.numbered(trimmed))
            } else if trimmed.hasPrefix("|") {
                // Accumulate all consecutive pipe-prefixed lines as a table
                var tableLines = [trimmed]
                while i + 1 < lines.count {
                    let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    guard next.hasPrefix("|") else { break }
                    tableLines.append(next)
                    i += 1
                }
                // Drop separator rows (cells contain only dashes/colons/spaces)
                let rows = tableLines
                    .filter { !isSeparatorRow($0) }
                    .map { parseCells($0) }
                    .filter { !$0.isEmpty }
                if !rows.isEmpty {
                    result.append(.table(rows))
                }
            } else if isTimestampLine(trimmed) {
                // Transcript timestamp lines stay as individual blocks
                result.append(.paragraph(trimmed))
            } else {
                // Merge consecutive plain lines into one paragraph,
                // stopping before any line that starts a new structural element.
                var para = trimmed
                while i + 1 < lines.count {
                    let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if next.isEmpty { break }
                    if next.hasPrefix("#") || next.hasPrefix("-") || next.hasPrefix("*") { break }
                    if next == "---" || next == "***" || next == "___" { break }
                    if isNumberedListItem(next) { break }
                    if next.hasPrefix("|") { break }
                    if isTimestampLine(next) { break }
                    para += " " + next
                    i += 1
                }
                result.append(.paragraph(para))
            }
            i += 1
        }

        // Strip leading/trailing spacers
        while case .spacer? = result.first { result.removeFirst() }
        while case .spacer? = result.last  { result.removeLast() }

        return result
    }

    private func isNumberedListItem(_ s: String) -> Bool {
        guard let dot = s.firstIndex(of: "."), dot != s.startIndex else { return false }
        let prefix = s[s.startIndex..<dot]
        return prefix.allSatisfy(\.isNumber) && !prefix.isEmpty
    }

    /// True when the line is a markdown table separator (`|---|---|`).
    private func isSeparatorRow(_ s: String) -> Bool {
        let stripped = s.replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
        return stripped.isEmpty
    }

    /// Split a `| cell | cell |` row into trimmed cell strings.
    private func parseCells(_ row: String) -> [String] {
        var s = row
        if s.hasPrefix("|") { s = String(s.dropFirst()) }
        if s.hasSuffix("|") { s = String(s.dropLast()) }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// True when a line starts with a `[MM:SS]` or `[H:MM:SS]` timestamp prefix,
    /// as emitted by the transcript formatter in the protocol output.
    private func isTimestampLine(_ s: String) -> Bool {
        guard s.hasPrefix("[") else { return false }
        guard let close = s.firstIndex(of: "]"), close != s.startIndex else { return false }
        let between = s[s.index(after: s.startIndex)..<close]
        return between.contains(":") && between.allSatisfy { $0.isNumber || $0 == ":" }
    }

    // MARK: - Block views

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .h1(let text):
            inlineText(text)
                .font(.system(size: 18, weight: .bold))
                .padding(.top, 20)
                .padding(.bottom, 4)
        case .h2(let text):
            inlineText(text)
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 14)
                .padding(.bottom, 2)
        case .h3(let text):
            inlineText(text)
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 10)
                .padding(.bottom, 2)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 10, alignment: .leading)
                inlineText(text)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 1)
        case .numbered(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                inlineText(text)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 1)
        case .rule:
            Divider().padding(.vertical, 10)
        case .paragraph(let text):
            inlineText(text)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
        case .table(let rows):
            tableView(rows)
                .padding(.vertical, 6)
        case .spacer:
            Color.clear.frame(height: 8)
        }
    }

    @ViewBuilder
    private func tableView(_ rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, cells in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        inlineText(cell)
                            .font(.system(size: 12, weight: rowIdx == 0 ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                    }
                }
                .background(rowIdx % 2 == 1 ? Color.primary.opacity(0.04) : Color.clear)

                if rowIdx < rows.count - 1 {
                    Divider()
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Inline formatting (bold/italic via AttributedString)

    private func inlineText(_ raw: String) -> Text {
        guard let attr = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return Text(raw)
        }
        return Text(attr)
    }
}
