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
- (void)importITunesLibrary:(id)sender;
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
