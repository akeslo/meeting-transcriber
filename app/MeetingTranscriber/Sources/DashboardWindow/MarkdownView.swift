import SwiftUI

/// Block-level markdown renderer. Handles headings, bullets, numbered lists,
/// bold/italic inline formatting, horizontal rules, and paragraphs.
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
            } else {
                // Merge consecutive plain lines into one paragraph
                var para = trimmed
                while i + 1 < lines.count {
                    let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                    if next.isEmpty { break }
                    if next.hasPrefix("#") || next.hasPrefix("-") || next.hasPrefix("*") { break }
                    if next == "---" || next == "***" || next == "___" { break }
                    if isNumberedListItem(next) { break }
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
        case .spacer:
            Color.clear.frame(height: 8)
        }
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
