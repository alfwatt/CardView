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

/// Converts the Markdown the user types into the styles it stands for, when `convertsTypedMarkdown` is set:
/// inline styles when their closing delimiter is typed, blocks when the space after their prefix is typed,
/// and rules and code blocks when return is typed after their lines
extension CardTextView {

    private enum InlineStyle {
        case bold, italic, code, strikethrough, link
    }

    /// the inline Markdown which ends with the character just typed, checked in order, the text between
    /// a pair of delimiters can't start or end with a space, or contain the delimiter
    private static let inlineMarkdown: [(expression: NSRegularExpression, style: InlineStyle)] = ([
        (#"(?<![*\\])\*\*([^*\s](?:[^*]*[^*\s])?)\*\*$"#, .bold),
        (#"(?<![\w\\])__([^_\s](?:[^_]*[^_\s])?)__$"#, .bold),
        (#"(?<![*\\])\*([^*\s](?:[^*]*[^*\s])?)\*$"#, .italic),
        (#"(?<![\w\\])_([^_\s](?:[^_]*[^_\s])?)_$"#, .italic),
        (#"(?<![~\\])~~([^~\s](?:[^~]*[^~\s])?)~~$"#, .strikethrough),
        (#"(?<![`\\])`([^`]+)`$"#, .code),
        (#"(?<![!\\])\[([^\]]+)\]\(([^()\s]+)\)$"#, .link),
    ] as [(pattern: String, style: InlineStyle)]).map { (try! NSRegularExpression(pattern: $0.pattern), $0.style) }

    /// the prefixes of blocks, typed at the start of a paragraph and followed by a space
    private static let headingPrefix = try! NSRegularExpression(pattern: #"^(#{1,6}) $"#)
    private static let bulletPrefix = try! NSRegularExpression(pattern: #"^[-*+] $"#)
    private static let numberPrefix = try! NSRegularExpression(pattern: #"^\d{1,9}[.)] $"#)
    private static let quotePrefix = try! NSRegularExpression(pattern: #"^> $"#)

    /// the lines which are blocks, followed by a return, `—-` is `---` after smart dashes
    private static let ruleLine = try! NSRegularExpression(pattern: #"^(?:-{3,}|—-+|\*{3,}|_{3,})$"#)
    private static let fenceLine = try! NSRegularExpression(pattern: #"^```([\w+#.-]*)$"#)

    /// convert the Markdown ending with the
    /// @param text the user just typed
    func typed(_ text: String) {
        if text == "\n" {
            if !(convertsTypedMarkdown && convertTypedLine()) {
                headingEnded()
            }
            return
        }
        guard convertsTypedMarkdown, selection.length == 0, let last = text.last else { return }
        if last == " " {
            convertTypedPrefix()
        }
        else if "*_~`)".contains(last) {
            convertTypedInline()
        }
    }

    // MARK: - Paragraphs

    /// the range of the text of the paragraph at the
    /// @param location provided, after its list marker and without its terminator
    private func paragraphText(at location: Int) -> (text: NSRange, enclosing: NSRange) {
        let string = storage.string as NSString
        var start = 0, end = 0, contentsEnd = 0
        string.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: min(location, string.length), length: 0))
        var text = NSRange(location: start, length: contentsEnd - start)
        var marker = NSRange()
        if text.length > 0, storage.attribute(.cardListMarker, at: start, longestEffectiveRange: &marker, in: text) != nil {
            text = NSRange(location: NSMaxRange(marker), length: contentsEnd - NSMaxRange(marker))
        }
        return (text, NSRange(location: start, length: end - start))
    }

    private func matches(_ expression: NSRegularExpression, _ string: String) -> NSTextCheckingResult? {
        expression.firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length))
    }

    /// remove the
    /// @param range of the text, keeping the selection where it was in the text which is left
    private func remove(_ range: NSRange) {
        let selected = selection
        edit(range) { storage in
            storage.deleteCharacters(in: range)
        }
        selection = Self.map(selected, through: [(range, 0)], length: storage.length)
    }

    // MARK: - Blocks

    /// `# `, `- `, `1. ` or `> ` typed at the start of a paragraph makes it a heading, list item or quote
    private func convertTypedPrefix() {
        let location = selection.location
        let paragraph = paragraphText(at: location)
        guard block(at: paragraph.enclosing.location) == .paragraph, paragraph.text.location < location else { return }
        let prefixRange = NSRange(location: paragraph.text.location, length: location - paragraph.text.location)
        let prefix = (storage.string as NSString).substring(with: prefixRange)
        let block: CardBlock
        if let heading = matches(Self.headingPrefix, prefix) {
            block = .heading(heading.range(at: 1).length)
        }
        else if matches(Self.bulletPrefix, prefix) != nil {
            block = .listItem(ordered: false, depth: 0)
        }
        else if matches(Self.numberPrefix, prefix) != nil {
            block = .listItem(ordered: true, depth: 0)
        }
        else if matches(Self.quotePrefix, prefix) != nil {
            block = .quote
        }
        else {
            return
        }
        remove(prefixRange)
        setBlock(block)
    }

    /// return typed after a line of `---` makes it a rule, after ```` ``` ```` starts or ends a code block,
    /// and after an empty list item ends the list
    /// @returns true if the line was converted
    private func convertTypedLine() -> Bool {
        let location = selection.location
        let current = paragraphText(at: location)
        guard selection.length == 0, current.text.location == location, current.enclosing.location > 0 else { return false }
        let previous = paragraphText(at: current.enclosing.location - 1)
        let line = (storage.string as NSString).substring(with: previous.text)

        switch block(at: previous.enclosing.location) {
        case .paragraph:
            if let fence = matches(Self.fenceLine, line) {
                let language = (line as NSString).substring(with: fence.range(at: 1))
                remove(previous.enclosing)
                setBlock(.codeBlock(language: language.isEmpty ? nil : language))
                return true
            }
            if matches(Self.ruleLine, line) != nil {
                let rule = NSMutableAttributedString()
                rule.appendAttachment(CardRuleAttachment(), fontSize: fontSize, paragraph: topStyle)
                let selected = selection
                edit(previous.text) { storage in
                    storage.replaceCharacters(in: previous.text, with: rule)
                }
                selection = Self.map(selected, through: [(previous.text, rule.length)], length: storage.length)
                return true
            }
        case .codeBlock:
            if line == "```" {
                remove(previous.enclosing)
                setBlock(.paragraph)
                return true
            }
        case .listItem:
            if previous.text.length == 0, current.text.length == 0 {
                remove(previous.enclosing)
                setBlock(.paragraph)
                return true
            }
        default:
            break
        }
        return false
    }

    // MARK: - Inline Styles

    /// the closing delimiter of `**bold**`, `*italic*`, `` `code` ``, `~~strikethrough~~` or `[a link](url)`,
    /// typed after the rest of it, styles its text and removes its delimiters
    private func convertTypedInline() {
        let location = selection.location
        let paragraph = paragraphText(at: location)
        guard paragraph.text.location < location else { return }
        if case .codeBlock = block(at: paragraph.enclosing.location) { return }

        let typedRange = NSRange(location: paragraph.text.location, length: location - paragraph.text.location)
        let typed = (storage.string as NSString).substring(with: typedRange)
        for (expression, style) in Self.inlineMarkdown {
            guard let match = matches(expression, typed) else { continue }
            let before = (typed as NSString).substring(to: match.range.location)
            if style != .code, before.filter({ $0 == "`" }).count % 2 == 1 { return } // inside code which hasn't ended yet
            let range = NSRange(location: typedRange.location + match.range.location, length: match.range.length)
            let textRange = NSRange(location: typedRange.location + match.range(at: 1).location, length: match.range(at: 1).length)
            if (storage.attribute(.font, at: range.location, effectiveRange: nil) as? ILFont)?.isMonospace == true { return }

            let plain = storage.attributes(at: range.location, effectiveRange: nil)
            let text = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: textRange))
            let whole = NSRange(location: 0, length: text.length)
            switch style {
            case .bold, .italic, .code:
                text.enumerateAttribute(.font, in: whole) { font, runRange, _ in
                    let font = font as? ILFont ?? .cardFont(size: fontSize)
                    let styled = switch style {
                    case .bold: font.withTraits(bold: true)
                    case .italic: font.withTraits(italic: true)
                    default: font.monospaced(true)
                    }
                    text.addAttribute(.font, value: styled, range: runRange)
                }
            case .strikethrough:
                text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: whole)
            case .link:
                let target = (typed as NSString).substring(with: match.range(at: 2))
                guard let url = URL(string: target, relativeTo: baseURL) else { return }
                text.addAttribute(.link, value: url, range: whole)
            }
            replace(range, with: text)
            typingAttributes = plain // what's typed next isn't styled
            return
        }
    }
}
