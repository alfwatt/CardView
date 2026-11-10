import Foundation
import ILFoundation
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// The base class of the card's formatters, with the attributes they style their units in
@objc(CardFormatter)
@objcMembers
open class CardFormatter: Formatter, @unchecked Sendable {

    /// the scale of units' fonts, relative to the value's
    static let unitScale: CGFloat = 0.9

    /// String attributes for units, based on the attributes provided
    public static func unitsAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var units = attributes
        let font = attributes[.font] as? ILFont ?? .cardFont(size: ILFont.cardBodySize)
        units[.font] = ILFont(name: font.fontName, size: font.pointSize * unitScale) ?? font
        units[.foregroundColor] = CardColor.secondary
        return units
    }

    /// String attributes for cardinal units, based on the attributes provided
    public static func cardinalAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var cardinal = attributes
        cardinal[.foregroundColor] = CardColor.secondary
        return cardinal
    }

    /// String attributes for monospaced text, based on the attributes provided
    public static func monospaceAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var monospace = attributes
        let font = attributes[.font] as? ILFont ?? .cardFont(size: ILFont.cardBodySize)
        monospace[.font] = ILFont.cardFont(size: font.pointSize, monospace: true)
        return monospace
    }

    /// @returns the
    /// @param value formatted with the
    /// @param formatter provided, as an attributed string if it makes them, with the
    /// @param attributes provided
    public static func attributedString(_ value: Any, formatter: Formatter, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        if let attributed = formatter.attributedString(for: value, withDefaultAttributes: attributes) {
            return attributed
        }
        return NSAttributedString(string: formatter.string(for: value) ?? String(describing: value), attributes: attributes)
    }

    // MARK: - Formatter

    open override func string(for obj: Any?) -> String? {
        obj.map { String(describing: $0) }
    }

    open override func attributedString(for obj: Any, withDefaultAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString? {
        NSAttributedString(string: string(for: obj) ?? "", attributes: attrs)
    }

    open override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String,
                                      errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        false // the card's formatters only format
    }
}

// MARK: -

/// formats arrays into lists, with a separator between the items
@objc(CardArrayFormatter)
@objcMembers
open class CardArrayFormatter: CardFormatter, @unchecked Sendable {
    /// String to use between each item in the array
    public var separator = ", "
    /// Formatter to use for each item in the array
    public var itemFormatter: Formatter?

    open override func string(for obj: Any?) -> String? {
        guard let obj else { return nil }
        guard let array = obj as? [Any] else {
            return itemFormatter?.string(for: obj) ?? String(describing: obj)
        }
        return array.map { itemFormatter?.string(for: $0) ?? String(describing: $0) }.joined(separator: separator)
    }

    open override func attributedString(for obj: Any, withDefaultAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString? {
        let attributes = attrs ?? [:]
        guard let array = obj as? [Any] else {
            return itemFormatter.map { CardFormatter.attributedString(obj, formatter: $0, attributes: attributes) }
                ?? NSAttributedString(string: String(describing: obj), attributes: attributes)
        }
        let list = NSMutableAttributedString()
        for (index, item) in array.enumerated() {
            if index > 0 {
                list.append(NSAttributedString(string: separator, attributes: CardFormatter.unitsAttributes(attributes)))
            }
            list.append(itemFormatter.map { CardFormatter.attributedString(item, formatter: $0, attributes: attributes) }
                ?? NSAttributedString(string: String(describing: item), attributes: attributes))
        }
        return list
    }
}

// MARK: -

/// formats data values into string with byte count: "420 Bytes", or a hex dump
@objc(CardDataFormatter)
@objcMembers
open class CardDataFormatter: CardFormatter, @unchecked Sendable {
    /// true to have the formatter display data as hex values, false to display byte counts
    public var formatAsHex = false
    /// Number of bytes for each line if formatAsHex is true
    public var hexLineBytes = 16
    /// Maximum number of bytes to show as hex
    public var hexMaxBytes = Int.max
    /// Formatter for the bytes representation
    public var bytesFormatter: Formatter = CardBytesFormatter()

