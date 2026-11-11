import Foundation
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// A text attachment drawn by a view, laid out with TextKit 2 on every platform,
/// subclasses provide the view and its size for the width of the line it's in
@objc(CardAttachment)
open class CardAttachment: NSTextAttachment, @unchecked Sendable {

    public init() {
        super.init(data: nil, ofType: nil)
        allowsTextAttachmentView = true
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// the view which draws the attachment, made each time the text lays it out
    @MainActor open func makeView() -> ILView {
        ILView()
    }

    /// the size of the attachment's
    /// @param view in a line of the
    /// @param lineWidth provided, at the
    /// @param font of the text around it.
    /// The default is the view's fitting size, scaled down to fit in the line
    @MainActor open func size(of view: ILView, lineWidth: CGFloat, font: ILFont?) -> CGSize {
        CardAttachment.fit(view.cardFittingSize, in: lineWidth)
    }

    /// the attachment's offset from the baseline, small attachments are centered on the text's x height, larger ones sit on the baseline
    open func baselineOffset(for size: CGSize, font: ILFont?) -> CGFloat {
        guard let font else { return 0 }
        if size.height <= (font.ascender - font.descender) * 1.5 {
            return ((font.xHeight - size.height) / 2).rounded()
        }
        return 0
    }

    /// @returns the
    /// @param size provided, scaled down to fit the
    /// @param width keeping its aspect
    public static func fit(_ size: CGSize, in width: CGFloat) -> CGSize {
        guard size.width > width, size.width > 0, width > 0 else { return size }
        return CGSize(width: width, height: (size.height * (width / size.width)).rounded())
    }

    /// the width left in the line fragment, after the position of the attachment
    static func lineWidth(_ fragment: CGRect, position: CGPoint, container: NSTextContainer?) -> CGFloat {
        max(1, fragment.width - position.x)
    }

    // MARK: - Layout

    /// the text layout managers and locations the attachment's views are in, so they can be laid out again when it changes
    private var placements: [(manager: Weak<NSTextLayoutManager>, location: NSTextLocation)] = []

    /// lay the attachment out again where it's shown, after its contents have changed
    @MainActor public func invalidateLayout() {
        for placement in placements {
            guard let manager = placement.manager.object,
                  let range = NSTextRange(location: placement.location, end: manager.location(placement.location, offsetBy: 1)) else {
                continue
            }
            manager.invalidateLayout(for: range)
            manager.textViewportLayoutController.layoutViewport()
        }
    }

    // MARK: - NSTextAttachment

    /// the attachment is drawn by its view, not an image, so the text doesn't draw a placeholder under it
    open override func image(for bounds: CGRect, attributes: [NSAttributedString.Key: Any] = [:], location: NSTextLocation,
                             textContainer: NSTextContainer?) -> ILImage? {
        CardAttachment.empty
    }

    static let empty = ILImage()

    open override func viewProvider(for parentView: ILView?, location: NSTextLocation, textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let manager = textContainer?.textLayoutManager
        if let manager {
            placements.removeAll { $0.manager.object == nil || $0.manager.object === manager && $0.location.compare(location) == .orderedSame }
            placements.append((Weak(manager), location))
        }
        let provider = CardAttachmentViewProvider(textAttachment: self, parentView: parentView, textLayoutManager: manager, location: location)
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

// MARK: -

/// Provides the view of a `CardAttachment`, sized to the line it's laid out in
final class CardAttachmentViewProvider: NSTextAttachmentViewProvider {

    override func loadView() {
        nonisolated(unsafe) let provider = self // TextKit loads and lays out the views of text views on the main thread
        MainActor.assumeIsolated {
            provider.view = (provider.textAttachment as? CardAttachment)?.makeView()
        }
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: NSTextLocation, textContainer: NSTextContainer?,
                                   proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        nonisolated(unsafe) let provider = self
#if canImport(AppKit)
        nonisolated(unsafe) let font = attributes[.font] as? ILFont // AppKit's fonts aren't Sendable
#else
        let font = attributes[.font] as? ILFont
#endif
        let width = CardAttachment.lineWidth(proposedLineFragment, position: position, container: textContainer)
        return MainActor.assumeIsolated {
            if provider.view == nil {
                provider.loadView()
            }
            guard let attachment = provider.textAttachment as? CardAttachment, let view = provider.view else { return .zero }
            let size = attachment.size(of: view, lineWidth: width, font: font)
            return CGRect(x: 0, y: attachment.baselineOffset(for: size, font: font), width: size.width, height: size.height)
        }
    }
}

// MARK: -

struct Weak<Object: AnyObject> {
    weak var object: Object?

    init(_ object: Object) {
        self.object = object
    }
}

extension ILView {
    /// the size the view would like to be
    @MainActor var cardFittingSize: CGSize {
#if canImport(AppKit)
        let fitting = fittingSize
#else
        let fitting = intrinsicContentSize
#endif
        if fitting.width > 0, fitting.height > 0, fitting.width != ILView.noIntrinsicMetric, fitting.height != ILView.noIntrinsicMetric {
            return fitting
        }
        return frame.size
    }
}
