#import <Cocoa/Cocoa.h>

// The pane that shows podcasts. It takes the place of the song list on the
// right while the podcasts row is chosen, the same way the iTunes sync pane
// does, and gives that back when anything else is picked.
//
// Shows on the left, that show's episodes on the right, laid out like the song
// list because an episode is a track and the columns already know how to say so.
@interface BTPodcastView : NSView

// Reads the podcasts folder again. Whatever was selected stays selected when it
// is still there, so a rescan does not throw away the reader's place.
- (void)reload;

@end
