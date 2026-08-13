#import "BTITunesSyncView.h"
#import "BTStyle.h"
#import "BTControls.h"
#import "BTITunesSync.h"
#import "BTLibrary.h"
#import "BTPreferences.h"
#import "BTPlaylist.h"
#import "BTDisplayView.h"

// Which columns are shown is remembered, since a reader who hides the ones that
// cannot come across wants them to stay hidden next time as well.
static NSString *const BTHideIneligibleKey = @"BTSyncHideIneligible";
static NSString *const BTHideAlreadySyncedKey = @"BTSyncHideAlreadySynced";

// A folder in the incoming playlists. iTunes gives each playlist the names of
// the folders above it; this turns those back into the tree they came from, so
// a folder can be opened, closed, and ticked as one thing.
@interface BTSyncFolder : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray *children;   // folders and playlists
@end

@implementation BTSyncFolder
- (id)init {
    self = [super init];
    if (self) _children = [NSMutableArray array];
    return self;
}
@end

// The list of playlists. Only here to place the disclosure triangle: AppKit sets
// it low in the row and hard against the first letter of the name.
@interface BTSyncOutlineView : NSOutlineView
@end

@implementation BTSyncOutlineView

// An outline view cannot inherit the table subclass, so the shared fill has to
// be called by hand. Without it this list alone draws the system's own blue,
// which is exactly what purple mode cannot reach.
- (void)highlightSelectionInClipRect:(NSRect)clipRect {
    BTDrawListSelection(self, clipRect);
}

- (BOOL)becomeFirstResponder {
    BOOL became = [super becomeFirstResponder];
    if (became) BTNoteListFocusChanged();
    return became;
}

- (BOOL)resignFirstResponder {
    BOOL resigned = [super resignFirstResponder];
    if (resigned) BTNoteListFocusChanged();
    return resigned;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    BTWatchListFocus(self);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSRect)frameOfOutlineCellAtRow:(NSInteger)row {
    NSRect frame = [super frameOfOutlineCellAtRow:row];
    // Up one, since a table draws top down and the triangle sat below the
    // middle of its row, and back two, to put air between it and the name.
    frame.origin.y -= 1.0;
    frame.origin.x -= 2.0;
    return frame;
}

@end

// The bar between the two lists. Wide enough to catch the pointer, with a dot
// on it so it reads as something to take hold of rather than as a seam.
@interface BTSyncDivider : NSSplitView
@end

@implementation BTSyncDivider

- (CGFloat)dividerThickness { return 11.0; }

- (void)drawDividerInRect:(NSRect)rect {
    [[BTStyle windowBackground] set];
    NSRectFill(rect);

    CGFloat side = 5.0;
    NSRect dot = NSMakeRect(NSMidX(rect) - side / 2.0, NSMidY(rect) - side / 2.0, side, side);
    [[NSColor colorWithCalibratedWhite:0.45 alpha:1.0] set];
    [[NSBezierPath bezierPathWithOvalInRect:dot] fill];
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.6] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSOffsetRect(NSInsetRect(dot, 1.5, 1.5), 0, 1)] fill];
}

@end

@interface BTITunesSyncView () <NSTableViewDataSource, NSTableViewDelegate,
                                NSOutlineViewDataSource, NSOutlineViewDelegate,
                                NSSplitViewDelegate>
@end

@implementation BTITunesSyncView {
    BTITunesSync *_sync;
    BOOL _comparing;

    NSTextField *_summary;

    NSButton *_hideIneligible;
    NSButton *_hideAlreadySynced;
    NSButton *_checkAll;
    NSButton *_syncButton;
    NSTextField *_chosenSummary;

    NSTextField *_songsHeading;
    NSTextField *_playlistsHeading;
    NSScrollView *_songsScroll;
    NSScrollView *_playlistsScroll;
    NSTableView *_songsTable;
    NSOutlineView *_playlistsTable;
    // Each list travels with its own heading, so dragging the bar between them
    // moves the words along with the rows they describe.
    NSView *_songsPane;
    NSView *_playlistsPane;
    BTSyncDivider *_panes;

    NSArray *_songs;          // what the two lists are showing, after hiding
    NSArray *_lists;          // the playlists, flat, after hiding
    NSArray *_playlistTree;   // the same ones as folders and playlists

    // Chosen by leaving them alone: everything starts checked, so only what has
    // been turned off has to be remembered.
    NSMutableSet *_uncheckedSongs;
    NSMutableSet *_uncheckedLists;

    // Which of a playlist's songs are still up for choosing, worked out once
    // when the comparison lands. Asking the question row by row meant walking
    // all twelve thousand incoming songs for every row drawn, which is why
    // ticking a box used to stop the window for seconds at a time.
    NSDictionary *_choosableByPlaylist;   // playlist id to song ids
}

