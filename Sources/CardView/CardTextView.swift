import Foundation
import SwiftUI
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// A column of a card, laid out with a tab stop
public enum CardColumn: Hashable, Sendable {
    /// a column with its text on the left, starting at the width provided from the last column
    case left(CardWidth)
    /// a column with its text on the right, ending at the width provided from the last column
    case right(CardWidth)

    var width: CardWidth {
        switch self {
        case .left(let width), .right(let width): width
        }
    }

    /// the column of the old `NSNumber` encoding: negative numbers are right tabs, positive numbers left tabs,
    /// numbers between -1 and 1 are fractions of the card's width
    public init(_ number: Double) {
        let width: CardWidth = abs(number) < 1 ? .fraction(abs(number)) : .points(abs(number))
        self = number < 0 ? .right(width) : .left(width)
    }
}

public enum CardWidth: Hashable, Sendable {
    case points(CGFloat)
    /// a fraction of the width of the card's text
    case fraction(CGFloat)
}

// MARK: -

/// A good looking text view for cards of styled text, with columns, rules, images, buttons and embedded views,
/// which reads and writes Markdown, on macOS, iOS, tvOS and visionOS
@objc(CardTextView)
@objcMembers
open class CardTextView: ILTextView {

    /// the size of the card's body text, headers are larger
    public var fontSize: CGFloat = ILFont.cardBodySize

    /// the URL images and links in the card's Markdown are relative to, e.g. the folder of its file
    public var baseURL: URL?

    /// provides the images of the card's Markdown, e.g. from a document which hasn't been saved, before they're loaded from their URLs
    public var imageLoader: ((URL) -> ILImage?)?

    /// convert the Markdown the user types into the styles it stands for, as they type it,
    /// e.g. `**bold**`, `_italic_`, `` `code` ``, `# ` at the start of a heading and `- ` at the start of a list item
    public var convertsTypedMarkdown = false

    /// the style stack, the top style is first
    private var styleStack: [NSParagraphStyle] = []
    /// the columns of each paragraph style made from them, so they're laid out again when the card is resized, by equal styles,
    /// not the same one, the text storage swaps a style for an equal one another text already has
    private let columnStyles = NSMapTable<NSParagraphStyle, NSArray>(keyOptions: [.strongMemory, .objectPersonality],
                                                                    valueOptions: .strongMemory)
    /// the width of the text the columns and tables were laid out in
    private var laidOutWidth: CGFloat = 0

    /// the space around the text of every card, on the Mac and iOS, a TV's cards stay inside its title safe area
    static let margin: CGFloat = 16

    /// the narrowest a card gets on the Mac, a narrower pane clips it rather than squeezing its text away
    public static let minimumWidth: CGFloat = 120

    // MARK: - Initializers

#if canImport(AppKit)
    /// a card laid out with TextKit 2, which draws its attachments' views
    public override init(frame: CGRect) {
        super.init(frame: frame)
        initView()
    }
#endif

    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        initView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        initView(decoded: true)
    }

    /// set up the card, a card
    /// @param decoded from a nib or storyboard keeps the background it was given there
    private func initView(decoded: Bool = false) {
#if os(tvOS)
        textContainerInset = UIEdgeInsets(top: 60, left: 90, bottom: 60, right: 90) // inside the TV's title safe area, the same on both sides
        contentInsetAdjustmentBehavior = .never
#elseif canImport(UIKit)
        textContainerInset = UIEdgeInsets(top: Self.margin, left: Self.margin, bottom: Self.margin, right: Self.margin)
        isEditable = false
        if !decoded {
            backgroundColor = .clear
        }
        addGestureRecognizer(actionTap)
#else
        textContainerInset = NSSize(width: Self.margin, height: Self.margin)
        isEditable = false
        isRichText = true
        drawsBackground = false
#endif
        linkTextAttributes = [.foregroundColor: CardColor.link, .underlineStyle: NSUnderlineStyle.single.rawValue]
        NotificationCenter.default.addObserver(self, selector: #selector(storageDidEdit(_:)), name: NSTextStorage.didProcessEditingNotification,
                                               object: nil) // the storage may not be made yet, a TextKit 2 view's is made later
    }

    /// the card's text storage
    public var storage: NSTextStorage {
#if canImport(AppKit)
        textStorage!
#else
        textStorage
#endif
    }

    /// remove all content from the card, the styles on the stack are kept
    public func clearCard() {
        storage.setAttributedString(NSAttributedString())
        actions.removeAll()
        for style in columnStyles.keyEnumerator().allObjects as! [NSParagraphStyle] where !styleStack.contains(where: { $0 === style }) {
            columnStyles.removeObject(forKey: style)
        }
    }

    // MARK: - Markdown

    /// the card's contents as Markdown, set it to show the Markdown in the card
    public var markdown: String {
        get {
            CardMarkdown.markdown(from: storage, baseURL: baseURL)
        }
        set {
            let text = (try? CardMarkdown.attributedString(from: newValue, fontSize: fontSize, paragraph: topStyle, baseURL: baseURL, width: textWidth > 0 ? textWidth : nil,
                                                         images: imageLoader))
                ?? NSAttributedString(string: newValue, attributes: CardStyle.text.attributes(fontSize: fontSize, paragraph: topStyle))
            storage.setAttributedString(text)
            laidOutWidth = textWidth
        }
    }

    /// append the
    /// @param markdown provided to the card, in its styles
    @discardableResult
    public func appendMarkdown(_ markdown: String) -> NSAttributedString {
        let text = (try? CardMarkdown.attributedString(from: markdown, fontSize: fontSize, paragraph: topStyle, baseURL: baseURL, width: textWidth > 0 ? textWidth : nil,
                                                         images: imageLoader))
            ?? NSAttributedString(string: markdown, attributes: CardStyle.text.attributes(fontSize: fontSize, paragraph: topStyle))
        storage.append(text)
        return text
    }

    // MARK: - Resizing

