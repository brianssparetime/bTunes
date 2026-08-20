#import <Cocoa/Cocoa.h>

@class BTTrack;

// The pane that shows podcasts. It takes the place of the song list on the
// right while the podcasts row is chosen, the same way the iTunes sync pane
// does, and gives that back when anything else is picked.
//
// Shows on the left, that show's episodes on the right, laid out like the song
// list because an episode is a track and the columns already know how to say so.
@interface BTPodcastView : NSView

// What the count along the bottom of the window should say while this pane is
// up: how many episodes the chosen show holds, how long they run, and how much
// disk they take. Said in the same shape as the song list's own count.
//
// Handed over rather than written here, because the bar belongs to the window.
// Called whenever the answer changes, including when the lengths finish being
// read, which is a while after the list first appears.
@property (nonatomic, copy) void (^statusDidChange)(NSString *status);

// The episodes on screen, in the order they are shown, and which one the
// transport button should start. The window's play button belongs to whatever
// list is in front of the reader, and while this pane is up the episodes of the
// chosen show are that list. Without these the button reads the song list
// behind the pane, finds it empty, and does nothing at all.
- (NSArray *)listedEpisodes;
- (BTTrack *)episodeToStart;

// Reads the podcasts folder again. Whatever was selected stays selected when it
// is still there, so a rescan does not throw away the reader's place.
- (void)reload;

// Says it again, for a window that has just put the pane back on screen and
// needs the bar to agree with what is in front of the reader.
- (void)reportStatusNow;

@end
