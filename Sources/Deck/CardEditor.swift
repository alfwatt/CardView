import SwiftUI
import CardView
#if canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

/// the URL the images of a deck's cards are relative to, they're found in the deck's images
let deckBaseURL = URL(string: "deck:///")!

/// @returns a closure which finds the images of the cards in the
/// @param images of a deck, and the system's symbols for `symbol:` URLs
func deckImages(_ images: [String: Data]) -> (URL) -> PlatformImage? {
    { url in
        if url.scheme == "symbol" {
            let name = url.absoluteString.dropFirst("symbol:".count)
#if canImport(AppKit)
            let image = NSImage(systemSymbolName: String(name), accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 64, weight: .regular))
            image?.isTemplate = true
            return image
#else
            return UIImage(systemName: String(name), withConfiguration: UIImage.SymbolConfiguration(pointSize: 64))?
                .withRenderingMode(.alwaysTemplate)
#endif
        }
        let path = url.relativeString.hasPrefix(DeckPackage.imagesName + "/") ? url.relativeString : String(url.path.drop { $0 == "/" })
        let name = path.removingPercentEncoding?.dropFirst(DeckPackage.imagesName.count + 1) ?? ""
        return images[String(name)].flatMap { PlatformImage(data: $0) }
    }
}

// MARK: -

/// Performs the editing commands of the card being edited, for the toolbar and the menus
@MainActor @Observable final class CardEditorModel {
    weak var card: CardTextView?
    var showingLinkPrompt = false
    var showingImageImporter = false

    /// the style of the selection, shown in the menus and the toolbar
    private(set) var block = CardBlock.paragraph
    private(set) var isBold = false
    private(set) var isItalic = false
    private(set) var isCode = false

    var canEdit: Bool { card != nil }

    /// @returns true if the selection is in a block of the same kind as the
    /// @param block provided, any list of the same kind, or any code block
    func isBlock(_ block: CardBlock) -> Bool {
        switch (self.block, block) {
        case (.listItem(let ordered, _), .listItem(let other, _)): ordered == other
        case (.codeBlock, .codeBlock): true
        default: self.block == block
        }
    }

    /// read the style of the selection, after it changes or the card is edited
    func selectionChanged() {
        guard let card else { return }
        block = card.selectedBlock
        isBold = card.isSelectionBold
        isItalic = card.isSelectionItalic
        isCode = card.isSelectionCode
    }

    func setBlock(_ block: CardBlock) { card?.setBlock(block); selectionChanged() }
    func toggleBold() { card?.toggleBold(); selectionChanged() }
    func toggleItalic() { card?.toggleItalic(); selectionChanged() }
    func toggleCode() { card?.toggleCode(); selectionChanged() }
    func insertRule() { card?.insertRule() }

    func insertLink(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let url = URL(string: trimmed.contains(":") ? trimmed : "https://" + trimmed) else { return }
        card?.insertLink(url)
    }

    func insertImage(_ image: PlatformImage, path: String, alt: String) {
        card?.insertImage(image, source: URL(string: path, relativeTo: deckBaseURL), alt: alt)
    }

#if os(iOS)
    func hideKeyboard() {
        card?.resignFirstResponder()
    }
#endif
}

extension FocusedValues {
    @Entry var cardEditor: CardEditorModel?
}

// MARK: -

/// A card showing the Markdown of a page of a deck, which writes its changes back as Markdown
struct CardEditor {
    var markdown: String
    var pageID: DeckPage.ID
    var editable = true
    var images: [String: Data] = [:]
    var model: CardEditorModel?
    var onChange: (String) -> Void = { _ in }

    @MainActor func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor func makeCard(_ coordinator: Coordinator) -> CardTextView {
        let card = CardTextView(frame: .zero)
        card.baseURL = deckBaseURL
#if os(tvOS)
        card.fontSize = 32
#else
        card.fontSize = 15
        card.isEditable = editable
        card.convertsTypedMarkdown = true
#endif
        card.delegate = coordinator
        coordinator.card = card
        model?.card = card
        return card
    }

    @MainActor func update(_ coordinator: Coordinator) {
        guard let card = coordinator.card else { return }
        card.imageLoader = deckImages(images)
        model?.card = card
        coordinator.model = model
        if coordinator.pageID != pageID {
            coordinator.flush()
            coordinator.pageID = pageID
            coordinator.show(markdown)
        }
        else if markdown != coordinator.lastMarkdown, coordinator.pending == nil { // e.g. undone
            coordinator.show(markdown)
        }
        coordinator.onChange = onChange
    }

    /// keeps the card and the page's Markdown in step, it writes the card's changes back after a pause in typing
    @MainActor final class Coordinator: NSObject {
        weak var card: CardTextView?
        var pageID: DeckPage.ID?
        var lastMarkdown = ""
        var pending: Task<Void, Never>?
        var onChange: (String) -> Void = { _ in }
        /// the hosting controller of the formatting bar on top of the keyboard
        var keyboardBar: AnyObject?
        /// shows the style of the selection
        weak var model: CardEditorModel?
        private var normalizing = false

        func show(_ markdown: String) {
            pending?.cancel()
            pending = nil
            lastMarkdown = markdown
            card?.markdown = markdown
            card?.selection = NSRange(location: 0, length: 0)
            model?.selectionChanged()
        }

        func changed() {
            guard !normalizing, let card else { return }
            normalizing = true
            card.normalizeBlocks()
            normalizing = false
            model?.selectionChanged()
            pending?.cancel()
            pending = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                self?.flush()
            }
        }

        /// write the card's changes back to its page
        func flush() {
            guard pending != nil, let card else { return }
            pending?.cancel()
            pending = nil
            let markdown = card.markdown
            lastMarkdown = markdown
            onChange(markdown)
        }
    }
}

#if canImport(AppKit)
extension CardEditor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let card = makeCard(context.coordinator)
        card.allowsUndo = false // the document undoes the changes to its pages
        card.isVerticallyResizable = true
        card.isHorizontallyResizable = false
        card.autoresizingMask = [.width]
        card.minSize = .zero
        card.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        card.textContainer?.widthTracksTextView = true
        scroll.documentView = card
        update(context.coordinator)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        update(context.coordinator)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.flush()
    }
}

extension CardEditor.Coordinator: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        changed()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        model?.selectionChanged()
    }
}
#else
extension CardEditor: UIViewRepresentable {
    func makeUIView(context: Context) -> CardTextView {
        let card = makeCard(context.coordinator)
        card.alwaysBounceVertical = true
#if os(iOS)
        if editable, let model {
            card.inputAccessoryView = context.coordinator.keyboardBar(model)
        }
#endif
        update(context.coordinator)
        return card
    }

    func updateUIView(_ card: CardTextView, context: Context) {
        update(context.coordinator)
    }

    static func dismantleUIView(_ card: CardTextView, coordinator: Coordinator) {
        coordinator.flush()
    }
}

extension CardEditor.Coordinator: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        changed()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        model?.selectionChanged()
    }
}

#if os(iOS)
extension CardEditor.Coordinator {
    /// @returns the formatting bar shown on top of the keyboard, which performs the commands of the
    /// @param model provided
    func keyboardBar(_ model: CardEditorModel) -> UIView {
        let host = UIHostingController(rootView: KeyboardFormatBar(editor: model))
        host.sizingOptions = .intrinsicContentSize
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(x: 0, y: 0, width: 0, height: 52)
        host.view.autoresizingMask = [.flexibleWidth]
        keyboardBar = host
        return host.view
    }
}
#endif
#endif
