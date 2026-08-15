#import <Cocoa/Cocoa.h>

// The equalizer window, opened from the Controls menu.
//
// One window, kept for the life of the application rather than rebuilt, because
// it holds no state of its own: the sliders read the shared equalizer and write
// back to it, and the sound follows whether or not the window is open.
@interface BTEqualizerController : NSWindowController

+ (instancetype)sharedController;

@end
