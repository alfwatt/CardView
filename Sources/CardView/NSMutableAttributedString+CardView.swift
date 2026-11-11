import Foundation
import SwiftUI
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Builds styled text for a card, in the background or on the card itself
public extension NSMutableAttributedString {

    // MARK: - Text

    /// append the
    /// @param string provided in the
    /// @param style at the
    /// @param fontSize in the
    /// @param paragraph style
    @discardableResult
    @objc(appendString:style:fontSize:paragraph:)
    func append(_ string: String, style: CardStyle = .text, fontSize: CGFloat, paragraph: NSParagraphStyle) -> NSAttributedString {
        let styled = NSAttributedString(string: string, attributes: style.attributes(fontSize: fontSize, paragraph: paragraph))
        append(styled)
        return styled
    }

    /// append a link to the
    /// @param url with the
    /// @param text provided, or the URL if there is none
    @discardableResult
    @objc(appendLink:text:fontSize:paragraph:)
    func appendLink(_ url: URL, text: String?, fontSize: CGFloat, paragraph: NSParagraphStyle) -> NSAttributedString {
        var attributes = CardStyle.text.attributes(fontSize: fontSize, paragraph: paragraph)
        attributes[.link] = url
        let link = NSAttributedString(string: text ?? url.absoluteString, attributes: attributes)
        append(link)
        return link
    }

    // MARK: - Spacing

    @discardableResult
    @objc(appendNewlineWithFontSize:paragraph:)
    func appendNewline(fontSize: CGFloat, paragraph: NSParagraphStyle) -> NSAttributedString {
        append("\n", fontSize: fontSize, paragraph: paragraph)
    }

    @discardableResult
    @objc(appendTabWithFontSize:paragraph:)
    func appendTab(fontSize: CGFloat, paragraph: NSParagraphStyle) -> NSAttributedString {
        append("\t", fontSize: fontSize, paragraph: paragraph)
    }

    // MARK: - Rules

    /// append a rule across the card in the
    /// @param color provided, the pale text color by default, at the
    /// @param width provided. Each rule is its own paragraph, the next line follows right below it, without a blank line
    @discardableResult
    @objc(appendRuleWithColor:width:fontSize:paragraph:)
    func appendRule(color: ILColor? = nil, width: CGFloat = 1, fontSize: CGFloat, paragraph: NSParagraphStyle) -> NSAttributedString {
        appendNewline(fontSize: fontSize, paragraph: paragraph)
        return appendAttachment(CardRuleAttachment(color: color, width: width), fontSize: fontSize, paragraph: paragraph)
    }

    /// append a section's
    /// @param title as a subheader, on a new line, after a small
    /// @param image if there is one, both with the
    /// @param attributes provided, e.g. a card's `actionAttributes`, with a rule under it
    @discardableResult
    func appendSection(_ title: String, image: ILImage? = nil, attributes: [NSAttributedString.Key: Any] = [:],
                       fontSize: CGFloat, paragraph: NSParagraphStyle) -> NSAttributedString {
        let start = length
        appendNewline(fontSize: fontSize, paragraph: paragraph)
        let header = length
        if let image {
            appendAttachment(CardImageAttachment(image: image, maxWidth: fontSize), style: .subheader, fontSize: fontSize, paragraph: paragraph) // centered on the title's x height
            append(" ", fontSize: fontSize, paragraph: paragraph)
        }
        append(title, style: .subheader, fontSize: fontSize, paragraph: paragraph)
        addAttributes(attributes, range: NSRange(location: header, length: length - header))
        appendRule(fontSize: fontSize, paragraph: paragraph)
        return attributedSubstring(from: NSRange(location: start, length: length - start))
    }

    // MARK: - Attachments

