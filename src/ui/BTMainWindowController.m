#import "BTMainWindowController.h"
#import "BTMainWindowViews.h"
#import "BTTrackColumns.h"
#import "BTStyle.h"
#import "BTControls.h"
#import "BTDisplayView.h"
#import "BTBrowserView.h"
#import "BTSmartPlaylistController.h"
#import "BTBurnPlan.h"
#import "BTBurnController.h"
#import "BTTrackInfoController.h"
#import "BTLibrary.h"
#import "BTITunesImport.h"
#import "BTITunesEntry.h"
#import "BTPlaylist.h"
#import "BTIPod.h"
#import "BTSyncView.h"
#import "BTITunesSyncView.h"
#import "BTPreferences.h"
#import "BTTrack.h"
#import "BTPlayer.h"

static NSString *const BTTrackPasteboardType = @"com.btunes.tracks";
static NSString *const BTPlaylistPasteboardType = @"com.btunes.playlist";
static NSString *const BTLibrarySource = @"Library";
// The same songs as the library, held in the order iTunes recorded them being
// added. Deliberately not the order BTunes learned of them, which for anything
// a sync brings is one moment for thousands of songs and says nothing at all.
static NSString *const BTRecentlyAddedSource = @"Recently Added";

// Column widths and their arrangement are left to the table, which saves them
// under this name. What the table is allowed to change on its own is set per
// column in BTTrackColumns: a saved width that anything may recompute is not a
// saved width. Which columns are shown is kept separately, because the #
// column is decided by the source rather than by preference and must not be
// restored over that decision.
static NSString *const BTColumnsAutosaveName = @"BTunesTrackColumns2";
static NSString *const BTHiddenColumnsKey = @"BTHiddenColumns";

// The source list holds three kinds of row: the library, an attached iPod, and
// playlists. Anything reaching for a playlist's own members has to ask first,
// because the other two answer none of them and a bare cast crashes on the
// first message sent.
static BTPlaylist *BTPlaylistFromSource(id item) {
    return [item isKindOfClass:[BTPlaylist class]] ? (BTPlaylist *)item : nil;
}

// What the window remembers between runs: which folders you closed, what you
// had selected, and which song was highlighted.
static NSString *const BTClosedFoldersKey = @"BTClosedFolders";
static NSString *const BTSelectedSourceKey = @"BTSelectedSource";
static NSString *const BTSelectedTrackKey = @"BTSelectedTrack";
// Where the bars between the panes were left. Kept in this machine's settings
// rather than with the library, since how wide a pane is says something about
// the screen it is on rather than about the music.
static NSString *const BTSourceWidthKey = @"BTSourcePaneWidth";
static NSString *const BTBrowserHeightKey = @"BTBrowserHeight";

// A playlist keeps its own sort, since that belongs to the playlist. The
// library has nowhere of its own to keep one, so it goes here.
static NSString *const BTLibrarySortKey = @"BTLibrarySort";
static NSString *const BTLibrarySortAscendingKey = @"BTLibrarySortAscending";

// How the selected source is written down. A playlist uses its own id, so these
// two only have to avoid looking like one.
static NSString *const BTLibraryWasSelected = @"library";
static NSString *const BTIPodWasSelected = @"ipod";
static NSString *const BTRecentWasSelected = @"recent";

// Tall enough for the readout, with the same air above and below it that the
// transport buttons sit in. The readout says how tall it needs to be, since
// what is in it follows the size of the type.
#define BT_CHROME_HEIGHT ([BTDisplayView naturalHeight] + 12.0)
#define BT_BOTTOM_HEIGHT 24.0
// Air above the first row, taken inside the list rather than between the panels.
// A gap between them exposes the window's own background as a band of flat gray
// running across the window.
#define BT_SOURCE_TOP_INSET 6.0

// How much of the window the title bar covers. Asked of AppKit rather than
// assumed, since the content view now runs underneath it.
static CGFloat BTTitleBarHeight(void) {
    NSRect content = NSMakeRect(0, 0, 100, 100);
    NSRect frame = [NSWindow frameRectForContentRect:content styleMask:NSTitledWindowMask];
    return NSHeight(frame) - NSHeight(content);
}

#pragma mark - Controller

@interface BTMainWindowController () <NSOutlineViewDataSource, NSOutlineViewDelegate,
                                      NSTableViewDataSource, NSTableViewDelegate,
                                      NSSplitViewDelegate, BTBrowserViewDelegate,
                                      NSWindowDelegate, BTKeyTableDelegate>
@end

@implementation BTMainWindowController {
    BTChromeView *_chrome;
    BTRoundButton *_previousButton;
    BTRoundButton *_playButton;
    BTRoundButton *_nextButton;
    BTVolumeView *_volumeView;
    BTDisplayView *_display;
    NSSearchField *_searchField;
    BTRoundButton *_miniButton;

    NSSplitView *_outerSplit;
    NSSplitView *_innerSplit;
    BTKeyOutlineView *_sourceList;
    BTBrowserView *_browser;
    BTKeyTableView *_trackTable;

    BTBottomBarView *_bottomBar;
    BTToggleButton *_shuffleButton;
    BTToggleButton *_repeatButton;
    BTToggleButton *_ejectButton;
    BTToggleButton *_syncButton;
    BTITunesSyncView *_iTunesSyncView;
    BOOL _showingITunesSync;

    id _selectedSource;              // BTLibrarySource or a BTPlaylist
    NSArray *_visibleTracks;
    // Track id to the song's place in the selected playlist, counted from one.
    // Held rather than derived from the row, so the number stays with the song
    // when the list is sorted by something else.
    NSDictionary *_sourceOrder;
    BOOL _showsPlaylistOrder;
    NSString *_sortColumn;
    BOOL _sortAscending;
    BOOL _browserHidden;
    BOOL _renameRequested;
    BTIPod *_iPod;
    BTSyncView *_syncView;
    NSMutableSet *_closedFolders;
    // Whether the bars have been put where they were left. Until they have, a
    // layout places them; after that a layout leaves them alone, or dragging one
    // would be undone by the next resize.
    BOOL _dividersPlaced;
    // Whether the last session has been read back yet. The window is built
    // before it has been, so until this is set there is nothing worth saving
    // and a great deal worth not overwriting.
    BOOL _sessionRestored;
    NSImage *_speakerImage;
    BTSmartPlaylistController *_sheetController;
    BTTrackInfoController *_infoController;
    NSUndoManager *_undoManager;
}

#pragma mark Construction

- (instancetype)initMainWindow {
    NSRect frame = NSMakeRect(0, 0, 860, 560);
    // A textured window hands the title bar over to the window's own
    // background, and a full size content view lets the chrome be drawn behind
    // it, so the gradient and the grain carry all the way to the top of the
    // window instead of stopping at a flat gray band.
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask |
                       NSMiniaturizableWindowMask | NSResizableWindowMask |
                       NSTexturedBackgroundWindowMask |
                       NSFullSizeContentViewWindowMask;
    NSWindow *window = [[BTMainWindow alloc] initWithContentRect:frame
                                                       styleMask:style
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
    [window setTitle:@"BTunes"];
    [window setMinSize:NSMakeSize(640, 420)];
    [window setFrameAutosaveName:@"BTunesMainWindow"];

    // The title bar takes the color of the chrome below it, so the top of the
    // window reads as one piece with the close, minimize and zoom buttons
    // sitting on it. Nothing moves: the content keeps its own area, the bar
    // above it simply stops being painted by the system.
    [window setTitlebarAppearsTransparent:YES];
    [window setBackgroundColor:[BTStyle chromeTop]];

    self = [super initWithWindow:window];
    if (self == nil) return nil;

    // The window hands out this controller's undo manager, so the search field
    // and the playlist edits share one stack and Command-Z means the last thing
    // done either way.
    [window setDelegate:self];

    _selectedSource = BTLibrarySource;
    _sortColumn = @"track";
    _sortAscending = YES;
    _closedFolders = [NSMutableSet set];
    _visibleTracks = @[];
    _speakerImage = [self buildSpeakerImage];

    [self buildChrome];
    [self buildBody];
    [self buildBottomBar];
    [self layoutContent];
    [self updateKeyViewLoop];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(libraryChanged:) name:BTLibraryDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(playerChanged:) name:BTPlayerDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(iPodChanged:) name:BTIPodDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(settingsChanged:) name:BTPreferencesDidChangeNotification object:nil];

    [self iPodChanged:nil];
    [self reloadEverything];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSImage *)buildSpeakerImage {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(12, 12)];
    [image lockFocus];
    [BTStyle drawSpeakerGlyphInRect:NSMakeRect(0, 0, 12, 12)
                              waves:1
                              color:[NSColor colorWithCalibratedWhite:0.15 alpha:1.0]];
    [image unlockFocus];
    return image;
}

- (NSImage *)iconForSource:(id)item {
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(14, 14)];
    [image lockFocus];

    NSColor *blue = [BTStyle sourceIcon];
    if ([item isKindOfClass:[BTIPod class]]) {
        // A little white slab with a wheel on it.
        NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(3.5, 0.5, 7, 13)
                                                             xRadius:1.5
                                                             yRadius:1.5];
        [[NSColor colorWithCalibratedWhite:0.97 alpha:1.0] set];
        [body fill];
        [[NSColor colorWithCalibratedWhite:0.40 alpha:1.0] set];
        [body stroke];

        [[NSColor colorWithCalibratedWhite:0.65 alpha:1.0] set];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5, 2, 4, 4)] fill];
        [[NSColor colorWithCalibratedRed:0.62 green:0.76 blue:0.93 alpha:1.0] set];
        NSRectFill(NSMakeRect(5, 7.5, 4, 4));
        [image unlockFocus];
        return image;
    }
    if (item == BTRecentlyAddedSource) {
        // A clock face, since the list is about when rather than what.
        NSBezierPath *face = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 13, 13)];
        [blue set];
        [face fill];
        [[NSColor whiteColor] set];
        NSBezierPath *hands = [NSBezierPath bezierPath];
        [hands setLineWidth:1.4];
        [hands moveToPoint:NSMakePoint(7, 7)];
        [hands lineToPoint:NSMakePoint(7, 10.5)];      // to the hour
        [hands moveToPoint:NSMakePoint(7, 7)];
        [hands lineToPoint:NSMakePoint(9.8, 7)];       // and past it
        [hands stroke];
        [image unlockFocus];
        return image;
    }
    if (item == BTLibrarySource) {
        NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 13, 13)];
        [blue set];
        [circle fill];
        [[NSColor whiteColor] set];
        NSRectFill(NSMakeRect(8, 5, 1.6, 6));
        NSBezierPath *head = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.4, 3.4, 4, 3.2)];
        [head fill];
    } else {
        BTPlaylist *playlist = (BTPlaylist *)item;
        if (playlist.kind == BTPlaylistKindFolder) {
            NSBezierPath *folder = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0.5, 2.5, 13, 9)
                                                                   xRadius:1.5
                                                                   yRadius:1.5];
            [[NSColor colorWithCalibratedRed:0.63 green:0.70 blue:0.80 alpha:1.0] set];
            [folder fill];
            [[NSColor colorWithCalibratedWhite:0.35 alpha:1.0] set];
            [folder stroke];
            NSRectFill(NSMakeRect(1.5, 11, 5, 1.5));
        } else {
            NSBezierPath *page = [NSBezierPath bezierPathWithRect:NSMakeRect(1.5, 1.5, 11, 11)];
            [[NSColor whiteColor] set];
            [page fill];
            [[NSColor colorWithCalibratedWhite:0.45 alpha:1.0] set];
            [page stroke];
            NSColor *ink = (playlist.kind == BTPlaylistKindSmart)
                ? [BTStyle smartPlaylistIcon] : blue;
            [ink set];
            NSRectFill(NSMakeRect(8, 5, 1.4, 5));
            NSBezierPath *head = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.6, 3.6, 3.6, 2.8)];
            [head fill];
            if (playlist.kind == BTPlaylistKindSmart) {
                NSRectFill(NSMakeRect(3, 10, 2, 2));
            }
        }
    }
    [image unlockFocus];
    return image;
}

