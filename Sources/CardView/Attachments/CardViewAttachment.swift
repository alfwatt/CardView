import Foundation
import SwiftUI
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Embeds a view in a card, at its size or scaled down to fit the card keeping its aspect
@objc(CardViewAttachment)
open class CardViewAttachment: CardAttachment, @unchecked Sendable {
    public let view: ILView
    /// the size of the view, nil for the view's fitting size
    public let size: CGSize?
    /// holds on to what owns the view, e.g. the hosting controller of a SwiftUI view
    let owner: AnyObject?

    @MainActor public init(view: ILView, size: CGSize? = nil) {
        self.view = view
        self.size = size
        self.owner = nil
        super.init()
    }

    /// embed a SwiftUI
    /// @param content view in the card, at the
    /// @param size provided or the view's ideal size
    @MainActor public init(_ content: some View, size: CGSize? = nil) {
#if canImport(AppKit)
        let hosting = NSHostingView(rootView: content)
        self.view = hosting
        self.owner = nil
#else
        let controller = UIHostingController(rootView: content)
        controller.view.backgroundColor = .clear
        if size == nil {
            controller.view.frame.size = controller.sizeThatFits(in: CGSize(width: 10_000, height: 10_000))
        }
        self.view = controller.view
        self.owner = controller
#endif
        self.size = size
        super.init()
    }

    public required init?(coder: NSCoder) {
        nil
    }

    // MARK: - CardAttachment

    @MainActor open override func makeView() -> ILView {
        view
    }

    @MainActor open override func size(of view: ILView, lineWidth: CGFloat, font: ILFont?) -> CGSize {
        CardAttachment.fit(size ?? view.cardFittingSize, in: lineWidth)
    }
}
