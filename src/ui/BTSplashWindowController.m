#import "BTSplashWindowController.h"

// VideoSlideshow holds its splash for as long as loading takes, which lands
// around two and a half seconds. BTunes loads faster than that, so it holds the
// splash to the same floor rather than flashing it.
#define BT_SPLASH_MINIMUM_SECONDS 2.5

@interface BTSplashImageView : NSImageView
@end

@implementation BTSplashImageView
// The window is borderless and transparent, so clicks should not fall through
// to whatever is behind it while the splash is up.
- (void)mouseDown:(NSEvent *)event { }
@end

@implementation BTSplashWindowController {
    NSDate *_shownAt;
}

+ (NSImage *)splashImage {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"btunes-splash" ofType:@"png"];
    if (path == nil) path = [[NSBundle mainBundle] pathForResource:@"BTunes" ofType:@"icns"];
    if (path == nil) return nil;
    return [[NSImage alloc] initWithContentsOfFile:path];
}

+ (instancetype)splashController {
    NSImage *image = [self splashImage];
    if (image == nil) return nil;

    NSSize size = [image size];
    if (size.width < 1 || size.height < 1) return nil;
    if (size.width > 420) {
        size = NSMakeSize(420, 420 * size.height / size.width);
    }

    NSRect frame = NSMakeRect(0, 0, size.width, size.height);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSBorderlessWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setOpaque:NO];
    [window setBackgroundColor:[NSColor clearColor]];
    [window setHasShadow:YES];
    [window setLevel:NSStatusWindowLevel];
    [window setIgnoresMouseEvents:NO];

    BTSplashImageView *view = [[BTSplashImageView alloc] initWithFrame:frame];
    [view setImageScaling:NSImageScaleProportionallyUpOrDown];
    [view setImage:image];
    [window setContentView:view];
    [window center];

    return [[self alloc] initWithWindow:window];
}

- (void)showSplash {
    _shownAt = [NSDate date];
    [[self window] makeKeyAndOrderFront:nil];
    [[self window] display];
}

- (void)dismissAfterMinimumTime:(void (^)(void))completion {
    NSTimeInterval shown = _shownAt ? -[_shownAt timeIntervalSinceNow] : BT_SPLASH_MINIMUM_SECONDS;
    NSTimeInterval remaining = BT_SPLASH_MINIMUM_SECONDS - shown;
    if (remaining < 0) remaining = 0;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[self window] orderOut:nil];
        if (completion) completion();
    });
}

@end
