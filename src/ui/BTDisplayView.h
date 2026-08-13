#import <Cocoa/Cocoa.h>

// The readout between the transport controls and the search field: what is
// playing, how far in, and a scrubbable progress bar. It follows the player and
// the iPod sync on its own, so there is nothing to drive from outside.
// Anything slow enough to need saying so shows it here, in the readout, rather
// than in the pane doing the work. userInfo carries "title", "message", and
// "fraction".
extern NSString *const BTDisplayProgressNotification;
extern NSString *const BTDisplayProgressDidEndNotification;

@interface BTDisplayView : NSView

// How tall the readout has to be for what it holds: two lines of type, the
// scrub bar, and the times beside it. Asked rather than assumed, since all three
// follow the size of the type and the chrome has to leave room for them.
+ (CGFloat)naturalHeight;

@end
