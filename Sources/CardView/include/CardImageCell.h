#if __has_include(<KitBridge/KitBridge.h>)
#import <KitBridge/KitBridge.h>
#else
@import KitBridge;
#endif

#if IL_APP_KIT
@interface CardImageCell : NSTextAttachmentCell {
    NSImageCell* image_cell;
}

+ (CardImageCell*) cellWithImage:(NSImage*) cell_image;

- (id) initWithImage:(NSImage*) cell_image;

@end

// MARK: -

/// Draws a template image in the label color of the appearance it's drawn in, so it follows light and dark mode
@interface CardTemplateImageCell : NSTextAttachmentCell

@end
#endif
