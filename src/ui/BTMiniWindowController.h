#import <Cocoa/Cocoa.h>

// Mini mode. Unlike iTunes 4's small player, this one is shaped like classic
// Winamp: a compact dark panel with the analyzer bars. Leaving mini mode
// returns to the full window.
@interface BTMiniWindowController : NSWindowController
- (instancetype)initMiniPlayer;
@end
