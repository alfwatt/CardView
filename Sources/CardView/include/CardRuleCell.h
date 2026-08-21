#if __has_include(<KitBridge/KitBridge.h>)
#import <KitBridge/KitBridge.h>
#else
@import KitBridge;
#endif

#if IL_APP_KIT
/// Draws a separator in an CardView
@interface CardRuleCell : NSTextAttachmentCell
@property(nonatomic,retain) ILColor* separator_color;
@property(nonatomic,assign) CGFloat separator_width;

+ (NSAttributedString*) separator;
+ (NSAttributedString*) separatorWithColor:(ILColor*) color;
+ (NSAttributedString*) separatorWithColor:(ILColor*) color width:(CGFloat) width;

- (id) initWithColor:(ILColor*) color width:(CGFloat) width;

@end
#endif
