import Foundation
import KitBridge
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// A button in a card, it performs its action or opens its URL when it's pressed
@objc(CardButtonAttachment)
open class CardButtonAttachment: CardAttachment, @unchecked Sendable {
    public let title: String
    public let buttonImage: ILImage?
    /// the URL the button opens, if it has no action, written out as a Markdown link
    public let url: URL?
    public let action: (@MainActor () -> Void)?

    /// the targets of the AppKit buttons, which call the action
    private var trampolines: [ButtonTrampoline] = []

    public init(title: String, image: ILImage? = nil, url: URL? = nil, action: (@MainActor () -> Void)? = nil) {
        self.title = title
        self.buttonImage = image
        self.url = url
        self.action = action
        super.init()
    }

    public required init?(coder: NSCoder) {
        title = ""
        buttonImage = nil
        url = nil
        action = nil
        super.init(coder: coder)
    }

    @MainActor func perform() {
        if let action {
            action()
        }
        else if let url {
#if canImport(AppKit)
            NSWorkspace.shared.open(url)
#else
            UIApplication.shared.open(url)
#endif
        }
    }

    // MARK: - CardAttachment

    @MainActor open override func makeView() -> ILView {
#if canImport(AppKit)
        let trampoline = ButtonTrampoline { [weak self] in self?.perform() }
        trampolines.append(trampoline)
        let button = NSButton(title: title, target: trampoline, action: #selector(ButtonTrampoline.fire))
        button.bezelStyle = .push
        if let buttonImage {
            button.image = buttonImage
            button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
        button.sizeToFit()
        return button
#else
        var configuration = UIButton.Configuration.bordered()
        configuration.title = title.isEmpty ? nil : title
        configuration.image = buttonImage
        configuration.imagePadding = 4
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.perform() })
        button.sizeToFit()
        return button
#endif
    }
}

// MARK: -

/// the target of an AppKit button, it calls a closure
@MainActor final class ButtonTrampoline: NSObject {
    let fireAction: @MainActor () -> Void

    init(_ fireAction: @escaping @MainActor () -> Void) {
        self.fireAction = fireAction
    }

    @objc func fire() {
        fireAction()
    }
}
