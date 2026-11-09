#if !os(tvOS)
import SwiftUI
import UniformTypeIdentifiers

/// A deck being edited, its changes are registered with the undo manager, so they're saved.
/// It's changed on the main thread, SwiftUI takes its snapshots there too, and writes them in the background
final class DeckDocument: ReferenceFileDocument, @unchecked Sendable {
    @Published var pages: [DeckPage]
    @Published var images: [String: Data]

    static var readableContentTypes: [UTType] { [.deck, .markdownText] }
    static var writableContentTypes: [UTType] { [.deck, .markdownText] }

    init(package: DeckPackage = DeckPackage()) {
        pages = package.pages
        images = package.images
    }

    init(configuration: ReadConfiguration) throws {
        let package = try DeckPackage(fileWrapper: configuration.file)
        pages = package.pages
        images = package.images
    }

    func snapshot(contentType: UTType) throws -> DeckPackage {
        DeckPackage(pages: pages, images: images)
    }

    func fileWrapper(snapshot: DeckPackage, configuration: WriteConfiguration) throws -> FileWrapper {
        snapshot.fileWrapper(contentType: configuration.contentType)
    }

}

// MARK: - Editing

@MainActor extension DeckDocument {

    func index(of id: DeckPage.ID) -> Int? {
        pages.firstIndex { $0.id == id }
    }

    /// set the Markdown of a page, it's undone as a whole
    func setMarkdown(_ markdown: String, page id: DeckPage.ID, undoManager: UndoManager?) {
        guard let index = index(of: id), pages[index].markdown != markdown else { return }
        let previous = pages[index].markdown
        pages[index].markdown = markdown
        undoManager?.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                document.setMarkdown(previous, page: id, undoManager: undoManager)
            }
        }
        undoManager?.setActionName(String(localized: "Typing"))
    }

    /// add a new page after the page provided, or at the end
    @discardableResult
    func addPage(after id: DeckPage.ID?, markdown: String = "", undoManager: UndoManager?) -> DeckPage {
        let page = DeckPage(markdown: markdown)
        let index = id.flatMap(index(of:)).map { $0 + 1 } ?? pages.count
        change(String(localized: "New Card"), undoManager: undoManager) { pages in
            pages.insert(page, at: index)
        }
        return page
    }

    func duplicatePage(_ id: DeckPage.ID, undoManager: UndoManager?) -> DeckPage? {
        guard let index = index(of: id) else { return nil }
        return addPage(after: id, markdown: pages[index].markdown, undoManager: undoManager)
    }

    func deletePages(at offsets: IndexSet, undoManager: UndoManager?) {
        change(String(localized: "Delete Card"), undoManager: undoManager) { pages in
            pages.remove(atOffsets: offsets)
            if pages.isEmpty {
                pages = [DeckPage(markdown: "")]
            }
        }
    }

    func movePages(from source: IndexSet, to destination: Int, undoManager: UndoManager?) {
        change(String(localized: "Move Card"), undoManager: undoManager) { pages in
            pages.move(fromOffsets: source, toOffset: destination)
        }
    }

    /// make a change to the pages, which is undone by restoring them
    private func change(_ name: String, undoManager: UndoManager?, _ change: (inout [DeckPage]) -> Void) {
        let before = pages
        change(&pages)
        registerRestore(before, undoManager: undoManager)
        undoManager?.setActionName(name)
    }

    private func registerRestore(_ restored: [DeckPage], undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                let before = document.pages
                document.pages = restored
                document.registerRestore(before, undoManager: undoManager)
            }
        }
    }

    /// add an image to the deck
    /// @returns its path in the package, relative to the deck
    func addImage(_ data: Data, name: String) -> String {
        let name = DeckPackage(pages: pages, images: images).imageName(for: name)
        images[name] = data
        return DeckPackage.imagesName + "/" + name
    }
}
#endif