- (void)buildChrome {
    NSView *content = [[self window] contentView];
    NSRect bounds = [content bounds];

    CGFloat chromeHeight = BT_CHROME_HEIGHT + BTTitleBarHeight();
    _chrome = [[BTChromeView alloc] initWithFrame:NSMakeRect(0, NSMaxY(bounds) - chromeHeight,
                                                             NSWidth(bounds), chromeHeight)];
    [_chrome setAutoresizingMask:(NSViewWidthSizable | NSViewMinYMargin)];
    [content addSubview:_chrome];

    _previousButton = [BTRoundButton buttonWithFrame:NSMakeRect(14, 16, 24, 24)
                                               glyph:BTGlyphPrevious
                                              target:self
                                              action:@selector(previousTrack:)];
    _playButton = [BTRoundButton buttonWithFrame:NSMakeRect(42, 12, 32, 32)
                                           glyph:BTGlyphPlay
                                          target:self
                                          action:@selector(playPause:)];
    _nextButton = [BTRoundButton buttonWithFrame:NSMakeRect(78, 16, 24, 24)
                                           glyph:BTGlyphNext
                                          target:self
                                          action:@selector(nextTrack:)];
    [_chrome addSubview:_previousButton];
    [_chrome addSubview:_playButton];
    [_chrome addSubview:_nextButton];

    _volumeView = [[BTVolumeView alloc] initWithFrame:NSMakeRect(112, 18, 100, 20)];
    _volumeView.target = self;
    _volumeView.action = @selector(volumeChanged:);
    [_volumeView setVolume:[[BTPlayer sharedPlayer] volume]];
    [_chrome addSubview:_volumeView];

    _display = [[BTDisplayView alloc] initWithFrame:NSMakeRect(230, 6, 340, [BTDisplayView naturalHeight])];
    [_display setAutoresizingMask:NSViewWidthSizable];
    [_chrome addSubview:_display];

    // The search field sits in from the right, with a round button beyond it in
    // the spot iTunes 4 used for Browse.
    _searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(NSWidth(bounds) - 204, 17, 150, 21)];

    BTSearchFieldCell *searchCell = [[BTSearchFieldCell alloc] initTextCell:@""];
    [searchCell setEditable:YES];
    [searchCell setSelectable:YES];
    [searchCell setScrollable:YES];
    [searchCell setBezeled:NO];
    [searchCell setBordered:NO];
    [searchCell setDrawsBackground:NO];
    [searchCell setFont:[BTStyle uiFont]];
    [searchCell setPlaceholderString:@"Search"];
    [searchCell setSendsWholeSearchString:NO];
    [_searchField setCell:searchCell];
    [_searchField setFocusRingType:NSFocusRingTypeNone];
    [_searchField setAutoresizingMask:NSViewMinXMargin];
    [_searchField setTarget:self];
    [_searchField setAction:@selector(searchChanged:)];
    [_chrome addSubview:_searchField];

    _miniButton = [BTRoundButton buttonWithFrame:NSMakeRect(NSWidth(bounds) - 42, 14, 27, 27)
                                           glyph:BTGlyphShrink
                                          target:nil
                                          action:@selector(toggleMiniMode:)];
    [_miniButton setToolTip:@"Mini player"];
    [_chrome addSubview:_miniButton];

    __weak BTMainWindowController *weakSelf = self;
    _chrome.layoutHandler = ^{ [weakSelf layoutChrome]; };
    [self layoutChrome];
}

- (void)buildBody {
    NSView *content = [[self window] contentView];
    NSRect bounds = [content bounds];
    NSRect bodyFrame = NSMakeRect(0, BT_BOTTOM_HEIGHT, NSWidth(bounds),
                                  NSHeight(bounds) - BT_CHROME_HEIGHT - BT_BOTTOM_HEIGHT);

    _outerSplit = [[NSSplitView alloc] initWithFrame:bodyFrame];
    [_outerSplit setVertical:YES];
    [_outerSplit setDividerStyle:NSSplitViewDividerStyleThin];
    [_outerSplit setDelegate:self];
    [_outerSplit setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [content addSubview:_outerSplit];

    // Source list.
    NSScrollView *sourceScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 170, NSHeight(bodyFrame))];
    [sourceScroll setHasVerticalScroller:YES];
    [sourceScroll setAutohidesScrollers:YES];
    [sourceScroll setBorderType:NSNoBorder];
    [sourceScroll setDrawsBackground:YES];
    [sourceScroll setBackgroundColor:[BTStyle listBackground]];
    [sourceScroll setFocusRingType:NSFocusRingTypeNone];
    [sourceScroll setAutomaticallyAdjustsContentInsets:NO];
    [sourceScroll setContentInsets:NSEdgeInsetsMake(BT_SOURCE_TOP_INSET, 0, 0, 0)];

    _sourceList = [[BTKeyOutlineView alloc] initWithFrame:[[sourceScroll contentView] bounds]];
    [_sourceList setFocusRingType:NSFocusRingTypeNone];
    NSTableColumn *sourceColumn = [[NSTableColumn alloc] initWithIdentifier:@"source"];
    // A starting width only. It follows the pane from here on, or a name wider
    // than this stays cut short however far the pane is dragged open.
    [sourceColumn setWidth:150];
    BTSourceCell *sourceCell = [[BTSourceCell alloc] init];
    [sourceCell setFont:[BTStyle uiFont]];
    [sourceCell setLineBreakMode:NSLineBreakByTruncatingTail];
    [sourceCell setEditable:YES];
    [sourceColumn setDataCell:sourceCell];
    [_sourceList addTableColumn:sourceColumn];
    [_sourceList setOutlineTableColumn:sourceColumn];
    [_sourceList setHeaderView:nil];
    [_sourceList setRowHeight:[BTStyle sourceRowHeight]];
    [_sourceList setIndentationPerLevel:14.0];
    [_sourceList setDataSource:self];
    [_sourceList setDelegate:self];
    [_sourceList setAllowsMultipleSelection:NO];
    [_sourceList setAllowsColumnSelection:NO];
    [_sourceList setTarget:self];
    [_sourceList setAction:@selector(sourceClicked:)];
    [_sourceList setDoubleAction:@selector(renameSelectedPlaylist:)];
    [_sourceList registerForDraggedTypes:@[BTTrackPasteboardType, BTPlaylistPasteboardType]];

    // Making a playlist is the thing this pane is for, so it is offered where
    // the pane is, empty space included, rather than only from the File menu.
    NSMenu *sourceMenu = [[NSMenu alloc] initWithTitle:@"Source"];
    [sourceMenu addItem:[self sourceItemTitled:@"New Playlist" action:@selector(newPlaylist:)]];
    [sourceMenu addItem:[self sourceItemTitled:@"New Smart Playlist..."
                                        action:@selector(newSmartPlaylist:)]];
    [sourceMenu addItem:[self sourceItemTitled:@"New Playlist Folder"
                                        action:@selector(newPlaylistFolder:)]];
    [sourceMenu addItem:[NSMenuItem separatorItem]];
    // Only alive on a playlist built from rules, which validateMenuItem: decides
    // from the row actually clicked rather than the row that happens to be
    // selected.
    [sourceMenu addItem:[self sourceItemTitled:@"Edit Smart Playlist..."
                                        action:@selector(editSmartPlaylist:)]];
    [_sourceList setMenu:sourceMenu];
    [sourceScroll setDocumentView:_sourceList];
    [_outerSplit addSubview:sourceScroll];

    // Browser above, track list below.
    _innerSplit = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(bodyFrame) - 170, NSHeight(bodyFrame))];
    [_innerSplit setVertical:NO];
    [_innerSplit setDividerStyle:NSSplitViewDividerStyleThin];
    [_innerSplit setDelegate:self];

    _browser = [[BTBrowserView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth([_innerSplit bounds]), 150)];
    _browser.browserDelegate = self;
    [_innerSplit addSubview:_browser];

    NSScrollView *trackScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth([_innerSplit bounds]), 300)];
    [trackScroll setHasVerticalScroller:YES];
    [trackScroll setAutohidesScrollers:YES];
    [trackScroll setBorderType:NSNoBorder];
    [trackScroll setFocusRingType:NSFocusRingTypeNone];

    _trackTable = [[BTKeyTableView alloc] initWithFrame:[[trackScroll contentView] bounds]];
    [_trackTable setFocusRingType:NSFocusRingTypeNone];
    BTAddTrackColumns(_trackTable);
    [_trackTable setRowHeight:[BTStyle listRowHeight]];
    [_trackTable setUsesAlternatingRowBackgroundColors:YES];
    [_trackTable setAllowsMultipleSelection:YES];
    [_trackTable setAllowsColumnSelection:NO];
    [_trackTable setDataSource:self];
    [_trackTable setDelegate:self];
    [_trackTable setTarget:self];
    [_trackTable setDoubleAction:@selector(playSelectedTrack:)];
    // Slack is spread across the columns rather than dumped on the last one.
    // The last one is the track number in a playlist, and widening a column of
    // two-digit numbers to fill the window looks like a mistake. The numeric
    // columns are capped, so the words take the space.
    [_trackTable setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
    // Copy carries songs out to another playlist; move rearranges them within
    // the one being shown.
    [_trackTable setDraggingSourceOperationMask:(NSDragOperationCopy | NSDragOperationMove)
                                       forLocal:YES];
    [_trackTable registerForDraggedTypes:@[BTTrackPasteboardType]];

    // Widths and arrangement are the table's own business to remember. Which
    // columns are shown is kept separately, so restoring it cannot argue with
    // the # column, whose presence follows the source.
    NSMenu *songMenu = [[NSMenu alloc] initWithTitle:@"Song"];
    NSMenuItem *info = [[NSMenuItem alloc] initWithTitle:@"Get Info"
                                                  action:@selector(getInfo:)
                                           keyEquivalent:@""];
    [info setTarget:self];
    [songMenu addItem:info];
    [_trackTable setMenu:songMenu];

    [_trackTable setAutosaveName:BTColumnsAutosaveName];
    [_trackTable setAutosaveTableColumns:YES];
    [self restoreColumnVisibility];
    [[_trackTable headerView] setMenu:[self buildColumnMenu]];
    [trackScroll setDocumentView:_trackTable];
    [_innerSplit addSubview:trackScroll];

    [_outerSplit addSubview:_innerSplit];
}

