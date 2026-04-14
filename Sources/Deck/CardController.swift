import AppKit
import CardView

class CardController: NSViewController {
    @IBOutlet var cardView: CardTextView!
    
    override func viewDidAppear() {
        super.viewDidAppear()
        cardView.append("Hello, World!")
        cardView.append("This is a card view.\n")
    }

    override var representedObject: Any? {
        didSet {
        }
    }
}
