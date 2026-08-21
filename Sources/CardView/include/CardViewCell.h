#if __has_include(<KitBridge/KitBridge.h>)
#import <KitBridge/KitBridge.h>
#else
@import KitBridge;
#endif

#if IL_APP_KIT
@interface CardViewCell : NSTextAttachmentCell
@property(nonatomic,retain) ILView* cellView;

+ (instancetype) cellWithView:(NSView*) view;

// MARK: -

- (instancetype) initWithView:(NSView*) view;

@end
#endif