#pragma mark - Building

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) return nil;

    _uncheckedSongs = [NSMutableSet set];
    _uncheckedLists = [NSMutableSet set];
    _songs = @[];
    _lists = @[];

    _summary = BTLabelWithText(@"", [BTStyle boldFont]);
    [self addSubview:_summary];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    _hideIneligible = [self checkboxTitled:@"Hide ineligible"
                                     action:@selector(hidingChanged:)
                                         on:[defaults boolForKey:BTHideIneligibleKey]];
    _hideAlreadySynced = [self checkboxTitled:@"Hide already synced"
                                        action:@selector(hidingChanged:)
                                            on:[defaults objectForKey:BTHideAlreadySyncedKey]
                                                ? [defaults boolForKey:BTHideAlreadySyncedKey] : YES];

    _checkAll = [BTPushButton buttonWithTitle:@"Uncheck All"
                                       target:self
                                       action:@selector(checkAllOrNone:)];
    [self addSubview:_checkAll];

    _songsHeading = BTLabelWithText(@"Music", [BTStyle boldFont]);
    _playlistsHeading = BTLabelWithText(@"Playlists", [BTStyle boldFont]);

    _songsScroll = [self listWithColumns:@[@[@"check", @"", @20],
                                           @[@"title", @"Song Name", @180],
                                           @[@"artist", @"Artist", @130],
                                           @[@"album", @"Album", @130]]];
    _playlistsScroll = [self outlineWithColumns:@[@[@"check", @"", @20],
                                                  @[@"name", @"Playlist", @200],
                                                  @[@"what", @"", @90]]];
    _songsTable = (NSTableView *)[_songsScroll documentView];
    _playlistsTable = (NSOutlineView *)[_playlistsScroll documentView];

    _playlistsPane = [self paneWithHeading:_playlistsHeading list:_playlistsScroll];
    _songsPane = [self paneWithHeading:_songsHeading list:_songsScroll];

    // Playlists first: a sync is chosen by playlist, and the songs are what
    // that choice pulls along.
    _panes = [[BTSyncDivider alloc] initWithFrame:NSZeroRect];
    [_panes setVertical:YES];
    [_panes setDividerStyle:NSSplitViewDividerStyleThin];
    [_panes setDelegate:self];
    [_panes addSubview:_playlistsPane];
    [_panes addSubview:_songsPane];
    [self addSubview:_panes];

    _syncButton = [BTPushButton buttonWithTitle:@"Sync" target:self action:@selector(runSync:)];
    [_syncButton setKeyEquivalent:@"\r"];
    [self addSubview:_syncButton];

    // What the button is about to do, beside the button that does it. The line
    // at the top says what iTunes has; this says what has been asked for, and
    // the two are easy to confuse when they are not kept apart.
    _chosenSummary = BTLabelWithText(@"", [BTStyle uiFont]);
    [_chosenSummary setAlignment:NSRightTextAlignment];
    [_chosenSummary setTextColor:[NSColor colorWithCalibratedWhite:0.35 alpha:1.0]];
    [self addSubview:_chosenSummary];

    [self showComparingState];
    // Laid out here as well as on resize. The pane is made at the size it is
    // going to be, so nothing ever resizes it, and waiting for that leaves
    // every one of these sitting at zero and the pane looking empty.
    [self layoutPane];
    return self;
}

- (NSButton *)checkboxTitled:(NSString *)title action:(SEL)action on:(BOOL)on {
    NSButton *box = [[NSButton alloc] initWithFrame:NSZeroRect];
    [box setCell:[[BTCheckboxCell alloc] init]];
    [box setButtonType:NSSwitchButton];
    [box setTitle:title];
    [box setFont:[BTStyle uiFont]];
    [box setState:(on ? NSOnState : NSOffState)];
    [box setTarget:self];
    [box setAction:action];
    [self addSubview:box];
    return box;
}

// identifier, heading, width. The first is always the tick.
//
// The scroll view is what comes back, not the table. Handing back the table and
// finding its scroll view again only works while something else is holding the
// scroll view up; nothing was, so it went as soon as this returned and the list
// never appeared.
- (NSScrollView *)listWithColumns:(NSArray *)specs {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [scroll setHasVerticalScroller:YES];
    [scroll setAutohidesScrollers:YES];
    [scroll setBorderType:NSBezelBorder];
    [scroll setFocusRingType:NSFocusRingTypeNone];

    NSTableView *table = [[BTListTableView alloc] initWithFrame:NSZeroRect];
    [table setFocusRingType:NSFocusRingTypeNone];
    [table setRowHeight:17.0];
    [table setUsesAlternatingRowBackgroundColors:YES];
    [table setAllowsMultipleSelection:NO];
    [table setAllowsColumnSelection:NO];
    [table setDataSource:self];
    [table setDelegate:self];

    NSUInteger i;
    for (i = 0; i < [specs count]; i++) {
        NSArray *spec = [specs objectAtIndex:i];
        NSString *identifier = [spec objectAtIndex:0];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
        [[column headerCell] setStringValue:[spec objectAtIndex:1]];
        [[column headerCell] setFont:[BTStyle uiFont]];
        [column setWidth:[[spec objectAtIndex:2] doubleValue]];

        if ([identifier isEqualToString:@"check"]) {
            NSButtonCell *cell = [[BTCheckboxCell alloc] init];
            [cell setButtonType:NSSwitchButton];
            [cell setAllowsMixedState:YES];
            [cell setTitle:@""];
            [cell setControlSize:NSSmallControlSize];
            [column setDataCell:cell];
            [column setEditable:YES];
        } else {
            NSTextFieldCell *cell = [[NSTextFieldCell alloc] init];
            [cell setFont:[BTStyle uiFont]];
            [cell setLineBreakMode:NSLineBreakByTruncatingTail];
            [column setDataCell:cell];
            [column setEditable:NO];
        }
        [table addTableColumn:column];
    }

    [scroll setDocumentView:table];
    return scroll;
}

