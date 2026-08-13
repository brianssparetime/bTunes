#import <Cocoa/Cocoa.h>

// The pane that brings music over from iTunes. It takes the place of the song
// list on the right while it is up, and gives that back when the sync finishes
// or when anything is picked in the source list.
//
// Nothing here writes to iTunes. The comparison reads the library file and the
// import records where songs already sit.
@interface BTITunesSyncView : NSView

// Called once the sync has run, so the window can go back to whatever it was
// showing before.
@property (nonatomic, copy) void (^didFinish)(void);

// Reads and compares, off the main thread, saying what it is doing meanwhile.
// Safe to call again; a comparison already running is left to finish.
- (void)beginComparing;

@end
