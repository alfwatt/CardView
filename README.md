# CardView.framework

iStumbler Labs CardView.framework — CardView is a good looking text view for macOS, iOS, tvOS
and visionOS, which reads and writes Markdown, with methods for building cards of styled text,
columns, rules, images, buttons and embedded views.

```swift
import CardView

let card = CardTextView()
card.markdown = """
# Wi-Fi

Connected to **Home**, on channel `36`.

---

| Signal | Noise |
| --: | --: |
| -52 dBm | -94 dBm |
"""
print(card.markdown) // and back again
```

<a id="markdown"></a>
## Markdown

Markdown is the preferred way to fill a card, and to read what's in it:

- `CardTextView.markdown`: set it to show Markdown in the card, get it to write the card out as Markdown
- `CardTextView.appendMarkdown(_:)`: append Markdown to the card, in its font size and top style
- `CardTextView.baseURL` and `imageLoader`: where the card's images and links are relative to, and a closure
  which provides images before they are loaded from their URLs
- `CardMarkdown.attributedString(from:fontSize:paragraph:baseURL:width:images:)` and
  `CardMarkdown.markdown(from:baseURL:)`: the same, for building cards' text in the background

Headings, paragraphs, **bold**, *italic*, `code`, ~~strikethrough~~, links, images, bulleted and numbered lists,
quotes, code blocks, tables and rules are read, and written back out the same way. Every paragraph of a card
is tagged with the `CardBlock` it is written out as, so a card built with the methods below, or edited by its
user, can be written out as Markdown too.

<a id="classes"></a>
## Classes

### [`CardTextView`](./Sources/CardView/CardTextView.swift)

A good looking subclass of `NSTextView` and `UITextView`, laid out with TextKit 2, with:

- **Markdown**: see above
- **Styles**: `append(_:style:)` appends text in one of the `CardStyle`s, named for the Markdown they're written out
  as: `text`, `header` (`#`), `subheader` (`##`), `strong` and `code`, with `centered`, `centeredHeader` and `gray`,
  which Markdown doesn't have, written out as text, and `appendLink(_:text:)`,
  `appendNewline()` and `appendTab()`
- **Rules, Images, Buttons and Views**: `appendRule(color:width:)`, `appendImage(_:source:)`,
  `appendButton(_:image:action:)`, `appendButton(_:url:)`, `appendView(_:size:)`, which also embeds SwiftUI views
- **Columns**: `paragraphStyle(columns:)`, `pushColumns(_:)` and `useColumns(_:)` lay text out in columns
  with tab stops, `[.right(.fraction(0.33)), .left(.points(5))]` is a right tab a third of the way across
  the card and a left tab five points to the right of that, they're laid out again when the card is resized
- **Style Stack**: `push(_:)` a paragraph style to override the default while building a card, `popStyle()`
  to restore the previous one
- **Formatter Registry**: `register(_:for:)` a `Formatter` for a class, `appendFormatted(_:)` formats values
  with the formatter for their class or its closest superclass
- **Promises**: `appendPromise()` appends an ellipsis `…` to be replaced later, `fulfill(_:with:)` replaces it,
  as often as needed, with text built in the background
