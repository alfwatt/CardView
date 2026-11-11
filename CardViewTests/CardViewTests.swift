import Foundation
import Testing
@testable import CardView
#if canImport(AppKit)
import AppKit
typealias ILFont = NSFont
typealias ILImage = NSImage
#else
import UIKit
typealias ILFont = UIFont
typealias ILImage = UIImage
#endif

/// a card wide enough to lay out columns and tables in
@MainActor func makeCard() -> CardTextView {
    let card = CardTextView(frame: CGRect(x: 0, y: 0, width: 432, height: 600))
    card.fontSize = 12
    return card
}

@MainActor func resize(_ card: CardTextView, width: CGFloat) {
#if canImport(AppKit)
    card.setFrameSize(CGSize(width: width, height: 600))
#else
    card.frame.size = CGSize(width: width, height: 600)
    card.layoutSubviews()
#endif
}

func symbol(_ name: String) -> ILImage {
#if canImport(AppKit)
    ILImage(systemSymbolName: name, accessibilityDescription: nil)!
#else
    ILImage(systemName: name)!
#endif
}

@MainActor struct CardTextViewTests {

    @Test func textKit2() {
        #expect(makeCard().textLayoutManager != nil)
    }

    @Test func clearCard() {
        let card = makeCard()
        card.appendNewline()
        card.clearCard()
        #expect(card.storage.string.isEmpty)
    }

    // MARK: - Style Stack

    @Test func pushStyle() {
        let card = makeCard()
        let top = NSMutableParagraphStyle()
        top.alignment = .center
        card.push(top)
        #expect(card.topStyle === top)
        #expect(card.popStyle() === top)
        #expect(card.topStyle == NSParagraphStyle.default)
        #expect(card.popStyle() == nil)
    }

    @Test func pushStyles() {
        let card = makeCard()
        let styles = [NSTextAlignment.left, .center, .right].map { alignment in
            let style = NSMutableParagraphStyle()
            style.alignment = alignment
            card.push(style)
            return style
        }
        for style in styles.reversed() {
            #expect(card.topStyle === style)
            #expect(card.popStyle() === style)
        }
        #expect(card.topStyle == NSParagraphStyle.default)
    }

    // MARK: - Columns

    @Test func columns() {
        let card = makeCard()
        let width = card.textWidth
        let style = card.paragraphStyle(columns: [.right(.fraction(0.25)), .left(.points(5))])
        #expect(style.tabStops.count == 2)
        #expect(style.tabStops[0].alignment == .right)
        #expect(abs(style.tabStops[0].location - (width * 0.25)) < 0.01)
        #expect(style.tabStops[1].alignment == .left)
        #expect(abs(style.tabStops[1].location - ((width * 0.25) + 5)) < 0.01)
        #expect(style.headIndent == style.tabStops[1].location)
    }

    @Test func columnNumbers() {
        #expect(CardColumn(-0.33) == .right(.fraction(0.33)))
        #expect(CardColumn(5) == .left(.points(5)))
        #expect(CardColumn(-100) == .right(.points(100)))
    }

    @Test func columnsFollowWidth() {
        let card = makeCard()
        card.useColumns([.left(.fraction(0.5))])
        card.append("Name")
        card.appendTab()
        card.append("Value")
        let before = (card.storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle).tabStops[0].location
        resize(card, width: 832)
        let after = (card.storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle).tabStops[0].location
        #expect(abs(after - (before + 200)) < 0.01)
        #expect(abs((card.topStyle.tabStops[0].location) - after) < 0.01)
    }

    // MARK: - Promises

    @Test func promise() {
        let card = makeCard()
        let promise = card.appendPromise()
        #expect(card.storage.string == "…")
        card.fulfill(promise, with: NSAttributedString(string: "Promised"))
        #expect(card.storage.string == "Promised")
        card.fulfill(promise, with: NSAttributedString(string: "Again"))
        #expect(card.storage.string == "Again")
    }

