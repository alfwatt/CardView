#if __has_include(<KitBridge/KitBridge.h>)
#import <KitBridge/KitBridge.h>
#else
@import KitBridge;
#endif
#if __has_include(<CardView/CardTextStyle.h>)
#import <CardView/CardTextStyle.h>
#else
#import "CardTextStyle.h"
#endif

NS_ASSUME_NONNULL_BEGIN

/// constants for -appendImage:withAttributes:target:action:
extern NSString* const CardTextAttachmentActionName;
extern NSString* const CardTextAttacmentTargetName;

@interface NSMutableAttributedString (CardView) <CardTextStyle>

@end

NS_ASSUME_NONNULL_END
