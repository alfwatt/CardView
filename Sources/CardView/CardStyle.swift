import Foundation
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// The text styles of a card, named for the Markdown they're written out as
@objc public enum CardStyle: Int, CaseIterable, Sendable {
    /// text, written out as it is
    case text
    /// a `# heading`
    case header
    /// a `## heading`
    case subheader
    /// text centered on the card, Markdown doesn't center text, so it's written out as a paragraph
    case centered
    /// a heading centered on the card, e.g. the name of the thing it's about, below its icon
    case centeredHeader
    /// `**strong**` text, e.g. the label of a value
    case strong
    /// text in the secondary text color, Markdown has no colors, so it's written out as it is
    case gray
    /// `` `code` ``
    case code

    /// the scale of the headers' fonts, relative to the card's font size
    static let headerScale: CGFloat = 1.25
    static let subheaderScale: CGFloat = 1.125

    /// the Markdown block a paragraph in this style is written out as
    public var block: CardBlock {
        switch self {
        case .header: .heading(1)
        case .subheader: .heading(2)
        default: .paragraph
        }
    }

    /// @returns the attributes of text in this style, at the
    /// @param fontSize provided, laid out in the
    /// @param paragraph style
    public func attributes(fontSize: CGFloat, paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: ILFont.cardFont(size: fontSize),
            .paragraphStyle: paragraph,
            .foregroundColor: CardColor.text,
            .cardBlock: block
        ]
        switch self {
        case .text:
            break
        case .header:
            attributes[.font] = ILFont.cardFont(size: fontSize * Self.headerScale, bold: true)
        case .subheader:
            attributes[.font] = ILFont.cardFont(size: fontSize * Self.subheaderScale, bold: true)
        case .centered, .centeredHeader:
            let centered = paragraph.mutableCopy() as! NSMutableParagraphStyle
            centered.alignment = .center
            centered.tabStops = [] // clear tabs
            attributes[.paragraphStyle] = centered
            if self == .centeredHeader {
                attributes[.font] = ILFont.cardFont(size: fontSize * Self.headerScale, bold: true)
            }
        case .strong:
            attributes[.font] = ILFont.cardFont(size: fontSize, bold: true)
        case .gray:
            attributes[.foregroundColor] = CardColor.secondary
        case .code:
            attributes[.font] = ILFont.cardFont(size: fontSize, monospace: true)
        }
        return attributes
    }
}

/// The 2.x names of the styles
public extension CardStyle {
    @available(*, deprecated, renamed: "text")
    static var plain: CardStyle { .text }
    @available(*, deprecated, renamed: "strong")
    static var label: CardStyle { .strong }
    @available(*, deprecated, renamed: "code")
    static var monospace: CardStyle { .code }
}

// MARK: -

/// The Markdown block a paragraph of a card is written out as, every paragraph of a card is tagged with one
/// in its `.cardBlock` attribute, so any card can be written out as Markdown, however it was built
public enum CardBlock: Hashable, Sendable {
    case paragraph
    /// `#` is level 1, `##` level 2…
    case heading(Int)
    case codeBlock(language: String?)
    case quote
    /// the item's marker, a bullet or its number, is the text before the paragraph's first tab
    case listItem(ordered: Bool, depth: Int)
    /// the row's cells are separated by tabs
    case tableRow(header: Bool, alignments: [CardTableAlignment])

    public var isListItem: Bool {
        if case .listItem = self { return true }
        return false
    }

    public var isTableRow: Bool {
        if case .tableRow = self { return true }
        return false
    }
}

public enum CardTableAlignment: Hashable, Sendable {
    case left, center, right
}

// MARK: -

public extension NSAttributedString.Key {
    /// the `CardBlock` of the paragraph the text is in
    static let cardBlock = NSAttributedString.Key("CardBlock")
    /// marks a list item's marker, the bullet or number before its first tab, it isn't written out as Markdown
    static let cardListMarker = NSAttributedString.Key("CardListMarker")
    /// the `UUID` string of the promise the text fulfills
    static let cardPromise = NSAttributedString.Key("CardPromise")
    /// the identifier of the action the text performs when it's clicked or tapped
    static let cardAction = NSAttributedString.Key("CardAction")
    /// the identifier of the section whose header the text is in, which performs the section's action
    static let cardSection = NSAttributedString.Key("CardSection")
}