    /// the visible symbols of control and separator characters
    static let symbols: [(Character, Character)] = [
        ("\u{000A}", "\u{240A}"), // LINE FEED → ␊
        ("\u{000B}", "\u{240B}"), // VERTICAL TAB → ␋
        ("\u{000C}", "\u{240C}"), // FORM FEED → ␌
        ("\u{000D}", "\u{240D}"), // CARRIAGE RETURN → ␍
        ("\u{0085}", "\u{00B7}"), // NEXT LINE → ·
        ("\u{2028}", "\u{00B7}"), // LINE SEPARATOR → ·
        ("\u{2029}", "\u{00B7}"), // PARAGRAPH SEPARATOR → ·
        ("\u{0009}", "\u{2409}"), // TAB → ␉
    ]

    /// @returns the
    /// @param lines provided with their control characters replaced with visible symbols
    public static func replaceSpecialCharactersWithSymbols(_ lines: String) -> String {
        String(lines.map { character in symbols.first { $0.0 == character }?.1 ?? character })
    }

    open override func string(for obj: Any?) -> String? {
        obj.flatMap { attributedString(for: $0, withDefaultAttributes: [:])?.string }
    }

    open override func attributedString(for obj: Any, withDefaultAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString? {
        let attributes = attrs ?? [:]
        guard let data = obj as? Data else {
            return NSAttributedString(string: String(describing: obj), attributes: attributes)
        }
        guard formatAsHex, !data.isEmpty, data.count < hexMaxBytes else {
            return CardFormatter.attributedString(data.count, formatter: bytesFormatter, attributes: attributes)
        }

        let monospace = CardFormatter.monospaceAttributes(attributes)
        let units = CardFormatter.unitsAttributes(monospace)
        let dump = NSMutableAttributedString()
        var index = data.startIndex
        while index < data.endIndex {
            if index > data.startIndex {
                dump.append(NSAttributedString(string: "\n", attributes: attributes))
            }
            let line = data[index ..< min(index + hexLineBytes, data.endIndex)]
            let hex = Data(line).hexString.padding(toLength: hexLineBytes * 2, withPad: " ", startingAt: 0)
            dump.append(NSAttributedString(string: "0x", attributes: units))
            dump.append(NSAttributedString(string: hex, attributes: monospace))
            let decoded = String(data: Data(line), encoding: .utf8).map(Self.replaceSpecialCharactersWithSymbols)
                ?? String(repeating: "\u{00B7}", count: line.count)
            dump.append(NSAttributedString(string: " " + decoded, attributes: units))
            index = line.endIndex
        }
        return dump
    }
}

// MARK: -

/// formats UTF data of any encoding into a string
@objc(CardStringDataFormatter)
@objcMembers
open class CardStringDataFormatter: CardFormatter, @unchecked Sendable {
    open override func string(for obj: Any?) -> String? {
        guard let data = obj as? Data else { return obj.map { String(describing: $0) } }
        return String(utfData: data)
    }
}

// MARK: -

/// formats URLs as clickable links
@objc(CardURLFormatter)
@objcMembers
open class CardURLFormatter: CardFormatter, @unchecked Sendable {
    /// URL Link color, the default link color if nil
    public var linkColor: ILColor?

    public init(linkColor: ILColor? = nil) {
        self.linkColor = linkColor
        super.init()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    open override func string(for obj: Any?) -> String? {
        (obj as? URL)?.absoluteString ?? obj.map { String(describing: $0) }
    }

    open override func attributedString(for obj: Any, withDefaultAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString? {
        guard let url = obj as? URL else { return super.attributedString(for: obj, withDefaultAttributes: attrs) }
        var attributes = attrs ?? [:]
        attributes[.link] = url
        attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        if let linkColor {
            attributes[.foregroundColor] = linkColor
        }
        return NSAttributedString(string: url.absoluteString, attributes: attributes)
    }
}

// MARK: -

/// formats property list data as the description of the property list
@objc(CardPListDataFormatter)
@objcMembers
open class CardPListDataFormatter: CardFormatter, @unchecked Sendable {
    open override func string(for obj: Any?) -> String? {
        guard let data = obj as? Data else { return obj.map { String(describing: $0) } }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)).map { String(describing: $0) }
    }
}

// MARK: -

/// formats a property list as pretty printed JSON
@objc(CardJSONObjectFormatter)
@objcMembers
open class CardJSONObjectFormatter: CardFormatter, @unchecked Sendable {
    open override func string(for obj: Any?) -> String? {
        guard let obj, JSONSerialization.isValidJSONObject(obj),
              let json = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: json, encoding: .utf8)
    }
}

// MARK: -

/// formats a property list as Markdown: dictionaries as bullet lists of `**key**: value`, arrays as numbered lists
/// https://daringfireball.net/projects/markdown/syntax.text
@objc(CardMarkdownFormatter)
@objcMembers
open class CardMarkdownFormatter: CardFormatter, @unchecked Sendable {

