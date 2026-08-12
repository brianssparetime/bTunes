#import <Cocoa/Cocoa.h>

// The readout between the transport controls and the search field: what is
// playing, how far in, and a scrubbable progress bar.
@interface BTDisplayView : NSView
- (void)refresh;
@end