    /// append an
    /// @param image centered on the card, from the
    /// @param source URL if it has one, so it's written out as Markdown
    @discardableResult
    @objc(appendImage:source:fontSize:paragraph:)
    func appendImage(_ image: ILImage, source: URL? = nil, fontSize: CGFloat, paragraph: NSParagraphStyle) -> NSAttributedString {
        if !isImageParagraph { // a paragraph's first character sets its alignment, so start a new one to center the image
            appendNewline(fontSize: fontSize, paragraph: paragraph)
        }
        return appendAttachment(CardImageAttachment(image: image, source: source), style: .centered, fontSize: fontSize, paragraph: paragraph)
    }

    /// append a button with the
    /// @param title and
    /// @param image provided, which performs the
    /// @param action when it's pressed
    @discardableResult
    @objc(appendButton:image:fontSize:paragraph:action:)
    func appendButton(_ title: String, image: ILImage? = nil, fontSize: CGFloat, paragraph: NSParagraphStyle,
                      action: @escaping @MainActor () -> Void) -> NSAttributedString {
        appendAttachment(CardButtonAttachment(title: title, image: image, action: action), fontSize: fontSize, paragraph: paragraph)
    }

    /// append a button with the
    /// @param title provided which opens the
    /// @param url when it's pressed
    @discardableResult
    @objc(appendButton:url:fontSize:paragraph:)
    func appendButton(_ title: String, url: URL, fontSize: CGFloat, paragraph: NSParagraphStyle) -> NSAttributedString {
        appendAttachment(CardButtonAttachment(title: title, url: url), fontSize: fontSize, paragraph: paragraph)
    }

    /// embed a
    /// @param view in the card, at the
    /// @param size provided or its fitting size
    @MainActor @discardableResult
    @objc(appendView:size:fontSize:paragraph:)
    func appendView(_ view: ILView, size: CGSize, fontSize: CGFloat, paragraph: NSParagraphStyle) -> NSAttributedString {
        appendAttachment(CardViewAttachment(view: view, size: size == .zero ? nil : size), fontSize: fontSize, paragraph: paragraph)
    }

    /// embed a SwiftUI view in the card, at the
    /// @param size provided or its ideal size
    @MainActor @discardableResult
    func appendView(_ view: some View, size: CGSize? = nil, fontSize: CGFloat, paragraph: NSParagraphStyle) -> NSAttributedString {
        appendAttachment(CardViewAttachment(view, size: size), fontSize: fontSize, paragraph: paragraph)
    }

    /// append any
    /// @param attachment in the
    /// @param style provided
    @discardableResult
    @objc(appendAttachment:style:fontSize:paragraph:)
    func appendAttachment(_ attachment: NSTextAttachment, style: CardStyle = .text, fontSize: CGFloat,
                          paragraph: NSParagraphStyle) -> NSAttributedString {
        var attributes = style.attributes(fontSize: fontSize, paragraph: paragraph)
        attributes[.attachment] = attachment
        let attached = NSAttributedString(string: String(Character(.attachmentCharacter)), attributes: attributes)
        append(attached)
        return attached
    }
}

extension NSAttributedString {
    /// true if the last paragraph is empty or has only images and spaces in it, e.g. a row of icons, so an image appended to it is centered
    var isImageParagraph: Bool {
        let text = string as NSString
        let newline = text.rangeOfCharacter(from: .newlines, options: .backwards)
        var index = newline.location == NSNotFound ? 0 : NSMaxRange(newline)
        while index < length {
            let character = text.character(at: index)
            if Int(character) == NSTextAttachment.character {
                guard attribute(.attachment, at: index, effectiveRange: nil) is CardImageAttachment else { return false }
            }
            else if !(Character(Unicode.Scalar(character) ?? " ").isWhitespace) {
                return false
            }
            index += 1
        }
        return true
    }
}

extension Unicode.Scalar {
    /// U+FFFC OBJECT REPLACEMENT CHARACTER, the character of each attachment
    static let attachmentCharacter = Unicode.Scalar(NSTextAttachment.character)!
}