    func markdown(_ obj: Any, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        switch obj {
        case let string as String:
            return CardMarkdownWriter.escaped(string)
        case let number as NSNumber:
            return number.stringValue
        case let array as [Any]:
            return array.enumerated().map { index, item in
                indent + "\(index + 1). " + nested(item, depth: depth)
            }.joined(separator: "\n")
        case let dictionary as [String: Any]:
            return dictionary.keys.sorted().map { key in
                indent + "- **\(CardMarkdownWriter.escaped(key))**: " + nested(dictionary[key]!, depth: depth)
            }.joined(separator: "\n")
        default:
            return CardMarkdownWriter.escaped(String(describing: obj))
        }
    }

    /// a list item's value, nested lists go deeper on the lines below
    private func nested(_ value: Any, depth: Int) -> String {
        if value is [Any] || value is [String: Any] {
            return "\n" + markdown(value, depth: depth + 1)
        }
        return markdown(value, depth: depth)
    }

    open override func string(for obj: Any?) -> String? {
        obj.map { markdown($0, depth: 0) }
    }
}

// MARK: - Date Formatters

/// formats dates into the user's preferred medium date and time format
@objc(CardDateFormatter)
@objcMembers
open class CardDateFormatter: DateFormatter, @unchecked Sendable {

    /// the formatter for the user's current locale
    public static let local: CardDateFormatter = {
        let formatter = CardDateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    open override func attributedString(for obj: Any, withDefaultAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString? {
        NSAttributedString(string: string(for: obj) ?? "", attributes: attrs)
    }
}

// MARK: - Units Formatter

/// formats number values with units in grey text
@objc(CardUnitsFormatter)
@objcMembers
open class CardUnitsFormatter: NumberFormatter, @unchecked Sendable {
    /// unit name string to add using the unit style after the number
    public var units: String?
    /// prefix unit name to add before the number using the unit style
    public var prefix: String?

    /// NARROW NO-BREAK SPACE U+202F, between the number and its units
    static let noBreakSpace = "\u{202F}"

    public override init() {
        super.init()
        numberStyle = .decimal
        minimumIntegerDigits = 1
        maximumIntegerDigits = 99
        minimumFractionDigits = 1
        maximumFractionDigits = 2
        usesGroupingSeparator = true
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// the value and units to display for the
    /// @param number provided, subclasses scale the value and choose the units
    open func scaled(_ number: NSNumber) -> (value: NSNumber, units: String?) {
        (number, units)
    }

    /// @returns the
    /// @param value provided as a string, without a fraction if it's an integer, e.g. "72 dpi" rather than "72.0 dpi"
    open func valueString(_ value: NSNumber) -> String {
        guard !CFNumberIsFloatType(value) else { return super.string(for: value) ?? "" }
        let digits = minimumFractionDigits
        minimumFractionDigits = 0
        defer { minimumFractionDigits = digits }
        return super.string(for: value) ?? ""
    }

    open override func string(for obj: Any?) -> String? {
        guard let number = obj as? NSNumber else { return nil }
        let (value, units) = scaled(number)
        var formatted = ""
        if let prefix {
            formatted += prefix + Self.noBreakSpace
        }
        formatted += valueString(value)
        if let units {
            formatted += Self.noBreakSpace + units
        }
        return formatted
    }

    open override func attributedString(for obj: Any, withDefaultAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString? {
        guard let number = obj as? NSNumber else { return nil }
        let attributes = attrs ?? [:]
        let unitsAttributes = CardFormatter.unitsAttributes(CardFormatter.monospaceAttributes(attributes))
        let (value, units) = scaled(number)
        let formatted = NSMutableAttributedString()
        if let prefix {
            formatted.append(NSAttributedString(string: prefix, attributes: unitsAttributes))
            formatted.append(NSAttributedString(string: Self.noBreakSpace, attributes: attributes))
        }
        formatted.append(NSAttributedString(string: valueString(value), attributes: attributes))
        if let units {
            formatted.append(NSAttributedString(string: Self.noBreakSpace, attributes: attributes))
            formatted.append(NSAttributedString(string: units, attributes: unitsAttributes))
        }
        return formatted
    }
}

// MARK: - Number Formatters

/// formats numeric values into boolean value strings: "Yes" or "No"
@objc(CardBooleanFormatter)
@objcMembers
open class CardBooleanFormatter: NumberFormatter, @unchecked Sendable {
    open override func string(for obj: Any?) -> String? {
        guard let number = obj as? NSNumber else { return "-" }
        return number.boolValue
            ? String(localized: "Yes", bundle: .cardView)
            : String(localized: "No", bundle: .cardView)
    }

    open override func attributedString(for obj: Any, withDefaultAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString? {
        NSAttributedString(string: string(for: obj) ?? "-", attributes: attrs)
    }
}

// MARK: -

/// formats numbers as byte sizes, in decimal (SI) units: https://en.wikipedia.org/wiki/Kilobyte
@objc(CardBytesFormatter)
@objcMembers
open class CardBytesFormatter: CardUnitsFormatter, @unchecked Sendable {

    static let scales: [(size: Double, units: String.LocalizationValue)] = [
        (1e18, "EB"), (1e15, "PB"), (1e12, "TB"), (1e9, "GB"), (1e6, "MB"), (1e3, "kB")
    ]

    open override func scaled(_ number: NSNumber) -> (value: NSNumber, units: String?) {
        let bytes = number.doubleValue
        for scale in Self.scales where bytes >= scale.size {
            return (NSNumber(value: bytes / scale.size), String(localized: scale.units, bundle: .cardView))
        }
        return (number, String(localized: "Bytes", bundle: .cardView))
    }
}

// MARK: -

/// formats numbers as a fraction, using the continued fraction method: https://en.wikipedia.org/wiki/Continued_fraction
@objc(CardFractionFormatter)
@objcMembers
open class CardFractionFormatter: CardUnitsFormatter, @unchecked Sendable {

    /// @returns the numerator and denominator of the fraction closest to the
    /// @param value provided, with a denominator no larger than the
    /// @param accuracy
    static func fraction(_ value: Double, accuracy: Double = 1.0e+4) -> (numerator: Int, denominator: Int) {
        // walk the continued fraction terms, accumulating the numerator/denominator
        // convergents directly (h/k recurrence), `accuracy` bounds how large the denominator is allowed to grow.
        var remainder = value
        let whole = floor(remainder)
        remainder -= whole

        var (h1, h2) = (1, Int(whole)) // numerator convergents
        var (k1, k2) = (0, 1) // denominator convergents
        var termsLeft = 64 // hard cap on iterations
        while remainder > 0, termsLeft > 0 {
            termsLeft -= 1
            remainder = 1 / remainder
            let term = floor(remainder)
            let h = Int(term) * h2 + h1
            let k = Int(term) * k2 + k1
            if Double(k) > accuracy {
                break // adding this term would exceed the requested denominator bound
            }
            (h1, h2) = (h2, h)
            (k1, k2) = (k2, k)
            remainder -= term
        }
        return (h2, k2)
    }

    /// FRACTION SLASH U+2044
    static let fractionSlash = "\u{2044}"

    /// the value as a fraction, or a whole number if it is one, e.g. "1⁄250" or "2"
    open override func valueString(_ value: NSNumber) -> String {
        let (numerator, denominator) = Self.fraction(value.doubleValue)
        return denominator == 1 ? "\(numerator)" : "\(numerator)\(Self.fractionSlash)\(denominator)"
    }

    open override func string(for obj: Any?) -> String? {
        guard obj is NSNumber else { return obj.map { String(describing: $0) } }
        return super.string(for: obj)
    }
}

// MARK: -

/// formats a time interval or duration as a timecode
@objc(CardTimecodeFormatter)
@objcMembers
open class CardTimecodeFormatter: NumberFormatter, @unchecked Sendable {
    /// display seconds as decimal value if true, frames of frameInterval if false
    public var decimalSeconds = true
    /// display unit separators 00h 00m 00s 00f if true, colon separators 00:00:00:00 if false
    public var unitSeparators = true
    /// interval for frame calculations, 24 FPS if zero
    public var frameInterval: Double = 0

    struct Timecode: Equatable {
        var hours: Int
        var minutes: Int
        var seconds: Int
        var frames: Int
        var decimalSeconds: Double
    }

    static func timecode(_ totalSeconds: Double, frameInterval: Double) -> Timecode {
        let integralSeconds = totalSeconds.rounded(.towardZero)
        let fractionalSeconds = totalSeconds - integralSeconds
        let hours = Int(floor(integralSeconds / 3600))
        let minutes = Int(floor((integralSeconds - Double(hours * 3600)) / 60))
        let interval = frameInterval == 0 ? (1.0 / 24) : frameInterval
        return Timecode(hours: hours, minutes: minutes,
                        seconds: Int(integralSeconds) - (hours * 3600) - (minutes * 60),
                        frames: Int(floor(fractionalSeconds / interval)),
                        decimalSeconds: totalSeconds - Double(hours * 3600) - Double(minutes * 60))
    }

    open override func string(for obj: Any?) -> String? {
        attributedString(for: obj as Any, withDefaultAttributes: [:])?.string
    }

    open override func attributedString(for obj: Any, withDefaultAttributes attrs: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString? {
        let attributes = attrs ?? [:]
        guard let number = obj as? NSNumber else {
            return NSAttributedString(string: String(describing: obj), attributes: attributes)
        }
        let separatorAttributes = unitSeparators
            ? CardFormatter.unitsAttributes(CardFormatter.monospaceAttributes(attributes))
            : CardFormatter.cardinalAttributes(attributes)
        let timecode = Self.timecode(number.doubleValue, frameInterval: frameInterval)
        let colon = String(localized: ":", bundle: .cardView, comment: "timecode separator")
        let string = NSMutableAttributedString()
        func append(_ value: String, _ separator: String?) {
            string.append(NSAttributedString(string: value, attributes: attributes))
            if let separator {
                string.append(NSAttributedString(string: separator, attributes: separatorAttributes))
            }
        }
        append(String(format: "%02ld", timecode.hours), unitSeparators ? String(localized: "h ", bundle: .cardView, comment: "hours timecode units") : colon)
        append(String(format: "%02ld", timecode.minutes), unitSeparators ? String(localized: "m ", bundle: .cardView, comment: "minutes timecode units") : colon)
        let seconds = String(localized: "s ", bundle: .cardView, comment: "seconds timecode units")
        if decimalSeconds {
            append(String(format: "%2.4f", timecode.decimalSeconds), unitSeparators ? seconds.trimmingCharacters(in: .whitespaces) : nil)
        }
        else {
            append(String(format: "%02ld", timecode.seconds), unitSeparators ? seconds : colon)
            append(String(format: "%02ld", timecode.frames), unitSeparators ? "f" : nil)
        }
        return string
    }
}

// MARK: -

extension Bundle {
    /// the bundle of CardView's localized strings
    static let cardView = Bundle(for: CardFormatter.self)
}

// MARK: - Value Transformer

/// A `ValueTransformer` which formats values with a `Formatter`, so formatters can be used by name in Interface Builder
@objc(CardFormattingTransformer)
@objcMembers
open class CardFormattingTransformer: ValueTransformer, @unchecked Sendable {
    public var formatter: Formatter?

    /// wrap the
    /// @param formatter in a transformer and register it with the
    /// @param name provided
    public static func register(_ formatter: Formatter, name: NSValueTransformerName) {
        let transformer = CardFormattingTransformer()
        transformer.formatter = formatter
        ValueTransformer.setValueTransformer(transformer, forName: name)
    }

    open override class func allowsReverseTransformation() -> Bool {
        false
    }

    open override class func transformedValueClass() -> AnyClass {
        NSObject.self // if this needs to be different, subclass and register a new transformer
    }

    open override func transformedValue(_ value: Any?) -> Any? {
        guard let value else { return nil }
        guard let formatter else { return String(describing: value) }
        return formatter.attributedString(for: value, withDefaultAttributes: nil) ?? formatter.string(for: value)
    }
}
