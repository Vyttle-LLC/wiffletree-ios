import SwiftUI
import WiffletreeDesignSystem

/// A coordinator's Markdown as blocks: paragraphs, headings, bullet and numbered lists and fenced
/// code, each with inline emphasis, code and links. Enough for a coordinator's replies; tables
/// read as plain lines.
struct MarkdownText: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.parse(source).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            inline(text)
        case .heading(let text):
            inline(text).font(.headline)
        case .item(let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundStyle(Tidal.subtle).monospacedDigit()
                inline(text)
            }
            .padding(.leading, 4)
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text).font(.footnote.monospaced())
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tidal.overlay, in: .rect(cornerRadius: 8))
        }
    }

    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        return Text(attributed)
    }
}

enum MarkdownBlock: Equatable {
    case paragraph(String)
    case heading(String)
    /// A list item with its marker, "•" or a number such as "2.".
    case item(marker: String, text: String)
    case code(String)

    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String]?

        func endParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }

        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    endParagraph()
                    code = []
                }
            } else if code != nil {
                code?.append(line)
            } else if trimmed.isEmpty {
                endParagraph()
            } else if let heading = trimmed.firstMatch(of: #/^#{1,6}\s+(.*)$/#) {
                endParagraph()
                blocks.append(.heading(String(heading.1)))
            } else if let bullet = trimmed.firstMatch(of: #/^[-*+]\s+(.*)$/#) {
                endParagraph()
                blocks.append(.item(marker: "•", text: String(bullet.1)))
            } else if let numbered = trimmed.firstMatch(of: #/^(\d+)[.)]\s+(.*)$/#) {
                endParagraph()
                blocks.append(.item(marker: "\(numbered.1).", text: String(numbered.2)))
            } else {
                paragraph.append(trimmed)
            }
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        endParagraph()
        return blocks
    }
}