#if canImport(AppKit)
    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: max(newSize.width, Self.minimumWidth), height: newSize.height))
        layoutWidth()
    }

    open override func layout() {
        fitKeys() // before the text is laid out, an edit after it leaves the viewport blank until the next layout
        super.layout()
    }
#else
    open override func layoutSubviews() {
        layoutWidth()
        fitKeys()
        super.layoutSubviews()
    }
#endif

    // MARK: - Keys

    /// the keys are fitted to their columns at the next layout, after the text changes or the card's width does
    private(set) var keysNeedFitting = false
    /// the keys are being fitted, their edits don't need fitting again
    private var fittingKeys = false

    @objc private func storageDidEdit(_ note: Notification) {
        guard !fittingKeys, let edited = note.object as? NSTextStorage, edited === textStorage, edited.editedMask.contains(.editedCharacters) else { return }
        setKeysNeedFitting()
    }

    private func setKeysNeedFitting() {
        keysNeedFitting = true
#if canImport(AppKit)
        needsLayout = true
#else
        setNeedsLayout()
#endif
    }

    /// the narrowest a key's column and its value's column get, in ems of the card's font size, a narrower card breaks the
    /// key and its value onto lines of their own
    static let narrowestKey: CGFloat = 4
    static let narrowestValue: CGFloat = 6

    /// fit the keys in a right aligned first column to the card's width, e.g. `\tBluetoothDeviceAddressData\tvalue`: in a narrow
    /// card each key is on a line of its own with its value indented below it, otherwise a key wider than its column is truncated
    /// in the middle, so it doesn't push its value out of the next column, a wider card shows more of it again,
    /// an editable card's keys are left as they're typed
    private func fitKeys() {
#if os(tvOS)
        let editable = false // a TV's cards are never edited
#else
        let editable = isEditable
#endif
        guard keysNeedFitting, !editable, textWidth > 0 else { return }
        keysNeedFitting = false
        fittingKeys = true
        defer { fittingKeys = false }
        storage.beginEditing()
        breakOrJoinKeys()
        truncateKeys()
        storage.endEditing()
    }

    /// the edges of the columns, from the card's leading edge, at its width
    private func columnEdges(_ columns: [CardColumn]) -> [CGFloat] {
        var edge: CGFloat = 0
        return columns.map { column in
            let width: CGFloat = switch column.width {
            case .points(let points): points
            case .fraction(let fraction): textWidth * fraction
            }
            edge += width
            return edge
        }
    }

    /// a paragraph style for the columns' keys and values on lines of their own, the value indented under its key
    private func brokenStyle(_ columns: [CardColumn], from style: NSParagraphStyle) -> NSParagraphStyle {
        let broken = NSMutableParagraphStyle()
        broken.setParagraphStyle(style)
        broken.tabStops = []
        broken.firstLineHeadIndent = 0
        broken.headIndent = fontSize
        columnStyles.setObject(columns.map(CardColumnBox.init) as NSArray, forKey: broken) // laid out again at a new width
        return broken
    }

    /// break the keys and their values onto lines of their own in a narrow card, `key⏎value`, the line break marked, and join them
    /// again as `\tkey\tvalue` when the card is wider, in the storage's editing
    private func breakOrJoinKeys() {
        let storage = storage
        let text = storage.string as NSString
        var paragraphs: [NSRange] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byParagraphs, .substringNotRequired]) { _, paragraph, _, _ in
            paragraphs.append(paragraph)
        }
        var broken: [[CardColumn]: NSParagraphStyle] = [:]
        var joined: [[CardColumn]: NSParagraphStyle] = [:]
        for paragraph in paragraphs.reversed() where paragraph.length > 1 { // from the end, so the earlier ranges stay put
            guard let style = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle,
                  let boxes = columnStyles.object(forKey: style) as? [CardColumnBox], let first = boxes.first?.column,
                  case .right = first else { continue }
            let columns = boxes.map(\.column)
            let edges = columnEdges(columns)
            let em = fontSize
            let narrow = edges[0] < CardTextView.narrowestKey * em || textWidth - (edges.last ?? 0) < CardTextView.narrowestValue * em
            var lineBreak: Int?
            storage.enumerateAttribute(.cardKeyBreak, in: paragraph) { value, range, stop in
                if value != nil {
                    lineBreak = range.location
                    stop.pointee = true
                }
            }
            let current = storage.string as NSString
            if let lineBreak {
                let whole = NSRange(location: paragraph.location, length: lineBreak + 1 - paragraph.location)
                if narrow { // stays broken, in the broken style, which the card's width reset
                    let brokenStyle = broken[columns] ?? brokenStyle(columns, from: style)
                    broken[columns] = brokenStyle
                    storage.addAttribute(.paragraphStyle, value: brokenStyle, range: current.paragraphRange(for: whole))
                    continue
                }
                var attributes = storage.attributes(at: lineBreak, effectiveRange: nil) // join: the line break a tab again, and a tab before the key
                attributes[.cardKeyBreak] = nil
                storage.replaceCharacters(in: NSRange(location: lineBreak, length: 1), with: NSAttributedString(string: "\t", attributes: attributes))
                storage.insert(NSAttributedString(string: "\t", attributes: attributes), at: paragraph.location)
                let joinedStyle = joined[columns] ?? paragraphStyle(columns: columns)
                joined[columns] = joinedStyle
                storage.addAttribute(.paragraphStyle, value: joinedStyle, range: (storage.string as NSString).paragraphRange(for: NSRange(location: paragraph.location, length: 0)))
                continue
            }
            guard narrow, paragraph.length > 2, current.character(at: paragraph.location) == 9 else { continue }
            let start = paragraph.location + 1
            let end = current.range(of: "\t", range: NSRange(location: start, length: NSMaxRange(paragraph) - start)).location
            guard end != NSNotFound, end > start, !current.substring(with: NSRange(location: start, length: end - start)).contains("\u{FFFC}") else { continue }
            // break: the tab after the key a line break, the whole key, and no tab before it
            var breakAttributes = storage.attributes(at: end, effectiveRange: nil)
            breakAttributes[.cardKeyBreak] = true
            storage.replaceCharacters(in: NSRange(location: end, length: 1), with: NSAttributedString(string: "\u{2028}", attributes: breakAttributes))
            var keyAttributes = storage.attributes(at: start, effectiveRange: nil)
            if let key = keyAttributes[.cardFullKey] as? String {
                keyAttributes[.cardFullKey] = nil
#if canImport(AppKit)
                keyAttributes[.toolTip] = nil
#endif
                storage.replaceCharacters(in: NSRange(location: start, length: end - start), with: NSAttributedString(string: key, attributes: keyAttributes))
            }
            storage.deleteCharacters(in: NSRange(location: paragraph.location, length: 1))
            let brokenStyle = broken[columns] ?? brokenStyle(columns, from: style)
            broken[columns] = brokenStyle
            storage.addAttribute(.paragraphStyle, value: brokenStyle, range: (storage.string as NSString).paragraphRange(for: NSRange(location: paragraph.location, length: 0)))
        }
    }

    /// truncate the keys wider than their columns, in the storage's editing
    private func truncateKeys() {
        let storage = storage
        let columnStyles = columnStyles
        let text = storage.string as NSString
        let tab = unichar(9)
        var edits: [(range: NSRange, key: NSAttributedString)] = []
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: [.byParagraphs, .substringNotRequired]) { _, paragraph, _, _ in
            guard paragraph.length > 2, text.character(at: paragraph.location) == tab,
                  let style = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle,
                  columnStyles.object(forKey: style) != nil, // the card's columns, not a table's
                  let column = style.tabStops.first, column.alignment == .right else { return }
            let start = paragraph.location + 1
            let end = text.range(of: "\t", range: NSRange(location: start, length: NSMaxRange(paragraph) - start)).location
            guard end != NSNotFound, end > start else { return }
            let range = NSRange(location: start, length: end - start)
            let shown = text.substring(with: range)
            guard !shown.contains("\u{FFFC}") else { return } // an image or a view, not a key
            var attributes = storage.attributes(at: start, effectiveRange: nil)
            let key = attributes[.cardFullKey] as? String ?? shown
            attributes[.cardFullKey] = nil
#if canImport(AppKit)
            attributes[.toolTip] = nil
#endif
            let fitted = CardTextView.truncatingMiddle(key, attributes: attributes, toFit: column.location - 4) // a little space before the column's edge
            guard fitted != shown else { return }
            if fitted != key {
                attributes[.cardFullKey] = key
#if canImport(AppKit)
                attributes[.toolTip] = key
#endif
            }
            edits.append((range, NSAttributedString(string: fitted, attributes: attributes)))
        }
        for edit in edits.reversed() {
            storage.replaceCharacters(in: edit.range, with: edit.key)
        }
    }

    /// @returns the string, or its start and end with an ellipsis between them, as much of it as fits the width in the attributes
    static func truncatingMiddle(_ string: String, attributes: [NSAttributedString.Key: Any], toFit width: CGFloat) -> String {
        var measured = attributes
        measured[.paragraphStyle] = nil
        func fits(_ text: String) -> Bool {
            NSAttributedString(string: text, attributes: measured).size().width <= width
        }
        guard width > 0, !fits(string) else { return string }
        let characters = Array(string)
        func kept(_ count: Int) -> String {
            let head = (count + 1) / 2
            return String(characters.prefix(head)) + "…" + String(characters.suffix(count - head))
        }
        var low = 0, high = characters.count - 1 // the characters kept, the most which fit
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(kept(middle)) { low = middle } else { high = middle - 1 }
        }
        return kept(low)
    }

    /// the width of the text, inside the text container's insets and padding, the columns are fractions of it
    public var textWidth: CGFloat {
#if canImport(AppKit)
        let padding = (textContainer?.lineFragmentPadding ?? 0) * 2
        return frame.width - (textContainerInset.width * 2) - padding
#else
        let padding = textContainer.lineFragmentPadding * 2
        return frame.width - textContainerInset.left - textContainerInset.right - padding
#endif
    }

    /// the columns and tables are fractions of the card's width, lay them out again when it changes
    private func layoutWidth() {
        let width = textWidth
        guard width > 0, abs(width - laidOutWidth) >= 0.5 else {
            return
        }
        let storage = storage
        var changes: [(NSRange, NSParagraphStyle)] = []
        var styles: [[CardColumn]: NSParagraphStyle] = [:] // one new style for each set of columns
        func style(for columns: [CardColumn]) -> NSParagraphStyle {
            if let style = styles[columns] { return style }
            let style = paragraphStyle(columns: columns)
            styles[columns] = style
            return style
        }
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
            if let block = attributes[.cardBlock] as? CardBlock, case .tableRow(_, let alignments) = block,
               let graph = attributes[.paragraphStyle] as? NSParagraphStyle {
                changes.append((range, CardMarkdown.tableStyle(alignments, width: width, paragraph: graph)))
            }
            else if let graph = attributes[.paragraphStyle] as? NSParagraphStyle, let columns = columnStyles.object(forKey: graph) as? [CardColumnBox] {
                changes.append((range, style(for: columns.map(\.column))))
            }
        }
        storage.beginEditing()
        for (range, style) in changes {
            storage.addAttribute(.paragraphStyle, value: style, range: range)
        }
        storage.endEditing()
        for (index, graph) in styleStack.enumerated() { // and the styles of what's appended next
            if let columns = columnStyles.object(forKey: graph) as? [CardColumnBox] {
                styleStack[index] = style(for: columns.map(\.column))
            }
        }
        laidOutWidth = width
        setKeysNeedFitting() // the columns moved
    }

    // MARK: - Style Stack

    /// the top style on the style stack, or the default paragraph style if the stack is empty
    public var topStyle: NSParagraphStyle {
        styleStack.first ?? .default
    }

    /// push a new style on to the stack, making it the top style
    /// @returns the number of styles on the stack
    @discardableResult
    @objc(pushStyle:)
    public func push(_ style: NSParagraphStyle) -> Int {
        styleStack.insert(style, at: 0)
        return styleStack.count
    }

    /// pop the top style off the stack
    /// @returns the style that was last pushed onto the stack, or nil if the stack is empty
    @discardableResult
    public func popStyle() -> NSParagraphStyle? {
        styleStack.isEmpty ? nil : styleStack.removeFirst()
    }

    // MARK: - Columns

    /// @returns a paragraph style with the
    /// @param columns provided as tab stops, e.g. `[.right(.fraction(0.33)), .left(.points(5))]` is a right tab
    /// a third of the way across the card, and a left tab five points to the right of that
    public func paragraphStyle(columns: [CardColumn]) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        var edge: CGFloat = 0
        style.tabStops = columns.map { column in
            let width: CGFloat = switch column.width {
            case .points(let points): points
            case .fraction(let fraction): textWidth * fraction
            }
            edge += width
            if case .right = column {
                return NSTextTab(textAlignment: .right, location: edge)
            }
            return NSTextTab(textAlignment: .left, location: edge)
        }
        style.lineBreakMode = .byCharWrapping
        style.firstLineHeadIndent = 0
        style.headIndent = edge
        columnStyles.setObject(columns.map(CardColumnBox.init) as NSArray, forKey: style)
        laidOutWidth = textWidth
        return style
    }

    /// push the style for the
    /// @param columns provided onto the style stack, text appended after uses the columns until it's popped
    /// @returns the number of styles on the stack
    @discardableResult
    public func pushColumns(_ columns: [CardColumn]) -> Int {
        push(paragraphStyle(columns: columns))
    }

    /// replace the styles on the stack with the style for the
    /// @param columns provided, for cards which change columns between sections
    public func useColumns(_ columns: [CardColumn]) {
        styleStack.removeAll()
        pushColumns(columns)
    }

    /// push columns in the `NSNumber` encoding of `CardColumn(_:)`
    @discardableResult
    @objc(pushColumns:)
    public func pushColumnWidths(_ widths: [NSNumber]) -> Int {
        pushColumns(widths.map { CardColumn($0.doubleValue) })
    }

    /// use columns in the `NSNumber` encoding of `CardColumn(_:)`
    @objc(useColumns:)
    public func useColumnWidths(_ widths: [NSNumber]) {
        useColumns(widths.map { CardColumn($0.doubleValue) })
    }

    // MARK: - Text

    /// append the
    /// @param string provided in the
    /// @param style provided, at the card's font size in its top style
    @discardableResult
    @objc(appendString:style:)
    public func append(_ string: String, style: CardStyle = .text) -> NSAttributedString {
        storage.append(string, style: style, fontSize: fontSize, paragraph: topStyle)
    }

    @discardableResult
    @objc(appendLink:text:)
    public func appendLink(_ url: URL, text: String? = nil) -> NSAttributedString {
        storage.appendLink(url, text: text, fontSize: fontSize, paragraph: topStyle)
    }

    @discardableResult
    public func appendNewline() -> NSAttributedString {
        storage.appendNewline(fontSize: fontSize, paragraph: topStyle)
    }

    @discardableResult
    public func appendTab() -> NSAttributedString {
        storage.appendTab(fontSize: fontSize, paragraph: topStyle)
    }

    /// append the
    /// @param string provided as it is, in its own attributes
    @discardableResult
    @objc(appendAttributedString:)
    public func appendAttributed(_ string: NSAttributedString) -> NSAttributedString {
        storage.append(string)
        return string
    }

    /// append a section's
    /// @param title as a subheader, on a new line, with a rule under it
    @discardableResult
    @objc(appendSection:)
    public func appendSection(_ title: String) -> NSAttributedString {
        appendSection(title, image: nil)
    }

    /// append a section's
    /// @param title as a subheader, on a new line, after a small
    /// @param image if there is one, as an action has, with a rule under it
    @discardableResult
    @objc(appendSection:image:)
    public func appendSection(_ title: String, image: ILImage?) -> NSAttributedString {
        let start = storage.length
        appendNewline()
        if let image {
            storage.appendAttachment(CardImageAttachment(image: image, maxWidth: fontSize), style: .subheader, fontSize: fontSize,
                                     paragraph: topStyle) // centered on the title's x height
            append(" ")
        }
        append(title, style: .subheader)
        appendRule()
        return storage.attributedSubstring(from: NSRange(location: start, length: storage.length - start))
    }

    /// append a section's
    /// @param title as a subheader, on a new line, after a small
    /// @param image if there is one, both with the
    /// @param attributes provided, e.g. the `sectionAttributes` of an action, with a rule under it
    @discardableResult
    public func appendSection(_ title: String, image: ILImage?, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        storage.appendSection(title, image: image, attributes: attributes, fontSize: fontSize, paragraph: topStyle)
    }

    /// @returns the attributes of text in the
    /// @param style provided, at the
    /// @param size provided or the card's font size, in the
    /// @param paragraph style provided or the card's top style
    public func attributes(_ style: CardStyle, size: CGFloat? = nil, paragraph: NSParagraphStyle? = nil) -> [NSAttributedString.Key: Any] {
        style.attributes(fontSize: size ?? fontSize, paragraph: paragraph ?? topStyle)
    }

    /// the width of the card for scaling its images, a new card's frame can be empty before it's laid out
    /// and an image scaled to no width can't be drawn, so it's 320 points until the card has a width
    public var safeContentWidth: CGFloat {
        frame.width > 0 ? frame.width : 320
    }

    // MARK: - Rules

    /// append a rule across the card, in the
    /// @param color provided or the pale text color, at the
    /// @param width provided
    @discardableResult
    @objc(appendRuleWithColor:width:)
    public func appendRule(color: ILColor? = nil, width: CGFloat = 1) -> NSAttributedString {
        storage.appendRule(color: color, width: width, fontSize: fontSize, paragraph: topStyle)
    }

    // MARK: - Attachments

    /// append an
    /// @param image centered on the card, from the
    /// @param source URL if it has one, so it's written out as Markdown
    @discardableResult
    @objc(appendImage:source:)
    public func appendImage(_ image: ILImage, source: URL? = nil) -> NSAttributedString {
        storage.appendImage(image, source: source, fontSize: fontSize, paragraph: topStyle)
    }

    /// append a button with the
    /// @param title and
    /// @param image provided, which performs the
    /// @param action when it's pressed
    @discardableResult
    @objc(appendButton:image:action:)
    public func appendButton(_ title: String, image: ILImage? = nil, action: @escaping @MainActor () -> Void) -> NSAttributedString {
        storage.appendButton(title, image: image, fontSize: fontSize, paragraph: topStyle, action: action)
    }

    /// append a button with the
    /// @param title provided, which opens the
    /// @param url when it's pressed
    @discardableResult
    @objc(appendButton:url:)
    public func appendButton(_ title: String, url: URL) -> NSAttributedString {
        storage.appendButton(title, url: url, fontSize: fontSize, paragraph: topStyle)
    }

    /// embed a
    /// @param view in the card, at the
    /// @param size provided or its fitting size if it's zero
    @discardableResult
    @objc(appendView:size:)
    public func appendView(_ view: ILView, size: CGSize = .zero) -> NSAttributedString {
        storage.appendView(view, size: size, fontSize: fontSize, paragraph: topStyle)
    }

    /// embed a SwiftUI
    /// @param view in the card, at the
    /// @param size provided or its ideal size
    @discardableResult
    public func appendView(_ view: some View, size: CGSize? = nil) -> NSAttributedString {
        storage.appendView(view, size: size, fontSize: fontSize, paragraph: topStyle)
    }

    // MARK: - Actions

    /// the actions of the card's text, by the identifiers in their `.cardAction` attributes
    private var actions: [String: @MainActor () -> Void] = [:]

    /// append text which performs an
    /// @param action when it's clicked or tapped: a small
    /// @param image if there is one, then the text appended by the
    /// @param content closure provided
    /// @returns the text appended
    @discardableResult
    public func appendAction(image: ILImage? = nil, _ content: () -> Void, action: @escaping @MainActor () -> Void) -> NSAttributedString {
        let start = storage.length
        if let image {
            storage.appendAttachment(CardImageAttachment(image: image, maxWidth: fontSize), fontSize: fontSize, paragraph: topStyle)
            append(" ")
        }
        content()
        let range = NSRange(location: start, length: storage.length - start)
        storage.addAttributes(actionAttributes(action), range: range)
        return storage.attributedSubstring(from: range)
    }

    /// @returns the attributes of text which performs an
    /// @param action when it's clicked or tapped, for text built apart from the card, e.g. to fulfill a promise
    public func actionAttributes(_ action: @escaping @MainActor () -> Void) -> [NSAttributedString.Key: Any] {
        let identifier = UUID().uuidString
        actions[identifier] = action
        var attributes: [NSAttributedString.Key: Any] = [.cardAction: identifier]
#if canImport(AppKit)
        attributes[.cursor] = NSCursor.pointingHand
#endif
        return attributes
    }

    // MARK: - Spoilers

    /// clicking or tapping a `>!spoiler!<` reveals it, and again hides it, when it's false spoilers stay hidden, e.g. for screenshots
    public var revealsSpoilers = true

    /// the identifiers of the spoilers which are revealed, kept when the card is cleared, so a card which is built again,
    /// e.g. to update its values, shows the spoilers that were revealed
    public var revealedSpoilers: Set<String> = []

    /// append the
    /// @param string provided as a spoiler, hidden until it's clicked or tapped, unless the spoiler with the
    /// @param identifier provided, or its text, was revealed, in the
    /// @param style provided, at the card's font size in its top style
    @discardableResult
    public func appendSpoiler(_ string: String, style: CardStyle = .text, identifier: String? = nil) -> NSAttributedString {
        let start = storage.length
        let spoiler = storage.appendSpoiler(string, style: style, identifier: identifier, fontSize: fontSize, paragraph: topStyle)
        if revealsSpoilers, revealedSpoilers.contains(identifier ?? string) {
            let range = NSRange(location: start, length: spoiler.length)
            storage.setSpoiler(hidden: false, range: range)
            return storage.attributedSubstring(from: range)
        }
        return spoiler
    }

    /// @returns the range of the spoiler at the
    /// @param index provided, or the character before it, nil if there isn't one there
    func spoiler(at index: Int) -> NSRange? {
        let storage = storage
        for location in [index, index - 1] where location >= 0 && location < storage.length {
            var range = NSRange()
            if storage.attribute(.cardSpoiler, at: location, longestEffectiveRange: &range,
                                 in: NSRange(location: 0, length: storage.length)) != nil {
                return range
            }
        }
        return nil
    }

    /// reveal the hidden spoiler, or hide the revealed spoiler, at the
    /// @param index provided
    /// @returns true if there was a spoiler there to reveal or hide
    @discardableResult
    func toggleSpoiler(at index: Int) -> Bool {
        guard revealsSpoilers, let range = spoiler(at: index) else { return false }
        let hidden = storage.attribute(.cardSpoiler, at: range.location, effectiveRange: nil) as? Bool ?? false
        let identifier = storage.attribute(.cardSpoilerIdentifier, at: range.location, effectiveRange: nil) as? String
            ?? (storage.string as NSString).substring(with: range)
        storage.setSpoiler(hidden: !hidden, range: range)
        if hidden {
            revealedSpoilers.insert(identifier)
        }
        else {
            revealedSpoilers.remove(identifier)
        }
        return true
    }

    /// @returns the action of the text at the
    /// @param index provided, or of the character before it, so the end of an action's line performs it too
    func action(at index: Int) -> (@MainActor () -> Void)? {
        let storage = storage
        for location in [index, index - 1] where location >= 0 && location < storage.length {
            if let identifier = storage.attribute(.cardAction, at: location, effectiveRange: nil) as? String {
                return actions[identifier]
            }
        }
        return nil
    }

    // MARK: - Sections

    /// the sections showing that their action was done, by their identifiers
    private var sectionsShowingDone: Set<String> = []

    /// @returns the attributes of a section's header which performs an
    /// @param action with the section's text as RTF when it's clicked or tapped, e.g. to copy it,
    /// then shows it was done, for headers built apart from the card with `appendSection(_:image:attributes:fontSize:paragraph:)`
    public func sectionAttributes(_ action: @escaping @MainActor (_ rtf: Data?) -> Void) -> [NSAttributedString.Key: Any] {
        let identifier = UUID().uuidString
        var attributes = actionAttributes { [weak self] in
            guard let self, let range = sectionRange(identifier) else { return }
            action(Self.rtf(of: storage.attributedSubstring(from: range)))
            showDone(section: identifier)
        }
        attributes[.cardSection] = identifier
        return attributes
    }

    /// @returns the range of the section with the
    /// @param identifier provided: its header, through the line before the next section's header
    func sectionRange(_ identifier: String) -> NSRange? {
        let storage = storage
        var start: Int?
        var end = storage.length
        storage.enumerateAttribute(.cardSection, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            guard let value = value as? String else { return }
            if value == identifier {
                start = start ?? range.location
            }
            else if start != nil {
                end = (storage.string as NSString).lineRange(for: NSRange(location: range.location, length: 0)).location
                stop.pointee = true
            }
        }
        guard let start else { return nil }
        return NSRange(location: start, length: max(end, start) - start)
    }

    /// @returns the
    /// @param text provided as RTF, in the colors it has in light mode so it can be read on a page,
    /// without its attachments, e.g. a section's symbol and rule, and the space or newline after each
    static func rtf(of text: NSAttributedString) -> Data? {
        let rich = NSMutableAttributedString(attributedString: text)
        rich.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rich.length), options: .reverse) { value, range, _ in
            guard value != nil else { return }
            var removed = range
            if NSMaxRange(range) < rich.length, [" ", "\n"].contains((rich.string as NSString).substring(with: NSRange(location: NSMaxRange(range), length: 1))) {
                removed.length += 1
            }
            rich.deleteCharacters(in: removed)
        }
        while let last = rich.string.last, last.isWhitespace {
            rich.deleteCharacters(in: NSRange(location: rich.length - 1, length: 1))
        }
        rich.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: rich.length)) { value, range, _ in
            guard let color = value as? ILColor else { return }
#if canImport(AppKit)
            var light = color
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance { light = color.usingColorSpace(.sRGB) ?? color }
#else
            let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
#endif
            rich.addAttribute(.foregroundColor, value: light, range: range)
        }
        return try? rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    /// show that the action of the section with the
    /// @param identifier provided was done, for a moment: a checkmark in place of its symbol, and its header highlighted
    func showDone(section identifier: String) {
        guard !sectionsShowingDone.contains(identifier), let range = sectionRange(identifier) else { return }
        sectionsShowingDone.insert(identifier)
        let symbol = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? CardImageAttachment
        let original = symbol?.image
        if let checkmark = ILImage(systemName: "checkmark.circle.fill") {
            symbol?.update(checkmark)
        }
        setHeaderHighlight(CardColor.accent.withAlphaComponent(0.2), section: identifier)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            if let original {
                symbol?.update(original)
            }
            self?.setHeaderHighlight(nil, section: identifier)
            self?.sectionsShowingDone.remove(identifier)
        }
    }

    /// set or remove the
    /// @param highlight color behind the header of the
    /// @param section with the identifier provided, wherever it is now, e.g. after a promise before it was fulfilled
    private func setHeaderHighlight(_ highlight: ILColor?, section identifier: String) {
        let storage = storage
        storage.enumerateAttribute(.cardSection, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value as? String == identifier else { return }
            if let highlight {
                storage.addAttribute(.backgroundColor, value: highlight, range: range)
            }
            else {
                storage.removeAttribute(.backgroundColor, range: range)
            }
        }
    }