// The same columns as a plain list, but the name column carries the disclosure
// triangle and indents, while the tick stays at the near edge whatever depth a
// playlist sits at. That is how a device sync pane is arranged and it reads the
// same way here.
- (NSScrollView *)outlineWithColumns:(NSArray *)specs {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [scroll setHasVerticalScroller:YES];
    [scroll setAutohidesScrollers:YES];
    [scroll setBorderType:NSBezelBorder];
    [scroll setFocusRingType:NSFocusRingTypeNone];

    NSOutlineView *outline = [[BTSyncOutlineView alloc] initWithFrame:NSZeroRect];
    [outline setFocusRingType:NSFocusRingTypeNone];
    [outline setRowHeight:17.0];
    [outline setUsesAlternatingRowBackgroundColors:YES];
    [outline setAllowsMultipleSelection:NO];
    [outline setAllowsColumnSelection:NO];
    [outline setIndentationPerLevel:14.0];
    [outline setDataSource:self];
    [outline setDelegate:self];

    NSTableColumn *nameColumn = nil;
    NSUInteger i;
    for (i = 0; i < [specs count]; i++) {
        NSArray *spec = [specs objectAtIndex:i];
        NSString *identifier = [spec objectAtIndex:0];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
        [[column headerCell] setStringValue:[spec objectAtIndex:1]];
        [[column headerCell] setFont:[BTStyle uiFont]];
        [column setWidth:[[spec objectAtIndex:2] doubleValue]];

        if ([identifier isEqualToString:@"check"]) {
            NSButtonCell *cell = [[BTCheckboxCell alloc] init];
            [cell setButtonType:NSSwitchButton];
            [cell setAllowsMixedState:YES];
            [cell setTitle:@""];
            [cell setControlSize:NSSmallControlSize];
            [column setDataCell:cell];
            [column setEditable:YES];
        } else {
            NSTextFieldCell *cell = [[NSTextFieldCell alloc] init];
            [cell setFont:[BTStyle uiFont]];
            [cell setLineBreakMode:NSLineBreakByTruncatingTail];
            [column setDataCell:cell];
            [column setEditable:NO];
        }
        if ([identifier isEqualToString:@"name"]) nameColumn = column;
        [outline addTableColumn:column];
    }
    [outline setOutlineTableColumn:nameColumn];

    [scroll setDocumentView:outline];
    return scroll;
}

// A heading with its list under it, kept together so the bar between the two
// moves both. The masks are what keep them in step while the bar is dragged,
// which never comes back through the pane's own layout.
- (NSView *)paneWithHeading:(NSTextField *)heading list:(NSScrollView *)scroll {
    NSView *pane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 300)];
    [heading setFrame:NSMakeRect(0, 300 - 16, 300, 16)];
    [heading setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [scroll setFrame:NSMakeRect(0, 0, 300, 300 - 20)];
    [scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [pane addSubview:heading];
    [pane addSubview:scroll];
    return pane;
}

- (BOOL)isOpaque { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    [[BTStyle windowBackground] set];
    NSRectFill([self bounds]);
}

#pragma mark - Layout

// Both of these, because the split view resizes the pane by one route and the
// window by the other, and being laid out twice costs nothing.
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutPane];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self layoutPane];
}

- (void)layoutPane {
    NSRect bounds = [self bounds];
    CGFloat margin = 14.0;
    CGFloat width = NSWidth(bounds) - margin * 2;
    CGFloat y = NSMaxY(bounds) - 28;

    [_summary setFrame:NSMakeRect(margin, y, width, 17)];

    y -= 28;
    [_hideIneligible setFrame:NSMakeRect(margin, y, 130, 18)];
    [_hideAlreadySynced setFrame:NSMakeRect(margin + 138, y, 160, 18)];
    CGFloat checkWidth = MAX(110.0, NSWidth([_checkAll frame]));
    CGFloat checkHeight = NSHeight([_checkAll frame]);
    [_checkAll setFrame:NSMakeRect(NSMaxX(bounds) - margin - checkWidth,
                                   y + 9 - checkHeight / 2.0, checkWidth, checkHeight)];

    CGFloat footer = 44.0;
    CGFloat listTop = y - 4;
    CGFloat listHeight = listTop - footer;
    if (listHeight < 60) listHeight = 60;

    NSRect wasSplit = [_panes frame];
    [_panes setFrame:NSMakeRect(margin, footer, width, listHeight)];
    // The first time round there is nothing to keep in proportion, so the two
    // start even.
    if (NSWidth(wasSplit) < 1.0) {
        [_panes setPosition:(width - [_panes dividerThickness]) / 2.0 ofDividerAtIndex:0];
    }
    CGFloat syncWidth = MAX(92.0, NSWidth([_syncButton frame]));
    CGFloat syncHeight = NSHeight([_syncButton frame]);
    [_syncButton setFrame:NSMakeRect(NSMaxX(bounds) - margin - syncWidth,
                                     22.0 - syncHeight / 2.0, syncWidth, syncHeight)];

    // Right up against the button and centred on it, so the count reads as
    // belonging to the button rather than to the pane above.
    CGFloat countRight = NSMinX([_syncButton frame]) - 12.0;
    CGFloat countLeft = margin + 110.0;
    if (countLeft > countRight - 40.0) countLeft = countRight - 40.0;
    // Two and a half points below where centring the box would put it. A label
    // and a button title centre their lines by different metrics, and matching
    // the boxes leaves the words visibly out of line with each other.
    [_chosenSummary setFrame:NSMakeRect(countLeft, 22.0 - 10.5, countRight - countLeft, 17)];

    [self sizeColumnsOf:_songsTable in:_songsScroll fixedFirst:20.0];
    [self sizeColumnsOf:_playlistsTable in:_playlistsScroll fixedFirst:20.0];
}

