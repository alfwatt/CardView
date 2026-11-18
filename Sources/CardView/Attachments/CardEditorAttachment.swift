import Foundation
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// An editor of a key's value in a card: a text field, tags, menu, toggle, radio group, button or color well,
/// it keeps the value as it's edited and calls its `onChange` with each new one
@objc(CardEditorAttachment)
open class CardEditorAttachment: CardAttachment, @unchecked Sendable {
    public let key: String
    public let type: CardEditorType
    /// the values the menus, radio groups and text field completions offer
    public let choices: [CardChoice]
    /// the name of the SF Symbol of a button
    public let symbol: String?
    /// the value as it's been edited
    public private(set) var value: Any?
    let onChange: @MainActor (Any?) -> Void

    /// the editor's control, made the first time it's laid out, so it keeps its focus when the text is laid out again
    private var control: ILView?
#if canImport(AppKit)
    /// the targets of the AppKit controls, which call their actions
    private var trampolines: [ButtonTrampoline] = []
#endif

    public init(key: String, type: CardEditorType, value: Any?, choices: [CardChoice] = [], symbol: String? = nil,
                onChange: @escaping @MainActor (Any?) -> Void) {
        self.key = key
        self.type = type
        self.value = value
        self.choices = choices
        self.symbol = symbol
        self.onChange = onChange
        super.init()
    }

    public required init?(coder: NSCoder) {
        nil
    }

    // MARK: - Values

    /// the value as a string, empty if there's none
    public var stringValue: String {
        switch value {
        case nil: ""
        case let string as String: string
        case let number as NSNumber: number.stringValue
        case let array as [Any]: array.map { "\($0)" }.joined(separator: ", ")
        default: "\(value!)"
        }
    }

    /// the value as a boolean, a number's or a string's like "true" or "yes"
    public var boolValue: Bool {
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return ["1", "true", "yes", "on"].contains(stringValue.lowercased())
    }

    /// the value as tags, an array of strings or a comma separated list of them
    public var tagsValue: [String] {
        (value as? [Any])?.map { "\($0)" } ?? Self.tags(stringValue)
    }

    /// @returns the tags in the comma separated
    /// @param list provided
    static func tags(_ list: String) -> [String] {
        list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// the choices, and the value if it isn't one of them, so it isn't lost
    var shownChoices: [CardChoice] {
        let current = stringValue
        return current.isEmpty || choices.contains { $0.value == current } ? choices : choices + [CardChoice(value: current)]
    }

    /// the editor's value was
    /// @param edited to the value provided, keep it and report it
    @MainActor func changed(_ edited: Any?) {
        value = edited
        onChange(edited)
    }

    // MARK: - CardAttachment

    @MainActor open override func makeView() -> ILView {
        if let control {
            return control
        }
        let made = makeControl()
        control = made
        return made
    }

    /// text and tags fields fill the rest of the line, the other controls are their own size
    @MainActor open override func size(of view: ILView, lineWidth: CGFloat, font: ILFont?) -> CGSize {
        switch type {
        case .text, .tags:
            return CGSize(width: max(lineWidth - 2, 40), height: Self.height(of: view))
        default:
            return CardAttachment.fit(view.cardFittingSize, in: lineWidth)
        }
    }

    /// controls sit on the baseline, centred on the text they'd be too high
    open override func baselineOffset(for size: CGSize, font: ILFont?) -> CGFloat {
        guard let font else { return 0 }
        return ((font.ascender + font.descender - size.height) / 2).rounded()
    }

    // MARK: - Controls

#if canImport(AppKit)
    /// the height of a text control
    @MainActor static func height(of view: ILView) -> CGFloat {
        (view as? NSControl)?.cell?.cellSize.height ?? view.fittingSize.height
    }

    /// call the
    /// @param fire closure when the
    /// @param control provided performs its action
    @MainActor private func target(_ control: NSControl, _ fire: @escaping @MainActor () -> Void) {
        let trampoline = ButtonTrampoline(fire)
        trampolines.append(trampoline)
        control.target = trampoline
        control.action = #selector(ButtonTrampoline.fire)
    }

    @MainActor private func makeControl() -> ILView {
        switch type {
        case .text where !choices.isEmpty:
            let combo = NSComboBox()
            combo.addItems(withObjectValues: choices.map(\.value))
            combo.completes = true
            combo.stringValue = stringValue
            combo.isContinuous = true
            target(combo) { [weak self, weak combo] in
                guard let self, let combo else { return }
                changed(combo.stringValue)
            }
            return combo
        case .text:
            let field = NSTextField(string: stringValue)
            field.isContinuous = true
            target(field) { [weak self, weak field] in
                guard let self, let field else { return }
                changed(field.stringValue)
            }
            return field
        case .tags:
            let tokens = NSTokenField()
            tokens.objectValue = tagsValue
            target(tokens) { [weak self, weak tokens] in
                guard let self, let tokens else { return }
                changed((tokens.objectValue as? [Any])?.map { "\($0)" } ?? Self.tags(tokens.stringValue))
            }
            return tokens
        case .menu:
            let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
            for choice in shownChoices { // added to the menu, the pop up's own addItem removes items with the same title
                let item = NSMenuItem(title: choice.label, action: nil, keyEquivalent: "")
                item.representedObject = choice.value
                popUp.menu?.addItem(item)
            }
            popUp.selectItem(at: shownChoices.firstIndex { $0.value == stringValue } ?? -1)
            target(popUp) { [weak self, weak popUp] in
                guard let self, let popUp else { return }
                changed(popUp.selectedItem?.representedObject as? String)
            }
            popUp.sizeToFit()
            return popUp
        case .toggle:
            let check = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            check.state = boolValue ? .on : .off
            target(check) { [weak self, weak check] in
                guard let self, let check else { return }
                changed(check.state == .on)
            }
            check.sizeToFit()
            return check
        case .radio:
            let group = NSStackView()
            group.orientation = .horizontal
            for choice in shownChoices {
                let radio = NSButton(radioButtonWithTitle: choice.label, target: nil, action: nil)
                radio.state = choice.value == stringValue ? .on : .off
                target(radio) { [weak self, weak group, weak radio] in
                    guard let self, let group, let radio else { return }
                    for case let other as NSButton in group.arrangedSubviews where other !== radio {
                        other.state = .off
                    }
                    radio.state = .on
                    changed(choice.value)
                }
                group.addArrangedSubview(radio)
            }
            group.frame.size = group.fittingSize
            return group
        case .button:
            let button = NSButton(title: stringValue, target: nil, action: nil)
            button.bezelStyle = .push
            if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: stringValue) {
                button.image = image
                button.imagePosition = stringValue.isEmpty ? .imageOnly : .imageLeading
                button.isBordered = !stringValue.isEmpty
            }
            target(button) { [weak self] in
                guard let self else { return }
                onChange(value)
            }
            button.sizeToFit()
            return button
        case .color:
            let well = NSColorWell(style: .minimal)
            well.color = ILColor(css: stringValue) ?? .black
            target(well) { [weak self, weak well] in
                guard let self, let well else { return }
                changed(well.color.cssHex)
            }
            well.frame.size = CGSize(width: 44, height: 22)
            return well
        }
    }
#else
    /// the height of a text control
    @MainActor static func height(of view: ILView) -> CGFloat {
        let height = view.intrinsicContentSize.height
        return height > 0 && height != ILView.noIntrinsicMetric ? height : 34
    }

