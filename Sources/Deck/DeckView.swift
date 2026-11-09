#if !os(tvOS)
import SwiftUI
import UniformTypeIdentifiers
import CardView

/// A deck's cards in the sidebar, and the selected card, being edited
struct DeckView: View {
    @ObservedObject var document: DeckDocument
    @Environment(\.undoManager) private var undoManager
    @State private var selection: DeckPage.ID?
    @State private var editor = CardEditorModel()
    @State private var link = ""
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// the card pushed onto the document's navigation stack on the iPhone
    @State private var pushed: DeckPage.ID?
    /// the cards are shown beside the card being edited on the iPad
    @State private var showingCards = true
#endif

    var body: some View {
        content
            .onAppear {
                selection = selection ?? document.pages.first?.id
            }
            .onChange(of: document.pages.map(\.id)) { _, ids in
                if let id = selection, ids.contains(id) { return }
                selection = ids.first
            }
            .focusedSceneValue(\.cardEditor, editor)
            .alert("Insert Link", isPresented: $editor.showingLinkPrompt) {
                TextField("URL", text: $link)
#if !os(macOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
#endif
                Button("Insert") {
                    editor.insertLink(link)
                    link = ""
                }
                Button("Cancel", role: .cancel) { link = "" }
            }
            .fileImporter(isPresented: $editor.showingImageImporter, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result {
                    insertImage(url)
                }
            }
    }

    /// the cards and the card being edited, the document's title is left alone so it can be renamed
    @ViewBuilder private var content: some View {
#if os(iOS)
        if sizeClass == .compact { // the document is already in a navigation stack, push the cards onto it
            cardList(selection: nil)
                .toolbar { newCardButton }
                .navigationDestination(item: $pushed) { id in
                    cardEditor(id)
                }
        }
        else {
            sidebarView
        }
#else
        splitView
#endif
    }

#if os(iOS)
    /// the cards beside the card being edited, in the document's navigation bar, not a split view's bars of its own
    private var sidebarView: some View {
        HStack(spacing: 0) {
            if showingCards {
                cardList(selection: $selection)
                    .listStyle(.sidebar)
                    .safeAreaInset(edge: .bottom) { // in the column, not the card's bar
                        HStack {
                            newCardButton
                                .labelStyle(.iconOnly)
                                .font(.title3)
                            Spacer()
                        }
                        .padding()
                    }
                    .frame(width: 280)
                    .transition(.move(edge: .leading))
                Divider()
                    .ignoresSafeArea()
            }
            detail
                .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(showingCards ? "Hide Cards" : "Show Cards", systemImage: "sidebar.leading") {
                    withAnimation { showingCards.toggle() }
                }
            }
        }
    }
#endif

    private var splitView: some View {
        NavigationSplitView {
            cardList(selection: $selection)
                .toolbar { newCardButton }
#if os(macOS)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200)
#endif
        } detail: {
            detail
        }
    }

    @ViewBuilder private var detail: some View {
        if let id = selection {
            cardEditor(id)
        }
        else {
            ContentUnavailableView("No Card Selected", systemImage: "rectangle.stack", description: Text("Choose a card, or make a new one."))
        }
    }

    /// the cards of the deck, selected in the sidebar, or pushed when there's no
    /// @param selection binding
    private func cardList(selection: Binding<DeckPage.ID?>?) -> some View {
        List(selection: selection) {
            ForEach(document.pages) { page in
                cardRow(page)
                    .tag(page.id)
                    .contextMenu {
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(page.id) }
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(page.id) }
                    }
            }
            .onMove { document.movePages(from: $0, to: $1, undoManager: undoManager) }
            .onDelete { document.deletePages(at: $0, undoManager: undoManager) }
        }
    }

    private var newCardButton: some View {
        Button("New Card", systemImage: "plus") { addPage() }
    }

    @ViewBuilder private func cardRow(_ page: DeckPage) -> some View {
        let title = Text(page.title).lineLimit(1)
#if os(iOS)
        if sizeClass == .compact {
            NavigationLink { cardEditor(page.id) } label: { title }
        }
        else {
            title
        }
#else
        title
#endif
    }

    @ViewBuilder private func cardEditor(_ id: DeckPage.ID) -> some View {
        if let index = document.index(of: id) {
            let card = CardEditor(markdown: document.pages[index].markdown, pageID: id, images: document.images, model: editor) { markdown in
                document.setMarkdown(markdown, page: id, undoManager: undoManager)
            }
#if !os(iOS) // on iOS the formatting commands are on top of the keyboard
            .toolbar { FormatToolbar(editor: editor) }
#endif
#if os(macOS)
            card.navigationSubtitle(document.pages[index].title)
#elseif os(iOS)
            if sizeClass == .compact { // a card pushed onto the document
                card
                    .navigationTitle(document.pages[index].title)
                    .navigationBarTitleDisplayMode(.inline)
            }
            else {
                card
            }
#else
            card
#endif
        }
    }
    // MARK: - Actions

    private func addPage() {
        selection = document.addPage(after: selection, undoManager: undoManager).id
#if os(iOS)
        if sizeClass == .compact {
            pushed = selection
        }
#endif
    }

    private func duplicate(_ id: DeckPage.ID) {
        selection = document.duplicatePage(id, undoManager: undoManager)?.id ?? selection
    }

    private func delete(_ id: DeckPage.ID) {
        guard let index = document.index(of: id) else { return }
        document.deletePages(at: [index], undoManager: undoManager)
    }

    /// copy the image into the deck and insert it in the card
    private func insertImage(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url), let image = PlatformImage(data: data) else { return }
        let path = document.addImage(data, name: url.lastPathComponent)
        editor.insertImage(image, path: path, alt: url.deletingPathExtension().lastPathComponent)
    }
}

