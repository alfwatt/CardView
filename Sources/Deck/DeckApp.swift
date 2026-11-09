import SwiftUI

/// Deck, a Markdown editor for decks of cards, on the Mac, iPhone, iPad and Vision Pro, and a viewer on the TV
@main
struct DeckApp: App {
    var body: some Scene {
#if os(tvOS)
        WindowGroup {
            DeckViewer(deck: .sample)
        }
#else
        DocumentGroup(newDocument: { DeckDocument() }) { file in
            DeckView(document: file.document)
        }
        .commands {
            DeckCommands()
        }
#endif
    }
}

#if os(tvOS)
/// The cards of a deck, one after another
struct DeckViewer: View {
    let deck: DeckPackage

    var body: some View {
        TabView {
            ForEach(deck.pages) { page in
                CardEditor(markdown: page.markdown, pageID: page.id, editable: false, images: deck.images)
            }
        }
        .tabViewStyle(.page)
    }
}
#endif
