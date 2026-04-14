#if SWIFT_PACKAGE
@import KitBridge;
#else
#import <KitBridge/KitBridge.h>
#endif

NS_ASSUME_NONNULL_BEGIN

/// @enum CardStyle Defines the various text styles
typedef NS_ENUM(NSUInteger, CardStyle) {
    CardPlainStyle,
    CardHeaderStyle,
    CardSubheaderStyle,
    CardCenteredStyle,
    CardLabelStyle,
    CardGrayStyle,
    CardMonospaceStyle
};

// MARK: -

@protocol CardTextStyle

// MARK: - Attributes

/// @return attributes for the
/// @param textStyle provided at the
/// @param fontSize  provided with the
/// @param graphStyle provided
///
+ (NSDictionary*) textStyle:(CardStyle) textStyle fontSize:(CGFloat) fontSize graphStyle:(NSParagraphStyle*) graphStyle;

// MARK: - Styles

- (NSAttributedString*) append:(NSString*) string size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (NSAttributedString*) append:(NSString*) string textStyle:(CardStyle) textStyle size:(CGFloat) fontSize style:(NSParagraphStyle*) graphStyle;

- (NSAttributedString*) appendHeader:(NSString*) string size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (NSAttributedString*) appendSubhead:(NSString*) string size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (NSAttributedString*) appendCentered:(NSString*) string size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (NSAttributedString*) appendLabel:(NSString*) string size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (NSAttributedString*) appendGray:(NSString*) string size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (NSAttributedString*) appendMonospace:(NSString*) string size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (NSAttributedString*) appendLink:(NSString*) url text:(NSString*) label size:(CGFloat) fontSize style:(NSParagraphStyle*) style;

// MARK: - Rules & Spacing

- (NSAttributedString*) appendRule:(NSParagraphStyle*) style;
- (NSAttributedString*) appendRuleWithAccentColor:(NSParagraphStyle*) style;
- (NSAttributedString*) appendRuleWithColor:(ILColor*) color width:(CGFloat) width style:(NSParagraphStyle*) style;
- (NSAttributedString*) appendNewline:(CGFloat) size style:(NSParagraphStyle*) style;
- (NSAttributedString*) appendTab:(CGFloat) size style:(NSParagraphStyle*) style;

// MARK: - Images

- (NSAttributedString*) appendImage:(ILImage*) image size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (NSAttributedString*) appendImage:(ILImage*) image withAttributes:(NSDictionary*) attributes;
- (NSAttributedString*) appendImage:(ILImage*) image withAttributes:(NSDictionary*) attributes target:(nullable id) target action:(SEL) action;

@end

NS_ASSUME_NONNULL_END
