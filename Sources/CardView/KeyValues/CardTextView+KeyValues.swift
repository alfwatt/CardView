import Foundation
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Labeled key: value lines, formatted or edited as a `KeyValueFormatter` or `KeyValueEditor` describes their keys
public extension CardTextView {

    /// append an
    /// @param attachment in the card's text style, e.g. an editor made for a line of the app's own
    @discardableResult
    func appendAttachment(_ attachment: NSTextAttachment) -> NSAttributedString {
        storage.appendAttachment(attachment, fontSize: fontSize, paragraph: topStyle)
    }

    /// append a
    /// @param key and its
    /// @param value to the card, labeled and formatted as the
    /// @param labels describe the key, after the
    /// @param prefix and with the
    /// @param separator provided between them, followed by a newline. Nothing is appended if there's no value
    @discardableResult
    func appendKeyValue(_ key: String, value: Any?, labels: KeyValueFormatter, prefix: String = "\t",
                        separator: String = "\t") -> NSAttributedString? {
        guard let value else { return nil }
        let start = storage.length
        append(prefix)
        append(labels.label(forKey: key), style: .strong)
        append(separator)
        appendAttributed(labels.formatted(value, forKey: key, attributes: attributes(.text)))
        appendNewline()
        return storage.attributedSubstring(from: NSRange(location: start, length: storage.length - start))
    }

    /// append a
    /// @param key and an editor of its
    /// @param value to the card, labeled as the
    /// @param editors describe the key, after the
    /// @param prefix and with the
    /// @param separator provided between them, followed by a newline. The editor calls
    /// @param onChange with each new value
    /// @returns the editor, nil if the editors describe none for the key and the value is formatted instead
    @discardableResult
    func appendEditor(_ key: String, value: Any?, editors: KeyValueEditor, prefix: String = "\t", separator: String = "\t",
                      onChange: @escaping @MainActor (Any?) -> Void) -> CardEditorAttachment? {
        guard let editor = editors.editor(forKey: key, value: value, onChange: onChange) else {
            appendKeyValue(key, value: value, labels: editors, prefix: prefix, separator: separator)
            return nil
        }
        append(prefix)
        append(editors.label(forKey: key), style: .strong)
        append(separator)
        appendAttachment(editor)
        appendNewline()
        return editor
    }
}
