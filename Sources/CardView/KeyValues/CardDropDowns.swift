import Foundation
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Small drop-down buttons beside the values of an editable card, offering their choices and actions, laid over the text,
/// so the text stays only text when it's copied, and undoing typing doesn't have characters of the buttons to undo
@MainActor
public final class CardDropDowns {

    /// An action in a drop-down's menu, after its choices, e.g. to open or search for a value
    public struct Action {
        public let title: String
        /// the name of the action's SF Symbol, if it has one
        public let symbol: String?
        public let perform: @MainActor () -> Void

        public init(_ title: String, symbol: String? = nil, perform: @escaping @MainActor () -> Void) {
            self.title = title
            self.symbol = symbol
            self.perform = perform
        }
    }

    /// A drop-down beside the character at `location`, offering its `choices` then its `actions`: after the end of
    /// a value, or before its start, so the drop-downs of values in a column line up
    public struct Item {
        /// where the drop-down goes, beside `location`
        public enum Placement: Sendable {
            /// after `location`, e.g. the end of a value
            case after
            /// before `location`, e.g. the start of a value, after it instead when there's no room before it
            case before
        }

        public let location: Int
        public let placement: Placement
        public let choices: [CardChoice]
        public let current: String
        /// the actions after the choices
        public let actions: [Action]
        /// the name of the button's SF Symbol, e.g. a dot to mark a value that's changed
        public let symbol: String
        /// the button's color, or the control's own
        public let tint: ILColor?
        /// what a click does, e.g. open a link, leaving the menu to a right click or a long press, or nil to show the menu
        public let primary: (@MainActor () -> Void)?
        /// the button's tooltip
        public let help: String?
        public let choose: @MainActor (String) -> Void

        public init(location: Int, placement: Placement = .after, choices: [CardChoice], current: String,
                    actions: [Action] = [], symbol: String = "chevron.down.circle", tint: ILColor? = nil,
                    primary: (@MainActor () -> Void)? = nil, help: String? = nil,
                    choose: @escaping @MainActor (String) -> Void) {
            self.location = location
            self.placement = placement
            self.choices = choices
            self.current = current
            self.actions = actions
            self.symbol = symbol
            self.tint = tint
            self.primary = primary
            self.help = help
            self.choose = choose
        }
    }

    /// the space between a drop-down and its value
    public static let spacing: CGFloat = 4

    /// the size of a drop-down button
#if canImport(AppKit)
    public static let size = CGSize(width: 18, height: 16)
#else
    public static let size = CGSize(width: 24, height: 24)
#endif

    /// the buttons, reused in order as the items change
    public private(set) var buttons: [ILView] = []
    private var items: [Item] = []
    private weak var card: CardTextView?
    private var frameObserver: NSObjectProtocol?
#if canImport(AppKit)
    private var trampolines: [ButtonTrampoline] = []
#endif

    public init() {}

    isolated deinit {
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
    }

    /// show the drop-downs of the
    /// @param items provided in the
    /// @param card, moving them when the card's width changes
    public func update(_ card: CardTextView, items: [Item]) {
#if !os(tvOS)
        if self.card !== card {
            self.card = card
            observeFrame(of: card)
        }
        self.items = items
        while buttons.count > items.count {
            buttons.removeLast().removeFromSuperview()
        }
        for (index, item) in items.enumerated() {
            if index == buttons.count {
                let button = makeButton(index)
                card.addSubview(button)
                buttons.append(button)
            }
            setMenu(of: buttons[index], to: item)
        }
        layout()
#endif
    }

    /// place the buttons beside their values
    public func layout() {
        guard let card, let manager = card.textLayoutManager else { return }
        manager.ensureLayout(for: manager.documentRange)
#if canImport(AppKit)
        let origin = card.textContainerOrigin
#else
        let origin = CGPoint(x: card.textContainerInset.left, y: card.textContainerInset.top)
#endif
        for (button, item) in zip(buttons, items) {
            guard let location = manager.location(manager.documentRange.location, offsetBy: item.location) else { continue }
            let caret = NSTextRange(location: location)
            var rect = CGRect.null
            manager.enumerateTextSegments(in: caret, type: .standard, options: []) { _, frame, _, _ in
                rect = frame
                return false
            }
            guard !rect.isNull else { continue }
            let before = rect.minX - Self.spacing - Self.size.width
            let x = item.placement == .before && before >= 0 ? before : rect.maxX + Self.spacing // no room before, e.g. a value under its key
            button.frame = CGRect(x: (origin.x + x).rounded(), y: (origin.y + rect.midY - Self.size.height / 2).rounded(),
                                  width: Self.size.width, height: Self.size.height)
        }
    }

