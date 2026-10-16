#if __has_include(<KitBridge/KitBridge.h>)
#import <KitBridge/KitBridge.h>
#else
@import KitBridge;
#endif

#if __has_include(<CardView/CardTextView.h>)
#import <CardView/CardTextView.h>
#import <CardView/CardFormatters.h>
#import <CardView/NSMutableAttributedString+CardView.h>
#import <CardView/CardRuleCell.h>

#ifdef IL_APP_KIT
#import <CardView/CardActionCell.h>
#import <CardView/CardImageCell.h>
#import <CardView/CardViewCell.h>
#endif // IL_APP_KIT

#else

#import "CardTextView.h"
#import "CardFormatters.h"
#import "NSMutableAttributedString+CardView.h"
#import "CardRuleCell.h"

#ifdef IL_APP_KIT
#import "CardActionCell.h"
#import "CardImageCell.h"
#import "CardViewCell.h"
#endif // IL_APP_KIT

#endif


