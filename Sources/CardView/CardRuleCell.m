#import "include/CardRuleCell.h"

#if IL_APP_KIT
@implementation CardRuleCell

+ (NSAttributedString*) separator  {
    NSTextAttachment* divider = NSTextAttachment.new;
    [divider setAttachmentCell:[CardRuleCell.alloc initWithColor:ILColor.grayColor width:1]];
    return [NSAttributedString attributedStringWithAttachment:divider];
}

+ (NSAttributedString*) separatorWithColor:(NSColor*) color {
    NSTextAttachment* divider = NSTextAttachment.new;
    [divider setAttachmentCell:[CardRuleCell.alloc initWithColor:color width:1]];
    return [NSAttributedString attributedStringWithAttachment:divider];
}

+ (NSAttributedString*) separatorWithColor:(NSColor*) color width:(CGFloat) width {
    NSTextAttachment* divider = NSTextAttachment.new;
    CardRuleCell* cell = [CardRuleCell.alloc initWithColor:color width:width];
    [divider setAttachmentCell:cell];
    return [NSAttributedString attributedStringWithAttachment:divider];
}

// MARK: -

- (id) initWithColor:(NSColor*) color width:(CGFloat) width {
    if ((self = super.init)) {
        self.separator_color = color;
        self.separator_width = width;
    }
    return self;
}

// MARK: - NSTextAttachmentCell

- (NSRect) cellFrameForTextContainer:(NSTextContainer*)textContainer proposedLineFragment:(NSRect)lineFrag glyphPosition:(NSPoint)position characterIndex:(NSUInteger)charIndex {
	NSRect frag = [super cellFrameForTextContainer:textContainer proposedLineFragment:lineFrag glyphPosition:position characterIndex:charIndex];
	NSSize size = textContainer.containerSize;
	size.width -= (2.0 * textContainer.lineFragmentPadding); // remove the padding
	
	frag.size.width = (size.width - frag.origin.x);
    frag.size.height = (self.separator_width + 2);
	return frag;
}

- (void) drawWithFrame:(NSRect)frame inView:(NSView*)aView {
    [NSGraphicsContext saveGraphicsState];
    [self.separator_color set];

    NSPoint start = NSMakePoint(frame.origin.x,
                                (frame.origin.y + (frame.size.height / 2)));
    NSPoint finish = NSMakePoint((frame.origin.x + frame.size.width), 
                                 (frame.origin.y + (frame.size.height / 2)));
    [NSBezierPath setDefaultLineWidth:self.separator_width];
	[NSBezierPath strokeLineFromPoint:start toPoint:finish];
    [NSGraphicsContext restoreGraphicsState];
}

@end
#endif

#if IL_UI_KIT
@implementation CardRuleCell

+ (NSAttributedString*) separatorWithColor:(ILColor*) color width:(CGFloat) width {
    return [NSAttributedString attributedStringWithAttachment:[CardRuleCell.alloc initWithColor:color width:width]];
}

- (id) initWithColor:(ILColor*) color width:(CGFloat) width {
    if ((self = [super initWithData:nil ofType:nil])) {
        self.separator_color = color;
        self.separator_width = width;
    }
    return self;
}

// MARK: - NSTextAttachment

/// from where the rule starts to the right of the text
- (CGRect) attachmentBoundsForTextContainer:(NSTextContainer*) textContainer proposedLineFragment:(CGRect) lineFrag
                              glyphPosition:(CGPoint) position characterIndex:(NSUInteger) charIndex {
    CGFloat width = textContainer.size.width - (2.0 * textContainer.lineFragmentPadding) - position.x;
    return CGRectMake(0, 0, MAX(width, 1), self.separator_width + 2);
}

/// the line drawn at the size of the bounds, in the color as the view's appearance resolves it
- (UIImage*) imageForBounds:(CGRect) imageBounds textContainer:(NSTextContainer*) textContainer characterIndex:(NSUInteger) charIndex {
    UITraitCollection* traits = UITraitCollection.currentTraitCollection; // the text view's, as it draws
    UIColor* color = [self.separator_color resolvedColorWithTraitCollection:traits];
    UIGraphicsImageRendererFormat* format = UIGraphicsImageRendererFormat.preferredFormat;
    format.opaque = NO;
    return [[UIGraphicsImageRenderer.alloc initWithSize:imageBounds.size format:format] imageWithActions:^(UIGraphicsImageRendererContext* context) {
        [color setFill];
        UIRectFill(CGRectMake(0, (imageBounds.size.height - self.separator_width) / 2, imageBounds.size.width, self.separator_width));
    }];
}

@end
#endif
