#if SWIFT_PACKAGE || __has_feature(modules)
#import "CardViewKitBridge.h"
#import "CardTextView.h"
#import "CardFormatters.h"
#import "NSMutableAttributedString+CardView.h"

#ifdef IL_APP_KIT
#import "CardActionCell.h"
#import "CardImageCell.h"
#import "CardRuleCell.h"
#import "CardViewCell.h"
#endif // IL_APP_KIT

#else

#import <CardView/CardViewKitBridge.h>
#import <CardView/CardTextView.h>
#import <CardView/CardFormatters.h>
#import <CardView/NSMutableAttributedString+CardView.h>

#ifdef IL_APP_KIT
#import <CardView/CardActionCell.h>
#import <CardView/CardImageCell.h>
#import <CardView/CardRuleCell.h>
#import <CardView/CardViewCell.h>
#endif // IL_APP_KIT

#endif
