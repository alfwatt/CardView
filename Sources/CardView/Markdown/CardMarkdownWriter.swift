import Foundation
#if canImport(KitBridgeSwift)
import KitBridgeSwift
#else
import KitBridge
#endif
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// An attachment which can be written out as Markdown
public protocol CardMarkdownConvertible {
    /// @returns the Markdown of the attachment, with URLs relative to the
    /// @param baseURL provided, or nil if it has none
    func markdown(relativeTo baseURL: URL?) -> String?
    /// true if the attachment is a block of its own, e.g. a rule, false if it's inline, e.g. an image
    var isMarkdownBlock: Bool { get }
}

extension CardRuleAttachment: CardMarkdownConvertible {
    public func markdown(relativeTo baseURL: URL?) -> String? { "---" }
    public var isMarkdownBlock: Bool { true }
}

extension CardImageAttachment: CardMarkdownConvertible {
    public func markdown(relativeTo baseURL: URL?) -> String? {
        guard let source else { return nil }
        return "![\(CardMarkdownWriter.escaped(alt))](\(CardMarkdownWriter.relative(source, to: baseURL)))"
    }
    public var isMarkdownBlock: Bool { false }
}

extension CardButtonAttachment: CardMarkdownConvertible {
    public func markdown(relativeTo baseURL: URL?) -> String? {
        guard let url else { return nil }
        return "[\(CardMarkdownWriter.escaped(title))](\(CardMarkdownWriter.relative(url, to: baseURL)))"
    }
    public var isMarkdownBlock: Bool { false }
}

// MARK: -

/// Writes the styled text of a card out as Markdown, each paragraph as the block it's tagged with
struct CardMarkdownWriter {
    let baseURL: URL?

    /// a block of Markdown, the lines of a paragraph, list item, table row or code block
    struct Written {
        var block: CardBlock
        var markdown: String
    }

