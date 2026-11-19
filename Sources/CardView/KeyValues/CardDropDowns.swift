import Foundation
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Small drop-down buttons beside the values of an editable card which have choices, laid over the text,
/// so the text stays only text when it's copied, and undoing typing doesn't have characters of the buttons to undo
@MainActor
public final class CardDropDowns {

    /// A drop-down beside the character at `location`, offering its `choices`: after the end of a value,
    /// or before its start, so the drop-downs of values in a column line up
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
        public let choose: @MainActor (String) -> Void

        public init(location: Int, placement: Placement = .after, choices: [CardChoice], current: String,
                    choose: @escaping @MainActor (String) -> Void) {
            self.location = location
            self.placement = placement
            self.choices = choices
            self.current = current
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
        let popUp = NSPopUpButton(frame: CGRect(origin: .zero, size: Self.size), pullsDown: true)
        popUp.isBordered = false
        popUp.controlSize = .mini
        (popUp.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        let trampoline = ButtonTrampoline { [weak self, weak popUp] in
            guard let self, let popUp, index < items.count, let value = popUp.selectedItem?.representedObject as? String else { return }
            items[index].choose(value)
        }
        trampolines.append(trampoline)
        popUp.target = trampoline
        popUp.action = #selector(ButtonTrampoline.fire)
        return popUp
    }

    private func setMenu(of button: ILView, to item: Item) {
        guard let popUp = button as? NSPopUpButton else { return }
        popUp.removeAllItems()
        let title = NSMenuItem(title: "", action: nil, keyEquivalent: "") // a pull down's first item is its button
        title.image = NSImage(systemSymbolName: "chevron.down.circle", accessibilityDescription: "Choices")
        popUp.menu?.addItem(title)
        for choice in item.choices {
            let menuItem = NSMenuItem(title: choice.label.isEmpty ? choice.value : choice.label, action: nil, keyEquivalent: "")
            menuItem.representedObject = choice.value
            menuItem.state = choice.value == item.current ? .on : .off
            popUp.menu?.addItem(menuItem)
        }
    }
#elseif !os(tvOS)
    private func makeButton(_ index: Int) -> ILView {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.down.circle"), for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.frame.size = Self.size
        return button
    }

    private func setMenu(of button: ILView, to item: Item) {
        guard let button = button as? UIButton else { return }
        let choose = item.choose
        button.menu = UIMenu(children: item.choices.map { choice in
            UIAction(title: choice.label.isEmpty ? choice.value : choice.label, state: choice.value == item.current ? .on : .off) { _ in
                choose(choice.value)
            }
        })
    }
#endif
}