- (void)updateColumnLayout {
    NSTableColumn *order = [_trackTable tableColumnWithIdentifier:@"order"];
    [order setHidden:!_showsPlaylistOrder];
}

#pragma mark - Choosing columns


- (NSMenuItem *)sourceItemTitled:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    [item setTarget:self];
    return item;
}

- (NSMenu *)buildColumnMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Columns"];
    NSArray *columns = [_trackTable tableColumns];
    NSUInteger i;
    for (i = 0; i < [columns count]; i++) {
        NSTableColumn *column = [columns objectAtIndex:i];
        if (!BTColumnCanBeHidden([column identifier])) continue;

        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[[column headerCell] stringValue]
                                                      action:@selector(toggleColumn:)
                                               keyEquivalent:@""];
        [item setTarget:self];
        [item setRepresentedObject:column];
        [menu addItem:item];
    }
    return menu;
}

- (void)toggleColumn:(NSMenuItem *)sender {
    NSTableColumn *column = [sender representedObject];
    [column setHidden:![column isHidden]];
    [self saveColumnVisibility];
    [_trackTable sizeToFit];
}

- (void)saveColumnVisibility {
    NSMutableArray *hidden = [NSMutableArray array];
    NSArray *columns = [_trackTable tableColumns];
    NSUInteger i;
    for (i = 0; i < [columns count]; i++) {
        NSTableColumn *column = [columns objectAtIndex:i];
        if (BTColumnCanBeHidden([column identifier]) && [column isHidden]) {
            [hidden addObject:[column identifier]];
        }
    }
    [[NSUserDefaults standardUserDefaults] setObject:hidden forKey:BTHiddenColumnsKey];
}

- (void)restoreColumnVisibility {
    NSArray *hidden = [[NSUserDefaults standardUserDefaults] arrayForKey:BTHiddenColumnsKey];
    if (hidden == nil) return;   // never chosen, so the starting set stands

    NSArray *columns = [_trackTable tableColumns];
    NSUInteger i;
    for (i = 0; i < [columns count]; i++) {
        NSTableColumn *column = [columns objectAtIndex:i];
        if (!BTColumnCanBeHidden([column identifier])) continue;
        [column setHidden:[hidden containsObject:[column identifier]]];
    }
}

- (void)buildBottomBar {
    NSView *content = [[self window] contentView];
    NSRect bounds = [content bounds];

    _bottomBar = [[BTBottomBarView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(bounds), BT_BOTTOM_HEIGHT)];
    [_bottomBar setAutoresizingMask:(NSViewWidthSizable | NSViewMaxYMargin)];
    [content addSubview:_bottomBar];

    // New playlist, shuffle, and repeat sit together at the bottom left.
    CGFloat buttonWidth = 22.0;
    CGFloat gap = 3.0;
    CGFloat left = 6.0;

    BTToggleButton *add = [BTToggleButton buttonWithFrame:NSMakeRect(left, 2, buttonWidth, 20)
                                                    glyph:BTGlyphPlus
                                                   target:self
                                                   action:@selector(newPlaylist:)];
    [add setToolTip:@"New playlist"];
    [_bottomBar addSubview:add];

    _shuffleButton = [BTToggleButton buttonWithFrame:NSMakeRect(left + buttonWidth + gap, 2, buttonWidth, 20)
                                               glyph:BTGlyphShuffle
                                              target:self
                                              action:@selector(toggleShuffle:)];
    [_shuffleButton setToolTip:@"Shuffle"];
    [_bottomBar addSubview:_shuffleButton];

    _repeatButton = [BTToggleButton buttonWithFrame:NSMakeRect(left + (buttonWidth + gap) * 2, 2, buttonWidth, 20)
                                              glyph:BTGlyphRepeat
                                             target:self
                                             action:@selector(cycleRepeat:)];
    [_repeatButton setToolTip:@"Repeat"];
    [_bottomBar addSubview:_repeatButton];

    // Bringing music over from iTunes. Furthest right and always there, so it
    // does not shift about as a device comes and goes.
    _syncButton = [BTToggleButton buttonWithFrame:NSMakeRect(NSWidth(bounds) - 30, 2, buttonWidth, 20)
                                            glyph:BTGlyphSync
                                           target:self
                                           action:@selector(showITunesSync:)];
    [_syncButton setToolTip:@"Bring music over from iTunes"];
    [_syncButton setAutoresizingMask:NSViewMinXMargin];
    [_bottomBar addSubview:_syncButton];

    // The eject button sits beside it, and only appears while a device is
    // attached.
    _ejectButton = [BTToggleButton buttonWithFrame:NSMakeRect(NSWidth(bounds) - 56, 2, 22, 20)
                                             glyph:BTGlyphEject
                                            target:self
                                            action:@selector(ejectIPod:)];
    [_ejectButton setToolTip:@"Eject iPod"];
    [_ejectButton setAutoresizingMask:NSViewMinXMargin];
    [_ejectButton setHidden:YES];
    [_bottomBar addSubview:_ejectButton];
}

// Where the three things at the right of the chrome sit, for a given width.
//
// The readout takes the slack and the search field keeps a steady width. It was
// the other way round, which meant a search box the width of the window on a
// wide screen, reading as a mistake. A wider readout simply shows more of the
// song, which is what the space is worth spending on.
//
// Kept as arithmetic on numbers rather than on views, so it can be checked
// without a window.
void BTChromeLayout(CGFloat chromeWidth, CGFloat volumeRight,
                    CGFloat *outMiniLeft,
                    CGFloat *outDisplayLeft, CGFloat *outDisplayWidth,
                    CGFloat *outSearchLeft, CGFloat *outSearchWidth) {
    const CGFloat rightMargin = 15.0;
    const CGFloat miniWidth = 27.0;
    const CGFloat displayLeft = 230.0;
    const CGFloat preferredSearch = 180.0;
    const CGFloat minimumSearch = 88.0;
    const CGFloat minimumDisplay = 200.0;

    // The space either side of the readout is the same: whatever sits between
    // the volume control and the readout on the left is repeated on the right.
    CGFloat gap = displayLeft - volumeRight;
    if (gap < 8.0) gap = 8.0;

    CGFloat miniLeft = chromeWidth - rightMargin - miniWidth;
    CGFloat searchRight = miniLeft - gap;

    CGFloat searchWidth = preferredSearch;
    CGFloat displayWidth = searchRight - searchWidth - gap - displayLeft;
    if (displayWidth < minimumDisplay) {
        // Too narrow for both at their best. The search field gives up width
        // first, because the readout carries the song.
        searchWidth = searchRight - minimumDisplay - gap - displayLeft;
        if (searchWidth < minimumSearch) searchWidth = minimumSearch;
        displayWidth = searchRight - searchWidth - gap - displayLeft;
    }
    if (displayWidth < 60.0) displayWidth = 60.0;

    if (outMiniLeft) *outMiniLeft = miniLeft;
    if (outDisplayLeft) *outDisplayLeft = displayLeft;
    if (outDisplayWidth) *outDisplayWidth = displayWidth;
    if (outSearchLeft) *outSearchLeft = searchRight - searchWidth;
    if (outSearchWidth) *outSearchWidth = searchWidth;
}

- (void)layoutChrome {
    CGFloat miniLeft = 0, displayLeft = 0, displayWidth = 0, searchLeft = 0, searchWidth = 0;
    BTChromeLayout(NSWidth([_chrome bounds]), NSMaxX([_volumeView frame]),
                   &miniLeft, &displayLeft, &displayWidth, &searchLeft, &searchWidth);

    [_miniButton setFrame:NSMakeRect(miniLeft, 14, 27.0, 27.0)];
    [_display setFrame:NSMakeRect(displayLeft, 6, displayWidth, [BTDisplayView naturalHeight])];
    [_searchField setFrame:NSMakeRect(searchLeft, 17, searchWidth, 21)];
}

// The source list has one column and it is the whole width of the pane. Set by
// hand rather than left to a column autoresizing style, because the outline view
// is inside a scroll view whose width is what the column has to match.
- (void)sizeSourceColumn {
    NSScrollView *scroll = [_sourceList enclosingScrollView];
    CGFloat width = [scroll contentSize].width;
    if (width < 20.0) return;

    [_sourceList setFrameSize:NSMakeSize(width, NSHeight([_sourceList frame]))];
    NSArray *columns = [_sourceList tableColumns];
    if ([columns count] > 0) [[columns objectAtIndex:0] setWidth:width];
}

// Where the bars were left, or where they start when nobody has moved them.
- (CGFloat)rememberedSourceWidth {
    NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:BTSourceWidthKey];
    CGFloat width = saved ? [saved doubleValue] : 170.0;
    return (width >= 120.0) ? width : 170.0;
}

- (CGFloat)rememberedBrowserHeight {
    NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:BTBrowserHeightKey];
    CGFloat height = saved ? [saved doubleValue] : 150.0;
    return (height >= 60.0) ? height : 150.0;
}

// A bar has been dragged, or the window resized. Either way the pane sizes are
// now what somebody is looking at, so they are what should come back.
- (void)splitViewDidResizeSubviews:(NSNotification *)note {
    if (!_dividersPlaced) return;
    id split = [note object];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    if (split == _outerSplit && [[_outerSplit subviews] count] == 2) {
        CGFloat width = NSWidth([[[_outerSplit subviews] objectAtIndex:0] frame]);
        if (width >= 120.0) [defaults setDouble:width forKey:BTSourceWidthKey];
    } else if (split == _innerSplit && [[_innerSplit subviews] count] == 2) {
        // Not while the browser is put away: its height is zero then, and a zero
        // is not a height anybody chose.
        if (_browserHidden) return;
        CGFloat height = NSHeight([[[_innerSplit subviews] objectAtIndex:0] frame]);
        if (height >= 60.0) [defaults setDouble:height forKey:BTBrowserHeightKey];
    }
}