#pragma mark - The bar between the lists

// Neither list may be squeezed to nothing. Below this a list shows its tick
// column and little else, which is not a view worth dragging to.
#define BT_SYNC_SMALLEST_PANE 170.0

- (CGFloat)splitView:(NSSplitView *)splitView
constrainMinCoordinate:(CGFloat)proposedMin
         ofSubviewAt:(NSInteger)dividerIndex {
    return BT_SYNC_SMALLEST_PANE;
}

- (CGFloat)splitView:(NSSplitView *)splitView
constrainMaxCoordinate:(CGFloat)proposedMax
         ofSubviewAt:(NSInteger)dividerIndex {
    return NSWidth([splitView bounds]) - BT_SYNC_SMALLEST_PANE - [splitView dividerThickness];
}

// The columns inside each list follow the width the bar was dragged to.
- (void)splitViewDidResizeSubviews:(NSNotification *)note {
    [self sizeColumnsOf:_songsTable in:_songsScroll fixedFirst:20.0];
    [self sizeColumnsOf:_playlistsTable in:_playlistsScroll fixedFirst:20.0];
}

// The tick column keeps its width and the rest share what is left, so neither
// list leaves a gap at its right edge.
- (void)sizeColumnsOf:(NSTableView *)table in:(NSScrollView *)scroll fixedFirst:(CGFloat)first {
    NSArray *columns = [table tableColumns];
    if ([columns count] < 2) return;

    CGFloat available = [scroll contentSize].width - first - 4.0;
    if (available < 60) available = 60;
    [[columns objectAtIndex:0] setWidth:first];

    CGFloat each = available / (CGFloat)([columns count] - 1);
    NSUInteger i;
    for (i = 1; i < [columns count]; i++) [[columns objectAtIndex:i] setWidth:each];
}

#pragma mark - Comparing

- (void)beginComparing {
    if (_comparing) return;
    _comparing = YES;
    _sync = nil;
    _songs = @[];
    _lists = @[];
    [_uncheckedSongs removeAllObjects];
    [_uncheckedLists removeAllObjects];
    [self showComparingState];

    NSString *path = [[BTPreferences sharedPreferences] iTunesLibraryPath];
    __weak BTITunesSyncView *weakSelf = self;

    [BTITunesSync syncWithLibraryAtPath:path
                                against:[BTLibrary sharedLibrary]
                               progress:^(double fraction, NSString *stage) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName:BTDisplayProgressNotification
                          object:nil
                        userInfo:@{@"title": @"Analyzing iTunes",
                                   @"message": (stage ? stage : @""),
                                   @"fraction": @(fraction)}];
    } completion:^(BTITunesSync *sync) {
        BTITunesSyncView *me = weakSelf;
        if (me == nil) return;
        me->_comparing = NO;
        me->_sync = sync;
        [me finishedComparing];
    }];
}

- (void)showComparingState {
    [_summary setStringValue:@"Analyzing iTunes"];
    [_syncButton setEnabled:NO];
    [_checkAll setEnabled:NO];
    [_checkAll setTitle:@"Uncheck All"];
}

- (void)finishedComparing {
    [[NSNotificationCenter defaultCenter]
        postNotificationName:BTDisplayProgressDidEndNotification object:nil];
    [_checkAll setEnabled:YES];

    if (_sync.error) {
        [_summary setStringValue:_sync.error];
        [_syncButton setEnabled:NO];
        return;
    }

    [self indexChoosableSongs];

    // What was turned down before starts turned down, and nothing more than
    // that: every one of these can still be ticked and brought across.
    NSUInteger i;
    for (i = 0; i < [_sync.incomingTracks count]; i++) {
        BTITunesSyncTrack *track = [_sync.incomingTracks objectAtIndex:i];
        if (track.excludedBefore && track.persistentID) {
            [_uncheckedSongs addObject:track.persistentID];
        }
    }

    [_summary setStringValue:[_sync summary]];
    [self rebuildLists];
}