#if canImport(AppKit)
    open override func mouseDown(with event: NSEvent) {
        let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        if let action = action(at: index) {
            action()
        }
        else if toggleSpoiler(at: index), !isEditable {
            return
        }
        else { // and an editable card's click puts the insertion point in the spoiler it reveals
            super.mouseDown(with: event)
        }
    }
#else
    /// the tap which performs the actions of the card's text
    private lazy var actionTap = UITapGestureRecognizer(target: self, action: #selector(onActionTap(_:)))

    /// the index of the character nearest the
    /// @param point provided
    private func characterIndex(at point: CGPoint) -> Int? {
        guard let position = closestPosition(to: point) else { return nil }
        return offset(from: beginningOfDocument, to: position)
    }

    open override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === actionTap else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        guard let index = characterIndex(at: gestureRecognizer.location(in: self)) else { return false }
        return action(at: index) != nil || (revealsSpoilers && spoiler(at: index) != nil)
    }

    @objc private func onActionTap(_ tap: UITapGestureRecognizer) {
        guard let index = characterIndex(at: tap.location(in: self)) else { return }
        if let action = action(at: index) {
            action()
        }
        else {
            toggleSpoiler(at: index)
        }
    }
#endif

    // MARK: - Formatter Registry

    private static var formatters: [ObjectIdentifier: Formatter] = [:]

    /// register a
    /// @param formatter for values of the
    /// @param type provided and its subclasses, e.g. `NSData.self` for `Data`
    @objc(registerFormatter:forClass:)
    public static func register(_ formatter: Formatter, for type: AnyClass) {
        formatters[ObjectIdentifier(type)] = formatter
    }

    /// @returns the formatter registered for the
    /// @param type provided, or its closest superclass
    @objc(registeredFormatterForClass:)
    public static func registeredFormatter(for type: AnyClass) -> Formatter? {
        var type: AnyClass? = type
        while let current = type {
            if let formatter = formatters[ObjectIdentifier(current)] {
                return formatter
            }
            type = current.superclass()
        }
        return nil
    }

    /// @returns the
    /// @param value formatted with the formatter registered for its class, in the
    /// @param attributes provided, a dash if there's no value
    @objc(formatted:withAttributes:)
    public static func formatted(_ value: Any?, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        guard let value else {
            return NSAttributedString(string: "-", attributes: attributes)
        }
        guard let formatter = registeredFormatter(for: type(of: value as AnyObject)) else {
            return NSAttributedString(string: String(describing: value), attributes: attributes)
        }
        return CardFormatter.attributedString(value, formatter: formatter, attributes: attributes)
    }

    // MARK: - Formatted Values

    /// append the
    /// @param value provided, formatted with the formatter registered for its class
    @discardableResult
    @objc(appendFormatted:)
    public func appendFormatted(_ value: Any?) -> NSAttributedString {
        let formatted = Self.formatted(value, attributes: CardStyle.text.attributes(fontSize: fontSize, paragraph: topStyle))
        storage.append(formatted)
        return formatted
    }

    /// append the
    /// @param value formatted with the
    /// @param formatter provided, in the
    /// @param attributes provided or the card's plain style
    @discardableResult
    @objc(append:formatter:attributes:)
    public func append(_ value: Any, formatter: Formatter, attributes: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString {
        let formatted = CardFormatter.attributedString(value, formatter: formatter,
                                                       attributes: attributes ?? CardStyle.text.attributes(fontSize: fontSize, paragraph: topStyle))
        storage.append(formatted)
        return formatted
    }

    // MARK: - Promises

    /// promise to append text later, an ellipsis `…` with the
    /// @param attributes provided is appended to the card in its place
    /// @returns the promise
    @objc(appendPromiseWithAttributes:)
    public func appendPromise(attributes: [NSAttributedString.Key: Any]? = nil) -> UUID {
        let promise = UUID()
        var promised = attributes ?? CardStyle.text.attributes(fontSize: fontSize, paragraph: topStyle)
        promised[.cardPromise] = promise.uuidString
        storage.append(NSAttributedString(string: "…", attributes: promised))
        return promise
    }

    /// fulfill a
    /// @param promise with the
    /// @param string provided. A promise can be fulfilled more than once, e.g. with loading or progress messages,
    /// the string can be built in the background in the card's styles with the `NSMutableAttributedString` extension
    @objc(fulfillPromise:withString:)
    public func fulfill(_ promise: UUID, with string: NSAttributedString) {
        let storage = storage
        var ranges: [NSRange] = []
        storage.enumerateAttribute(.cardPromise, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if value as? String == promise.uuidString {
                ranges.append(range)
            }
        }
        guard let first = ranges.first else { return }
        let fulfilled = NSMutableAttributedString(attributedString: string)
        fulfilled.addAttribute(.cardPromise, value: promise.uuidString, range: NSRange(location: 0, length: fulfilled.length))
        storage.beginEditing()
        for range in ranges.dropFirst().reversed() { // the string may have had several runs, scrub them in reverse so the ranges stay put
            storage.replaceCharacters(in: range, with: "")
        }
        storage.replaceCharacters(in: first, with: fulfilled)
        storage.endEditing()
    }

    /// fulfill a
    /// @param promise with the
    /// @param value provided, formatted with the formatter registered for its class
    @objc(fulfillPromise:withFormatted:)
    public func fulfill(_ promise: UUID, formatted value: Any?) {
        fulfill(promise, with: Self.formatted(value, attributes: CardStyle.text.attributes(fontSize: fontSize, paragraph: topStyle)))
    }

    // MARK: - Presenting

#if os(tvOS)
    /// a card takes the focus, so the remote's touch surface scrolls it
    open override var canBecomeFocused: Bool {
        true
    }

    @objc private func onDismissSwipe(_ swipe: UISwipeGestureRecognizer) {
        (next as? UIViewController)?.dismiss(animated: true)
    }

    /// show the card full screen over the system's blur, Menu returns
    public func presentFullScreen(from view: UIView) {
        let controller = UIViewController()
        backgroundColor = .clear
        controller.view = self
        controller.modalPresentationStyle = .blurOverFullScreen
        isUserInteractionEnabled = true // scrolled with the remote's touch surface
        isScrollEnabled = true
        panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        showsVerticalScrollIndicator = true
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] { // back and forward return too
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(onDismissSwipe(_:)))
            swipe.direction = direction
            addGestureRecognizer(swipe)
        }
        var presenter = view.window?.rootViewController
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        presenter?.present(controller, animated: true)
    }
#endif
}

// MARK: -

/// a column in an `NSArray`, for the map of the column styles
final class CardColumnBox: NSObject {
    let column: CardColumn

    init(_ column: CardColumn) {
        self.column = column
    }
}
