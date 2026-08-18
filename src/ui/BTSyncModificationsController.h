#import <Cocoa/Cocoa.h>

@class BTITunesSyncModification;

// What the window shows and what ticking a row does. The window holds no
// choices of its own: every tick belongs to the sync pane, so closing the
// window and opening it again shows the same answers.
@protocol BTSyncModificationsSource <NSObject>
- (NSArray *)syncModifications;                                    // BTITunesSyncModification
- (BOOL)modificationIsChosen:(BTITunesSyncModification *)addition;
- (BOOL)modificationCanBeChosen:(BTITunesSyncModification *)addition;
- (NSString *)wordForModification:(BTITunesSyncModification *)addition;
- (void)setModification:(BTITunesSyncModification *)addition chosen:(BOOL)chosen;
// The window has gone, by its close button or by escape, so the button that
// opened it can say so.
- (void)modificationsWindowClosed;
@end

// The songs iTunes has added to playlists that are already here, one to a row.
//
// A window rather than a drawer under the two lists. These are the pairs a sync
// settles into once the library has been imported, so the list is routinely the
// longest thing in the pane, and squeezing it in under two lists that also want
// the room leaves all three too short to read.
@interface BTSyncModificationsController : NSWindowController

- (instancetype)initWithSource:(id <BTSyncModificationsSource>)source;

// The ticks are kept by the sync pane, so anything ticked over there has to be
// redrawn here.
- (void)refresh;

@end