#pragma mark - What the lists show

- (void)hidingChanged:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:([_hideIneligible state] == NSOnState) forKey:BTHideIneligibleKey];
    [defaults setBool:([_hideAlreadySynced state] == NSOnState) forKey:BTHideAlreadySyncedKey];
    [self rebuildLists];
}

- (void)rebuildLists {
    BOOL hideBlocked = ([_hideIneligible state] == NSOnState);
    BOOL hideHere = ([_hideAlreadySynced state] == NSOnState);

    NSMutableArray *songs = [NSMutableArray array];
    NSUInteger i;
    for (i = 0; i < [_sync.incomingTracks count]; i++) {
        BTITunesSyncTrack *track = [_sync.incomingTracks objectAtIndex:i];
        if (hideHere && track.alreadyHere) continue;
        if (hideBlocked && track.blocked != BTITunesBlockNone) continue;
        [songs addObject:track];
    }

    NSMutableArray *lists = [NSMutableArray array];
    for (i = 0; i < [_sync.playlists count]; i++) {
        BTITunesSyncPlaylist *playlist = [_sync.playlists objectAtIndex:i];
        if (hideHere && playlist.alreadyHere) continue;
        if (hideBlocked && playlist.blocked != BTITunesBlockNone) continue;
        [lists addObject:playlist];
    }

    _songs = songs;
    _lists = lists;
    _playlistTree = [self treeFromPlaylists:lists];
    [_songsHeading setStringValue:[NSString stringWithFormat:@"Music (%lu)", (unsigned long)[songs count]]];
    [_playlistsHeading setStringValue:[NSString stringWithFormat:@"Playlists (%lu)", (unsigned long)[lists count]]];

    [_songsTable reloadData];
    [_playlistsTable reloadData];
    [self expandEveryFolder];
    [self updateButtons];
}

// Folders are rebuilt out of the names iTunes hangs on each playlist, so a
// folder exists here only when something inside it survived the hiding.
- (NSArray *)treeFromPlaylists:(NSArray *)playlists {
    NSMutableArray *roots = [NSMutableArray array];
    NSMutableDictionary *foldersByPath = [NSMutableDictionary dictionary];

    NSUInteger i, j;
    for (i = 0; i < [playlists count]; i++) {
        BTITunesSyncPlaylist *playlist = [playlists objectAtIndex:i];
        NSMutableArray *into = roots;
        NSMutableString *path = [NSMutableString string];

        for (j = 0; j < [playlist.folderNames count]; j++) {
            NSString *name = [playlist.folderNames objectAtIndex:j];
            [path appendFormat:@"/%@", name];

            BTSyncFolder *folder = [foldersByPath objectForKey:path];
            if (folder == nil) {
                folder = [[BTSyncFolder alloc] init];
                folder.name = name;
                [foldersByPath setObject:folder forKey:path];
                [into addObject:folder];
            }
            into = folder.children;
        }
        [into addObject:playlist];
    }
    return roots;
}

- (void)expandEveryFolder {
    NSInteger row;
    for (row = 0; row < [_playlistsTable numberOfRows]; row++) {
        id item = [_playlistsTable itemAtRow:row];
        if ([item isKindOfClass:[BTSyncFolder class]]) [_playlistsTable expandItem:item];
    }
}

#pragma mark - What is ticked

- (BOOL)songIsChosen:(BTITunesSyncTrack *)track {
    return [track eligible] && ![_uncheckedSongs containsObject:track.persistentID];
}

// The songs each playlist would bring that are still up for choosing. A song
// already in the library comes along regardless, so it is not one of them.
- (void)indexChoosableSongs {
    NSMutableSet *choosableIDs = [NSMutableSet set];
    NSUInteger i, j;
    for (i = 0; i < [_sync.incomingTracks count]; i++) {
        BTITunesSyncTrack *track = [_sync.incomingTracks objectAtIndex:i];
        if ([track eligible] && track.persistentID) [choosableIDs addObject:track.persistentID];
    }

    NSMutableDictionary *byPlaylist = [NSMutableDictionary dictionary];
    for (i = 0; i < [_sync.playlists count]; i++) {
        BTITunesSyncPlaylist *playlist = [_sync.playlists objectAtIndex:i];
        if (playlist.persistentID == nil) continue;
        NSMutableArray *mine = [NSMutableArray array];
        for (j = 0; j < [playlist.incomingTrackIDs count]; j++) {
            NSString *songID = [playlist.incomingTrackIDs objectAtIndex:j];
            if ([choosableIDs containsObject:songID]) [mine addObject:songID];
        }
        [byPlaylist setObject:mine forKey:playlist.persistentID];
    }
    _choosableByPlaylist = byPlaylist;
}

- (NSArray *)choosableSongsOf:(BTITunesSyncPlaylist *)playlist {
    NSArray *songIDs = playlist.persistentID
        ? [_choosableByPlaylist objectForKey:playlist.persistentID] : nil;
    return songIDs ? songIDs : @[];
}

