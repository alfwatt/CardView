import Foundation

/// The kinds of editor a key's values can have in a card, the `editor` of its key/value labels
public enum CardEditorType: String, CaseIterable, Sendable {
    /// a text field, a combo box if there are choices, the value is a string
    case text
    /// a field of tags, the value is an array of strings
    case tags
    /// a pull down menu of the choices, the value is the chosen one's
    case menu
    /// a check box or switch, the value is a boolean
    case toggle
    /// a radio group of the choices, the value is the chosen one's
    case radio
    /// a button, which reports its value when it's pressed
    case button
    /// a color well, the value is a CSS hex color string, e.g. `#FF8000`
    case color
}

/// One of the values an editor offers, with its label
public struct CardChoice: Hashable, Sendable {
    public let value: String
    public let label: String

    public init(value: String, label: String? = nil) {
        self.value = value
        self.label = label ?? value
    }
}

// MARK: -

/// Edits the values of keys in a card, as well as labeling and formatting them
public protocol KeyValueEditor: KeyValueFormatter {
    /// @returns the type of editor for the values of the
    /// @param key provided, nil if they're only shown
    func editorType(forKey key: String) -> CardEditorType?

    /// @returns the values an editor of the
    /// @param key provided offers, in order
    func choices(forKey key: String) -> [CardChoice]
}

public extension KeyValueEditor {
    /// @returns an editor of the
    /// @param value of the
    /// @param key provided, which calls
    /// @param onChange with each new value, nil if the key has no editor
    @MainActor
    func editor(forKey key: String, value: Any?, onChange: @escaping @MainActor (Any?) -> Void) -> CardEditorAttachment? {
        guard let type = editorType(forKey: key) else { return nil }
        return CardEditorAttachment(key: key, type: type, value: value, choices: choices(forKey: key),
                                    symbol: symbol(forKey: key), onChange: onChange)
    }
}

// MARK: -

extension CardKeyValueLabels: KeyValueEditor {

    public func editorType(forKey key: String) -> CardEditorType? {
        (labels[key]?[CardKeyValueKeys.editor] as? String).flatMap(CardEditorType.init(rawValue:))
    }

    /// the key's `editor/choices`, else the values it has labels for, labeled with them
    public func choices(forKey key: String) -> [CardChoice] {
        let keyInfo = labels[key]
        let values = keyInfo?[CardKeyValueKeys.values] as? [String: String] ?? [:]
        let choices = keyInfo?[CardKeyValueKeys.editorChoices] as? [String]
            ?? values.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return choices.map { CardChoice(value: $0, label: values[$0]) }
    }
}
