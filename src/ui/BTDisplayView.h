#import <Cocoa/Cocoa.h>

// The readout between the transport controls and the search field: what is
// playing, how far in, and a scrubbable progress bar. It follows the player and
// the iPod sync on its own, so there is nothing to drive from outside.
@interface BTDisplayView : NSView
@end
