import Foundation
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// A `key⇥value` line of a card's text, read back from the text as it's been edited
public struct CardKeyValueLine: Equatable, Sendable {
    public let key: String
    /// the value, with its line breaks as newlines
    public let value: String
    /// the paragraph, without its terminator
    public let range: NSRange
    public let keyRange: NSRange
    public let valueRange: NSRange
}

/// Keys and values as lines of editable text, `⇥key⇥value`, so they're selected, copied and pasted as text,
/// and read back by their structure, not their attributes, which typing and pasting don't keep
public enum CardKeyValueText {
    /// LINE SEPARATOR U+2028, a line break in a value which keeps it in its paragraph
    public static let lineBreak = "\u{2028}"

    /// @returns the line of the
    /// @param key and
    /// @param value provided, with the value's newlines as line breaks, without a paragraph terminator
    public static func line(key: String, value: String) -> String {
        "\t" + key + "\t" + lineBroken(value)
    }

    /// @returns the
    /// @param value provided with its newlines as line breaks
    public static func lineBroken(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: lineBreak).replacingOccurrences(of: "\n", with: lineBreak)
    }

    /// @returns the
    /// @param text provided as plain text, without attachment characters and with line breaks as newlines, e.g. to copy it
    public static func plainText(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FFFC}", with: "").replacingOccurrences(of: lineBreak, with: "\n")
    }

    /// @returns the key/value lines of the
    /// @param text in the
    /// @param range provided: each paragraph is `⇥key⇥value`, the leading tab is optional, a line without a tab is
    /// `key: value`, or a key without a value. Empty and read-only paragraphs are skipped
    public static func lines(in text: NSAttributedString, range: NSRange) -> [CardKeyValueLine] {
        let string = text.string as NSString
        var lines: [CardKeyValueLine] = []
        string.enumerateSubstrings(in: range, options: [.byParagraphs, .substringNotRequired]) { _, paragraph, _, _ in
            guard paragraph.length > 0, text.attribute(.cardReadOnly, at: paragraph.location, effectiveRange: nil) == nil,
                  let line = line(in: string, paragraph: paragraph) else { return }
            lines.append(line)
        }
        return lines
    }

    /// the key/value line of the
    /// @param paragraph of the
    /// @param string provided, nil if it's only whitespace
    static func line(in string: NSString, paragraph: NSRange) -> CardKeyValueLine? {
        var start = paragraph.location
        if string.character(at: start) == 9 { // the key column's tab
            start += 1
        }
        let rest = NSRange(location: start, length: NSMaxRange(paragraph) - start)
        var keyRange = rest
        var valueRange = NSRange(location: NSMaxRange(paragraph), length: 0)
        let tab = string.range(of: "\t", range: rest)
        let colon = string.range(of: ": ", range: rest)
        if tab.location != NSNotFound {
            keyRange = NSRange(location: start, length: tab.location - start)
            valueRange = NSRange(location: NSMaxRange(tab), length: NSMaxRange(paragraph) - NSMaxRange(tab))
        }
        else if colon.location != NSNotFound {
            keyRange = NSRange(location: start, length: colon.location - start)
            valueRange = NSRange(location: NSMaxRange(colon), length: NSMaxRange(paragraph) - NSMaxRange(colon))
        }
        let key = string.substring(with: keyRange).trimmingCharacters(in: .whitespaces)
        let value = string.substring(with: valueRange).replacingOccurrences(of: lineBreak, with: "\n")
        guard !key.isEmpty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return CardKeyValueLine(key: key, value: value, range: paragraph, keyRange: keyRange, valueRange: valueRange)
    }
}

// MARK: -

/// Editable key/value lines in a card
public extension CardTextView {

    /// append a line of the
    /// @param key and its
    /// @param value as text, the key as its label from the
    /// @param labels provided, in the card's columns, followed by a newline, text which can't be edited if it's
    /// @param readOnly, e.g. links the app changes itself
    @discardableResult
    func appendKeyValueLine(_ key: String, value: String, labels: KeyValueFormatter, readOnly: Bool = false) -> NSAttributedString {
        let start = storage.length
        append("\t")
        append(labels.label(forKey: key), style: .strong)
        append("\t")
        append(CardKeyValueText.lineBroken(value))
        appendNewline()
        let range = NSRange(location: start, length: storage.length - start)
        if readOnly {
            storage.addAttribute(.cardReadOnly, value: true, range: range)
        }
        else {
            styleKeyValueLines(in: range)
        }
        return storage.attributedSubstring(from: range)
    }

    /// style the key/value lines in the
    /// @param range provided after they've been edited or pasted: in the
    /// @param paragraph style provided or the card's top style, keys strong, values plain text and links if they're URLs,
    /// e.g. `lit:abf06135`. Only the attributes change, never the characters, read-only lines are left as they are
    func styleKeyValueLines(in range: NSRange, paragraph: NSParagraphStyle? = nil) {
        let storage = storage
        let text = storage.string as NSString
        let keyAttributes = attributes(.strong, paragraph: paragraph)
        let valueAttributes = attributes(.text, paragraph: paragraph)
        storage.beginEditing()
        text.enumerateSubstrings(in: range, options: .byParagraphs) { _, paragraph, enclosing, _ in
            guard enclosing.length > 0, storage.attribute(.cardReadOnly, at: enclosing.location, effectiveRange: nil) == nil else { return }
            storage.setAttributes(valueAttributes, range: enclosing)
            guard paragraph.length > 0, let line = CardKeyValueText.line(in: text, paragraph: paragraph) else { return }
            storage.setAttributes(keyAttributes, range: line.keyRange)
            if let url = CardLinkFormatter.url(line.value) {
                storage.addAttribute(.link, value: url, range: line.valueRange)
            }
        }
        storage.endEditing()
    }

    /// @returns true if replacing the
    /// @param range of the card's text with the
    /// @param replacement provided keeps its read-only text and attachments, e.g. a rule, as they are,
    /// for apps to call from their text view's delegate before an edit
    func allowsKeyValueEdit(in range: NSRange, replacement: String) -> Bool {
        let length = storage.length
        func readOnly(_ index: Int) -> Bool {
            index >= 0 && index < length && storage.attribute(.cardReadOnly, at: index, effectiveRange: nil) != nil
        }
        guard range.length > 0 else {
            return !readOnly(range.location) // not into, or before, a read-only line
        }
        var allowed = true
        storage.enumerateAttributes(in: range) { attributes, _, stop in
            if attributes[.cardReadOnly] != nil || attributes[.attachment] != nil {
                allowed = false
                stop.pointee = true
            }
        }
        // nor joining a read-only line to the one before it
        if allowed, readOnly(NSMaxRange(range)), (storage.string as NSString).character(at: NSMaxRange(range) - 1) == 10 {
            allowed = false
        }
        return allowed
    }
}
