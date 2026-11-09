import Foundation
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

// MARK: - Colors

/// the dynamic colors cards are drawn in, they follow light and dark mode on every platform
enum CardColor {
#if canImport(AppKit)
    static var text: ILColor { .labelColor }
    static var secondary: ILColor { .secondaryLabelColor }
    static var tertiary: ILColor { .tertiaryLabelColor }
    static var link: ILColor { .linkColor }
    static var accent: ILColor { .controlAccentColor }
#else
    static var text: ILColor { .label }
    static var secondary: ILColor { .secondaryLabel }
    static var tertiary: ILColor { .tertiaryLabel }
    static var link: ILColor { .link }
    static var accent: ILColor { .tintColor }
#endif
}

// MARK: - Fonts

extension ILFont {
    /// the size of a card's body text, the system's font size, a TV's cards are read from across the room
#if os(tvOS)
    public static let cardBodySize: CGFloat = 24
#else
    public static let cardBodySize: CGFloat = ILFont.systemFontSize
#endif

    static func cardFont(size: CGFloat, bold: Bool = false, italic: Bool = false, monospace: Bool = false) -> ILFont {
        let base: ILFont
        if monospace {
            base = .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        }
        else {
            base = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        }
        return italic ? base.withTraits(italic: true) : base
    }

#if canImport(AppKit)
    var isBold: Bool { fontDescriptor.symbolicTraits.contains(.bold) }
    var isItalic: Bool { fontDescriptor.symbolicTraits.contains(.italic) }
    var isMonospace: Bool { fontDescriptor.symbolicTraits.contains(.monoSpace) }

    func withTraits(bold: Bool? = nil, italic: Bool? = nil) -> ILFont {
        var traits = fontDescriptor.symbolicTraits
        if let bold { if bold { traits.insert(.bold) } else { traits.remove(.bold) } }
        if let italic { if italic { traits.insert(.italic) } else { traits.remove(.italic) } }
        return ILFont(descriptor: fontDescriptor.withSymbolicTraits(traits), size: pointSize) ?? self
    }
#else
    var isBold: Bool { fontDescriptor.symbolicTraits.contains(.traitBold) }
    var isItalic: Bool { fontDescriptor.symbolicTraits.contains(.traitItalic) }
    var isMonospace: Bool { fontDescriptor.symbolicTraits.contains(.traitMonoSpace) }

    func withTraits(bold: Bool? = nil, italic: Bool? = nil) -> ILFont {
        var traits = fontDescriptor.symbolicTraits
        if let bold { if bold { traits.insert(.traitBold) } else { traits.remove(.traitBold) } }
        if let italic { if italic { traits.insert(.traitItalic) } else { traits.remove(.traitItalic) } }
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return ILFont(descriptor: descriptor, size: pointSize)
    }
#endif

    /// the same face as this font, without its bold, italic or monospace traits
    func monospaced(_ monospace: Bool) -> ILFont {
        guard monospace != isMonospace else { return self }
        return .cardFont(size: pointSize, bold: isBold, italic: isItalic, monospace: monospace)
    }
}

// MARK: - Images

extension ILImage {
#if canImport(AppKit)
    var isTemplateImage: Bool { isTemplate }
#else
    var isTemplateImage: Bool { renderingMode == .alwaysTemplate }
#endif
}