    @Test func multiplePromises() {
        let card = makeCard()
        let first = card.appendPromise()
        let second = card.appendPromise()
        #expect(card.storage.string == "……")
        card.fulfill(first, with: NSAttributedString(string: "First"))
        #expect(card.storage.string == "First…")
        card.fulfill(second, with: NSAttributedString(string: "Second"))
        #expect(card.storage.string == "FirstSecond")
    }

    @Test func promiseWithRuns() {
        let card = makeCard()
        let promise = card.appendPromise()
        card.append(" after")
        let runs = NSMutableAttributedString(string: "bold", attributes: [.font: ILFont.boldSystemFont(ofSize: 12)])
        runs.append(NSAttributedString(string: " plain"))
        card.fulfill(promise, with: runs)
        card.fulfill(promise, with: NSAttributedString(string: "done"))
        #expect(card.storage.string == "done after")
    }

    // MARK: - Formatter Registry

    @Test func formatterRegistry() {
        let formatter = CardDataFormatter()
        CardTextView.register(formatter, for: NSData.self)
        #expect(CardTextView.registeredFormatter(for: NSData.self) === formatter)
        #expect(CardTextView.registeredFormatter(for: NSMutableData.self) === formatter) // a subclass
        #expect(CardTextView.formatted(Data(count: 420), attributes: [:]).string == "420\u{202F}Bytes")
        #expect(CardTextView.formatted(nil, attributes: [:]).string == "-")
    }

    @Test func promiseWithFormatted() {
        CardTextView.register(CardDataFormatter(), for: NSData.self)
        let card = makeCard()
        let promise = card.appendPromise()
        card.fulfill(promise, formatted: Data(count: 2000))
        #expect(card.storage.string == "2.0\u{202F}kB")
    }

    // MARK: - Sections

    @Test func section() {
        let card = makeCard()
        card.append("Before")
        let section = card.appendSection("Title")
        #expect(card.storage.string.hasPrefix("Before\nTitle\n"))
        #expect(card.storage.string.hasSuffix(section.string))
        var hasRule = false
        card.storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: card.storage.length)) { value, _, _ in
            hasRule = hasRule || value is CardRuleAttachment
        }
        #expect(hasRule)
    }

    @Test func aSectionsActionHasItsTextAsRTFAndShowsItWasDone() throws {
        let card = makeCard()
        card.append("Before")
        var copied: Data?
        let header = card.storage.length + 1
        card.appendSection("First", image: ILImage(systemName: "doc"), attributes: card.sectionAttributes { copied = $0 })
        card.appendNewline()
        card.append("Key\tValue")
        card.appendNewline()
        card.appendSection("Second", image: nil, attributes: card.sectionAttributes { _ in })
        card.append("Not in the first")
        card.action(at: header)?()
        let rtf = try #require(copied)
        let text = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        #expect(text.string == "First\nKey\tValue")
        #expect(card.storage.attribute(.backgroundColor, at: header, effectiveRange: nil) != nil) // highlighted for a moment
    }

    @Test func appendAttributed() {
        let card = makeCard()
        let bold = NSAttributedString(string: "bold", attributes: [.font: ILFont.boldSystemFont(ofSize: 20)])
        card.appendAttributed(bold)
        #expect(card.storage.string == "bold")
        #expect((card.storage.attribute(.font, at: 0, effectiveRange: nil) as? ILFont)?.pointSize == 20)
    }

    @Test func attributes() {
        let card = makeCard()
        #expect((card.attributes(.text)[.font] as? ILFont)?.pointSize == 12)
        #expect((card.attributes(.text, size: 20)[.font] as? ILFont)?.pointSize == 20)
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        #expect((card.attributes(.text, paragraph: centered)[.paragraphStyle] as? NSParagraphStyle)?.alignment == .center)
    }

    @Test func action() {
        let card = makeCard()
        card.append("Before ")
        var performed = 0
        let line = card.appendAction(image: symbol("doc.on.doc"), {
            card.append("Action", style: .subheader)
        }, action: { performed += 1 })
        card.appendNewline()
        card.append("After")
        #expect(line.string.hasSuffix(" Action"))
        #expect(card.action(at: 0) == nil)
        let start = (card.storage.string as NSString).range(of: "Action").location
        card.action(at: start)?()
        card.action(at: start + 6)?() // the end of the line
        #expect(performed == 2)
        #expect(card.action(at: card.storage.length - 1) == nil)
        card.clearCard()
        #expect(card.action(at: 0) == nil)
    }

    @Test func safeContentWidth() {
        #expect(makeCard().safeContentWidth == 432)
        #expect(CardTextView(frame: .zero, textContainer: nil).safeContentWidth == 320)
    }
}

