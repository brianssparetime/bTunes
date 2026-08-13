#import <Cocoa/Cocoa.h>

// The full window: transport and readout across the top, sources on the left,
// the three browser columns above the track list, shuffle and repeat at the
// bottom right.
@interface BTMainWindowController : NSWindowController

- (instancetype)initMainWindow;
- (void)reloadEverything;

- (void)newPlaylist:(id)sender;
- (void)newSmartPlaylist:(id)sender;
- (void)newPlaylistFolder:(id)sender;
- (void)editSmartPlaylist:(id)sender;
- (void)addToLibrary:(id)sender;
// Opens the pane that brings music over from iTunes, and closes it again if it
// is already up. The only way in: the sync compares, shows what is new, and
// lets it be chosen.
- (void)showITunesSync:(id)sender;
// Makes an audio CD of the selected playlist. Everything is settled in one
// dialog before anything is written.
- (void)burnPlaylist:(id)sender;
- (void)deleteSelection:(id)sender;
- (void)playPause:(id)sender;
- (void)nextTrack:(id)sender;
- (void)previousTrack:(id)sender;
- (void)toggleShuffle:(id)sender;
- (void)cycleRepeat:(id)sender;
- (void)toggleMute:(id)sender;
- (void)volumeUp:(id)sender;
- (void)volumeDown:(id)sender;
- (void)focusSearch:(id)sender;
- (void)getInfo:(id)sender;

@end