    /// a text field with the
    /// @param text provided, which calls
    /// @param edited with its text as it changes
    @MainActor private func textField(_ text: String, edited: @escaping @MainActor (String) -> Void) -> UITextField {
        let field = UITextField()
        field.text = text
        field.borderStyle = .roundedRect
        field.addAction(UIAction { [weak field] _ in edited(field?.text ?? "") }, for: .editingChanged)
        return field
    }

    @MainActor private func makeControl() -> ILView {
        switch type {
        case .text:
            let field = textField(stringValue) { [weak self] text in self?.changed(text) }
            if !choices.isEmpty { // a menu of the choices beside the field
                let actions = choices.map { choice in
                    UIAction(title: choice.label) { [weak self, weak field] _ in
                        field?.text = choice.value
                        self?.changed(choice.value)
                    }
                }
                let button = UIButton(type: .system)
                button.setImage(UIImage(systemName: "chevron.down.circle"), for: .normal)
                button.menu = UIMenu(children: actions)
                button.showsMenuAsPrimaryAction = true
                field.rightView = button
                field.rightViewMode = .always
            }
            return field
        case .tags:
            return textField(tagsValue.joined(separator: ", ")) { [weak self] text in self?.changed(Self.tags(text)) }
        case .menu:
            let actions = shownChoices.map { choice in
                UIAction(title: choice.label, state: choice.value == stringValue ? .on : .off) { [weak self] _ in
                    self?.changed(choice.value)
                }
            }
            var configuration: UIButton.Configuration = .bordered()
            configuration.title = shownChoices.first { $0.value == stringValue }?.label
            let button = UIButton(configuration: configuration)
            button.menu = UIMenu(children: actions)
            button.showsMenuAsPrimaryAction = true
            button.changesSelectionAsPrimaryAction = true
            button.sizeToFit()
            return button
        case .toggle:
#if os(tvOS)
            var configuration: UIButton.Configuration = .bordered()
            configuration.image = UIImage(systemName: boolValue ? "checkmark.square" : "square")
            let button = UIButton(configuration: configuration)
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, let button else { return }
                changed(!boolValue)
                button.configuration?.image = UIImage(systemName: boolValue ? "checkmark.square" : "square")
            }, for: .primaryActionTriggered)
            button.sizeToFit()
            return button
#else
            let toggle = UISwitch()
            toggle.isOn = boolValue
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                guard let self, let toggle else { return }
                changed(toggle.isOn)
            }, for: .valueChanged)
            toggle.sizeToFit()
            return toggle
#endif
        case .radio:
            let choices = shownChoices
            let segments = UISegmentedControl(items: choices.map(\.label))
            segments.selectedSegmentIndex = choices.firstIndex { $0.value == stringValue } ?? UISegmentedControl.noSegment
            segments.addAction(UIAction { [weak self, weak segments] _ in
                guard let self, let segments, choices.indices.contains(segments.selectedSegmentIndex) else { return }
                changed(choices[segments.selectedSegmentIndex].value)
            }, for: .valueChanged)
            segments.sizeToFit()
            return segments
        case .button:
            var configuration: UIButton.Configuration = stringValue.isEmpty ? .borderless() : .bordered()
            configuration.title = stringValue.isEmpty ? nil : stringValue
            configuration.image = symbol.flatMap { UIImage(systemName: $0) }
            configuration.imagePadding = 4
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                onChange(value)
            })
            button.sizeToFit()
            return button
        case .color:
#if os(tvOS)
            return textField(stringValue) { [weak self] text in self?.changed(text) }
#else
            let well = UIColorWell()
            well.supportsAlpha = false
            well.selectedColor = ILColor(css: stringValue)
            well.addAction(UIAction { [weak self, weak well] _ in
                guard let self, let well else { return }
                changed(well.selectedColor?.cssHex)
            }, for: .valueChanged)
            well.sizeToFit()
            return well
#endif
        }
    }
#endif
}
