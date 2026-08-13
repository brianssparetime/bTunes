#import <Cocoa/Cocoa.h>
#import "BTControls.h"

// The views and cells the main window is built from.
//
// None of them knows anything about the controller: each draws what it is given
// and sends what it is clicked on up the responder chain. That is why they can
// sit apart from the two thousand lines that arrange them, and it is the line
// the split was made along.

// The strip along the top holding the transport, the readout and the search
// field. The readout and the search field are placed by hand on every resize,
// so the readout can take the slack rather than leaving a gap beside it.
@interface BTChromeView : NSView
@property (nonatomic, copy) void (^layoutHandler)(void);
@end

// The strip along the bottom: how many songs, how long they run, how much disk.
@interface BTBottomBarView : NSView
@property (nonatomic, copy) NSString *statusText;
@end

// A row in the source list: a drawn icon, the name, and an eject mark on a
// device.
@interface BTSourceCell : NSTextFieldCell
@property (nonatomic, strong) NSImage *icon;
@property (nonatomic, assign) BOOL showsEject;

// Where the eject mark sits inside a row, so the row and the click test agree.
+ (NSRect)ejectRectInFrame:(NSRect)frame;
@end

// A track number that shows the speaker instead of the number while its row is
// the one playing, so the indicator needs no column of its own.
@interface BTTrackNumberCell : NSTextFieldCell
@property (nonatomic, strong) NSImage *indicator;
@end

// What a list tells its delegate when the delete key is pressed in it.
@protocol BTKeyTableDelegate <NSObject>
- (void)tableViewDeletePressed:(NSTableView *)tableView;
@end

// The window itself, which catches transport keys that no view claimed.
@interface BTMainWindow : NSWindow
@end

// The two lists. Both answer the delete key; the outline view also opens and
// closes a folder with the arrows, and ejects when the eject mark is clicked.
@interface BTKeyTableView : BTListTableView
@end

@interface BTKeyOutlineView : BTListOutlineView
@end
