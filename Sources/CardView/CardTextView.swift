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
    /// the columns of each paragraph style made from them, so they're laid out again when the card is resized
    private let columnStyles = NSMapTable<NSParagraphStyle, NSArray>(keyOptions: [.strongMemory, .objectPointerPersonality],
                                                                    valueOptions: .strongMemory)
    /// the width of the text the columns and tables were laid out in
    private var laidOutWidth: CGFloat = 0

    /// the space around the text of every card, on the Mac and iOS, a TV's cards stay inside its title safe area
    static let margin: CGFloat = 16

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
        initView()
    }

    private func initView() {
#if os(tvOS)
        textContainerInset = UIEdgeInsets(top: 60, left: 90, bottom: 60, right: 90) // inside the TV's title safe area, the same on both sides
        contentInsetAdjustmentBehavior = .never
#elseif canImport(UIKit)
        textContainerInset = UIEdgeInsets(top: Self.margin, left: Self.margin, bottom: Self.margin, right: Self.margin)
        isEditable = false
        backgroundColor = .clear
#else
        textContainerInset = NSSize(width: Self.margin, height: Self.margin)
        isEditable = false
        isRichText = true
        drawsBackground = false
#endif
        linkTextAttributes = [.foregroundColor: CardColor.link, .underlineStyle: NSUnderlineStyle.single.rawValue]
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
        super.setFrameSize(newSize)
        layoutWidth()
    }
#else
    open override func layoutSubviews() {
        super.layoutSubviews()
        layoutWidth()
    }
#endif

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