// A playlist's tick is its own, and says one thing: whether this playlist comes
// across.
//
// It is deliberately not worked out from which of its songs are ticked. A song
// sits in many playlists, so reading the tick back off the songs meant ticking
// one song ticked every playlist holding it, and each of those then arrived
// holding that song alone. Ticking one playlist ticked its songs, which ticked
// every other playlist sharing any of them. One song in common was enough to
// drag a playlist across that the reader never chose.
- (NSInteger)stateOfPlaylist:(BTITunesSyncPlaylist *)playlist {
    if (![playlist eligible]) return NSOffState;
    return [_uncheckedLists containsObject:playlist.persistentID] ? NSOffState : NSOnState;
}

// Every song the still-ticked playlists would bring.
- (NSSet *)songsWantedByCheckedPlaylists {
    NSMutableSet *wanted = [NSMutableSet set];
    NSUInteger i;
    for (i = 0; i < [_sync.playlists count]; i++) {
        BTITunesSyncPlaylist *playlist = [_sync.playlists objectAtIndex:i];
        if ([self stateOfPlaylist:playlist] == NSOffState) continue;
        [wanted addObjectsFromArray:[self choosableSongsOf:playlist]];
    }
    return wanted;
}

// Every playlist under a folder, however deep.
- (NSArray *)playlistsUnder:(id)item {
    if ([item isKindOfClass:[BTITunesSyncPlaylist class]]) return @[item];

    NSMutableArray *found = [NSMutableArray array];
    NSArray *children = [(BTSyncFolder *)item children];
    NSUInteger i;
    for (i = 0; i < [children count]; i++) {
        [found addObjectsFromArray:[self playlistsUnder:[children objectAtIndex:i]]];
    }
    return found;
}

// A folder is ticked when everything inside it is, empty when none of it is, and
// dashed in between. A folder holding nothing that can come across is simply
// off.
- (NSInteger)stateOfItem:(id)item {
    if ([item isKindOfClass:[BTITunesSyncPlaylist class]]) {
        return [self stateOfPlaylist:(BTITunesSyncPlaylist *)item];
    }

    NSArray *inside = [self playlistsUnder:item];
    BOOL anyOn = NO, anyOff = NO;
    NSUInteger i;
    for (i = 0; i < [inside count]; i++) {
        BTITunesSyncPlaylist *playlist = [inside objectAtIndex:i];
        if (![playlist eligible]) continue;
        if ([self stateOfPlaylist:playlist] == NSOffState) anyOff = YES; else anyOn = YES;
        if (anyOn && anyOff) return NSMixedState;
    }
    return anyOn ? NSOnState : NSOffState;
}

- (void)setItem:(id)item chosen:(BOOL)chosen {
    NSArray *inside = [self playlistsUnder:item];
    NSUInteger i;
    for (i = 0; i < [inside count]; i++) {
        BTITunesSyncPlaylist *playlist = [inside objectAtIndex:i];
        if ([playlist eligible]) [self setPlaylist:playlist chosen:chosen];
    }
}

- (void)setPlaylist:(BTITunesSyncPlaylist *)playlist chosen:(BOOL)chosen {
    // Ticking a playlist ticks its music, which is the whole point of the two
    // panes standing side by side. It ticks nothing else: no other playlist is
    // touched, however much music they have in common.
    if (chosen) {
        [_uncheckedLists removeObject:playlist.persistentID];
        [_uncheckedSongs minusSet:[NSSet setWithArray:[self choosableSongsOf:playlist]]];
        return;
    }

    // Off first, so the playlist being turned off is not counted among the ones
    // still wanting its songs.
    [_uncheckedLists addObject:playlist.persistentID];

    // Its songs go with it, except any that a playlist still ticked would
    // bring. Taking those too would empty a playlist the reader never touched,
    // which is the same fault the other way round.
    NSArray *mine = [self choosableSongsOf:playlist];
    NSSet *stillWanted = [self songsWantedByCheckedPlaylists];
    NSUInteger i;
    for (i = 0; i < [mine count]; i++) {
        NSString *songID = [mine objectAtIndex:i];
        if (![stillWanted containsObject:songID]) [_uncheckedSongs addObject:songID];
    }
}

// What the Sync button would bring across. A count of nothing is said outright
// rather than left blank, since a blank line beside a dead button reads as
// something that failed to fill in.
static NSString *BTChosenSummary(NSUInteger playlists, NSUInteger songs) {
    if (playlists == 0 && songs == 0) return @"Nothing checked";

    NSMutableArray *parts = [NSMutableArray array];
    if (playlists > 0) {
        [parts addObject:[NSString stringWithFormat:@"%lu playlist%@",
                          (unsigned long)playlists, playlists == 1 ? @"" : @"s"]];
    }
    if (songs > 0) {
        [parts addObject:[NSString stringWithFormat:@"%lu song%@",
                          (unsigned long)songs, songs == 1 ? @"" : @"s"]];
    }
    return [parts componentsJoinedByString:@", "];
}

