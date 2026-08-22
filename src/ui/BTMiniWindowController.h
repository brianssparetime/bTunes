#import <Cocoa/Cocoa.h>

// Mini mode. Unlike iTunes 4's small player, this one is shaped like classic
// Winamp: a compact dark panel with the analyzer bars. Leaving mini mode
// returns to the full window.
@interface BTMiniWindowController : NSWindowController
- (instancetype)initMiniPlayer;

// The corner the small player was last left in is its own, kept apart from the
// full window's and across a restart. Placing it beside another window is the
// fallback for a machine that has never had it anywhere.
- (void)placeAtTopLeftOfWindow:(NSWindow *)other;
- (void)rememberPlace;
@end
