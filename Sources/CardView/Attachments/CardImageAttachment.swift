import Foundation
#if canImport(KitBridgeSwift)
import KitBridgeSwift
#else
import KitBridge
#endif
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// An image in a card, scaled down to fit the width of the card, template images are drawn in the text color
@objc(CardImageAttachment)
open class CardImageAttachment: CardAttachment, @unchecked Sendable {
    /// where the image came from, written out as Markdown relative to the card's base URL
    public let source: URL?
    /// the image's alternate text
    public let alt: String
    /// the widest the image is drawn, nil to fit the card
    public var maxWidth: CGFloat?

    /// the image views showing the image, so they are updated when it loads
    private var imageViews: [Weak<ILImageView>] = []

    public init(image: ILImage?, source: URL? = nil, alt: String = "", maxWidth: CGFloat? = nil) {
        self.source = source
        self.alt = alt
        self.maxWidth = maxWidth
        super.init()
        self.image = image
    }

    /// an image loaded from the
    /// @param source URL provided, file and data URLs load right away, remote images load in the background when they're shown
    public convenience init(source: URL, alt: String = "", maxWidth: CGFloat? = nil) {
        let image: ILImage? = if source.isFileURL || source.scheme == "data" {
            (try? Data(contentsOf: source)).flatMap { ILImage(data: $0) }
        }
        else {
            nil
        }
        self.init(image: image, source: source, alt: alt, maxWidth: maxWidth)
    }

    public required init?(coder: NSCoder) {
        source = nil
        alt = ""
        super.init(coder: coder)
    }

    /// true while the remote image is loading
    @MainActor private var loading = false

    /// load a remote image, and lay it out again when it arrives
    @MainActor private func load(_ url: URL) {
        guard !loading else { return }
        loading = true
        Task { @MainActor [weak self] in
            defer { self?.loading = false }
            guard let (data, _) = try? await URLSession.shared.data(from: url), let image = ILImage(data: data) else { return }
            self?.update(image)
        }
    }

    @MainActor private func update(_ image: ILImage) {
        self.image = image
        for imageView in imageViews {
            imageView.object?.image = image
        }
        invalidateLayout()
    }

    // MARK: - CardAttachment

    @MainActor open override func makeView() -> ILView {
        if image == nil, let source, !source.isFileURL, source.scheme != "data" {
            load(source)
        }
        let imageView = ILImageView()
        imageView.image = image
#if canImport(AppKit)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = image?.isTemplate == true ? CardColor.text : nil
        imageView.setAccessibilityLabel(alt)
#else
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = CardColor.text
        imageView.accessibilityLabel = alt
#endif
        imageViews.removeAll { $0.object == nil }
        imageViews.append(Weak(imageView))
        return imageView
    }

    @MainActor open override func size(of view: ILView, lineWidth: CGFloat, font: ILFont?) -> CGSize {
        guard let size = image?.size, size.width > 0, size.height > 0 else {
            return CGSize(width: 1, height: font?.pointSize ?? 12) // until it loads
        }
        return CardAttachment.fit(size, in: min(lineWidth, maxWidth ?? lineWidth))
    }
}
