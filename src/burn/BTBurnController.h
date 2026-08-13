#import <Cocoa/Cocoa.h>

@class BTPlaylist;

// The one dialog a burn gets. Everything is chosen here, before anything is
// written, because after that point the disc is either right or it is scrap.
@interface BTBurnController : NSWindowController

// Puts the dialog up as a sheet, and burns if it is accepted. One at a time:
// there is one drive and a burn holds it for its whole length.
+ (void)burnPlaylist:(BTPlaylist *)playlist modalForWindow:(NSWindow *)parent;

// Whether a dialog is up or a disc is being written. There is one drive, so a
// second burn has nowhere to go and the menu says so rather than beeping.
+ (BOOL)isBusy;

@end