- (void)layoutContent {
    NSRect bounds = [[[self window] contentView] bounds];
    CGFloat chromeHeight = BT_CHROME_HEIGHT + BTTitleBarHeight();

    // The chrome reaches up under the title bar. Its controls are positioned
    // from its bottom edge, so they stay where they were.
    [_chrome setFrame:NSMakeRect(0, NSMaxY(bounds) - chromeHeight, NSWidth(bounds), chromeHeight)];
    [_bottomBar setFrame:NSMakeRect(0, 0, NSWidth(bounds), BT_BOTTOM_HEIGHT)];
    [_outerSplit setFrame:NSMakeRect(0, BT_BOTTOM_HEIGHT, NSWidth(bounds),
                                     NSHeight(bounds) - chromeHeight - BT_BOTTOM_HEIGHT)];

    // Only the first time. The two bars were placed at 170 and 150 on every
    // layout, so a bar dragged anywhere went back the next time the window was
    // resized and nothing about it survived a restart. Laying out again keeps
    // whatever width each pane has, which is what resizeSubviewsWithOldSize:
    // below is for.
    if (!_dividersPlaced) {
        _dividersPlaced = YES;
        [_outerSplit setPosition:[self rememberedSourceWidth] ofDividerAtIndex:0];
        [_innerSplit setPosition:[self rememberedBrowserHeight] ofDividerAtIndex:0];
    }
    [_outerSplit adjustSubviews];
    [_innerSplit adjustSubviews];

    // No gap between the last column and the edge of the table. The slack is
    // shared among the columns that hold words, since those are the only ones
    // carrying the autoresizing mask; the numbers keep the width they were
    // given. That is what stopped the columns walking two points to the right on
    // every launch over whatever had been set by hand.
    [_trackTable sizeToFit];
    [self sizeSourceColumn];
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    // The window may have been resized from its saved frame before it appeared.
    [self layoutContent];
    [self restoreSessionState];
}

// Tab moves between the panes in a fixed order: search, sources, the three
// browser columns, the track list, back to search. The browser drops out of the
// order while it is put away.
- (void)updateKeyViewLoop {
    [_searchField setNextKeyView:_sourceList];
    if (_browserHidden) {
        [_sourceList setNextKeyView:_trackTable];
    } else {
        [_sourceList setNextKeyView:[_browser firstColumnView]];
        [[_browser lastColumnView] setNextKeyView:_trackTable];
    }
    [_trackTable setNextKeyView:_searchField];
    [[self window] setInitialFirstResponder:_trackTable];
}

// Selecting the iPod puts the sync pane where the browser and track list are.
// Three things can occupy the right half: the songs, the iPod, or the iTunes
// sync. Only one of them is put there at a time.
- (void)updateRightPane {
    NSArray *subviews = [_outerSplit subviews];
    if ([subviews count] != 2) return;
    NSView *current = [subviews objectAtIndex:1];

    NSView *wanted = _innerSplit;
    if (_showingITunesSync) {
        if (_iTunesSyncView == nil) {
            _iTunesSyncView = [[BTITunesSyncView alloc] initWithFrame:[current frame]];
            __weak BTMainWindowController *weakSelf = self;
            _iTunesSyncView.didFinish = ^{ [weakSelf closeITunesSync]; };
        }
        wanted = _iTunesSyncView;
    } else if ([_selectedSource isKindOfClass:[BTIPod class]]) {
        if (_syncView == nil) _syncView = [[BTSyncView alloc] initWithFrame:[current frame]];
        _syncView.iPod = (BTIPod *)_selectedSource;
        wanted = _syncView;
    }

    if (current != wanted) {
        [_outerSplit replaceSubview:current with:wanted];
        [wanted setFrame:[current frame]];
    }
    [_outerSplit adjustSubviews];
}

// The sync only ever occupies the right half, so picking anything on the left
// leaves it by putting that source's songs back in its place.
- (void)showITunesSync:(id)sender {
    // The same button both ways: it opened the pane, so it puts it away and
    // gives back whatever was being looked at before.
    if (_showingITunesSync) {
        [self closeITunesSync];
        return;
    }
    _showingITunesSync = YES;
    _syncButton.on = YES;
    [self updateRightPane];
    [_iTunesSyncView beginComparing];
}

// A click that lands on the row already selected sends no selection change, so
// the sync pane would sit there while the source list looked as though it had
// been answered.
- (void)sourceClicked:(id)sender {
    if (_showingITunesSync) [self closeITunesSync];
}

- (void)closeITunesSync {
    if (!_showingITunesSync) return;
    _showingITunesSync = NO;
    _syncButton.on = NO;
    [self updateRightPane];
    [self reloadEverything];
}

- (void)iPodChanged:(NSNotification *)note {
    BTIPod *found = [BTIPod attachedIPod];
    BOOL had = (_iPod != nil);
    _iPod = found;

    // Fall back to the library when the device the pane was showing goes away.
    if (_iPod == nil && [_selectedSource isKindOfClass:[BTIPod class]]) {
        _selectedSource = BTLibrarySource;
        [self updateRightPane];
        [self updateBrowserVisibility];
    }
    [_sourceList reloadData];
    [self updateBottomBar];
    if (had != (found != nil)) [self reloadEverything];
}

- (void)ejectIPod:(id)sender {
    if (_iPod == nil) return;

    if (![_iPod eject]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"The iPod would not eject."];
        [alert setInformativeText:@"Something is still using it. Try again in a moment."];
        [alert runModal];
        return;
    }
    [self iPodChanged:nil];
}

- (void)updateBottomBar {
    [_ejectButton setHidden:(_iPod == nil)];
}

- (void)updateBrowserVisibility {
    BOOL hidden = (_selectedSource != BTLibrarySource);
    if (hidden == _browserHidden) return;

    _browserHidden = hidden;
    [_browser setHidden:hidden];
    [self updateKeyViewLoop];
    if (!hidden) {
        // Give it back the height it had before it was put away, and failing
        // that the height it was last dragged to.
        NSRect frame = [_browser frame];
        if (NSHeight(frame) < 60.0) {
            frame.size.height = [self rememberedBrowserHeight];
            [_browser setFrame:frame];
        }
    }
    [_innerSplit adjustSubviews];
}

#pragma mark - Reloading

// The iPod shows a sync pane rather than songs, so it contributes none.
//
// A playlist's own order is captured here, where its songs are resolved, rather
// than worked out again later. A playlist that holds one album whole leads with
// the album's numbering instead, and a smart playlist has no order of its own
// since the rules decide what is in it.
- (NSArray *)baseTracks {
    BTLibrary *library = [BTLibrary sharedLibrary];
    BTPlaylist *playlist = BTPlaylistFromSource(_selectedSource);

    if (playlist == nil) {
        _sourceOrder = nil;
        _showsPlaylistOrder = NO;
        BOOL wholeLibrary = (_selectedSource == BTLibrarySource ||
                             _selectedSource == BTRecentlyAddedSource ||
                             _selectedSource == nil);
        return wholeLibrary ? library.tracks : @[];
    }

    NSArray *tracks = [playlist resolveTracks:library.tracks];
    NSMutableDictionary *order = [NSMutableDictionary dictionaryWithCapacity:[tracks count]];
    NSUInteger i;
    for (i = 0; i < [tracks count]; i++) {
        [order setObject:@(i + 1) forKey:[[tracks objectAtIndex:i] trackID]];
    }
    _sourceOrder = order;
    _showsPlaylistOrder = YES;
    return tracks;
}

// A source opens the way it was last left. Until it has been sorted by hand it
// opens the way its kind suggests.
// Recently Added is one view with one order, and that order is the whole of
// what it is for. There is nothing to sort it by and so nothing to remember.
- (BOOL)selectedSourceSortIsFrozen {
    return _selectedSource == BTRecentlyAddedSource;
}

- (void)adoptSortForSelectedSource {
    if ([self selectedSourceSortIsFrozen]) {
        _sortColumn = @"dateAdded";
        _sortAscending = NO;              // newest at the top
        return;
    }

    BTPlaylist *playlist = BTPlaylistFromSource(_selectedSource);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSString *remembered = playlist ? playlist.sortColumn
                                    : [defaults stringForKey:BTLibrarySortKey];
    if ([remembered length] > 0) {
        _sortColumn = remembered;
        _sortAscending = playlist ? playlist.sortAscending
                                  : [defaults boolForKey:BTLibrarySortAscendingKey];
        return;
    }

    _sortColumn = [self defaultSortColumnForSelectedSource];
    _sortAscending = YES;
}

- (void)rememberSortForSelectedSource {
    if ([self selectedSourceSortIsFrozen]) return;

    BTPlaylist *playlist = BTPlaylistFromSource(_selectedSource);
    if (playlist) {
        playlist.sortColumn = _sortColumn;
        playlist.sortAscending = _sortAscending;
        [[BTLibrary sharedLibrary] noteChanged];
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:(_sortColumn ? _sortColumn : @"") forKey:BTLibrarySortKey];
    [defaults setBool:_sortAscending forKey:BTLibrarySortAscendingKey];
}

// A playlist opens in its own order. Everything else opens by track number.
- (NSString *)defaultSortColumnForSelectedSource {
    return BTPlaylistFromSource(_selectedSource) ? @"order" : @"track";
}

// Folders come up open, since a closed one hides the playlists it holds. One
// you have closed yourself stays closed: the list is rebuilt on every library
// change, and without remembering that, playing a song would open it again.
// Both ways, not only open. A folder left closed last time has to be closed
// here, and the window is built with every folder open before the record of
// which ones were closed has even been read.
- (void)expandFolders {
    NSInteger row;
    for (row = 0; row < [_sourceList numberOfRows]; row++) {
        id item = [_sourceList itemAtRow:row];
        if (item == nil || ![_sourceList isExpandable:item]) continue;
        BTPlaylist *folder = BTPlaylistFromSource(item);
        if (folder && [_closedFolders containsObject:folder.playlistID]) {
            [_sourceList collapseItem:item];
            continue;
        }
        [_sourceList expandItem:item];
    }
}

- (void)outlineViewItemDidCollapse:(NSNotification *)note {
    BTPlaylist *folder = BTPlaylistFromSource([[note userInfo] objectForKey:@"NSObject"]);
    if (folder == nil) return;
    [_closedFolders addObject:folder.playlistID];
    [self saveSessionState];
}

- (void)outlineViewItemDidExpand:(NSNotification *)note {
    BTPlaylist *folder = BTPlaylistFromSource([[note userInfo] objectForKey:@"NSObject"]);
    if (folder == nil) return;
    [_closedFolders removeObject:folder.playlistID];
    [self saveSessionState];
}