- (void)updateButtons {
    NSUInteger i, chosenSongs = 0, chosenLists = 0;
    for (i = 0; i < [_sync.incomingTracks count]; i++) {
        if ([self songIsChosen:[_sync.incomingTracks objectAtIndex:i]]) chosenSongs++;
    }
    for (i = 0; i < [_sync.playlists count]; i++) {
        if ([self stateOfPlaylist:[_sync.playlists objectAtIndex:i]] != NSOffState) chosenLists++;
    }

    // Anything ticked and the button offers to clear it; nothing ticked and it
    // offers to tick everything back.
    BOOL anything = (chosenSongs > 0 || chosenLists > 0);
    [_checkAll setTitle:(anything ? @"Uncheck All" : @"Check All")];
    [_syncButton setEnabled:anything];
    [_chosenSummary setStringValue:BTChosenSummary(chosenLists, chosenSongs)];
}

- (void)checkAllOrNone:(id)sender {
    BOOL turningOn = [[_checkAll title] isEqualToString:@"Check All"];
    [_uncheckedSongs removeAllObjects];
    [_uncheckedLists removeAllObjects];

    if (!turningOn) {
        NSUInteger i;
        for (i = 0; i < [_sync.incomingTracks count]; i++) {
            BTITunesSyncTrack *track = [_sync.incomingTracks objectAtIndex:i];
            if (track.persistentID) [_uncheckedSongs addObject:track.persistentID];
        }
        for (i = 0; i < [_sync.playlists count]; i++) {
            BTITunesSyncPlaylist *playlist = [_sync.playlists objectAtIndex:i];
            if (playlist.persistentID) [_uncheckedLists addObject:playlist.persistentID];
        }
    }

    [_songsTable reloadData];
    [_playlistsTable reloadData];
    [self expandEveryFolder];
    [self updateButtons];
}