    private func observeFrame(of card: CardTextView) {
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
#if canImport(AppKit)
        card.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: card, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
#endif
    }

    // MARK: - Buttons

#if canImport(AppKit)
    private func makeButton(_ index: Int) -> ILView {
        let popUp = CardDropDownButton(frame: CGRect(origin: .zero, size: Self.size), pullsDown: true)
        popUp.isBordered = false
        popUp.controlSize = .mini
        (popUp.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        let trampoline = ButtonTrampoline { [weak self, weak popUp] in
            guard let self, let popUp, index < items.count else { return }
            if let action = popUp.selectedItem?.representedObject as? CardDropDownAction {
                action.perform()
            }
            else if let value = popUp.selectedItem?.representedObject as? String {
                items[index].choose(value)
            }
        }
        trampolines.append(trampoline)
        popUp.target = trampoline
        popUp.action = #selector(ButtonTrampoline.fire)
        return popUp
    }

    private func setMenu(of button: ILView, to item: Item) {
        guard let popUp = button as? CardDropDownButton else { return }
        popUp.removeAllItems()
        popUp.primary = item.primary
        popUp.toolTip = item.help
        popUp.contentTintColor = item.tint
        let title = NSMenuItem(title: "", action: nil, keyEquivalent: "") // a pull down's first item is its button
        var image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.help ?? "Choices")
        if let tint = item.tint {
            image = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint]))
        }
        title.image = image
        popUp.menu?.addItem(title)
        for choice in item.choices {
            let menuItem = NSMenuItem(title: choice.label.isEmpty ? choice.value : choice.label, action: nil, keyEquivalent: "")
            menuItem.representedObject = choice.value
            menuItem.state = choice.value == item.current ? .on : .off
            popUp.menu?.addItem(menuItem)
        }
        if !item.choices.isEmpty && !item.actions.isEmpty {
            popUp.menu?.addItem(.separator())
        }
        for action in item.actions {
            let menuItem = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
            menuItem.representedObject = CardDropDownAction(action.perform)
            menuItem.image = action.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            popUp.menu?.addItem(menuItem)
        }
    }
#elseif !os(tvOS)
    private static let primaryIdentifier = UIAction.Identifier("CardDropDowns.primary")

    private func makeButton(_ index: Int) -> ILView {
        let button = UIButton(type: .system)
        button.frame.size = Self.size
        return button
    }

    private func setMenu(of button: ILView, to item: Item) {
        guard let button = button as? UIButton else { return }
        let choose = item.choose
        button.setImage(UIImage(systemName: item.symbol), for: .normal)
        button.tintColor = item.tint
        button.accessibilityLabel = item.help
        let choices = UIMenu(options: .displayInline, children: item.choices.map { choice in
            UIAction(title: choice.label.isEmpty ? choice.value : choice.label, state: choice.value == item.current ? .on : .off) { _ in
                choose(choice.value)
            }
        })
        let actions = UIMenu(options: .displayInline, children: item.actions.map { action in
            UIAction(title: action.title, image: action.symbol.flatMap { UIImage(systemName: $0) }) { _ in action.perform() }
        })
        button.menu = UIMenu(children: [choices, actions])
        // a click does the primary action and a long press shows the menu, or a tap shows it
        button.showsMenuAsPrimaryAction = item.primary == nil
        button.removeAction(identifiedBy: Self.primaryIdentifier, for: .primaryActionTriggered) // the reused button's last one
        if let primary = item.primary {
            button.addAction(UIAction(identifier: Self.primaryIdentifier) { _ in primary() }, for: .primaryActionTriggered)
        }
    }
#endif
}

#if canImport(AppKit)
/// a drop-down's button, which does its primary action when it's clicked, if it has one, and shows its menu
/// when it's right clicked, or when it hasn't
final class CardDropDownButton: NSPopUpButton {
    var primary: (@MainActor () -> Void)?

    override func mouseDown(with event: NSEvent) {
        if let primary, !event.modifierFlags.contains(.control) {
            primary()
        }
        else {
            super.mouseDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        super.mouseDown(with: event) // the menu
    }
}
#endif

/// an action in a drop-down's menu item, its `representedObject`
final class CardDropDownAction: NSObject {
    let perform: @MainActor () -> Void

    init(_ perform: @escaping @MainActor () -> Void) {
        self.perform = perform
    }
}
