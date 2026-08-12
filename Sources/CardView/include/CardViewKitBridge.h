#ifndef CARD_VIEW_KIT_BRIDGE_H
#define CARD_VIEW_KIT_BRIDGE_H

#if SWIFT_PACKAGE
#import "KitBridge.h"
#elif __has_feature(modules)
#import <TargetConditionals.h>

#if TARGET_OS_IPHONE || TARGET_OS_TV
#import <UIKit/UIKit.h>
#define ILColor UIColor
#define ILImage UIImage
#define ILTextView UITextView
#define ILView UIView
#define IL_UI_KIT 1
#elif TARGET_OS_OSX
#import <AppKit/AppKit.h>
#define ILColor NSColor
#define ILImage NSImage
#define ILTextView NSTextView
#define ILView NSView
#define IL_APP_KIT 1
#endif

@protocol ILViewLifecycle;
#else
#import <KitBridge/KitBridge.h>
#endif

#endif
