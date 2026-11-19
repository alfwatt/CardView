import SwiftUI

/// Performs the formatting commands on a card being edited, and shows the style of its selection, for a `CardFormatBar`,
/// a toolbar or menus. With a selection a command styles it, with none it styles the text typed next
@MainActor @Observable public final class CardFormatting {
    public weak var card: CardTextView? {
        didSet { selectionChanged() }
    }
    /// false while the selection is somewhere the commands don't apply, e.g. outside a card's body
    public var isEnabled = true

    /// the style of the selection
    public private(set) var block = CardBlock.paragraph
    public private(set) var isBold = false
    public private(set) var isItalic = false
    public private(set) var isCode = false

    public init() {}

    public var canEdit: Bool { isEnabled && card?.isEditable == true }

    /// @returns true if the selection is in a block of the same kind as the
    /// @param block provided, any list of the same kind, or any code block
    public func isBlock(_ block: CardBlock) -> Bool {
        switch (self.block, block) {
        case (.listItem(let ordered, _), .listItem(let other, _)): ordered == other
        case (.codeBlock, .codeBlock): true
        default: self.block == block
        }
    }

    /// read the style of the selection, after it changes or the card is edited
    public func selectionChanged() {
        guard let card else { return }
        block = card.selectedBlock
        isBold = card.isSelectionBold
        isItalic = card.isSelectionItalic
        isCode = card.isSelectionCode
    }

    public func setBlock(_ block: CardBlock) { perform { $0.setBlock(block) } }
    public func toggleBold() { perform { $0.toggleBold() } }
    public func toggleItalic() { perform { $0.toggleItalic() } }
    public func toggleCode() { perform { $0.toggleCode() } }
    public func insertRule() { perform { $0.insertRule() } }

    /// link the selection to the URL in the
    /// @param string provided, `https://` is added when it has no scheme
    public func insertLink(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let url = URL(string: trimmed.contains(":") ? trimmed : "https://" + trimmed) else { return }
        perform { $0.insertLink(url) }
    }

    private func perform(_ command: (CardTextView) -> Void) {
        guard canEdit, let card else { return }
        command(card)
        card.normalizeBlocks()
        selectionChanged()
    }
}

/// A bar of formatting commands for a card: the block of the selected paragraphs, bold, italic and code,
/// a rule and a link, each on when the selection is
public struct CardFormatBar: View {
    let formatting: CardFormatting
    @State private var showingLinkPrompt = false
    @State private var link = ""

    public init(formatting: CardFormatting) {
        self.formatting = formatting
    }

    public var body: some View {
        HStack(spacing: 2) {
            Menu {
                block("Heading", .heading(1))
                block("Subheading", .heading(2))
                block("Body", .paragraph)
                Divider()
                block("Bulleted List", .listItem(ordered: false, depth: 0))
                block("Numbered List", .listItem(ordered: true, depth: 0))
                block("Quote", .quote)
                block("Code Block", .codeBlock(language: nil))
            } label: {
                Label("Style", systemImage: "textformat.size")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            style("Bold", "bold", formatting.isBold) { $0.toggleBold() }
            style("Italic", "italic", formatting.isItalic) { $0.toggleItalic() }
            style("Code", "chevron.left.forwardslash.chevron.right", formatting.isCode) { $0.toggleCode() }
            Button("Rule", systemImage: "minus") { formatting.insertRule() }
                .help("Rule")
            Button("Link…", systemImage: "link") { showingLinkPrompt = true }
                .help("Link")
                .popover(isPresented: $showingLinkPrompt) {
                    TextField("URL", text: $link)
                        .frame(width: 240)
                        .padding()
                        .onSubmit {
                            formatting.insertLink(link)
                            link = ""
                            showingLinkPrompt = false
                        }
                }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(!formatting.canEdit)
    }

    /// checking a block makes the selection one, unchecking it makes it body text
    private func block(_ title: LocalizedStringKey, _ block: CardBlock) -> some View {
        Toggle(title, isOn: Binding(get: { formatting.isBlock(block) },
                                    set: { formatting.setBlock($0 ? block : .paragraph) }))
    }

    private func style(_ title: LocalizedStringKey, _ image: String, _ isOn: Bool, _ toggle: @escaping (CardFormatting) -> Void) -> some View {
        Toggle(title, systemImage: image, isOn: Binding(get: { isOn }, set: { _ in toggle(formatting) }))
            .toggleStyle(.button)
            .help(Text(title))
    }
}
