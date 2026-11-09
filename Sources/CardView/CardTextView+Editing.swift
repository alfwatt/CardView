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

/// Commands for editing a card, which keep its paragraphs tagged with the Markdown blocks they're written out as
public extension CardTextView {

    /// the selected range of the card's text
    var selection: NSRange {
        get {
#if canImport(AppKit)
            selectedRange()
#else
            selectedRange
#endif
        }
        set {
#if canImport(AppKit)
            setSelectedRange(newValue)
#else
            selectedRange = newValue
#endif
        }
    }

    /// @returns the block of the paragraph at the
    /// @param location provided
    func block(at location: Int) -> CardBlock {
        let storage = storage
        guard storage.length > 0 else { return .paragraph }
        let index = min(location, storage.length - 1)
        let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: index, length: 0))
        return storage.attribute(.cardBlock, at: paragraph.location, effectiveRange: nil) as? CardBlock ?? .paragraph
    }

    /// the block of the paragraph the selection starts in
    var selectedBlock: CardBlock {
        let location = selection.location
        if location == storage.length, location > 0, !storage.string.hasSuffix("\n") {
            return block(at: location - 1)
        }
        return storage.length == 0 ? (typingAttributes[.cardBlock] as? CardBlock ?? .paragraph) : block(at: location)
    }

    // MARK: - Blocks

    /// make the paragraphs in the selection the
    /// @param block provided, keeping the bold, italic and code of their text
    func setBlock(_ block: CardBlock) {
        let attributes = CardMarkdown.attributes(for: block, fontSize: fontSize, paragraph: topStyle, width: textWidth)
        let selected = selection
        let ranges = paragraphRanges(in: selected)
        var removed: [(range: NSRange, length: Int)] = []
        edit(ranges.reduce(selected) { NSUnionRange($0, $1) }) { storage in
            for range in ranges.reversed() {
                if let marker = restyle(storage, range: range, attributes: attributes, block: block) {
                    removed.insert((marker, 0), at: 0)
                }
            }
        }
        selection = Self.map(selected, through: removed, length: storage.length)
        if storage.length == 0 || selection.location == storage.length {
            typingAttributes = attributes
        }
        normalizeBlocks()
    }

    /// the ranges of the paragraphs in the range provided, with their terminators
    private func paragraphRanges(in range: NSRange) -> [NSRange] {
        let string = storage.string as NSString
        guard string.length > 0 else { return [] }
        var ranges: [NSRange] = []
        let span = string.paragraphRange(for: NSRange(location: min(range.location, string.length), length: range.length))
        string.enumerateSubstrings(in: span, options: [.byParagraphs, .substringNotRequired]) { _, _, enclosing, _ in
            ranges.append(enclosing)
        }
        if ranges.isEmpty || (range.location == string.length && string.hasSuffix("\n")) {
            ranges.append(NSRange(location: string.length, length: 0)) // the empty paragraph at the end
        }
        return ranges
    }

    /// restyle the paragraph in the range provided with the attributes of its new block
    /// @returns the range of the list marker it removed, if it had one
    private func restyle(_ storage: NSTextStorage, range: NSRange, attributes: [NSAttributedString.Key: Any], block: CardBlock) -> NSRange? {
        var marker: NSRange?
        storage.enumerateAttributes(in: range) { runAttributes, runRange, _ in
            if runAttributes[.cardListMarker] != nil {
                marker = runRange
                return
            }
            var restyled = attributes
            let base = attributes[.font] as? ILFont ?? .cardFont(size: fontSize)
            let font = runAttributes[.font] as? ILFont
            let old = CardMarkdown.attributes(for: runAttributes[.cardBlock] as? CardBlock ?? .paragraph, fontSize: fontSize, paragraph: topStyle)
            let oldBase = old[.font] as? ILFont // the bold of a heading or the code of a code block isn't kept
            let bold = base.isBold || (font?.isBold == true && oldBase?.isBold != true)
            let code = base.isMonospace || (font?.isMonospace == true && oldBase?.isMonospace != true)
            restyled[.font] = base.withTraits(bold: bold, italic: font?.isItalic == true).monospaced(code)
            for key in [NSAttributedString.Key.link, .attachment, .strikethroughStyle, .cardPromise, .cardHTML] {
                if let value = runAttributes[key] {
                    restyled[key] = value
                }
            }
            storage.setAttributes(restyled, range: runRange)
        }
        if let marker {
            storage.deleteCharacters(in: marker)
        }
        return marker
    }

    /// @returns the
    /// @param range provided, after the
    /// @param changes to the text, the ranges they replaced in ascending order and the length of their replacements,
    /// clamped to the
    /// @param length of the text. A location inside a change moves to its end
    static func map(_ range: NSRange, through changes: [(range: NSRange, length: Int)], length: Int) -> NSRange {
        func map(_ location: Int) -> Int {
            var mapped = location
            for change in changes where change.range.location <= location {
                if NSMaxRange(change.range) <= location {
                    mapped += change.length - change.range.length
                }
                else {
                    mapped += (change.range.location + change.length) - location
                }
            }
            return min(max(mapped, 0), length)
        }
        let start = map(range.location)
        return NSRange(location: start, length: max(map(NSMaxRange(range)) - start, 0))
    }

    /// keep the markers of list items at the start of their paragraphs and their numbers in order,
    /// and remove the markers of paragraphs which aren't list items, call it after the card is edited
    func normalizeBlocks() {
        let storage = storage
        let string = storage.string as NSString
        var changes: [(range: NSRange, marker: NSAttributedString)] = []
        var numbers: [Int] = []
        var previousIsList = false
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, _ in
            guard enclosing.length > 0 else { return }
            let block = storage.attribute(.cardBlock, at: enclosing.location, effectiveRange: nil) as? CardBlock ?? .paragraph
            var markerRange = NSRange(location: enclosing.location, length: 0)
            if range.length > 0, storage.attribute(.cardListMarker, at: range.location, longestEffectiveRange: &markerRange, in: range) == nil {
                markerRange = NSRange(location: range.location, length: 0)
            }
            guard case .listItem(let ordered, let depth) = block else {
                if markerRange.length > 0 {
                    changes.append((markerRange, NSAttributedString()))
                }
                previousIsList = false
                return
            }
            if !previousIsList {
                numbers = []
            }
            numbers = Array(numbers.prefix(depth + 1))
            while numbers.count <= depth { numbers.append(0) }
            numbers[depth] += 1
            previousIsList = true

            let markerText = CardMarkdown.listMarker(ordered: ordered, number: numbers[depth]) + "\t"
            if string.substring(with: markerRange) != markerText {
                var attributes = CardMarkdown.attributes(for: block, fontSize: self.fontSize, paragraph: self.topStyle, width: self.textWidth)
                attributes[.cardListMarker] = true
                changes.append((markerRange, NSAttributedString(string: markerText, attributes: attributes)))
            }
        }
        guard !changes.isEmpty else { return }

        let selected = selection
        edit(NSRange(location: 0, length: storage.length)) { storage in
            for change in changes.reversed() {
                storage.replaceCharacters(in: change.range, with: change.marker)
            }
        }
        selection = Self.map(selected, through: changes.map { ($0.range, $0.marker.length) }, length: storage.length)
    }

    // MARK: - Inline Styles

    /// make the selection bold, or plain if it's all bold already
    func toggleBold() {
        toggleFont({ $0.isBold }) { font, on in font.withTraits(bold: on) }
    }

    /// make the selection italic, or upright if it's all italic already
    func toggleItalic() {
        toggleFont({ $0.isItalic }) { font, on in font.withTraits(italic: on) }
    }

    /// make the selection code, or text if it's all code already
    func toggleCode() {
        toggleFont({ $0.isMonospace }) { font, on in font.monospaced(on) }
    }

    /// true if the selected text is all bold, or the text typed next is when nothing is selected
    var isSelectionBold: Bool { selectionFonts(allSatisfy: \.isBold) }

    /// true if the selected text is all italic, or the text typed next is when nothing is selected
    var isSelectionItalic: Bool { selectionFonts(allSatisfy: \.isItalic) }

    /// true if the selected text is all code, or the text typed next is when nothing is selected
    var isSelectionCode: Bool { selectionFonts(allSatisfy: \.isMonospace) }

    private func selectionFonts(allSatisfy has: (ILFont) -> Bool) -> Bool {
        let range = selection
        guard range.length > 0 else {
            return has(typingAttributes[.font] as? ILFont ?? .cardFont(size: fontSize))
        }
        var all = true
        storage.enumerateAttribute(.font, in: range) { font, _, stop in
            if !has(font as? ILFont ?? .cardFont(size: fontSize)) {
                all = false
                stop.pointee = true
            }
        }
        return all
    }

    private func toggleFont(_ has: (ILFont) -> Bool, _ change: (ILFont, Bool) -> ILFont) {
        let range = selection
        guard range.length > 0 else {
            let font = typingAttributes[.font] as? ILFont ?? .cardFont(size: fontSize)
            typingAttributes[.font] = change(font, !has(font))
            return
        }
        let all = selectionFonts(allSatisfy: has)
        edit(range) { storage in
            storage.enumerateAttribute(.font, in: range) { font, runRange, _ in
                storage.addAttribute(.font, value: change(font as? ILFont ?? .cardFont(size: fontSize), !all), range: runRange)
            }
        }
        selection = range
    }

    // MARK: - Inserting

    /// insert a rule in a paragraph of its own, in place of the selection
    func insertRule() {
        let string = storage.string as NSString
        let range = selection
        let attributes = CardMarkdown.attributes(for: .paragraph, fontSize: fontSize, paragraph: topStyle)
        let rule = NSMutableAttributedString()
        if range.location > 0, string.character(at: range.location - 1) != 0x0A {
            rule.append(NSAttributedString(string: "\n", attributes: attributes))
        }
        rule.appendAttachment(CardRuleAttachment(), fontSize: fontSize, paragraph: topStyle)
        rule.append(NSAttributedString(string: "\n", attributes: attributes))
        replace(range, with: rule)
    }

    /// insert an
    /// @param image in place of the selection, from the
    /// @param source URL provided, so it's written out as Markdown
    func insertImage(_ image: ILImage, source: URL?, alt: String = "") {
        var attributes = typingAttributes
        attributes[.attachment] = CardImageAttachment(image: image, source: source, alt: alt)
        attributes[.link] = nil
        replace(selection, with: NSAttributedString(string: String(Character(.attachmentCharacter)), attributes: attributes))
    }

    /// link the selection to the
    /// @param url provided, or insert the
    /// @param text with the link if nothing is selected
    func insertLink(_ url: URL, text: String? = nil) {
        let range = selection
        if range.length > 0 {
            edit(range) { storage in
                storage.addAttribute(.link, value: url, range: range)
            }
            selection = range
        }
        else {
            var attributes = typingAttributes
            attributes[.link] = url
            replace(range, with: NSAttributedString(string: text ?? url.absoluteString, attributes: attributes))
        }
    }

    // MARK: - Editing

    /// replace the
    /// @param range of the text with the
    /// @param text provided, and select what follows it
    func replace(_ range: NSRange, with text: NSAttributedString) {
        edit(range) { storage in
            storage.replaceCharacters(in: range, with: text)
        }
        selection = NSRange(location: range.location + text.length, length: 0)
    }

    /// make a change to the
    /// @param range of the text, so it can be undone, and tell the delegate the text changed
    internal func edit(_ range: NSRange, _ change: (NSTextStorage) -> Void) {
#if canImport(AppKit)
        let undoable = isEditable // a card which isn't editable doesn't take changes from its user, only from its code
        guard !undoable || shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        change(storage)
        storage.endEditing()
        if undoable {
            didChangeText()
        }
#else
        storage.beginEditing()
        change(storage)
        storage.endEditing()
        delegate?.textViewDidChange?(self)
#endif
    }
}

// MARK: - New Paragraphs

extension CardTextView {

    /// the paragraph after a heading is body text
    func headingEnded() {
        let location = selection.location
        guard location > 0, case .heading = block(at: location - 1) else { return }
        let attributes = CardMarkdown.attributes(for: .paragraph, fontSize: fontSize, paragraph: topStyle)
        typingAttributes = attributes
        let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        if paragraph.location == location, paragraph.length <= 1 {
            storage.setAttributes(attributes, range: paragraph)
        }
    }

#if canImport(AppKit)
    open override func insertNewline(_ sender: Any?) {
        super.insertNewline(sender)
        typed("\n")
    }

    open override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        let text = (string as? NSAttributedString)?.string ?? string as? String ?? ""
        if text != "\n" { // insertNewline(_:) handles returns
            typed(text)
        }
    }
#elseif !os(tvOS)
    open override func insertText(_ text: String) {
        super.insertText(text)
        typed(text)
    }
#endif
}