// MARK: -

struct FormatterTests {

    @Test func bytes() {
        let bytes = CardBytesFormatter()
        #expect(bytes.string(for: 999) == "999\u{202F}Bytes")
        #expect(bytes.string(for: 1_500) == "1.5\u{202F}kB")
        #expect(bytes.string(for: 2_000_000) == "2.0\u{202F}MB")
        #expect(bytes.string(for: 3_250_000_000_000) == "3.25\u{202F}TB")
    }

    @Test func units() {
        let units = CardUnitsFormatter()
        units.units = "dBm"
        units.prefix = "≈"
        #expect(units.string(for: -62.5) == "≈\u{202F}-62.5\u{202F}dBm")
        let attributed = units.attributedString(for: NSNumber(value: 1), withDefaultAttributes: [.font: ILFont.systemFont(ofSize: 12)])
        #expect(attributed?.string == "≈\u{202F}1\u{202F}dBm")
    }

    @Test func fraction() {
        #expect(CardFractionFormatter.fraction(0.5) == (1, 2))
        #expect(CardFractionFormatter.fraction(0.75) == (3, 4))
        #expect(CardFractionFormatter.fraction(Double.pi, accuracy: 1000) == (355, 113))
        #expect(CardFractionFormatter().string(for: 1.25) == "5\u{2044}4")
    }

    @Test func timecode() {
        let timecode = CardTimecodeFormatter.timecode(3723.5, frameInterval: 0)
        #expect(timecode.hours == 1)
        #expect(timecode.minutes == 2)
        #expect(timecode.seconds == 3)
        #expect(timecode.frames == 12)
        let formatter = CardTimecodeFormatter()
        #expect(formatter.string(for: 3723.5) == "01h 02m 3.5000s")
        formatter.decimalSeconds = false
        formatter.unitSeparators = false
        #expect(formatter.string(for: 3723.5) == "01:02:03:12")
    }

    @Test func boolean() {
        let boolean = CardBooleanFormatter()
        #expect(boolean.string(for: true) == "Yes")
        #expect(boolean.string(for: false) == "No")
        #expect(boolean.string(for: "x") == "-")
    }

    @Test func array() {
        let array = CardArrayFormatter()
        #expect(array.string(for: [1, 2, 3]) == "1, 2, 3")
        array.separator = " / "
        array.itemFormatter = CardBooleanFormatter()
        #expect(array.string(for: [true, false]) == "Yes / No")
        #expect(array.attributedString(for: [true, false], withDefaultAttributes: [:])?.string == "Yes / No")
    }

    @Test func hexData() {
        let data = CardDataFormatter()
        data.formatAsHex = true
        data.hexLineBytes = 4
        #expect(data.string(for: Data("abc\n".utf8)) == "0x6162630a abc␊")
    }

    @Test func markdownFormatter() {
        let markdown = CardMarkdownFormatter()
        #expect(markdown.string(for: ["b": 2, "a": "x*y"]) == "- **a**: x\\*y\n- **b**: 2")
        #expect(markdown.string(for: ["one", "two"]) == "1. one\n2. two")
    }
}

// MARK: -

@MainActor struct MarkdownTests {

    func read(_ markdown: String) throws -> NSAttributedString {
        try CardMarkdown.attributedString(from: markdown, fontSize: 12, width: 400)
    }

