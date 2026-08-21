#if __has_include(<KitBridge/KitBridge.h>)
#import <KitBridge/KitBridge.h>
#else
@import KitBridge;
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

- (nullable NSAttributedString*) append:(NSString*) string size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (nullable NSAttributedString*) append:(NSString*) string textStyle:(CardStyle) textStyle size:(CGFloat) fontSize style:(NSParagraphStyle*) graphStyle;

- (nullable NSAttributedString*) appendHeader:(NSString*) string size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (nullable NSAttributedString*) appendSubhead:(NSString*) string size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (nullable NSAttributedString*) appendCentered:(NSString*) string size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (nullable NSAttributedString*) appendLabel:(NSString*) string size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (nullable NSAttributedString*) appendGray:(NSString*) string size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (nullable NSAttributedString*) appendMonospace:(NSString*) string size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (nullable NSAttributedString*) appendLink:(NSString*) url text:(NSString*) label size:(CGFloat) fontSize style:(NSParagraphStyle*) style;

// MARK: - Rules & Spacing

- (nullable NSAttributedString*) appendRule:(NSParagraphStyle*) style;
- (nullable NSAttributedString*) appendRuleWithAccentColor:(NSParagraphStyle*) style;
- (nullable NSAttributedString*) appendRuleWithColor:(ILColor*) color width:(CGFloat) width style:(NSParagraphStyle*) style;
- (nullable NSAttributedString*) appendNewline:(CGFloat) size style:(NSParagraphStyle*) style;
- (nullable NSAttributedString*) appendTab:(CGFloat) size style:(NSParagraphStyle*) style;

// MARK: - Images

- (nullable NSAttributedString*) appendImage:(ILImage*) image size:(CGFloat) fontSize style:(NSParagraphStyle*) style;
- (nullable NSAttributedString*) appendImage:(ILImage*) image withAttributes:(NSDictionary*) attributes;
- (nullable NSAttributedString*) appendImage:(ILImage*) image withAttributes:(NSDictionary*) attributes target:(nullable id) target action:(SEL) action;

@end

NS_ASSUME_NONNULL_END
