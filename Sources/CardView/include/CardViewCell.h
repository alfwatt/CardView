@import KitBridge;

#if IL_APP_KIT
@interface CardViewCell : NSTextAttachmentCell
@property(nonatomic,retain) ILView* cellView;

+ (instancetype) cellWithView:(NSView*) view;

// MARK: -

- (instancetype) initWithView:(NSView*) view;

@end
#endif