    func blocks(_ text: NSAttributedString) -> [CardBlock] {
        var blocks: [CardBlock] = []
        let string = text.string as NSString
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byParagraphs) { _, range, _, _ in
            blocks.append(text.attribute(.cardBlock, at: range.location, effectiveRange: nil) as? CardBlock ?? .paragraph)
        }
        return blocks
    }

    @Test func headings() throws {
        let text = try read("# One\n\n## Two\n\n### Three\n\nBody")
        #expect(text.string == "One\nTwo\nThree\nBody")
        #expect(blocks(text) == [.heading(1), .heading(2), .heading(3), .paragraph])
        let font = text.attribute(.font, at: 0, effectiveRange: nil) as! ILFont
        #expect(font.isBold)
        #expect(font.pointSize == 15)
    }

    @Test func inline() throws {
        let text = try read("Some **bold**, *italic*, `code` and [a link](https://istumbler.net).")
        #expect(text.string == "Some bold, italic, code and a link.")
        #expect((text.attribute(.font, at: 5, effectiveRange: nil) as! ILFont).isBold)
        #expect((text.attribute(.font, at: 11, effectiveRange: nil) as! ILFont).isItalic)
        #expect((text.attribute(.font, at: 19, effectiveRange: nil) as! ILFont).isMonospace)
        #expect(text.attribute(.link, at: 28, effectiveRange: nil) as? URL == URL(string: "https://istumbler.net"))
    }

    @Test func lists() throws {
        let text = try read("- one\n- two\n    1. nested\n\nAfter")
        #expect(text.string == "•\tone\n•\ttwo\n1.\tnested\nAfter")
        #expect(blocks(text) == [.listItem(ordered: false, depth: 0), .listItem(ordered: false, depth: 0),
                                 .listItem(ordered: true, depth: 1), .paragraph])
    }

    @Test func quoteAndCode() throws {
        let text = try read("> quoted\n\n```swift\nlet x = 1\n\nlet y = 2\n```")
        #expect(text.string == "quoted\nlet x = 1\n\nlet y = 2")
        #expect(blocks(text) == [.quote, .codeBlock(language: "swift"), .codeBlock(language: "swift"), .codeBlock(language: "swift")])
    }

    @Test func table() throws {
        let text = try read("| Name | Value |\n|---|--:|\n| a | 1 |")
        #expect(text.string == "Name\tValue\na\t1")
        let alignments: [CardTableAlignment] = [.left, .right]
        #expect(blocks(text) == [.tableRow(header: true, alignments: alignments), .tableRow(header: false, alignments: alignments)])
        let style = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        #expect(style.tabStops.count == 1)
        #expect(style.tabStops[0].alignment == .right)
    }

    @Test func ruleAndImage() throws {
        let base = URL(fileURLWithPath: "/tmp/Card.deck/")
        let text = try CardMarkdown.attributedString(from: "Above\n\n---\n\n![An image](Images/a.png)", fontSize: 12, baseURL: base)
        #expect(text.attribute(.attachment, at: 6, effectiveRange: nil) is CardRuleAttachment)
        let image = text.attribute(.attachment, at: 8, effectiveRange: nil) as? CardImageAttachment
        #expect(image?.alt == "An image")
        #expect(image?.source?.absoluteURL == base.appendingPathComponent("Images/a.png"))
        #expect(CardMarkdown.markdown(from: text, baseURL: base) == "Above\n\n---\n\n![An image](Images/a.png)")
    }

    @Test(arguments: [
        "# Title\n\nSome **bold**, *italic*, `code` and [a link](https://istumbler.net).",
        "## Subhead\n\n- one\n- two\n    1. nested\n    2. again\n- three\n\nAfter the list",
        "> a quote\n\n```swift\nlet x = 1\n\nlet y = 2\n```",
        "| Name | Value |\n| --- | --: |\n| a | 1 |\n| b | 2 |",
        "Above\n\n---\n\nBelow, with a line\\\nbreak",
        "1\\. starts like a list, with \\*stars\\* and snake_case",
    ])
    func roundTrip(_ markdown: String) throws {
        let written = CardMarkdown.markdown(from: try read(markdown))
        #expect(written == markdown)
        #expect(CardMarkdown.markdown(from: try read(written)) == written)
    }

    @Test func builderToMarkdown() {
        let card = makeCard()
        card.append("Header", style: .header)
        card.appendNewline()
        card.append("Label", style: .strong)
        card.append(" and ")
        card.append("code", style: .code)
        card.appendRule()
        card.append("Last")
        #expect(card.markdown == "# Header\n\n**Label** and `code`\n\n---\n\nLast")
    }

    @Test func imagesAfterARuleOrTextAreCentered() {
        let card = makeCard()
        card.appendSection("Image")
        card.appendImage(symbol("photo"))
        card.append(" ")
        card.appendImage(symbol("doc")) // a row of images stays on one line
        card.append("Text")
        card.appendImage(symbol("eye"))
        let text = card.storage.string as NSString
        #expect(text.components(separatedBy: "\n").count == 5) // the section's newlines, then one before each paragraph of images
        var index = 0
        while index < card.storage.length {
            if card.storage.attribute(.attachment, at: index, effectiveRange: nil) is CardImageAttachment {
                let paragraph = text.paragraphRange(for: NSRange(location: index, length: 0))
                let style = card.storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
                #expect(style?.alignment == .center)
            }
            index += 1
        }
    }

    @Test func cardMarkdown() {
        let card = makeCard()
        card.markdown = "# Title\n\n- item"
        #expect(card.storage.string == "Title\n•\titem")
        #expect(card.markdown == "# Title\n\n- item")
    }
}