- **Editing**: `setBlock(_:)`, `toggleBold()`, `toggleItalic()`, `toggleCode()`, `insertRule()`,
  `insertImage(_:source:alt:)`, `insertLink(_:text:)` and `normalizeBlocks()` edit a card and keep its
  paragraphs tagged with their Markdown blocks, and `convertsTypedMarkdown` converts Markdown as it's typed:
  `**strong**`, `*emphasis*`, `` `code` ``, `~~strikethrough~~` and `[links](url)` when they're closed, `# `, `- `,
  `1. ` and `> ` at the start of a paragraph, and `---` and ```` ``` ```` lines when return is typed after them
- **tvOS**: `presentFullScreen(from:)` shows a card over the system's blur, scrolled with the remote

The core of the class is available to Objective-C, e.g. `[card appendString:@"Name" style:CardStyleStrong]`.

### [`NSMutableAttributedString+CardView`](./Sources/CardView/NSMutableAttributedString+CardView.swift)

The same `append…` methods, with a font size and paragraph style, for building a card's text in the background.

### [Attachments](./Sources/CardView/Attachments)

Attachments are drawn by views with TextKit 2's `NSTextAttachmentViewProvider` on every platform,
and follow light and dark mode:

- `CardRuleAttachment`: a rule from where it starts across the card
- `CardImageAttachment`: an image, scaled down to fit the card, template images are drawn in the text color,
  remote images load when they're shown
- `CardButtonAttachment`: a button with an action, or which opens a URL
- `CardViewAttachment`: any view, or a SwiftUI view, at its size or scaled down to fit the card
- `CardAttachment`: the base class, subclass it for attachments of your own

### [`CardFormatters`](./Sources/CardView/Formatters/CardFormatters.swift)

`Formatter` subclasses for the values on cards:

- `CardArrayFormatter`: arrays as lists, with a separator and a formatter for their items
- `CardDataFormatter`: data as its size, "420 Bytes", or as a hex dump
- `CardStringDataFormatter`: UTF data of any encoding as a string
- `CardURLFormatter`: URLs as links
- `CardPListDataFormatter`: property list data as its description
- `CardJSONObjectFormatter`: property lists as JSON
- `CardMarkdownFormatter`: property lists as Markdown lists
- `CardDateFormatter`: dates in the user's medium date and time format, `CardDateFormatter.local`
- `CardUnitsFormatter`: numbers with their units in gray text
- `CardBooleanFormatter`: numbers as "Yes" or "No"
- `CardBytesFormatter`: numbers as byte sizes
- `CardFractionFormatter`: numbers as fractions, with the continued fraction method
- `CardTimecodeFormatter`: time intervals as timecodes
- `CardFormattingTransformer`: a `ValueTransformer` which formats values with a `Formatter`

<a id="deck"></a>
## Deck

[Deck](./Sources/Deck) is a simple Markdown editor for decks of cards, for the Mac, iPhone, iPad and
Vision Pro, with a viewer on the TV. A deck is a package of Markdown files, one for each card, listed in order
in its `Deck.json`, with the cards' images in its `Images` folder. Deck opens plain Markdown files too,
with their cards separated by `<!-- card -->` lines.

<a id="Changes"></a>
## Changes

- `3.0.0` - Breaking API changes, CardView is written in Swift:
  - Adds Markdown reading and writing: `CardTextView.markdown`, `CardMarkdown`, `CardBlock`
  - Attachments drawn by views on every platform: rules, images, buttons and embedded views,
    which replace the `NSCell` based drawing
  - Editing commands, for editing cards and writing them out as Markdown, and Markdown converted as it's typed
  - `CardStyle`s are named for the Markdown they're written out as: `plain`, `label` and `monospace` are deprecated for `text`, `strong` and `code`
  - Deck is a Markdown editor for macOS, iOS and visionOS, and a viewer on tvOS
  - Requires macOS 14, iOS 17, tvOS 17 or visionOS 26, and TextKit 2
  - The classes keep their Objective-C names, e.g. `CardTextView` and `CardUnitsFormatter`, for Interface Builder and `NSClassFromString`, and the formatters' settings are key value coded

| 2.x | 3.0 |
| --- | --- |
| `appendHeader:`, `appendSubhead:`, `appendLabel:`, `appendGray:`, `appendCentered:`, `appendCenteredHeader:`, `appendMonospace:` | `append(_:style:)`, `[card appendString:style:]` |
| `plain`, `label`, `monospace` styles | `text`, `strong`, `code`, the old names are deprecated aliases in Swift, Objective-C has only the new `CardStyleText`, `CardStyleStrong` and `CardStyleCode` |
| `appendStyled:string:` | `append(_:style:)` |
| `appendLink:text:` with a string | `appendLink(_:text:)` with a `URL` |
| `appendRuleWithAccentColor` | `appendRule(color: .controlAccentColor)` |
| `appendImage:withAttributes:target:action:` | `appendButton(_:image:action:)` |
| `pushColumns:`/`useColumns:` with `NSNumber`s | `pushColumns(_:)`/`useColumns(_:)` with `CardColumn`s, the `NSNumber`s still work from Objective-C |
| `paragraphStyleForColumns:` | `paragraphStyle(columns:)` |
| `pushStyle:` | `push(_:)` |
| `appendPromiseWithAttributes:`, `fulfillPromise:withString:` | `appendPromise(attributes:)`, `fulfill(_:with:)` |
| `registerFormatter:forClass:` | `register(_:for:)` |
| `append:withFormatter:andAttributes:` | `append(_:formatter:attributes:)` |
| `CardRuleCell`, `CardImageCell`, `CardTemplateImageCell`, `CardActionCell`, `CardViewCell` | `CardRuleAttachment`, `CardImageAttachment`, `CardButtonAttachment`, `CardViewAttachment` |
| `CardTextStyle` protocol, `+textStyle:fontSize:graphStyle:` | `CardStyle.attributes(fontSize:paragraph:)` |
| `CardFormatters` | `CardFormatter` |
| `CardListFormatter` | `CardArrayFormatter` |
| `+[CardDateFormatter localDateFormatter]` | `CardDateFormatter.local` |
| `+[CardURLFormatter formatterWithLinkColor:]` | `CardURLFormatter(linkColor:)` |
| `+[CardFormattingTransformer setFormattingTransformer:forName:]` | `CardFormattingTransformer.register(_:name:)` |
| `columns` property | removed, use `pushColumns(_:)` |

- `2.0.1` - [12 Apr 2026](../../releases/tag/2.0.1)
  - many small fixes

- `2.0.0` - [28 Apr 2025](../../releases/tag/2.0.0) 
  - Breaking API changes: 
    - `CardTextView` is simplifed and tersified
    - `+formatted:withAttributes:` is now a class method
    - `CardSeperatorCell` -> `CardRuleCell`
    - Remove `CardViewDelegate` inteface
  - Adds `CardTextStyle` inteface for stying strings
  - Adds `NSMutableAttributedString+CardView`
  - Adds Promises and Style Stack to `CardTextView`
  - Hex formatter for abritrary data
  - Depend on ILFoundation

- `1.3`   — [19 Aug 2024](../../releases/tag/1.3)
  - Swift Package Manager Support

- `1.2`   – [19 May 2017](../../releases/tag/1.2)

- `1.1`   — [29 May 2016](../../releases/tag/1.1)
  - Add CardBytesFormatter

- `1.0.1` — [13 May 2016](../../releases/tag/1.0.1)
  - Add CardListFormatter

- `1.0`   — [27 Apr 2016](../../releases/tag/1.0)
  - First!

========

<a id="license"></a>
## License

    The MIT License (MIT)

    Copyright © 2014-2026 Alf Watt

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NON INFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