    func write(_ text: NSAttributedString) -> String {
        let bodySize = Self.bodySize(of: text)
        var blocks: [Written] = []
        let string = text.string as NSString
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            let block = (range.location < text.length ? text.attribute(.cardBlock, at: range.location, effectiveRange: nil) as? CardBlock : nil)
                ?? Self.guessBlock(text, range: range, bodySize: bodySize)
            blocks.append(contentsOf: self.write(text, range: range, block: block))
        }
        return join(blocks)
    }

    /// @returns the blocks of a paragraph, it's split around attachments which are blocks of their own, e.g. rules
    func write(_ text: NSAttributedString, range: NSRange, block: CardBlock) -> [Written] {
        if case .codeBlock = block {
            return [Written(block: block, markdown: (text.string as NSString).substring(with: range))]
        }
        var written: [Written] = []
        var start = range.location
        text.enumerateAttribute(.attachment, in: range) { value, attachmentRange, _ in
            guard let convertible = value as? CardMarkdownConvertible, convertible.isMarkdownBlock,
                  let markdown = convertible.markdown(relativeTo: baseURL) else {
                return
            }
            written.append(contentsOf: paragraph(text, range: NSRange(location: start, length: attachmentRange.location - start), block: block))
            written.append(Written(block: .paragraph, markdown: markdown))
            start = NSMaxRange(attachmentRange)
        }
        written.append(contentsOf: paragraph(text, range: NSRange(location: start, length: NSMaxRange(range) - start), block: block))
        return written
    }

    /// @returns the Markdown of a paragraph, without its prefix, or nothing if it's empty
    func paragraph(_ text: NSAttributedString, range: NSRange, block: CardBlock) -> [Written] {
        let markdown: String
        if case .tableRow = block {
            markdown = cells(text, range: range).map { inline(text, range: $0, block: block).replacingOccurrences(of: "|", with: "\\|") }
                .joined(separator: " | ")
        }
        else {
            markdown = inline(text, range: range, block: block)
        }
        guard !markdown.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return [Written(block: block, markdown: markdown)]
    }

    /// the ranges of a table row's cells, between its tabs
    func cells(_ text: NSAttributedString, range: NSRange) -> [NSRange] {
        let string = text.string as NSString
        var cells: [NSRange] = []
        var start = range.location
        var tab = string.range(of: "\t", options: [], range: range)
        while tab.location != NSNotFound {
            cells.append(NSRange(location: start, length: tab.location - start))
            start = NSMaxRange(tab)
            tab = string.range(of: "\t", options: [], range: NSRange(location: start, length: NSMaxRange(range) - start))
        }
        cells.append(NSRange(location: start, length: NSMaxRange(range) - start))
        return cells
    }

    // MARK: - Inline

    /// a run of text with the same Markdown
    struct Span: Equatable {
        var text = ""
        var bold = false
        var italic = false
        var code = false
        var strike = false
        var html = false
        var link: URL?

        func sameMarkup(_ other: Span) -> Bool {
            bold == other.bold && italic == other.italic && code == other.code && strike == other.strike && html == other.html && link == other.link
        }
    }

    /// @returns the inline Markdown of the text in the range provided, bold is the base of headings and table headers
    func inline(_ text: NSAttributedString, range: NSRange, block: CardBlock) -> String {
        let boldBase: Bool = switch block {
        case .heading: true
        case .tableRow(let header, _): header
        default: false
        }
        var spans: [Span] = []
        text.enumerateAttributes(in: range) { attributes, runRange, _ in
            guard attributes[.cardListMarker] == nil else { return }
            var span = Span()
            let font = attributes[.font] as? ILFont
            span.bold = !boldBase && font?.isBold == true
            span.italic = font?.isItalic == true
            span.code = font?.isMonospace == true
            span.strike = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
            span.html = attributes[.cardHTML] != nil
            span.link = (attributes[.link] as? URL) ?? (attributes[.link] as? String).flatMap { URL(string: $0) }
            if let attachment = attributes[.attachment] as? NSTextAttachment {
                if let convertible = attachment as? CardMarkdownConvertible, !convertible.isMarkdownBlock,
                   let markdown = convertible.markdown(relativeTo: baseURL) {
                    spans.append(Span(text: markdown, html: true)) // already Markdown
                }
                return
            }
            span.text = (text.string as NSString).substring(with: runRange)
            if let last = spans.last, last.sameMarkup(span) {
                spans[spans.count - 1].text += span.text
            }
            else {
                spans.append(span)
            }
        }
        var markdown = spans.map(render).joined()
        markdown = markdown.replacingOccurrences(of: "\u{2028}", with: "\\\n")
        return Self.escapedLineStart(markdown, block: block)
    }

    /// @returns the Markdown of a span, its whitespace is kept outside of its markers
    func render(_ span: Span) -> String {
        if span.html {
            return span.text
        }
        let leading = span.text.prefix { $0 == " " }
        let trailing = span.text.reversed().prefix { $0 == " " }
        guard leading.count < span.text.count else { return span.text }
        let core = String(span.text.dropFirst(leading.count).dropLast(trailing.count))

        var markdown: String
        if span.code {
            let fence = core.contains("`") ? "``" : "`"
            markdown = fence + (core.hasPrefix("`") || core.hasSuffix("`") ? " \(core) " : core) + fence
        }
        else {
            markdown = Self.escaped(core)
        }
        if span.strike { markdown = "~~\(markdown)~~" }
        if span.italic { markdown = "*\(markdown)*" }
        if span.bold { markdown = "**\(markdown)**" }
        if let link = span.link { markdown = "[\(markdown)](\(Self.relative(link, to: baseURL)))" }
        return String(leading) + markdown + String(trailing)
    }

    // MARK: - Blocks

    /// @returns the blocks joined, with blank lines between them, except between the items of a list, the rows of a table
    /// and the lines of a code block, which are on lines of their own
    func join(_ blocks: [Written]) -> String {
        var markdown = ""
        var previous: CardBlock?
        var numbers: [Int] = [] // of each depth of the ordered lists
        var table: [CardTableAlignment]?

        for written in blocks {
            let block = written.block
            if let previous {
                markdown += Self.continues(previous, block) ? "\n" : "\n\n"
            }
            switch block {
            case .paragraph:
                markdown += written.markdown
            case .heading(let level):
                markdown += String(repeating: "#", count: min(max(level, 1), 6)) + " " + written.markdown
            case .quote:
                markdown += "> " + written.markdown.replacingOccurrences(of: "\n", with: "\n> ")
            case .codeBlock(let language):
                let fence = written.markdown.contains("```") ? "````" : "```"
                if let previous, Self.continues(previous, block) {
                    markdown.removeLast(fence.count + 1) // continue the block above, without its closing fence
                    markdown += written.markdown + "\n" + fence
                }
                else {
                    markdown += fence + (language ?? "") + "\n" + written.markdown + "\n" + fence
                }
            case .listItem(let ordered, let depth):
                if previous?.isListItem != true {
                    numbers = []
                }
                numbers = Array(numbers.prefix(depth + 1))
                while numbers.count <= depth { numbers.append(0) }
                numbers[depth] += 1
                let indent = String(repeating: "    ", count: depth)
                let continuation = "\n" + indent + (ordered ? "   " : "  ")
                markdown += indent + (ordered ? "\(numbers[depth]). " : "- ") + written.markdown.replacingOccurrences(of: "\n", with: continuation)
            case .tableRow(_, let alignments):
                markdown += "| " + written.markdown + " |"
                if table == nil {
                    let separators = alignments.map { alignment in
                        switch alignment {
                        case .left: "---"
                        case .center: ":-:"
                        case .right: "--:"
                        }
                    }
                    markdown += "\n| " + separators.joined(separator: " | ") + " |"
                }
            }
            table = block.isTableRow ? (table ?? []) : nil
            previous = block
        }
        return markdown
    }

    /// true if the block follows the previous one on the next line, without a blank line between them
    static func continues(_ previous: CardBlock, _ block: CardBlock) -> Bool {
        switch (previous, block) {
        case (.listItem, .listItem), (.tableRow, .tableRow): true
        case (.codeBlock(let a), .codeBlock(let b)): a == b
        default: false
        }
    }

    // MARK: - Escaping

    /// @returns the
    /// @param text provided with its Markdown punctuation escaped
    static func escaped(_ text: String) -> String {
        var escaped = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            switch character {
            case "\\", "*", "`", "[", "]", "<":
                escaped.append("\\")
            case "_":
                let before = index > 0 ? characters[index - 1] : " "
                let after = index + 1 < characters.count ? characters[index + 1] : " "
                if !(before.isLetter || before.isNumber) || !(after.isLetter || after.isNumber) {
                    escaped.append("\\")
                }
            case "~" where index + 1 < characters.count && characters[index + 1] == "~":
                escaped.append("\\")
            default:
                break
            }
            escaped.append(character)
        }
        return escaped
    }

    /// @returns the Markdown with the characters which would start a block at the start of its lines escaped
    static func escapedLineStart(_ markdown: String, block: CardBlock) -> String {
        guard let first = markdown.first else { return markdown }
        let rest = markdown.dropFirst()
        switch first {
        case "#", ">":
            return "\\" + markdown
        case "-", "+":
            if rest.isEmpty || rest.first == " " || markdown.allSatisfy({ $0 == first }) { return "\\" + markdown }
        case "=" where markdown.allSatisfy({ $0 == "=" }):
            return "\\" + markdown
        case _ where first.isNumber:
            let digits = markdown.prefix { $0.isNumber }
            let after = markdown.dropFirst(digits.count)
            if let mark = after.first, mark == "." || mark == ")", after.dropFirst().first == " " || after.count == 1 {
                return digits + "\\" + after
            }
        default:
            break
        }
        return markdown
    }

    /// @returns the
    /// @param url provided relative to the
    /// @param baseURL if it's inside it, or the whole URL
    static func relative(_ url: URL, to baseURL: URL?) -> String {
        if let baseURL {
            if url.baseURL == baseURL {
                return url.relativeString
            }
            if url.isFileURL, baseURL.isFileURL {
                let base = baseURL.standardizedFileURL.path.hasSuffix("/") ? baseURL.standardizedFileURL.path : baseURL.standardizedFileURL.path + "/"
                let path = url.standardizedFileURL.path
                if path.hasPrefix(base) {
                    let relative = String(path.dropFirst(base.count))
                    return relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relative
                }
            }
        }
        let string = url.absoluteString
        return string.contains(" ") ? "<\(string)>" : string
    }

    // MARK: - Untagged Text

    /// the most common font size of the text, the size of its body
    static func bodySize(of text: NSAttributedString) -> CGFloat {
        var sizes: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { font, range, _ in
            if let font = font as? ILFont {
                sizes[font.pointSize, default: 0] += range.length
            }
        }
        return sizes.max { $0.value < $1.value }?.key ?? ILFont.cardBodySize
    }

    /// @returns the block of a paragraph which isn't tagged with one, a large bold font is a heading
    static func guessBlock(_ text: NSAttributedString, range: NSRange, bodySize: CGFloat) -> CardBlock {
        guard range.length > 0, let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? ILFont, font.isBold else {
            return .paragraph
        }
        if font.pointSize >= bodySize * 1.2 { return .heading(1) }
        if font.pointSize >= bodySize * 1.1 { return .heading(2) }
        return .paragraph
    }
}