// MARK: -

@MainActor struct EditingTests {

    @Test func setBlock() {
        let card = makeCard()
        card.markdown = "one\n\ntwo"
        card.selection = NSRange(location: 0, length: 5)
        card.setBlock(.listItem(ordered: true, depth: 0))
        #expect(card.markdown == "1. one\n2. two")
        card.selection = NSRange(location: 0, length: 0)
        card.setBlock(.heading(1))
        #expect(card.markdown == "# one\n\n1. two")
        card.setBlock(.paragraph)
        #expect(card.markdown == "one\n\n1. two")
    }

    @Test func toggles() {
        let card = makeCard()
        card.markdown = "plain text"
        card.selection = NSRange(location: 0, length: 5)
        card.toggleBold()
        #expect(card.markdown == "**plain** text")
        card.toggleItalic()
        #expect(card.markdown == "***plain*** text")
        card.toggleBold()
        card.toggleItalic()
        card.selection = NSRange(location: 6, length: 4)
        card.toggleCode()
        #expect(card.markdown == "plain `text`")
    }

    @Test func selectionStyle() {
        let card = makeCard()
        card.markdown = "# Title\n\n**bold** *italic* `code`"
        card.selection = NSRange(location: 1, length: 2)
        #expect(card.selectedBlock == .heading(1))
        let text = card.storage.string as NSString
        card.selection = text.range(of: "bold")
        #expect(card.selectedBlock == .paragraph && card.isSelectionBold && !card.isSelectionItalic)
        card.selection = text.range(of: "italic")
        #expect(card.isSelectionItalic && !card.isSelectionBold)
        card.selection = text.range(of: "code")
        #expect(card.isSelectionCode)
        card.selection = NSRange(location: text.range(of: "bold").location, length: 13)
        #expect(!card.isSelectionBold && !card.isSelectionItalic)
    }

    @Test func insertRuleAndLink() {
        let card = makeCard()
        card.markdown = "above"
        card.selection = NSRange(location: 5, length: 0)
        card.insertRule()
        card.insertLink(URL(string: "https://istumbler.net")!, text: "link")
        #expect(card.markdown == "above\n\n---\n\n[link](https://istumbler.net)")
    }

