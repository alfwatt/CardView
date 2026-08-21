@import KitBridge;
#import "CardTextStyle.h"

NS_ASSUME_NONNULL_BEGIN

/// constants for -appendImage:withAttributes:target:action:
extern NSString* const CardTextAttachmentActionName;
extern NSString* const CardTextAttacmentTargetName;

@interface NSMutableAttributedString (CardView) <CardTextStyle>

@end

NS_ASSUME_NONNULL_END
