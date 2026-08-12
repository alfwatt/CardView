#import "CardViewKitBridge.h"

#if SWIFT_PACKAGE || __has_feature(modules)
#import "CardTextStyle.h"
#else
#import <CardView/CardTextStyle.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/// constants for -appendImage:withAttributes:target:action:
extern NSString* const CardTextAttachmentActionName;
extern NSString* const CardTextAttacmentTargetName;

@interface NSMutableAttributedString (CardView) <CardTextStyle>

@end

NS_ASSUME_NONNULL_END