#pragma mark - Session state

// Nothing is written back before the last session has been read.
//
// The window is built with the library selected and every folder open, and
// building it opens the folders, which is a change and asks to be saved. Saving
// it overwrote both of the things restoring was about to read, so whatever was
// selected last time was gone before anything looked for it and the window
// always opened on the library.
- (void)saveSessionState {
    if (!_sessionRestored) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:[_closedFolders allObjects] forKey:BTClosedFoldersKey];

    BTPlaylist *playlist = BTPlaylistFromSource(_selectedSource);
    NSString *source = BTLibraryWasSelected;
    if (playlist) {
        source = playlist.playlistID;
    } else if ([_selectedSource isKindOfClass:[BTIPod class]]) {
        source = BTIPodWasSelected;
    } else if (_selectedSource == BTRecentlyAddedSource) {
        source = BTRecentWasSelected;
    }
    [defaults setObject:source forKey:BTSelectedSourceKey];

    NSInteger row = [_trackTable selectedRow];
    if (row >= 0 && row < (NSInteger)[_visibleTracks count]) {
        [defaults setObject:[[_visibleTracks objectAtIndex:(NSUInteger)row] trackID]
                     forKey:BTSelectedTrackKey];
    } else {
        [defaults removeObjectForKey:BTSelectedTrackKey];
    }
}

- (void)restoreSessionState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Read before anything else, because picking the source below clears the
    // song selection and writes that back out. The song being restored would
    // otherwise be forgotten a moment before it was looked up.
    NSString *rememberedTrack = [defaults stringForKey:BTSelectedTrackKey];

    NSArray *closed = [defaults arrayForKey:BTClosedFoldersKey];
    if (closed) [_closedFolders addObjectsFromArray:closed];

    // Whatever was open last time comes back, so long as it still exists. A
    // playlist may have been deleted since, and the iPod may simply not be
    // plugged in this time; either way the library is what is left.
    NSString *source = [defaults stringForKey:BTSelectedSourceKey];
    if ([source isEqualToString:BTIPodWasSelected]) {
        if (_iPod) _selectedSource = _iPod;
    } else if ([source isEqualToString:BTRecentWasSelected]) {
        _selectedSource = BTRecentlyAddedSource;
    } else if ([source length] > 0 && ![source isEqualToString:BTLibraryWasSelected]) {
        BTPlaylist *playlist = [[BTLibrary sharedLibrary] playlistWithID:source];
        if (playlist) _selectedSource = playlist;
    }

    if (_selectedSource != BTLibrarySource) {
        [self updateBrowserVisibility];
        [self updateRightPane];
    }
    [self adoptSortForSelectedSource];
    [self reloadEverything];
    [self showSortIndicator];

    // The left pane has to agree with what the right one is showing. A playlist
    // sitting in a folder that was left closed would otherwise leave nothing
    // highlighted beside a track list full of its songs.
    BTPlaylist *restored = BTPlaylistFromSource(_selectedSource);
    if (restored) [self revealPlaylist:restored];

    NSInteger row = [_sourceList rowForItem:_selectedSource];
    if (row >= 0) {
        [_sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                 byExtendingSelection:NO];
    }

    if ([rememberedTrack length] > 0) {
        NSUInteger i;
        for (i = 0; i < [_visibleTracks count]; i++) {
            if ([[[_visibleTracks objectAtIndex:i] trackID] isEqualToString:rememberedTrack]) {
                [_trackTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i]
                         byExtendingSelection:NO];
                [_trackTable scrollRowToVisible:(NSInteger)i];
                break;
            }
        }
    }

    // The songs get the keyboard to open with. Only the list holding it draws
    // the strong selection, so leaving it nowhere would open the window with
    // every selection gray and nothing looking chosen.
    [[self window] makeFirstResponder:_trackTable];

    // From here on a change is somebody's choice rather than the window being
    // put together, and is worth keeping.
    _sessionRestored = YES;
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    if ([note object] == _trackTable) [self saveSessionState];
}

- (void)reloadEverything {
    NSArray *base = [self baseTracks];
    [self updateColumnLayout];

    NSString *search = [_searchField stringValue];
    if ([search length] > 0) {
        NSMutableArray *filtered = [NSMutableArray array];
        NSUInteger i;
        for (i = 0; i < [base count]; i++) {
            BTTrack *t = [base objectAtIndex:i];
            if ([t matchesSearchString:search]) [filtered addObject:t];
        }
        base = filtered;
    }

    [_browser setSourceTracks:base];

    [_sourceList reloadData];
    [self expandFolders];
    [self reloadTrackList];
    [self updateTransport];
}

// What the track list shows is whatever survives the browser columns, in the
// current sort order. The browser can narrow on its own without the source or
// the search changing, so this is the smaller of the two reloads.
- (void)reloadTrackList {
    _visibleTracks = BTSortTracks([_browser filteredTracks], _sortColumn, _sortAscending, _sourceOrder);
    [_trackTable reloadData];
    [self updateStatus];
}

- (void)updateStatus {
    NSTimeInterval total = 0;
    long long bytes = 0;
    NSUInteger i;
    for (i = 0; i < [_visibleTracks count]; i++) {
        BTTrack *t = [_visibleTracks objectAtIndex:i];
        total += t.duration;
        bytes += t.fileSize;
    }

    NSUInteger count = [_visibleTracks count];
    _bottomBar.statusText = [NSString stringWithFormat:@"%lu song%@, %@, %@",
                             (unsigned long)count,
                             (count == 1 ? @"" : @"s"),
                             [BTTrack runningTimeStringFromInterval:total],
                             BTSizeString(bytes)];
    [_bottomBar setNeedsDisplay:YES];
}

- (void)updateTransport {
    BTPlayer *player = [BTPlayer sharedPlayer];
    _playButton.glyph = [player isPlaying] ? BTGlyphPause : BTGlyphPlay;
    _shuffleButton.on = player.shuffle;
    _repeatButton.on = (player.repeatMode != BTRepeatModeOff);
    _repeatButton.glyph = (player.repeatMode == BTRepeatModeOne) ? BTGlyphRepeatOne : BTGlyphRepeat;
    [_volumeView setVolume:[player volume]];
}

- (void)libraryChanged:(NSNotification *)note {
    [self reloadEverything];
}

// Purple mode reaches colours that are drawn rather than stored, so every view
// has to be told, not only the ones that reload their contents.
static void BTRedrawEverything(NSView *view) {
    [view setNeedsDisplay:YES];
    NSArray *subviews = [view subviews];
    NSUInteger i;
    for (i = 0; i < [subviews count]; i++) {
        BTRedrawEverything([subviews objectAtIndex:i]);
    }
}

- (void)settingsChanged:(NSNotification *)note {
    [self reloadEverything];
    BTRedrawEverything([[self window] contentView]);
}

- (void)playerChanged:(NSNotification *)note {
    [self updateTransport];
    [_trackTable setNeedsDisplay:YES];
}

#pragma mark - Source list data

// Playlists come in three kinds and each kind sits together: the smart ones
// first, then the folders, then the ones built by hand. The same order applies
// inside a folder as at the top, so a smart playlist is at the top of whatever
// holds it.
//
// Within a kind nothing is rearranged. Whatever arrangement is there is somebody
// having put it there, and grouping is no reason to lose it.
// By name, the way a list of names is looked through: you know what the playlist
// is called, so the question is always where that name falls.
//
// Compared the way the Finder compares, so "Disc 2" comes before "Disc 10"
// rather than after it, and so an accent or a capital does not send a name
// somewhere nobody would look for it.
static NSComparisonResult BTCompareSourceNames(BTPlaylist *a, BTPlaylist *b) {
    NSString *left = a.name ? a.name : @"";
    NSString *right = b.name ? b.name : @"";
    NSComparisonResult result = [left localizedStandardCompare:right];
    // Two playlists of the same name still have to fall in a settled order, or
    // they would swap places every time the list was rebuilt.
    if (result == NSOrderedSame) {
        result = [(a.playlistID ? a.playlistID : @"") compare:(b.playlistID ? b.playlistID : @"")];
    }
    return result;
}

- (NSArray *)sourcesArranged:(NSArray *)playlists {
    NSMutableArray *smart = [NSMutableArray array];
    NSMutableArray *folders = [NSMutableArray array];
    NSMutableArray *byHand = [NSMutableArray array];

    NSUInteger i;
    for (i = 0; i < [playlists count]; i++) {
        BTPlaylist *playlist = [playlists objectAtIndex:i];
        if (playlist.kind == BTPlaylistKindSmart) {
            [smart addObject:playlist];
        } else if (playlist.kind == BTPlaylistKindFolder) {
            [folders addObject:playlist];
        } else {
            [byHand addObject:playlist];
        }
    }

    NSComparator byName = ^NSComparisonResult(id a, id b) {
        return BTCompareSourceNames(a, b);
    };
    [smart sortUsingComparator:byName];
    [folders sortUsingComparator:byName];
    [byHand sortUsingComparator:byName];

    [smart addObjectsFromArray:folders];
    [smart addObjectsFromArray:byHand];
    return smart;
}

