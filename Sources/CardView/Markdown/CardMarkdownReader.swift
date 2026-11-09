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

/// Reads and writes the Markdown of a card
public enum CardMarkdown {

    /// @returns the styled text of the
    /// @param markdown provided, at the
    /// @param fontSize in the
    /// @param paragraph style provided, with images and links relative to the
    /// @param baseURL and tables laid out across the
    /// @param width provided, the
    /// @param images closure provides the images of URLs, before they're loaded from the URL
    public static func attributedString(from markdown: String, fontSize: CGFloat = ILFont.cardBodySize,
                                        paragraph: NSParagraphStyle = .default, baseURL: URL? = nil,
                                        width: CGFloat? = nil, images: ((URL) -> ILImage?)? = nil) throws -> NSAttributedString {
        let reader = CardMarkdownReader(fontSize: fontSize, paragraph: paragraph, baseURL: baseURL, width: width, images: images)
        return try reader.read(markdown)
    }

    /// @returns the Markdown of the
    /// @param text provided, with the sources of images and links relative to the
    /// @param baseURL provided
    public static func markdown(from text: NSAttributedString, baseURL: URL? = nil) -> String {
        CardMarkdownWriter(baseURL: baseURL).write(text)
    }

    // MARK: - Layout

    /// the indent of each level of lists and quotes, relative to the font size
    static let indentScale: CGFloat = 1.5

    /// @returns the paragraph style of a table row with the
    /// @param alignments of its columns, across the
    /// @param width provided, based on the
    /// @param paragraph style provided
    public static func tableStyle(_ alignments: [CardTableAlignment], width: CGFloat, paragraph: NSParagraphStyle) -> NSParagraphStyle {
        let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
        let column = width / CGFloat(max(alignments.count, 1))
        style.tabStops = alignments.enumerated().dropFirst().map { index, alignment in
            let start = column * CGFloat(index)
            return switch alignment {
            case .left: NSTextTab(textAlignment: .left, location: start)
            case .center: NSTextTab(textAlignment: .center, location: start + (column / 2))
            case .right: NSTextTab(textAlignment: .right, location: start + column - 4)
            }
        }
        style.defaultTabInterval = column
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    /// @returns the attributes of a paragraph of the
    /// @param block provided, at the
    /// @param fontSize in the
    /// @param paragraph style provided, tables are laid out across the
    /// @param width provided
    public static func attributes(for block: CardBlock, fontSize: CGFloat, paragraph: NSParagraphStyle,
                                  width: CGFloat? = nil) -> [NSAttributedString.Key: Any] {
        let graph = paragraph.mutableCopy() as! NSMutableParagraphStyle
        let indent = fontSize * indentScale
        graph.paragraphSpacing = (fontSize * 0.5).rounded()
        var style = CardStyle.text
        switch block {
        case .paragraph:
            break
        case .heading(let level):
            style = level == 1 ? .header : (level == 2 ? .subheader : .strong)
            graph.paragraphSpacingBefore = (fontSize * 0.25).rounded()
        case .codeBlock:
            style = .code
            graph.firstLineHeadIndent += indent
            graph.headIndent += indent
            graph.paragraphSpacing = 0
        case .quote:
            style = .gray
            graph.firstLineHeadIndent += indent
            graph.headIndent += indent
        case .listItem(_, let depth):
            let start = graph.headIndent + (indent * CGFloat(depth))
            graph.firstLineHeadIndent = start
            graph.headIndent = start + indent
            graph.tabStops = [NSTextTab(textAlignment: .left, location: start + indent)]
            graph.paragraphSpacing = (fontSize * 0.25).rounded()
        case .tableRow(let header, let alignments):
            style = header ? .strong : .text
            graph.paragraphSpacing = (fontSize * 0.25).rounded()
            let width = width ?? (fontSize * 10 * CGFloat(alignments.count))
            var attributes = style.attributes(fontSize: fontSize, paragraph: tableStyle(alignments, width: width, paragraph: graph))
            attributes[.cardBlock] = block
            return attributes
        }
        var attributes = style.attributes(fontSize: fontSize, paragraph: graph)
        attributes[.cardBlock] = block
        return attributes
    }

    /// @returns the marker of a list item, its bullet or the
    /// @param number provided
    static func listMarker(ordered: Bool, number: Int) -> String {
        ordered ? "\(number)." : "•"
    }
}

// MARK: -

public extension NSAttributedString.Key {
    /// marks raw HTML in Markdown, which is written out as it was read
    static let cardHTML = NSAttributedString.Key("CardHTML")
}

// MARK: -

/// Reads Markdown, parsed by Foundation, into the styles of a card
struct CardMarkdownReader {
    let fontSize: CGFloat
    let paragraph: NSParagraphStyle
    let baseURL: URL?
    let width: CGFloat?
    let images: ((URL) -> ILImage?)?

    /// a paragraph of the text, from the blocks the Markdown parser found it in
    struct Block {
        /// the identity of the paragraph, or the row of a table
        var key: Int
        var block: CardBlock
        var attributes: [NSAttributedString.Key: Any]
        /// the list item it's the first paragraph of, it gets the item's marker
        var listItem: Int?
        var marker: String?
        /// the column of a table cell
        var cell: Int?