#pragma mark - The lists

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)[_songs count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                          row:(NSInteger)row {
    NSString *identifier = [tableColumn identifier];
    if (row < 0 || row >= (NSInteger)[_songs count]) return nil;

    BTITunesSyncTrack *track = [_songs objectAtIndex:(NSUInteger)row];
    if ([identifier isEqualToString:@"check"]) {
        return @([self songIsChosen:track] ? NSOnState : NSOffState);
    }
    if ([identifier isEqualToString:@"title"]) {
        return [track.title length] > 0 ? track.title : @"(untitled)";
    }
    if ([identifier isEqualToString:@"artist"]) return track.artist ? track.artist : @"";
    return track.album ? track.album : @"";
}

#pragma mark - The playlists, as folders

- (NSArray *)childrenOfItem:(id)item {
    if (item == nil) return _playlistTree;
    if ([item isKindOfClass:[BTSyncFolder class]]) return [(BTSyncFolder *)item children];
    return @[];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    return (NSInteger)[[self childrenOfItem:item] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return [[self childrenOfItem:item] objectAtIndex:(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [[self childrenOfItem:item] count] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                       byItem:(id)item {
    NSString *identifier = [tableColumn identifier];

    if ([item isKindOfClass:[BTSyncFolder class]]) {
        if ([identifier isEqualToString:@"check"]) return @([self stateOfItem:item]);
        if ([identifier isEqualToString:@"name"]) return [(BTSyncFolder *)item name];
        NSUInteger inside = [[self playlistsUnder:item] count];
        return [NSString stringWithFormat:@"%lu playlists", (unsigned long)inside];
    }

    BTITunesSyncPlaylist *playlist = item;
    if ([identifier isEqualToString:@"check"]) return @([self stateOfPlaylist:playlist]);
    if ([identifier isEqualToString:@"name"]) return playlist.name;
    return [self wordForPlaylist:playlist];
}

- (void)outlineView:(NSOutlineView *)outlineView
    setObjectValue:(id)object
    forTableColumn:(NSTableColumn *)tableColumn
            byItem:(id)item {
    if (![[tableColumn identifier] isEqualToString:@"check"]) return;

    // A dash means partly chosen, and the next click takes all of it.
    [self setItem:item chosen:([self stateOfItem:item] != NSOnState)];
    [_songsTable reloadData];
    [outlineView reloadData];
    [self updateButtons];
}

- (void)outlineView:(NSOutlineView *)outlineView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn
               item:(id)item {
    BOOL blocked = NO, here = NO;
    NSInteger reason = 0;

    if ([item isKindOfClass:[BTITunesSyncPlaylist class]]) {
        BTITunesSyncPlaylist *playlist = item;
        blocked = (playlist.blocked != BTITunesBlockNone);
        here = playlist.alreadyHere;
        reason = playlist.blocked;
    } else {
        // A folder is only as available as what is inside it.
        blocked = ([[self playlistsUnder:item] count] > 0);
        NSArray *inside = [self playlistsUnder:item];
        NSUInteger i;
        for (i = 0; i < [inside count]; i++) {
            if ([[inside objectAtIndex:i] eligible]) { blocked = NO; break; }
        }
    }

    if ([cell isKindOfClass:[NSButtonCell class]]) {
        [(NSButtonCell *)cell setEnabled:!(blocked || here)];
        return;
    }
    if (![cell isKindOfClass:[NSTextFieldCell class]]) return;

    [(NSTextFieldCell *)cell setHighlighted:NO];
    NSColor *ink = [NSColor blackColor];
    if (blocked) ink = [BTStyle ineligibleTextForReason:reason];
    else if (here) ink = [BTStyle ineligibleTextForReason:0];
    [(NSTextFieldCell *)cell setTextColor:ink];
}

// What is about to happen to it, or why nothing can.
- (NSString *)wordForPlaylist:(BTITunesSyncPlaylist *)playlist {
    switch (playlist.blocked) {
        case BTITunesBlockSmart:            return @"smart";
        case BTITunesBlockHoldsProtected:   return @"locked songs";
        case BTITunesBlockHoldsNotOnDisk:   return @"not downloaded";
        default: break;
    }
    if (playlist.alreadyHere) return @"already here";
    if (playlist.change == BTITunesPlaylistGrew) {
        return [NSString stringWithFormat:@"+%lu songs", (unsigned long)[playlist.incomingTrackIDs count]];
    }
    return [NSString stringWithFormat:@"%lu songs", (unsigned long)[playlist.incomingTrackIDs count]];
}

- (void)tableView:(NSTableView *)tableView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn
                row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)[_songs count]) return;
    BTITunesSyncTrack *track = [_songs objectAtIndex:(NSUInteger)row];
    BOOL blocked = (track.blocked != BTITunesBlockNone);
    BOOL here = track.alreadyHere;
    NSInteger reason = track.blocked;

    // Nothing that cannot come across can be ticked, and it says so by being
    // gray rather than by disappearing.
    if ([cell isKindOfClass:[NSButtonCell class]]) {
        [(NSButtonCell *)cell setEnabled:!(blocked || here)];
        return;
    }
    if (![cell isKindOfClass:[NSTextFieldCell class]]) return;

    [(NSTextFieldCell *)cell setHighlighted:NO];
    NSColor *ink = [NSColor blackColor];
    if (blocked) ink = [BTStyle ineligibleTextForReason:reason];
    else if (here) ink = [BTStyle ineligibleTextForReason:0];
    [(NSTextFieldCell *)cell setTextColor:ink];
}

- (void)tableView:(NSTableView *)tableView
   setObjectValue:(id)object
   forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row {
    if (![[tableColumn identifier] isEqualToString:@"check"]) return;
    if (row < 0 || row >= (NSInteger)[_songs count]) return;

    BTITunesSyncTrack *track = [_songs objectAtIndex:(NSUInteger)row];
    if (![track eligible]) return;

    if ([self songIsChosen:track]) {
        [_uncheckedSongs addObject:track.persistentID];
    } else {
        [_uncheckedSongs removeObject:track.persistentID];
    }

    // A playlist holding it now reads as partly chosen, and so does the folder
    // that playlist sits in, so the whole tree is redrawn rather than one row.
    [tableView reloadData];
    [_playlistsTable reloadData];
    [self updateButtons];
}

#pragma mark - Doing it

- (void)runSync:(id)sender {
    if (_sync == nil || _sync.error) return;

    NSMutableSet *songs = [NSMutableSet set];
    NSMutableSet *lists = [NSMutableSet set];
    NSMutableArray *leftBehind = [NSMutableArray array];

    // The persistent id is the only handle on any of this: what is chosen, what
    // was left behind, and what the import matches against. An entry without one
    // could never be imported anyway, and putting a nil in a set throws, so it
    // is passed over here rather than a moment later and less clearly.
    NSUInteger i;
    for (i = 0; i < [_sync.incomingTracks count]; i++) {
        BTITunesSyncTrack *track = [_sync.incomingTracks objectAtIndex:i];
        if (![track eligible] || track.persistentID == nil) continue;
        if ([self songIsChosen:track]) {
            [songs addObject:track.persistentID];
        } else {
            [leftBehind addObject:track.persistentID];
        }
    }
    for (i = 0; i < [_sync.playlists count]; i++) {
        BTITunesSyncPlaylist *playlist = [_sync.playlists objectAtIndex:i];
        if (![playlist eligible] || playlist.persistentID == nil) continue;
        if ([self stateOfPlaylist:playlist] != NSOffState) [lists addObject:playlist.persistentID];
    }

    BTLibrary *library = [BTLibrary sharedLibrary];
    NSDictionary *result = [_sync importInto:library chosenSongs:songs chosenPlaylists:lists];

    // What was left unticked starts unticked next time. What came across is no
    // longer left behind, so it stops being remembered as such.
    [library setExcluded:YES forPersistentIDs:leftBehind];
    [library setExcluded:NO forPersistentIDs:[songs allObjects]];

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"The sync finished."];
    [alert setInformativeText:[NSString stringWithFormat:
        @"%@ songs and %@ playlists came across, and %@ playlists here grew.\n\n"
        @"The songs are played where they already sit. Nothing was moved, copied, "
        @"or written back to iTunes.",
        [result objectForKey:@"songsAdded"],
        [result objectForKey:@"playlistsAdded"],
        [result objectForKey:@"playlistsGrown"]]];
    [alert runModal];

    if (self.didFinish) self.didFinish();
}

@end