// MARK: -

/// The formatting commands of the card being edited, in the toolbar
struct FormatToolbar: ToolbarContent {
    let editor: CardEditorModel

    var body: some ToolbarContent {
        ToolbarItemGroup {
            FormatButtons(editor: editor)
        }
    }
}

#if os(iOS)
/// The formatting commands of the card being edited, on top of the keyboard
struct KeyboardFormatBar: View {
    let editor: CardEditorModel

    var body: some View {
        HStack(spacing: 16) {
            FormatButtons(editor: editor)
            Spacer()
            Button("Hide Keyboard", systemImage: "keyboard.chevron.compact.down") { editor.hideKeyboard() }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 20)
        .frame(height: 44)
        .glassEffect(in: .capsule)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}
#endif

struct FormatButtons: View {
    let editor: CardEditorModel

    var body: some View {
        Menu("Style", systemImage: "textformat.size") {
            BlockButtons(editor: editor)
        }
        StyleToggles(editor: editor)
            .toggleStyle(.button)
        InsertButtons(editor: editor)
    }
}

/// the blocks of the paragraphs in the selection, the selection's is checked
struct BlockButtons: View {
    let editor: CardEditorModel?
    /// the menu bar's items have keyboard shortcuts
    var shortcuts = false

    var body: some View {
        block("Heading", .heading(1), "1", [.command, .option])
        block("Subheading", .heading(2), "2", [.command, .option])
        block("Body", .paragraph, "0", [.command, .option])
        Divider()
        block("Bulleted List", .listItem(ordered: false, depth: 0), "8", [.command, .shift])
        block("Numbered List", .listItem(ordered: true, depth: 0), "7", [.command, .shift])
        block("Quote", .quote, "'", [.command])
        block("Code Block", .codeBlock(language: nil), nil, [])
    }

    /// checking a block makes the selection one, unchecking it makes it body text
    private func block(_ title: LocalizedStringKey, _ block: CardBlock, _ key: KeyEquivalent?, _ modifiers: EventModifiers) -> some View {
        Toggle(title, isOn: Binding(get: { editor?.isBlock(block) == true },
                                    set: { editor?.setBlock($0 ? block : .paragraph) }))
            .keyboardShortcut(shortcuts ? key.map { KeyboardShortcut($0, modifiers: modifiers) } : nil)
    }
}

/// bold, italic and code, on when the selection is
struct StyleToggles: View {
    let editor: CardEditorModel?
    var shortcuts = false

    var body: some View {
        style("Bold", "bold", "b", \.isBold) { $0.toggleBold() }
        style("Italic", "italic", "i", \.isItalic) { $0.toggleItalic() }
        style("Code", "chevron.left.forwardslash.chevron.right", "e", \.isCode) { $0.toggleCode() }
    }

    private func style(_ title: LocalizedStringKey, _ image: String, _ key: KeyEquivalent, _ isOn: KeyPath<CardEditorModel, Bool>,
                       _ toggle: @escaping (CardEditorModel) -> Void) -> some View {
        Toggle(title, systemImage: image, isOn: Binding(get: { editor?[keyPath: isOn] == true },
                                                       set: { _ in editor.map(toggle) }))
            .keyboardShortcut(shortcuts ? KeyboardShortcut(key) : nil)
    }
}

struct InsertButtons: View {
    let editor: CardEditorModel?

    var body: some View {
        Button("Rule", systemImage: "minus") { editor?.insertRule() }
        Button("Link…", systemImage: "link") { editor?.showingLinkPrompt = true }
        Button("Image…", systemImage: "photo") { editor?.showingImageImporter = true }
    }
}

// MARK: -

/// The Format menu, for the card being edited
struct DeckCommands: Commands {
    @FocusedValue(\.cardEditor) private var editor

    var body: some Commands {
        CommandMenu("Format") {
            Group {
                BlockButtons(editor: editor, shortcuts: true)
                Divider()
                StyleToggles(editor: editor, shortcuts: true)
                    .labelStyle(.titleOnly)
                Divider()
                InsertButtons(editor: editor)
            }
            .disabled(editor?.canEdit != true)
        }
    }
}
#endif