        /// space the paragraph from the one before it
        mutating func spaceBefore(_ space: CGFloat) {
            guard let style = attributes[.paragraphStyle] as? NSParagraphStyle, style.paragraphSpacingBefore < space else { return }
            let spaced = style.mutableCopy() as! NSMutableParagraphStyle
            spaced.paragraphSpacingBefore = space
            attributes[.paragraphStyle] = spaced
        }
    }

    func read(_ markdown: String) throws -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        let parsed = try AttributedString(markdown: markdown, options: options, baseURL: baseURL)
        let text = NSMutableAttributedString()
        var current: Block?
        var markedItems = Set<Int>()
        var lastCell: Int?

        for run in parsed.runs {
            var block = self.block(run.presentationIntent)
            if block.key != current?.key {
                if let current {
                    text.append(NSAttributedString(string: "\n", attributes: current.attributes))
                    if !CardMarkdownWriter.continues(current.block, block.block) {
                        block.spaceBefore(fontSize * 0.5) // between a list, quote, table or code block and what's around it
                    }
                }
                lastCell = nil
                if let item = block.listItem, markedItems.insert(item).inserted, let marker = block.marker {
                    var markerAttributes = block.attributes
                    markerAttributes[.cardListMarker] = true
                    text.append(NSAttributedString(string: marker + "\t", attributes: markerAttributes))
                }
                current = block
            }
            if let cell = block.cell, cell != lastCell {
                if lastCell != nil {
                    text.append(NSAttributedString(string: "\t", attributes: block.attributes))
                }
                lastCell = cell
            }

            var string = String(parsed[run.range].characters)
            var attributes = block.attributes
            let inline = run.inlinePresentationIntent ?? []
            if case .codeBlock = block.block {
                if string.hasSuffix("\n") {
                    string.removeLast()
                }
            }
            else if inline.contains(.lineBreak) {
                string = "\u{2028}" // a line break, inside the paragraph
            }
            if let font = attributes[.font] as? ILFont {
                var styled = font
                if inline.contains(.stronglyEmphasized) { styled = styled.withTraits(bold: true) }
                if inline.contains(.emphasized) { styled = styled.withTraits(italic: true) }
                if inline.contains(.code) { styled = styled.monospaced(true) }
                attributes[.font] = styled
            }
            if inline.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if inline.contains(.inlineHTML) || inline.contains(.blockHTML) {
                attributes[.cardHTML] = true
            }
            if let link = run.link {
                attributes[.link] = link
            }
            if let imageURL = run.imageURL {
                attributes[.attachment] = if let image = images?(imageURL) {
                    CardImageAttachment(image: image, source: imageURL, alt: string)
                }
                else {
                    CardImageAttachment(source: imageURL, alt: string)
                }
                string = String(Character(.attachmentCharacter))
            }
            if block.block == .paragraph, string == "⸻", run.presentationIntent?.components.first?.kind == .thematicBreak {
                attributes[.attachment] = CardRuleAttachment()
                string = String(Character(.attachmentCharacter))
            }
            text.append(NSAttributedString(string: string, attributes: attributes))
        }
        return text
    }

    /// @returns the block of a run of text, from its presentation intent
    func block(_ intent: PresentationIntent?) -> Block {
        let components = intent?.components ?? []
        var block = Block(key: components.first?.identity ?? -1, block: .paragraph, attributes: [:])
        var depth = -1
        var ordered: Bool?
        var quoted = false
        var tableAlignments: [CardTableAlignment]?
        var header = false

        for component in components {
            switch component.kind {
            case .header(let level):
                block.block = .heading(level)
            case .codeBlock(let language):
                block.block = .codeBlock(language: language)
            case .blockQuote:
                quoted = true
            case .listItem(let ordinal):
                if block.listItem == nil {
                    block.listItem = component.identity
                    block.marker = "\(ordinal)."
                }
            case .orderedList, .unorderedList:
                depth += 1
                if ordered == nil {
                    ordered = component.kind == .orderedList
                    if component.kind == .unorderedList {
                        block.marker = "•"
                    }
                }
            case .tableCell(let column):
                block.cell = column
            case .tableHeaderRow:
                block.key = component.identity
                header = true
            case .tableRow:
                block.key = component.identity
            case .table(let columns):
                tableAlignments = columns.map { column in
                    switch column.alignment {
                    case .center: .center
                    case .right: .right
                    default: .left
                    }
                }
            default:
                break
            }
        }

        if let ordered, depth >= 0, !quoted, block.block == .paragraph {
            block.block = .listItem(ordered: ordered, depth: depth)
        }
        else if depth < 0 || quoted {
            block.listItem = nil
            block.marker = nil
        }
        if let tableAlignments {
            block.block = .tableRow(header: header, alignments: tableAlignments)
        }
        if quoted, block.block == .paragraph {
            block.block = .quote
        }
        var attributes = CardMarkdown.attributes(for: block.block, fontSize: fontSize, paragraph: paragraph, width: width)
        if quoted, block.block != .quote { // e.g. a heading in a quote
            let quote = CardMarkdown.attributes(for: .quote, fontSize: fontSize, paragraph: paragraph, width: width)
            attributes[.paragraphStyle] = quote[.paragraphStyle]
            attributes[.foregroundColor] = quote[.foregroundColor]
        }
        block.attributes = attributes
        return block
    }
}
