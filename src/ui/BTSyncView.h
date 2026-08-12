#import <Cocoa/Cocoa.h>

@class BTIPod;

// The pane shown when the iPod is selected in the source list: the playlists,
// each with a checkbox on the right, a folder reflecting the state of what is
// inside it, and the buttons to sync and to eject.
@interface BTSyncView : NSView

@property (nonatomic, strong) BTIPod *iPod;

- (void)reload;

@end
