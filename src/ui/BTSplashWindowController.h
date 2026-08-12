#import <Cocoa/Cocoa.h>

// The startup splash. Shows the logo for at least a second, and longer if the
// library is still loading.
@interface BTSplashWindowController : NSWindowController

// Returns nil when there is no splash image in the bundle, so a build without
// artwork simply starts without one.
+ (instancetype)splashController;

- (void)showSplash;

// Runs the block once the splash has been up for its minimum time, then closes.
- (void)dismissAfterMinimumTime:(void (^)(void))completion;

@end
