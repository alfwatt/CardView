import Foundation
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// keys of the key/value labels property list, which describes how each property key and its values are shown and edited, e.g.:
/// ```
/// {
///   "key": {
///     "label": "key label",
///     "formatter": "CardUnitsFormatter",
///     "prefix": "value prefix",
///     "units": "value suffix",
///     "symbol": "SF Symbol name",
///     "values": {
///       "value": "value label"
///     },
///     "editor": "menu",
///     "editor/choices": ["value", "other value"]
///   }
/// }
/// ```
public enum CardKeyValueKeys {
    /// the display label for a key
    public static let label = "label"
    /// the class name of the `Formatter` of the key's values, e.g. `CardBytesFormatter`
    public static let formatter = "formatter"
    /// the [String: String] map of value display labels
    public static let values = "values"
    /// prefix string for the value
    public static let prefix = "prefix"
    /// units string (suffix) for the value
    public static let units = "units"
    /// the name of the SF Symbol shown with the key
    public static let symbol = "symbol"
    /// the `CardEditorType` of the key's values, e.g. `menu`
    public static let editor = "editor"
    /// the values an editor offers, in order, the keys of `values` if there are none
    public static let editorChoices = "editor/choices"
}

// MARK: -

/// Labels keys and formats their values, for cards and apps which show key: value data
public protocol KeyValueFormatter {
    /// @returns the display label of the
    /// @param key provided
    func label(forKey key: String) -> String

    /// @returns the name of the SF Symbol shown with the
    /// @param key provided, if it has one
    func symbol(forKey key: String) -> String?

    /// @returns the formatter of the values of the
    /// @param key provided, nil if the value's class decides how it's formatted
    func formatter(forKey key: String) -> Formatter?
}

public extension KeyValueFormatter {
    /// @returns the
    /// @param value of the
    /// @param key provided, formatted with its formatter or the one registered for the value's class, in the
    /// @param attributes provided, a dash if there's no value
    @MainActor
    func formatted(_ value: Any?, forKey key: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        guard let value, let formatter = formatter(forKey: key) else {
            return CardTextView.formatted(value, attributes: attributes)
        }
        return CardFormatter.attributedString(value, formatter: formatter, attributes: attributes)
    }
}

// MARK: -

/// Key/value labels loaded from a property list, in the format `CardKeyValueKeys` describes
@objc(CardKeyValueLabels)
@objcMembers
open class CardKeyValueLabels: NSObject, KeyValueFormatter, @unchecked Sendable {
    /// the description of each key, by key
    public let labels: [String: [String: Any]]

    public init(labels: [String: [String: Any]]) {
        self.labels = labels
        super.init()
    }

    /// load the labels from the property list at the
    /// @param url provided, nil if it can't be read
    public convenience init?(contentsOf url: URL) {
        guard let plist = NSDictionary(contentsOf: url) as? [String: [String: Any]] else { return nil }
        self.init(labels: plist)
    }

    /// @returns these labels with the descriptions of the
    /// @param other keys provided merged over them, key by key, e.g. an app's choices for a key
    public func merging(_ other: [String: [String: Any]]) -> CardKeyValueLabels {
        CardKeyValueLabels(labels: labels.merging(other) { mine, theirs in mine.merging(theirs) { $1 } })
    }

    // MARK: - Keys

    /// @returns the
    /// @param key provided as words, without its framework's prefix or suffix, e.g. "kMDItemFSSize" as "FS Size"
    /// or "SubsecTimeOriginal" as "Subsec Time Original". Type identifiers and extended attribute names, which have dots,
    /// and keys with spaces, are already as readable as they are
    public static func readable(_ key: String) -> String {
        guard !key.contains(where: { $0 == "." || $0 == " " }) else { return key }
        var name = key.trimmingCharacters(in: CharacterSet(charactersIn: "{}_"))
        for prefix in ["kMDItem", "kCGImageProperty", "NSURL", "NSFile", "kSecProperty", "kSecOID", "kSec", "kCF", "NS", "k"]
        where name.hasPrefix(prefix) && name.dropFirst(prefix.count).first?.isUppercase == true {
            name.removeFirst(prefix.count)
            break
        }
        if name.hasSuffix("Key"), name.count > 3 {
            name.removeLast(3)
        }
        var words = ""
        let characters = Array(name.replacingOccurrences(of: "_", with: " "))
        for (index, character) in characters.enumerated() {
            if index > 0, character != " ", characters[index - 1] != " " {
                let previous = characters[index - 1]
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                if (character.isUppercase && (previous.isLowercase || previous.isNumber)) // "subsecTime", "35mmFilm"
                    || (character.isUppercase && previous.isUppercase && next?.isLowercase == true) // "DPIWidth"
                    || (character.isNumber && previous.isLowercase) { // "In35mm"
                    words.append(" ")
                }
            }
            words.append(character)
        }
        return words
    }

    // MARK: - KeyValueFormatter

    /// the label of the
    /// @param key provided, or the key made readable if it doesn't have one
    open func label(forKey key: String) -> String {
        labels[key]?[CardKeyValueKeys.label] as? String ?? Self.readable(key)
    }

    open func symbol(forKey key: String) -> String? {
        labels[key]?[CardKeyValueKeys.symbol] as? String
    }

    /// @returns the formatter the labels describe for the values of the
    /// @param key: its value labels, its named formatter, or a units formatter for its prefix and units,
    /// nil if they describe none and the value's class decides how it's formatted
    open func formatter(forKey key: String) -> Formatter? {
        let keyInfo = labels[key]
        var formatter: Formatter?
        if let formatterName = keyInfo?[CardKeyValueKeys.formatter] as? String {
            if let formatterType = NSClassFromString(formatterName) as? Formatter.Type {
                formatter = formatterType.init()
            }
            else {
                NSLog("WARNING no formatter class named: %@", formatterName)
            }
        }
        else if keyInfo?[CardKeyValueKeys.prefix] != nil || keyInfo?[CardKeyValueKeys.units] != nil {
            formatter = CardUnitsFormatter()
        }
        if let formatter {
            configure(formatter, keyInfo: keyInfo)
        }

        if let values = keyInfo?[CardKeyValueKeys.values] as? [String: String] { // enumerated values
            return CardValuesFormatter(values: values, formatter: formatter)
        }
        return formatter
    }

    /// configure the
    /// @param formatter of a key with its
    /// @param keyInfo, the prefix and units of a units formatter, subclasses configure their own formatters
    open func configure(_ formatter: Formatter, keyInfo: [String: Any]?) {
        if let units = formatter as? CardUnitsFormatter {
            units.prefix = keyInfo?[CardKeyValueKeys.prefix] as? String ?? units.prefix
            units.units = keyInfo?[CardKeyValueKeys.units] as? String ?? units.units
        }
    }
}
