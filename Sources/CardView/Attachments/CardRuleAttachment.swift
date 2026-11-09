import Foundation
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// A rule across the card, from where it starts to the right of the text
@objc(CardRuleAttachment)
open class CardRuleAttachment: CardAttachment, @unchecked Sendable {
    public let color: ILColor
    public let width: CGFloat

    public init(color: ILColor? = nil, width: CGFloat = 1) {
        self.color = color ?? CardColor.tertiary
        self.width = width
        super.init()
    }

    public required init?(coder: NSCoder) {
        color = CardColor.tertiary
        width = 1
        super.init(coder: coder)
    }

    @MainActor open override func makeView() -> ILView {
        CardRuleView(color: color, width: width)
    }

    @MainActor open override func size(of view: ILView, lineWidth: CGFloat, font: ILFont?) -> CGSize {
        CGSize(width: lineWidth, height: width + 2)
    }

    open override func baselineOffset(for size: CGSize, font: ILFont?) -> CGFloat {
        0
    }
}

// MARK: -

/// Draws a line across its middle, in the color as its appearance resolves it
final class CardRuleView: ILView {
    let color: ILColor
    let width: CGFloat

    init(color: ILColor, width: CGFloat) {
        self.color = color
        self.width = width
        super.init(frame: .zero)
#if canImport(UIKit)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
#endif
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: CGRect) {
        color.setFill()
        let line = CGRect(x: 0, y: ((bounds.height - width) / 2).rounded(), width: bounds.width, height: width)
#if canImport(AppKit)
        line.fill()
#else
        UIRectFill(line)
#endif
    }
}