    @Test func listNumbers() {
        let card = makeCard()
        card.markdown = "1. one\n2. two"
        card.selection = NSRange(location: card.storage.length, length: 0)
        card.replace(card.selection, with: NSAttributedString(string: "\nthree", attributes: card.storage.attributes(at: card.storage.length - 1, effectiveRange: nil)))
        card.normalizeBlocks()
        #expect(card.storage.string.hasSuffix("3.\tthree"))
        #expect(card.markdown == "1. one\n2. two\n3. three")
    }
}

// MARK: -

/// type the
/// @param text into the
/// @param card one character at a time, as its user would
@MainActor func type(_ text: String, into card: CardTextView) {
    for character in text {
#if canImport(AppKit)
        if character == "\n" {
            card.insertNewline(nil)
        }
        else {
            card.insertText(String(character), replacementRange: card.selection)
        }
#else
        card.insertText(String(character))
#endif
        card.normalizeBlocks() // as Deck does after each change
    }
}

@MainActor struct TypedMarkdownTests {

    func editingCard() -> CardTextView {
        let card = makeCard()
        card.isEditable = true
        card.convertsTypedMarkdown = true
        return card
    }

    @Test(arguments: [
        ("**bold** text", "**bold** text"),
        ("__bold__ text", "**bold** text"),
        ("*italic* text", "*italic* text"),
        ("an _italic_ word", "an *italic* word"),
        ("`code` text", "`code` text"),
        ("~~struck~~ text", "~~struck~~ text"),
        ("[a link](https://istumbler.net) text", "[a link](https://istumbler.net) text"),
    ])
    func inline(typed: String, markdown: String) {
        let card = editingCard()
        type(typed, into: card)
        #expect(!card.storage.string.contains("*") && !card.storage.string.contains("_"))
        #expect(card.markdown == markdown)
    }

    @Test func notConverted() {
        let card = editingCard()
        type("snake_case_name 2 * 3 * 4 `a*b*` \\*not\\*", into: card)
        #expect(card.storage.string == "snake_case_name 2 * 3 * 4 a*b* \\*not\\*")
    }

    @Test func plainAfterStyle() {
        let card = editingCard()
        type("**bold** plain", into: card)
        #expect(card.markdown == "**bold** plain")
    }

    @Test func blocks() {
        let card = editingCard()
        type("# Title\n- one\ntwo\n\nbody\n1. first\n\n> quoted", into: card)
        #expect(card.markdown == "# Title\n\n- one\n- two\n\nbody\n\n1. first\n\n> quoted")
    }

    @Test func ruleAndCode() {
        let card = editingCard()
        type("above\n---\n```swift\nlet a = 1\n```\nbelow", into: card)
        #expect(card.markdown == "above\n\n---\n\n```swift\nlet a = 1\n```\n\nbelow")
    }

    @Test func offByDefault() {
        let card = makeCard()
        card.isEditable = true
        type("# **not**", into: card)
        #expect(card.storage.string == "# **not**")
    }
}

// MARK: -

@MainActor struct AttachmentTests {

    @Test func fit() {
        #expect(CardAttachment.fit(CGSize(width: 200, height: 100), in: 100) == CGSize(width: 100, height: 50))
        #expect(CardAttachment.fit(CGSize(width: 50, height: 100), in: 100) == CGSize(width: 50, height: 100))
    }

    @Test func ruleFillsLine() {
        let rule = CardRuleAttachment(width: 2)
        let size = rule.size(of: rule.makeView(), lineWidth: 300, font: nil)
        #expect(size == CGSize(width: 300, height: 4))
    }

    @Test func imageScales() {
        let image = symbol("star")
        let attachment = CardImageAttachment(image: image, maxWidth: 4)
        let size = attachment.size(of: attachment.makeView(), lineWidth: 300, font: nil)
        #expect(size.width == 4)
    }

    @Test func buttonMarkdown() {
        let button = CardButtonAttachment(title: "Open", url: URL(string: "https://istumbler.net")!)
        #expect(button.markdown(relativeTo: nil) == "[Open](https://istumbler.net)")
        #expect(CardButtonAttachment(title: "Act") {}.markdown(relativeTo: nil) == nil)
    }
}
