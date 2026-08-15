#import <Cocoa/Cocoa.h>

@class BTSourceList, BTPlaylist, BTIPod, BTAudioDisc;

// The three rows that are not objects: the whole library, the same songs in
// the order iTunes recorded them being added, and the place music comes over
// from iTunes.
//
// Compared by pointer rather than by their words, so these are the constants to
// test against and not equal strings written out again somewhere else.
extern NSString *const BTLibrarySource;
extern NSString *const BTRecentlyAddedSource;
extern NSString *const BTITunesSyncSource;

// The list holds three kinds of row: the library and its by-date view, a device,
// and playlists. Anything reaching for a playlist's own members has to ask
// first, because the other two answer none of them and a bare cast crashes on
// the first message sent.
BTPlaylist *BTPlaylistFromSource(id item);

@protocol BTSourceListDelegate <NSObject>

// A different row is chosen. What that means to the rest of the window is the
// window's business, which is the whole reason the chosen row is asked for here
// rather than kept here.
- (void)sourceListSelectionDidChange:(BTSourceList *)list;

// The delete key, in the list.
- (void)sourceListDeletePressed:(BTSourceList *)list;

// A folder was opened or closed. Which ones are shut is part of the session,
// and the window is what writes that down.
- (void)sourceListFoldersDidChange:(BTSourceList *)list;

// The three ways a row changes something. Handed over rather than done here,
// because every change to a playlist has to be one that can be taken back, and
// the undo manager belongs to the window.
- (void)sourceList:(BTSourceList *)list
    renamePlaylist:(BTPlaylist *)playlist
                to:(NSString *)name;
- (void)sourceList:(BTSourceList *)list
       addTrackIDs:(NSArray *)trackIDs
        toPlaylist:(BTPlaylist *)playlist;
- (void)sourceList:(BTSourceList *)list
      movePlaylist:(BTPlaylist *)playlist
          toFolder:(BTPlaylist *)folder;

@end

// The left bar: the library, a disc, Recently Added, an attached iPod, and the
// playlists under them.
//
// It owns the rows and everything done to them — how they are arranged, what
// mark each wears, renaming, opening and closing folders, and both kinds of drag
// — and reports what was chosen. It decides nothing about what the rest of the
// window then shows.
@interface BTSourceList : NSObject

- (instancetype)initWithDelegate:(id<BTSourceListDelegate>)delegate;

// The list inside its scroller. The scroll view is what goes in a split view;
// the outline view is what holds the keyboard and answers about rows.
@property (nonatomic, readonly) NSScrollView *scrollView;
@property (nonatomic, readonly) NSOutlineView *outlineView;

// What the tree holds besides the library and the playlists. Setting either
// rebuilds the rows.
@property (nonatomic, strong) BTIPod *iPod;
@property (nonatomic, strong) BTAudioDisc *disc;

// The row chosen now, or nil when none is.
@property (nonatomic, readonly) id selectedSource;
// The same, when it is a playlist rather than the library, a device, or nothing.
@property (nonatomic, readonly) BTPlaylist *selectedPlaylist;

// The row a click actually landed on, and nil when none did. Strict, because
// the eject mark asks this: falling back to the selection would eject whatever
// happened to be highlighted rather than the device that was clicked.
@property (nonatomic, readonly) id clickedSource;

// The playlist a menu item should act on: the row right-clicked, or the row
// selected when the menu came from the menu bar and nothing was clicked at all.
@property (nonatomic, readonly) BTPlaylist *clickedPlaylist;

// Folders somebody closed by hand, by playlist id. The list is rebuilt whenever
// the library changes, so without this a folder would open again every time a
// song was added. Handed over at startup and read back as it changes.
@property (nonatomic, copy) NSArray *closedFolderIDs;

// Rebuilds the rows and puts the folders back the way they were left.
- (void)reload;

// Opens whatever folders it takes to bring a row into view and selects it.
// Selecting a row this way tells the delegate, the same as clicking it would.
- (void)selectSource:(id)source;

// A new playlist appears with its name ready to be typed over, which is the one
// moment renaming is offered without being asked for twice.
- (void)selectPlaylistForRenaming:(BTPlaylist *)playlist;

// The one column is the whole width of the pane. Set by hand rather than left
// to an autoresizing style, because the outline view sits inside a scroll view
// whose width is what the column has to match.
- (void)sizeColumnToPane;

@end
