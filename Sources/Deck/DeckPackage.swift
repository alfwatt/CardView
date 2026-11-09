import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// a deck of cards, a package of a Markdown file for each card, with their images
    static let deck = UTType(exportedAs: "net.istumbler.deck", conformingTo: .package)
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// A card of a deck, its Markdown
struct DeckPage: Identifiable, Hashable, Sendable {
    var id = UUID()
    var markdown: String

    /// the text of the card's first line, without its Markdown
    var title: String {
        let line = markdown.split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        let title = line.trimmingCharacters(in: CharacterSet(charactersIn: "#>-*` ").union(.whitespaces))
            .replacingOccurrences(of: "**", with: "")
        return title.isEmpty ? String(localized: "Untitled") : title
    }
}

/// The files of a deck: `Deck.json` lists its cards in order, each card is a Markdown file, its images are in `Images/`.
/// A plain Markdown file is a deck too, its cards are separated by `<!-- card -->` lines
struct DeckPackage: Sendable, Equatable {
    var pages: [DeckPage]
    /// the images of the cards, by their names in `Images/`
    var images: [String: Data]

    static let manifestName = "Deck.json"
    static let imagesName = "Images"
    /// separates the cards of a deck in a plain Markdown file
    static let cardSeparator = "<!-- card -->"

    struct Manifest: Codable {
        var version = 1
        var pages: [String]
    }

    enum Failure: Error {
        case unreadable
    }

    init(pages: [DeckPage] = [DeckPage(markdown: "# \(String(localized: "Untitled"))\n")], images: [String: Data] = [:]) {
        self.pages = pages
        self.images = images
    }

    // MARK: - Reading

    init(fileWrapper: FileWrapper) throws {
        if fileWrapper.isRegularFile {
            guard let data = fileWrapper.regularFileContents, let markdown = String(data: data, encoding: .utf8) else {
                throw Failure.unreadable
            }
            self.init(markdown: markdown)
            return
        }
        guard let files = fileWrapper.fileWrappers else { throw Failure.unreadable }
        let order: [String]
        if let data = files[Self.manifestName]?.regularFileContents, let manifest = try? JSONDecoder().decode(Manifest.self, from: data) {
            order = manifest.pages
        }
        else { // a package without its manifest, its Markdown files in order of their names
            order = files.keys.filter { $0.hasSuffix(".md") }.sorted()
        }
        var pages = order.compactMap { name in
            files[name]?.regularFileContents.flatMap { String(data: $0, encoding: .utf8) }.map { DeckPage(markdown: $0) }
        }
        if pages.isEmpty {
            pages = [DeckPage(markdown: "")]
        }
        self.init(pages: pages, images: (files[Self.imagesName]?.fileWrappers ?? [:]).compactMapValues(\.regularFileContents))
    }

    /// a deck from a Markdown file, with its cards separated by `<!-- card -->` lines
    init(markdown: String) {
        let cards = markdown.components(separatedBy: "\n" + Self.cardSeparator + "\n")
        self.init(pages: cards.map { DeckPage(markdown: $0.trimmingCharacters(in: .newlines)) })
    }

    // MARK: - Writing

    /// the Markdown of a deck in a single file, its images aren't included
    var markdown: String {
        pages.map(\.markdown).joined(separator: "\n\n" + Self.cardSeparator + "\n\n") + "\n"
    }

    /// @returns the files of the deck, a package or a Markdown file for the
    /// @param contentType provided
    func fileWrapper(contentType: UTType = .deck) -> FileWrapper {
        if contentType.conforms(to: .markdownText) || contentType.conforms(to: .plainText) {
            return FileWrapper(regularFileWithContents: Data(markdown.utf8))
        }
        var files: [String: FileWrapper] = [:]
        var names: [String] = []
        for (index, page) in pages.enumerated() {
            let name = String(format: "%02d-%@.md", index + 1, Self.slug(page.title))
            names.append(name)
            files[name] = FileWrapper(regularFileWithContents: Data(page.markdown.utf8))
        }
        let manifest = (try? JSONEncoder.sorted.encode(Manifest(pages: names))) ?? Data()
        files[Self.manifestName] = FileWrapper(regularFileWithContents: manifest)
        if !images.isEmpty {
            files[Self.imagesName] = FileWrapper(directoryWithFileWrappers: images.mapValues { FileWrapper(regularFileWithContents: $0) })
        }
        return FileWrapper(directoryWithFileWrappers: files)
    }

    /// @returns a file name for a card with the
    /// @param title provided
    static func slug(_ title: String) -> String {
        let words = title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let slug = words.prefix(6).joined(separator: "-")
        return slug.isEmpty ? "card" : slug
    }

    /// @returns a name for an image in `Images/`, which isn't the name of another image
    func imageName(for name: String) -> String {
        let url = URL(fileURLWithPath: name)
        let base = Self.slug(url.deletingPathExtension().lastPathComponent)
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        var candidate = "\(base).\(ext)"
        var index = 2
        while images[candidate] != nil {
            candidate = "\(base)-\(index).\(ext)"
            index += 1
        }
        return candidate
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

// MARK: - Sample

extension DeckPackage {
    /// the deck shown on the TV, and in a new deck's help
    static let sample = DeckPackage(pages: [
        DeckPage(markdown: """
            # Deck

            A deck is a stack of cards, each one is written in **Markdown** and drawn by *CardView*.

            ![Cards](symbol:rectangle.stack)

            Swipe to the next card.
            """),
        DeckPage(markdown: """
            ## Lists and Tables

            - Headings, **bold**, *italic* and `code`
            - Lists
                1. bulleted
                2. and numbered
            - [Links](https://github.com/alfwatt/CardView)

            | Platform | Since |
            | --- | --: |
            | macOS | 13 |
            | iOS | 16 |
            | tvOS | 16 |
            | visionOS | 26 |
            """),
        DeckPage(markdown: """
            ## Rules, Quotes and Code

            > A card is a good looking text view.

            ---

            ```swift
            card.markdown = "# Hello, World!"
            ```
            """),
    ])
}
