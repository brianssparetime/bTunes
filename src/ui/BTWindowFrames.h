#import <Cocoa/Cocoa.h>

// Where a window was last left, remembered per window rather than per
// application. The full window and the small player keep separate corners of
// the screen, so switching between them moves neither, and both survive a
// restart.

extern NSString * const BTMainWindowFrameName;
extern NSString * const BTMiniWindowFrameName;

// Position and size. Answers NO when nothing has been saved under that name,
// which is the caller's cue to place the window itself.
BOOL BTRestoreWindowFrame(NSWindow *window, NSString *name);

// Position alone, keeping the window's top left corner where it was left. For
// a window whose size is fixed in the code: a frame saved before that size
// changed must not be allowed to resize it.
BOOL BTRestoreWindowPosition(NSWindow *window, NSString *name);

void BTSaveWindowFrame(NSWindow *window, NSString *name);