- (NSArray *)childrenOfSourceItem:(id)item {
    if (item == nil) {
        NSMutableArray *roots = [NSMutableArray arrayWithObjects:BTLibrarySource,
                                 BTRecentlyAddedSource, nil];
        // The iPod sits under the two library views, above the playlists.
        if (_iPod) [roots addObject:_iPod];
        [roots addObjectsFromArray:[self sourcesArranged:[BTLibrary sharedLibrary].playlists]];
        return roots;
    }
    BTPlaylist *playlist = BTPlaylistFromSource(item);
    if (playlist == nil || playlist.kind != BTPlaylistKindFolder) return @[];
    return [self sourcesArranged:playlist.children];
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    return (NSInteger)[[self childrenOfSourceItem:item] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return [[self childrenOfSourceItem:item] objectAtIndex:(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [[self childrenOfSourceItem:item] count] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                       byItem:(id)item {
    if (item == BTLibrarySource) return @"Library";
    if (item == BTRecentlyAddedSource) return @"Recently Added";
    if ([item isKindOfClass:[BTIPod class]]) return [(BTIPod *)item name];
    return [(BTPlaylist *)item name];
}

- (void)outlineView:(NSOutlineView *)outlineView
     setObjectValue:(id)object
     forTableColumn:(NSTableColumn *)tableColumn
             byItem:(id)item {
    BTPlaylist *playlist = BTPlaylistFromSource(item);
    if (playlist == nil) return;
    if ([object isKindOfClass:[NSString class]] && [(NSString *)object length] > 0) {
        [playlist setName:object];
        [[BTLibrary sharedLibrary] noteChanged];
    }
}

- (void)outlineView:(NSOutlineView *)outlineView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn
               item:(id)item {
    if ([cell isKindOfClass:[BTSourceCell class]]) {
        BTSourceCell *sourceCell = cell;
        sourceCell.icon = [self iconForSource:item];
        sourceCell.showsEject = [item isKindOfClass:[BTIPod class]];

        BOOL selected = ([outlineView selectedRow] == [outlineView rowForItem:item]);
        [sourceCell setHighlighted:NO];
        // White words on the gray fill are barely words, so the text follows
        // the fill rather than the selection.
        BOOL strong = (selected && BTListHasFocus(outlineView));
        [sourceCell setTextColor:(strong ? [NSColor whiteColor] : [NSColor blackColor])];
    }
}

// Renaming happens on a double click, or right after a playlist is created.
// Without this gate, tabbing through the window opens an editor on whatever
// row it lands on.
- (BOOL)outlineView:(NSOutlineView *)outlineView
shouldEditTableColumn:(NSTableColumn *)tableColumn
               item:(id)item {
    return _renameRequested && BTPlaylistFromSource(item) != nil;
}

- (void)beginRenamingRow:(NSInteger)row {
    if (row < 0) return;
    if (BTPlaylistFromSource([_sourceList itemAtRow:row]) == nil) return;

    _renameRequested = YES;
    [_sourceList editColumn:0 row:row withEvent:nil select:YES];
    _renameRequested = NO;
}

- (void)renameSelectedPlaylist:(id)sender {
    NSInteger row = [_sourceList clickedRow];
    if (row < 0) row = [_sourceList selectedRow];
    [self beginRenamingRow:row];
}

// The playlist the source list has selected, or nil when the selection is the
// library, the iPod, or nothing at all.
- (BTPlaylist *)selectedPlaylist {
    NSInteger row = [_sourceList selectedRow];
    return (row >= 0) ? BTPlaylistFromSource([_sourceList itemAtRow:row]) : nil;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = [_sourceList selectedRow];
    id item = (row >= 0) ? [_sourceList itemAtRow:row] : BTLibrarySource;
    if (item == nil) item = BTLibrarySource;
    _selectedSource = item;
    _showingITunesSync = NO;
    _syncButton.on = NO;

    // Nothing is chosen in a list nobody has looked at yet. Left alone, the
    // selection stays on whatever row number it was and lands on an unrelated
    // song in the new source, which reads as a choice somebody made.
    [_trackTable deselectAll:nil];

    [self adoptSortForSelectedSource];
    [self saveSessionState];

    [self showSortIndicator];

    [_browser resetSelection];
    [self updateBrowserVisibility];
    [self updateRightPane];
    [self reloadEverything];
}

#pragma mark - Source list drag and drop

- (BOOL)outlineView:(NSOutlineView *)outlineView
         writeItems:(NSArray *)items
       toPasteboard:(NSPasteboard *)pasteboard {
    if ([items count] != 1) return NO;
    BTPlaylist *playlist = BTPlaylistFromSource([items objectAtIndex:0]);
    if (playlist == nil) return NO;

    [pasteboard declareTypes:@[BTPlaylistPasteboardType] owner:self];
    [pasteboard setString:playlist.playlistID forType:BTPlaylistPasteboardType];
    return YES;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView
                  validateDrop:(id<NSDraggingInfo>)info
                  proposedItem:(id)item
            proposedChildIndex:(NSInteger)index {
    NSPasteboard *pasteboard = [info draggingPasteboard];
    BTPlaylist *target = BTPlaylistFromSource(item);

    if ([[pasteboard types] containsObject:BTTrackPasteboardType]) {
        // Songs land on a static playlist, never on the library, the iPod, or a
        // folder.
        if (target == nil || target.kind != BTPlaylistKindStatic) return NSDragOperationNone;
        if (index != NSOutlineViewDropOnItemIndex) return NSDragOperationNone;
        return NSDragOperationCopy;
    }

    if ([[pasteboard types] containsObject:BTPlaylistPasteboardType]) {
        // The top level, or a folder. Dropping onto the library or the iPod
        // means nothing.
        if (item != nil && (target == nil || target.kind != BTPlaylistKindFolder)) {
            return NSDragOperationNone;
        }
        // Which folder, not which position. Names decide the order now, so a
        // line drawn between two playlists would promise a place the list would
        // not keep. Dropping between them is taken as dropping into whatever
        // holds them, and the folder lights up to say so.
        if (index != NSOutlineViewDropOnItemIndex) {
            [outlineView setDropItem:item dropChildIndex:NSOutlineViewDropOnItemIndex];
        }
        return NSDragOperationMove;
    }
    return NSDragOperationNone;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView
         acceptDrop:(id<NSDraggingInfo>)info
               item:(id)item
         childIndex:(NSInteger)index {
    NSPasteboard *pasteboard = [info draggingPasteboard];
    BTLibrary *library = [BTLibrary sharedLibrary];
    BTPlaylist *target = BTPlaylistFromSource(item);

    if ([[pasteboard types] containsObject:BTTrackPasteboardType]) {
        if (target == nil) return NO;
        NSArray *ids = [NSKeyedUnarchiver unarchiveObjectWithData:[pasteboard dataForType:BTTrackPasteboardType]];
        NSUInteger i;
        for (i = 0; i < [ids count]; i++) {
            NSString *trackID = [ids objectAtIndex:i];
            if (![target.trackIDs containsObject:trackID]) [target.trackIDs addObject:trackID];
        }
        [library noteChanged];
        return YES;
    }

    if ([[pasteboard types] containsObject:BTPlaylistPasteboardType]) {
        NSString *playlistID = [pasteboard stringForType:BTPlaylistPasteboardType];
        BTPlaylist *moving = [library playlistWithID:playlistID];
        if (moving == nil) return NO;
        // The end of wherever it lands. Where it sits in the list is decided by
        // its name, so the place in the array is only where it is kept.
        [library movePlaylist:moving toFolder:target atIndex:-1];
        return YES;
    }
    return NO;
}

#pragma mark - Track table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)[_visibleTracks count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                          row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)[_visibleTracks count]) return nil;
    return BTTrackColumnValue([tableColumn identifier],
                              [_visibleTracks objectAtIndex:(NSUInteger)row],
                              _sourceOrder);
}

- (void)tableView:(NSTableView *)tableView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn
                row:(NSInteger)row {
    if (![cell isKindOfClass:[NSTextFieldCell class]]) return;
    if (row < 0 || row >= (NSInteger)[_visibleTracks count]) return;

    // The row fill is drawn once, by the table. Letting each cell draw its own
    // highlight on top of that produces a patchwork, since a cell in a list
    // without focus paints a different color than the row underneath it.
    BOOL selected = [[tableView selectedRowIndexes] containsIndex:(NSUInteger)row];
    [(NSTextFieldCell *)cell setHighlighted:NO];

    // A locked purchase is listed but cannot play, so it reads as unavailable.
    BTTrack *track = [_visibleTracks objectAtIndex:(NSUInteger)row];

    if ([cell isKindOfClass:[BTTrackNumberCell class]]) {
        // The mark has a column to itself at the near end, so it stays where the
        // eye looks for it however the track number is arranged.
        BOOL playing = (track == [[BTPlayer sharedPlayer] currentTrack]);
        BOOL isTheMark = [[tableColumn identifier] isEqualToString:@"playing"];
        [(BTTrackNumberCell *)cell setIndicator:((playing && isTheMark) ? _speakerImage : nil)];
    }
    // The same gray the sync pane draws a locked purchase in, asked for by the
    // same name. Written out here, giving one of them its own colour later
    // would change one list and not the other.
    NSColor *color = track.isProtected
        ? [BTStyle ineligibleTextForReason:BTITunesBlockProtected]
        : [NSColor blackColor];
    [(NSTextFieldCell *)cell setTextColor:((selected && BTListHasFocus(tableView)) ? [NSColor whiteColor]
                                                                                   : color)];
}

// Marks the column the list is sorted by, so a source that opened the way it
// was left says so rather than leaving the arrangement unexplained.
- (void)showSortIndicator {
    NSArray *columns = [_trackTable tableColumns];
    NSUInteger i;
    for (i = 0; i < [columns count]; i++) {
        [_trackTable setIndicatorImage:nil inTableColumn:[columns objectAtIndex:i]];
    }

    // No mark on a frozen list. An arrow on a column head is an invitation to
    // click it, and clicking it here does nothing.
    if ([self selectedSourceSortIsFrozen]) {
        [_trackTable setHighlightedTableColumn:nil];
        return;
    }

    NSTableColumn *sorted = [_sortColumn length] > 0
        ? [_trackTable tableColumnWithIdentifier:_sortColumn] : nil;
    [_trackTable setHighlightedTableColumn:sorted];
    if (sorted == nil) return;

    [_trackTable setIndicatorImage:[NSImage imageNamed:(_sortAscending ? @"NSAscendingSortIndicator"
                                                                      : @"NSDescendingSortIndicator")]
                     inTableColumn:sorted];
}

- (void)tableView:(NSTableView *)tableView
    didClickTableColumn:(NSTableColumn *)tableColumn {
    NSString *identifier = [tableColumn identifier];
    // The mark is not a fact anyone would sort by.
    if ([identifier isEqualToString:@"playing"]) return;
    if ([self selectedSourceSortIsFrozen]) return;
    if ([identifier isEqualToString:_sortColumn]) {
        _sortAscending = !_sortAscending;
    } else {
        _sortColumn = identifier;
        _sortAscending = YES;
    }

    [self showSortIndicator];
    [self rememberSortForSelectedSource];
    [self reloadEverything];
}

- (BOOL)tableView:(NSTableView *)tableView
    writeRowsWithIndexes:(NSIndexSet *)rowIndexes
            toPasteboard:(NSPasteboard *)pasteboard {
    NSMutableArray *ids = [NSMutableArray array];
    NSUInteger row = [rowIndexes firstIndex];
    while (row != NSNotFound) {
        if (row < [_visibleTracks count]) {
            [ids addObject:[[_visibleTracks objectAtIndex:row] trackID]];
        }
        row = [rowIndexes indexGreaterThanIndex:row];
    }
    [pasteboard declareTypes:@[BTTrackPasteboardType] owner:self];
    [pasteboard setData:[NSKeyedArchiver archivedDataWithRootObject:ids] forType:BTTrackPasteboardType];
    return YES;
}

#pragma mark - Taking it back

- (NSUndoManager *)undoManager {
    if (_undoManager == nil) _undoManager = [[NSUndoManager alloc] init];
    return _undoManager;
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
    return [self undoManager];
}

// Named differently from the selector they answer would be the usual caution,
// but these do the work themselves rather than passing it along, so there is
// nothing to recurse into.
- (void)undo:(id)sender { [[self undoManager] undo]; }
- (void)redo:(id)sender { [[self undoManager] redo]; }

// Every rearrangement goes through here, so all of them can be taken back the
// same way. Restoring registers the arrangement it replaced, which is what
// makes redo work without a second path through the code.
- (void)restoreOrder:(NSArray *)order ofPlaylist:(BTPlaylist *)playlist named:(NSString *)name {
    NSUndoManager *undo = [self undoManager];
    [[undo prepareWithInvocationTarget:self]
        restoreOrder:[NSArray arrayWithArray:playlist.trackIDs] ofPlaylist:playlist named:name];
    [undo setActionName:name];

    [playlist.trackIDs removeAllObjects];
    [playlist.trackIDs addObjectsFromArray:order];
    [[BTLibrary sharedLibrary] noteChanged];
}

// Records what a playlist looked like before it was changed. Call it with the
// order as it stood, then make the change.
- (void)recordOrder:(NSArray *)previous ofPlaylist:(BTPlaylist *)playlist named:(NSString *)name {
    NSUndoManager *undo = [self undoManager];
    [[undo prepareWithInvocationTarget:self] restoreOrder:previous ofPlaylist:playlist named:name];
    [undo setActionName:name];
}

#pragma mark - Rearranging a playlist

// A playlist can be rearranged only while it is showing its own order. Sorted
// by title, "put this between these two rows" says nothing about where the song
// belongs in the playlist, because those two rows are not neighbours there.
//
// Only a playlist someone arranged by hand has an order to change. A folder
// takes its order from its children, and a smart playlist from its rules.
- (BTPlaylist *)rearrangeablePlaylist {
    BTPlaylist *playlist = BTPlaylistFromSource(_selectedSource);
    if (playlist == nil || playlist.kind != BTPlaylistKindStatic) return nil;
    if (![_sortColumn isEqualToString:@"order"] || !_sortAscending) return nil;
    return playlist;
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation {
    if ([info draggingSource] != _trackTable) return NSDragOperationNone;
    if ([self rearrangeablePlaylist] == nil) return NSDragOperationNone;

    // Between two songs, never onto one. A song dropped onto another song has
    // no meaning here.
    [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation {
    BTPlaylist *playlist = [self rearrangeablePlaylist];
    if (playlist == nil) return NO;

    NSData *data = [[info draggingPasteboard] dataForType:BTTrackPasteboardType];
    NSArray *dragged = data ? [NSKeyedUnarchiver unarchiveObjectWithData:data] : nil;
    if ([dragged count] == 0) return NO;

    // Where the drop lands, named by the song it lands above rather than by a
    // row number. A list narrowed by the search field shows only some of the
    // playlist, and a row number would mean the wrong place in it.
    NSInteger target = (NSInteger)[playlist.trackIDs count];
    if (row >= 0 && row < (NSInteger)[_visibleTracks count]) {
        NSString *below = [[_visibleTracks objectAtIndex:(NSUInteger)row] trackID];
        NSUInteger found = [playlist.trackIDs indexOfObject:below];
        if (found != NSNotFound) target = (NSInteger)found;
    }

    [self recordOrder:[NSArray arrayWithArray:playlist.trackIDs]
           ofPlaylist:playlist
                named:@"Rearrange"];
    [playlist moveTrackIDs:dragged toIndex:target];

    // The library reloads the window as it changes, so the numbers are already
    // the new ones by the time the songs are picked out again.
    [[BTLibrary sharedLibrary] noteChanged];
    [self selectTracksWithIDs:dragged];
    return YES;
}

// The songs that were just moved stay selected, so a second drag carries on
// from where the first left off instead of starting from nothing.
- (void)selectTracksWithIDs:(NSArray *)trackIDs {
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    NSUInteger i;
    for (i = 0; i < [_visibleTracks count]; i++) {
        if ([trackIDs containsObject:[[_visibleTracks objectAtIndex:i] trackID]]) [rows addIndex:i];
    }
    if ([rows count] == 0) return;
    [_trackTable selectRowIndexes:rows byExtendingSelection:NO];
    [_trackTable scrollRowToVisible:(NSInteger)[rows firstIndex]];
}

// The song under the pointer when the menu was opened, or the selected one when
// this came from the menu bar instead.
- (BTTrack *)trackForInfo {
    NSInteger row = [_trackTable clickedRow];
    if (row < 0) row = [_trackTable selectedRow];
    if (row < 0 || row >= (NSInteger)[_visibleTracks count]) return nil;
    return [_visibleTracks objectAtIndex:(NSUInteger)row];
}

// What Command-I means depends on what is in front of you. On a smart playlist
// it opens the rules; on a song it opens the song. Both are "tell me about the
// thing I am looking at", which is the one idea the shortcut carries.
- (BTPlaylist *)smartPlaylistForInfo {
    if ([[self window] firstResponder] != _sourceList) return nil;
    BTPlaylist *playlist = [self selectedPlaylist];
    return (playlist && playlist.kind == BTPlaylistKindSmart) ? playlist : nil;
}

- (void)getInfo:(id)sender {
    if ([self smartPlaylistForInfo]) {
        [self editSmartPlaylist:sender];
        return;
    }

    BTTrack *track = [self trackForInfo];
    if (track == nil) return;

    _infoController = [[BTTrackInfoController alloc] initWithTrack:track];
    [_infoController beginSheetForWindow:[self window] completion:^(BOOL changed) {
        if (changed) [[BTLibrary sharedLibrary] noteChanged];
        self->_infoController = nil;
    }];
}

- (void)playSelectedTrack:(id)sender {
    NSInteger row = [_trackTable clickedRow];
    if (row < 0) row = [_trackTable selectedRow];
    if (row < 0 || row >= (NSInteger)[_visibleTracks count]) return;
    [[BTPlayer sharedPlayer] playTrack:[_visibleTracks objectAtIndex:(NSUInteger)row] inList:_visibleTracks];
}

#pragma mark - Delete

- (void)tableViewDeletePressed:(NSTableView *)tableView {
    if (tableView == (NSTableView *)_sourceList) {
        [self deleteSelectedPlaylist];
    } else {
        [self deleteSelectedTracks];
    }
}

- (void)deleteSelectedPlaylist {
    BTPlaylist *playlist = [self selectedPlaylist];
    if (playlist == nil) return;

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithFormat:@"Delete the playlist \"%@\"?", playlist.name]];
    [alert setInformativeText:@"The songs stay in the library."];
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    if (_selectedSource == playlist) _selectedSource = BTLibrarySource;
    [[BTLibrary sharedLibrary] removePlaylist:playlist];
}

- (void)deleteSelectedTracks {
    NSIndexSet *rows = [_trackTable selectedRowIndexes];
    if ([rows count] == 0) return;

    NSMutableArray *tracks = [NSMutableArray array];
    NSUInteger row = [rows firstIndex];
    while (row != NSNotFound) {
        if (row < [_visibleTracks count]) [tracks addObject:[_visibleTracks objectAtIndex:row]];
        row = [rows indexGreaterThanIndex:row];
    }

    BTLibrary *library = [BTLibrary sharedLibrary];
    BTPlaylist *playlist = BTPlaylistFromSource(_selectedSource);
    if (playlist && playlist.kind == BTPlaylistKindStatic) {
        NSUInteger i;
        for (i = 0; i < [tracks count]; i++) {
            [playlist.trackIDs removeObject:[[tracks objectAtIndex:i] trackID]];
        }
        [library noteChanged];
        return;
    }
    // A smart playlist, a folder, and the iPod have no manual removal. Only the
    // library itself takes songs out.
    if (_selectedSource != BTLibrarySource) return;

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithFormat:@"Remove %lu song%@ from the library?",
                           (unsigned long)[tracks count], ([tracks count] == 1 ? @"" : @"s")]];
    [alert setInformativeText:@"The files stay on disk. BTunes never deletes audio files."];
    [alert addButtonWithTitle:@"Remove"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    [library removeTracks:tracks];
}

#pragma mark - Split view

// Laying the panes out by hand. Leaving it to the split view left the right
// edge of the window empty, because the panes kept the widths they were built
// with instead of growing into the window.
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
    NSArray *subviews = [splitView subviews];
    if ([subviews count] != 2) {
        [splitView adjustSubviews];
        return;
    }

    NSView *first = [subviews objectAtIndex:0];
    NSView *second = [subviews objectAtIndex:1];
    NSSize size = [splitView bounds].size;
    CGFloat divider = [splitView dividerThickness];

    if ([splitView isVertical]) {
        CGFloat left = NSWidth([first frame]);
        CGFloat maximum = size.width - 200.0;
        if (left < 120.0) left = 120.0;
        if (maximum > 120.0 && left > maximum) left = maximum;

        CGFloat right = size.width - left - divider;
        if (right < 0) right = 0;
        [first setFrame:NSMakeRect(0, 0, left, size.height)];
        [second setFrame:NSMakeRect(left + divider, 0, right, size.height)];
        [self sizeSourceColumn];
        return;
    }

    // The browser belongs to the library. On a playlist the top pane goes away
    // entirely and the track list takes the whole area.
    CGFloat top = _browserHidden ? 0.0 : NSHeight([first frame]);
    if (!_browserHidden) {
        CGFloat maximum = size.height - 120.0;
        if (top < 60.0) top = 60.0;
        if (maximum > 60.0 && top > maximum) top = maximum;
    }

    CGFloat bottom = size.height - top - divider;
    if (bottom < 0) bottom = 0;

    if ([splitView isFlipped]) {
        [first setFrame:NSMakeRect(0, 0, size.width, top)];
        [second setFrame:NSMakeRect(0, top + divider, size.width, bottom)];
    } else {
        [first setFrame:NSMakeRect(0, bottom + divider, size.width, top)];
        [second setFrame:NSMakeRect(0, 0, size.width, bottom)];
    }
}

- (CGFloat)splitView:(NSSplitView *)splitView
constrainMinCoordinate:(CGFloat)proposedMin
         ofSubviewAt:(NSInteger)dividerIndex {
    return (splitView == _outerSplit) ? 120.0 : 60.0;
}

- (CGFloat)splitView:(NSSplitView *)splitView
constrainMaxCoordinate:(CGFloat)proposedMax
         ofSubviewAt:(NSInteger)dividerIndex {
    return (splitView == _outerSplit) ? 320.0 : (NSHeight([splitView bounds]) - 120.0);
}

#pragma mark - Browser

- (void)browserViewSelectionDidChange:(BTBrowserView *)browser {
    [self reloadTrackList];
}

#pragma mark - Actions

- (void)searchChanged:(id)sender {
    [self reloadEverything];
}

- (void)focusSearch:(id)sender {
    [[self window] makeFirstResponder:_searchField];
}

- (void)volumeChanged:(id)sender {
    [[BTPlayer sharedPlayer] setVolume:[_volumeView volume]];
}

- (void)playPause:(id)sender {
    BTPlayer *player = [BTPlayer sharedPlayer];

    // A song already loaded is what this button controls, whatever list happens
    // to be on screen. Looking at another playlist is not asking to play it: the
    // button showed a pause mark, so it pauses. Starting the other playlist is
    // what double-clicking a song in it is for.
    if ([player currentTrack]) {
        [player togglePlayPause];
        return;
    }

    // Nothing loaded, so this starts what is on screen: whatever source is
    // selected on the left, narrowed by the browser and the search field. That
    // list is also what next and previous walk, so a playlist plays its own
    // songs and stops at the end of them rather than running on into the
    // library.
    NSInteger row = [_trackTable selectedRow];
    if (row < 0 || row >= (NSInteger)[_visibleTracks count]) row = 0;
    if ([_visibleTracks count] == 0) return;

    [player playTrack:[_visibleTracks objectAtIndex:(NSUInteger)row] inList:_visibleTracks];
}

- (void)nextTrack:(id)sender { [[BTPlayer sharedPlayer] next]; }
- (void)previousTrack:(id)sender { [[BTPlayer sharedPlayer] previous]; }

- (void)toggleShuffle:(id)sender {
    BTPlayer *player = [BTPlayer sharedPlayer];
    player.shuffle = !player.shuffle;
    [self updateTransport];
}

- (void)cycleRepeat:(id)sender {
    BTPlayer *player = [BTPlayer sharedPlayer];
    player.repeatMode = (BTRepeatMode)((player.repeatMode + 1) % 3);
    [self updateTransport];
}

// Renumbers a playlist into album order. Only a playlist arranged by hand has
// an order to renumber: a folder takes its from its children and a smart
// playlist from its rules, and the library has none at all.
- (void)syncPlaylistOrder:(id)sender {
    BTPlaylist *playlist = [self selectedPlaylist];
    if (playlist == nil || playlist.kind != BTPlaylistKindStatic) return;

    [self recordOrder:[NSArray arrayWithArray:playlist.trackIDs]
           ofPlaylist:playlist
                named:@"Sync Playlist Order"];
    [playlist arrangeByAlbumUsingTracks:[BTLibrary sharedLibrary].tracks];
    [[BTLibrary sharedLibrary] noteChanged];
}

- (void)toggleMute:(id)sender {
    [[BTPlayer sharedPlayer] toggleMute];
    [self updateTransport];
}

- (void)volumeUp:(id)sender {
    BTPlayer *player = [BTPlayer sharedPlayer];
    float v = [player volume] + 0.05f;
    [player setVolume:(v > 1.0f ? 1.0f : v)];
    [self updateTransport];
}

- (void)volumeDown:(id)sender {
    BTPlayer *player = [BTPlayer sharedPlayer];
    float v = [player volume] - 0.05f;
    [player setVolume:(v < 0.0f ? 0.0f : v)];
    [self updateTransport];
}

- (BTPlaylist *)folderForNewPlaylist {
    BTPlaylist *selected = [self selectedPlaylist];
    if (selected == nil) return nil;
    return (selected.kind == BTPlaylistKindFolder) ? selected : selected.parent;
}

// Opens whatever folders it takes to bring a playlist into view, outermost
// first, since the source list can only place a row whose folders are all open.
// A folder that was closed by hand is reopened, because a selection nothing can
// see is worse than a folder that did not stay shut.
- (void)revealPlaylist:(BTPlaylist *)playlist {
    NSMutableArray *ancestors = [NSMutableArray array];
    BTPlaylist *parent = playlist.parent;
    while (parent) {
        [ancestors insertObject:parent atIndex:0];
        parent = parent.parent;
    }
    NSUInteger i;
    for (i = 0; i < [ancestors count]; i++) {
        [_sourceList expandItem:[ancestors objectAtIndex:i]];
    }
}

- (void)selectPlaylist:(BTPlaylist *)playlist {
    [self revealPlaylist:playlist];
    NSInteger row = [_sourceList rowForItem:playlist];
    if (row >= 0) {
        [_sourceList selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        [self beginRenamingRow:row];
    }
}

- (void)newPlaylist:(id)sender {
    BTPlaylist *playlist = [BTPlaylist playlistWithName:@"untitled playlist" kind:BTPlaylistKindStatic];
    [[BTLibrary sharedLibrary] addPlaylist:playlist toFolder:[self folderForNewPlaylist]];
    [_sourceList reloadData];
    [self selectPlaylist:playlist];
}

- (void)newPlaylistFolder:(id)sender {
    BTPlaylist *folder = [BTPlaylist playlistWithName:@"untitled folder" kind:BTPlaylistKindFolder];
    [[BTLibrary sharedLibrary] addPlaylist:folder toFolder:[self folderForNewPlaylist]];
    [_sourceList reloadData];
    [self selectPlaylist:folder];
}

- (void)newSmartPlaylist:(id)sender {
    BTPlaylist *playlist = [BTPlaylist playlistWithName:@"untitled smart playlist" kind:BTPlaylistKindSmart];
    BTPlaylist *folder = [self folderForNewPlaylist];

    _sheetController = [[BTSmartPlaylistController alloc] initWithPlaylist:playlist];
    [_sheetController beginSheetForWindow:[self window] completion:^(BOOL accepted) {
        if (accepted) {
            [[BTLibrary sharedLibrary] addPlaylist:playlist toFolder:folder];
            [self->_sourceList reloadData];
            [self selectPlaylist:playlist];
        }
        self->_sheetController = nil;
    }];
}

- (void)editSmartPlaylist:(id)sender {
    NSInteger clicked = [_sourceList clickedRow];
    BTPlaylist *playlist = (clicked >= 0) ? BTPlaylistFromSource([_sourceList itemAtRow:clicked])
                                          : [self selectedPlaylist];
    if (playlist == nil || playlist.kind != BTPlaylistKindSmart) return;

    _sheetController = [[BTSmartPlaylistController alloc] initWithPlaylist:playlist];
    [_sheetController beginSheetForWindow:[self window] completion:^(BOOL accepted) {
        if (accepted) {
            [[BTLibrary sharedLibrary] noteChanged];
        }
        self->_sheetController = nil;
    }];
}

- (void)addToLibrary:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:YES];
    [panel setAllowedFileTypes:[BTLibrary supportedExtensions]];
    [panel setPrompt:@"Add"];
    [panel setMessage:@"Choose songs or folders to add to the library."];

    // Starts where the music is kept, rather than wherever the panel last was.
    NSString *musicFolder = [[BTPreferences sharedPreferences] musicFolder];
    if ([[NSFileManager defaultManager] fileExistsAtPath:musicFolder]) {
        [panel setDirectoryURL:[NSURL fileURLWithPath:musicFolder]];
    }

    if ([panel runModal] != NSFileHandlingPanelOKButton) return;

    NSMutableArray *paths = [NSMutableArray array];
    NSArray *urls = [panel URLs];
    NSUInteger i;
    for (i = 0; i < [urls count]; i++) {
        [paths addObject:[[urls objectAtIndex:i] path]];
    }

    _bottomBar.statusText = @"Adding songs to the library...";
    [_bottomBar setNeedsDisplay:YES];

    [[BTLibrary sharedLibrary] importPaths:paths completion:^(NSUInteger added) {
        [self reloadEverything];
    }];
}

// One playlist, one disc. A folder takes its contents from its children and the
// library never fits, so neither is offered; the menu is dead for both.
- (void)burnPlaylist:(id)sender {
    BTPlaylist *playlist = [self selectedPlaylist];
    if (![BTBurnPlan canBurnPlaylist:playlist]) return;
    [BTBurnController burnPlaylist:playlist modalForWindow:[self window]];
}

- (void)deleteSelection:(id)sender {
    if ([[self window] firstResponder] == _sourceList) {
        [self deleteSelectedPlaylist];
    } else {
        [self deleteSelectedTracks];
    }
}

#pragma mark - Menu validation

// A key equivalent carrying no modifier is also an ordinary letter. While
// something is being typed the letter has to win: searching for "moon hooch"
// should not mute the music, and renaming a playlist should not pause it.
static BOOL BTSomethingIsBeingTyped(NSWindow *window) {
    id responder = [window firstResponder];
    return ([responder isKindOfClass:[NSTextView class]] &&
            [(NSTextView *)responder isFieldEditor]);
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = [item action];

    if ([[item keyEquivalent] length] > 0 && [item keyEquivalentModifierMask] == 0 &&
        BTSomethingIsBeingTyped([self window])) {
        return NO;
    }

    if (action == @selector(editSmartPlaylist:)) {
        NSInteger clicked = [_sourceList clickedRow];
        BTPlaylist *selected = (clicked >= 0)
            ? BTPlaylistFromSource([_sourceList itemAtRow:clicked]) : [self selectedPlaylist];
        return (selected != nil && selected.kind == BTPlaylistKindSmart);
    }
    // The menu says which of the two it is about to do rather than making it a
    // surprise.
    if (action == @selector(getInfo:)) {
        if ([self smartPlaylistForInfo]) {
            [item setTitle:@"Edit Smart Playlist..."];
            return YES;
        }
        [item setTitle:@"Get Info"];
        return [self trackForInfo] != nil;
    }
    // Alive for any playlist a disc could be made from. Why a particular one
    // cannot be burned is a sentence, and a grey menu item cannot say it, so
    // the dialog says it and holds the Burn button dead instead.
    if (action == @selector(burnPlaylist:)) {
        if ([BTBurnController isBusy]) return NO;
        return [BTBurnPlan canBurnPlaylist:[self selectedPlaylist]];
    }
    if (action == @selector(syncPlaylistOrder:)) {
        BTPlaylist *selected = [self selectedPlaylist];
        return (selected != nil && selected.kind == BTPlaylistKindStatic &&
                [selected.trackIDs count] > 1);
    }
    // The menu says what it will take back, rather than a bare "Undo".
    if (action == @selector(undo:)) {
        [item setTitle:[[self undoManager] undoMenuItemTitle]];
        return [[self undoManager] canUndo];
    }
    if (action == @selector(redo:)) {
        [item setTitle:[[self undoManager] redoMenuItemTitle]];
        return [[self undoManager] canRedo];
    }
    // The tick is set as the menu opens rather than kept in step by hand, so it
    // cannot drift from the column it describes.
    if (action == @selector(toggleColumn:)) {
        NSTableColumn *column = [item representedObject];
        [item setState:([column isHidden] ? NSOffState : NSOnState)];
        return YES;
    }
    return YES;
}

@end
