#import "BTMainWindowController.h"
#import "BTMainWindowViews.h"
#import "BTSourceList.h"
#import "BTDragTypes.h"
#import "BTTrackColumns.h"
#import "BTStyle.h"
#import "BTControls.h"
#import "BTDisplayView.h"
#import "BTBrowserView.h"
#import "BTSmartPlaylistController.h"
#import "BTBurnPlan.h"
#import "BTBurnController.h"
#import "BTBlankDisc.h"
#import "BTTrackInfoController.h"
#import "BTLibrary.h"
#import "BTITunesImport.h"
#import "BTITunesEntry.h"
#import "BTPlaylist.h"
#import "BTIPod.h"
#import "BTAudioDisc.h"
#import "BTDiscImport.h"
#import "BTDiscLookup.h"
#import "BTSyncView.h"
#import "BTITunesSyncView.h"
#import "BTPreferences.h"
#import "BTTrack.h"
#import "BTPlayer.h"

// Column widths and their arrangement are left to the table, which saves them
// under this name. What the table is allowed to change on its own is set per
// column in BTTrackColumns: a saved width that anything may recompute is not a
// saved width. Which columns are shown is kept separately, because the #
// column is decided by the source rather than by preference and must not be
// restored over that decision.
static NSString *const BTColumnsAutosaveName = @"BTunesTrackColumns2";
static NSString *const BTHiddenColumnsKey = @"BTHiddenColumns";

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

// The two round buttons at the right of the chrome, and how far up from its
// floor they sit. Written down once: the arithmetic that places them and the
// code that builds them both need the size, and it used to appear in five
// places where any one of them could be changed alone.
#define BT_CHROME_BUTTON_SIDE 27.0
#define BT_CHROME_BUTTON_FOOT 14.0

// How much one press of the volume keys moves the knob.
#define BT_VOLUME_STEP 0.05f

// How much of the window the title bar covers. Asked of AppKit rather than
// assumed, since the content view now runs underneath it.
static CGFloat BTTitleBarHeight(void) {
    NSRect content = NSMakeRect(0, 0, 100, 100);
    NSRect frame = [NSWindow frameRectForContentRect:content styleMask:NSTitledWindowMask];
    return NSHeight(frame) - NSHeight(content);
}

#pragma mark - Controller

@interface BTMainWindowController () <NSTableViewDataSource, NSTableViewDelegate,
                                      NSSplitViewDelegate, BTBrowserViewDelegate,
                                      NSWindowDelegate, BTKeyTableDelegate,
                                      BTSourceListDelegate>
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
    BTRoundButton *_actionButton;
    BOOL _actionIsImport;

    NSSplitView *_outerSplit;
    NSSplitView *_innerSplit;
    BTSourceList *_sources;
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
    BTIPod *_iPod;
    BTAudioDisc *_disc;
    // The disc already asked about, so it is asked about once and not on every
    // volume that comes and goes afterwards.
    __weak BTAudioDisc *_lookedUp;
    BTSyncView *_syncView;
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
    _visibleTracks = @[];
    _speakerImage = [self buildSpeakerImage];

    [self buildChrome];
    [self buildBody];
    [self buildBottomBar];
    [self layoutContent];
    [self updateKeyViewLoop];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(libraryChanged:) name:BTLibraryDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(trackDetailChanged:) name:BTLibraryTrackDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(playerChanged:) name:BTPlayerDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(iPodChanged:) name:BTIPodDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(discChanged:) name:BTAudioDiscDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(blankDiscChanged:) name:BTBlankDiscDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(settingsChanged:) name:BTPreferencesDidChangeNotification object:nil];

    [self iPodChanged:nil];
    [self discChanged:nil];
    [self reloadEverything];
    [self updateActionButton];
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

    // Hidden until there is something for it to do. What it does depends on
    // what is selected and what is in the drive, and updateActionButton decides.
    _actionButton = [BTRoundButton buttonWithFrame:NSMakeRect(NSWidth(bounds) - 76, 14, 27, 27)
                                             glyph:BTGlyphBurn
                                            target:self
                                            action:@selector(chromeAction:)];
    [_actionButton setHidden:YES];
    [_chrome addSubview:_actionButton];

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

    // The source list builds itself. What it is for is choosing a row; what a
    // chosen row means to the rest of the window is answered back here.
    _sources = [[BTSourceList alloc] initWithDelegate:self];
    [[_sources scrollView] setFrame:NSMakeRect(0, 0, 170, NSHeight(bodyFrame))];

    // Making a playlist is the thing that pane is for, so it is offered where
    // the pane is, empty space included, rather than only from the File menu.
    // Built here because every item on it is an action of this window's.
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
    [[_sources outlineView] setMenu:sourceMenu];
    [_outerSplit addSubview:[_sources scrollView]];

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
    [_trackTable setAction:@selector(trackClicked:)];
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
void BTChromeLayout(CGFloat chromeWidth, CGFloat volumeRight, BOOL actionShown,
                    CGFloat *outMiniLeft, CGFloat *outActionLeft,
                    CGFloat *outDisplayLeft, CGFloat *outDisplayWidth,
                    CGFloat *outSearchLeft, CGFloat *outSearchWidth) {
    const CGFloat rightMargin = 15.0;
    const CGFloat miniWidth = BT_CHROME_BUTTON_SIDE;
    const CGFloat actionWidth = BT_CHROME_BUTTON_SIDE;
    const CGFloat displayLeft = 230.0;
    const CGFloat preferredSearch = 180.0;
    const CGFloat minimumSearch = 88.0;
    const CGFloat minimumDisplay = 200.0;

    // The space either side of the readout is the same: whatever sits between
    // the volume control and the readout on the left is repeated on the right.
    CGFloat gap = displayLeft - volumeRight;
    if (gap < 8.0) gap = 8.0;

    CGFloat miniLeft = chromeWidth - rightMargin - miniWidth;

    // The one thing that comes and goes up here: burning a playlist when a blank
    // disc is in, importing a disc when one is being looked at, and nothing the
    // rest of the time. The search field gives up the room for it, since the
    // readout is already the first to be squeezed and would be squeezed twice.
    CGFloat actionLeft = miniLeft - gap - actionWidth;
    CGFloat searchRight = actionShown ? (actionLeft - gap * 0.6) : (miniLeft - gap);

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
    if (outActionLeft) *outActionLeft = actionLeft;
    if (outDisplayLeft) *outDisplayLeft = displayLeft;
    if (outDisplayWidth) *outDisplayWidth = displayWidth;
    if (outSearchLeft) *outSearchLeft = searchRight - searchWidth;
    if (outSearchWidth) *outSearchWidth = searchWidth;
}

- (void)layoutChrome {
    CGFloat miniLeft = 0, actionLeft = 0, displayLeft = 0, displayWidth = 0;
    CGFloat searchLeft = 0, searchWidth = 0;
    BTChromeLayout(NSWidth([_chrome bounds]), NSMaxX([_volumeView frame]),
                   ![_actionButton isHidden],
                   &miniLeft, &actionLeft, &displayLeft, &displayWidth,
                   &searchLeft, &searchWidth);

    [_miniButton setFrame:NSMakeRect(miniLeft, BT_CHROME_BUTTON_FOOT,
                                     BT_CHROME_BUTTON_SIDE, BT_CHROME_BUTTON_SIDE)];
    [_actionButton setFrame:NSMakeRect(actionLeft, BT_CHROME_BUTTON_FOOT,
                                       BT_CHROME_BUTTON_SIDE, BT_CHROME_BUTTON_SIDE)];
    [_display setFrame:NSMakeRect(displayLeft, 6, displayWidth, [BTDisplayView naturalHeight])];
    [_searchField setFrame:NSMakeRect(searchLeft, 17, searchWidth, 21)];
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
    [_sources sizeColumnToPane];
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
    [_searchField setNextKeyView:[_sources outlineView]];
    if (_browserHidden) {
        [[_sources outlineView] setNextKeyView:_trackTable];
    } else {
        [[_sources outlineView] setNextKeyView:[_browser firstColumnView]];
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
    _sources.iPod = found;
    [self updateBottomBar];
    if (had != (found != nil)) [self reloadEverything];
}

// A disc arriving or leaving. What was selected falls back to the library when
// the disc it was showing has gone, the way the iPod already does.
//
// This runs on any volume mounting or unmounting anywhere, not only on a disc,
// and every run reads the drive afresh. So the disc already in hand is kept
// whenever the drive holds that same disc: a new reading knows nothing of the
// names a lookup put on the old one, and swapping the object underneath the
// selection leaves the left bar pointing at a disc that is no longer in the list.
- (void)discChanged:(NSNotification *)note {
    BTAudioDisc *found = [BTAudioDisc insertedDisc];
    BTAudioDisc *was = _disc;
    _disc = [found isSameDiscAs:was] ? was : found;

    // Gone, or a different disc: either way what was on screen is not there any
    // more. Kept on the same test as the reload below, so the two agree.
    if (_selectedSource != _disc && [_selectedSource isKindOfClass:[BTAudioDisc class]]) {
        _selectedSource = BTLibrarySource;
        [self updateRightPane];
        [self updateBrowserVisibility];
    }
    _sources.disc = _disc;
    // Only when the drive actually changed. A memory stick being plugged in is
    // no reason to rebuild a list of twelve thousand songs.
    if (was != _disc) [self reloadEverything];
    [self updateActionButton];

    // A disc that did not name itself gets looked up, once, as it arrives. It is
    // shown numbered in the meantime rather than held back: the songs play
    // either way and the names arrive when they arrive.
    //
    // The disc that was kept, never the reading that was thrown away. Naming a
    // discarded object puts the answer nowhere, which is what happened every
    // time a volume appeared while a lookup was in flight.
    if (_disc && ![_disc named] && _disc != _lookedUp &&
        [[BTPreferences sharedPreferences] looksUpDiscs]) {
        _lookedUp = _disc;
        [self lookUpDisc:_disc];
    }
}

- (void)lookUpDisc:(BTAudioDisc *)disc {
    [BTDiscLookup lookUpDisc:disc completion:^(NSString *album, NSString *artist,
                                               NSArray *titles, NSString *error) {
        // The disc may have been taken out while the asking was going on, and
        // the answer is then about something that is no longer there.
        if (self->_disc != disc) return;
        if (error != nil || [titles count] == 0) {
            NSLog(@"BTunes: the disc could not be named (%@)", error ? error : @"nothing came back");
            return;
        }
        if (![disc applyTitles:titles album:album artist:artist]) {
            NSLog(@"BTunes: the disc found holds %lu songs and this one holds %lu, so it was left alone",
                  (unsigned long)[titles count], (unsigned long)[[disc tracks] count]);
            return;
        }
        [self->_sources reload];
        if ([self->_selectedSource isKindOfClass:[BTAudioDisc class]]) [self reloadEverything];
    }];
}

// The mark on a row ejects that row's device, whichever kind it is. The button
// at the bottom right is the iPod's alone and goes through ejectIPod: below.
- (void)ejectSource:(id)sender {
    id item = [_sources clickedSource];

    if ([item isKindOfClass:[BTAudioDisc class]]) {
        if (![(BTAudioDisc *)item eject]) {
            [self sayEjectFailed:@"The disc would not eject."];
            return;
        }
        [self discChanged:nil];
        return;
    }
    [self ejectIPod:sender];
}

- (void)sayEjectFailed:(NSString *)what {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:what];
    [alert setInformativeText:@"Something is still using it. Try again in a moment."];
    [alert runModal];
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

// What the one button up in the chrome is for at this moment, or nothing.
//
// Two offers, and they can never both apply: a blank disc is not an audio CD,
// and a playlist is not the disc. So it is one button that changes its mark
// rather than two that would have to know about each other.
- (void)updateActionButton {
    BOOL wasShown = ![_actionButton isHidden];
    BOOL show = NO;

    if ([_selectedSource isKindOfClass:[BTAudioDisc class]]) {
        // A disc is being looked at, so it can be taken in.
        show = YES;
        _actionIsImport = YES;
        _actionButton.glyph = BTGlyphImport;
        [_actionButton setToolTip:@"Import this CD"];
    } else if ([BTBlankDisc present] && !_showingITunesSync) {
        // A blank disc is in, so a playlist that would actually fit can go on it.
        BTPlaylist *playlist = [_sources selectedPlaylist];
        if ([BTBurnPlan canBurnPlaylist:playlist] && ![BTBurnController isBusy]) {
            BTBurnPlan *plan = [BTBurnPlan planForPlaylist:playlist
                                                    tracks:[BTLibrary sharedLibrary].tracks];
            if ([plan refusal] == BTBurnRefusalNone) {
                show = YES;
                _actionIsImport = NO;
                _actionButton.glyph = BTGlyphBurn;
                [_actionButton setToolTip:@"Burn this playlist to the disc"];
            }
        }
    }

    [_actionButton setHidden:!show];
    // The search field's width follows whether this is there, so the chrome is
    // laid out again rather than only redrawn.
    if (show != wasShown) [self layoutChrome];
}

- (void)chromeAction:(id)sender {
    if (_actionIsImport) {
        [self importDisc:sender];
    } else {
        [self burnPlaylist:sender];
    }
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
        // A disc plays its own songs, which are files on the mounted volume and
        // are in nobody's library.
        if ([_selectedSource isKindOfClass:[BTAudioDisc class]]) {
            return [(BTAudioDisc *)_selectedSource tracks];
        }
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
    [defaults setObject:[_sources closedFolderIDs] forKey:BTClosedFoldersKey];

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
    if (closed) [_sources setClosedFolderIDs:closed];

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
    [_sources selectSource:_selectedSource];

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

    [_sources reload];
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
    // A playlist that grew past what a disc holds stops being offered.
    [self updateActionButton];
}

// A play count or a date, on a song that is already in the list where it is.
// The cells are redrawn and nothing else: the rows are the same rows, and a
// list that resorted itself under the pointer because a song started playing
// would be worse than one that waits until it is next built.
- (void)trackDetailChanged:(NSNotification *)note {
    [_trackTable setNeedsDisplay:YES];
}

- (void)blankDiscChanged:(NSNotification *)note {
    [self updateActionButton];
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



#pragma mark - What the source list says

// A row was chosen. Everything that follows from that is here, because the
// source list knows which row and this window knows what a row means.
- (void)sourceListSelectionDidChange:(BTSourceList *)list {
    id item = [list selectedSource];
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
    [self updateActionButton];

    [self showSortIndicator];

    [_browser resetSelection];
    [self updateBrowserVisibility];
    [self updateRightPane];
    [self reloadEverything];
}

// A click that landed on the row already chosen sends no selection change, so
// the sync pane would sit there while the source list looked as though it had
// been answered.
- (void)sourceListWasClicked:(BTSourceList *)list {
    if (_showingITunesSync) [self closeITunesSync];
}

- (void)sourceListDeletePressed:(BTSourceList *)list {
    [self deleteSelectedPlaylist];
}

- (void)sourceListFoldersDidChange:(BTSourceList *)list {
    [self saveSessionState];
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

        // Under the pointer, that same spot offers to start the row. Not on the
        // row already playing, which has the speaker there and nothing to
        // offer, and not on a song that cannot play at all.
        BOOL offering = (isTheMark && !playing && !track.isProtected &&
                         row == [_trackTable hoveredRow]);
        [(BTTrackNumberCell *)cell setShowsPlay:offering];
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
    if ([[self window] firstResponder] != [_sources outlineView]) return nil;
    BTPlaylist *playlist = [_sources selectedPlaylist];
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

// The whole cell, not the mark inside it. The mark says what the cell does; the
// cell is the target, because an eighteen point column holding a nine point
// triangle is not something to ask anybody to hit.
- (void)trackClicked:(id)sender {
    NSInteger column = [_trackTable clickedColumn];
    if (column < 0) return;
    NSString *identifier = [[[_trackTable tableColumns] objectAtIndex:(NSUInteger)column] identifier];
    if (![identifier isEqualToString:@"playing"]) return;

    NSInteger row = [_trackTable clickedRow];
    if (row < 0 || row >= (NSInteger)[_visibleTracks count]) return;
    BTTrack *track = [_visibleTracks objectAtIndex:(NSUInteger)row];
    if (track.isProtected) return;
    if (track == [[BTPlayer sharedPlayer] currentTrack]) return;

    [[BTPlayer sharedPlayer] playTrack:track inList:_visibleTracks];
}

- (void)playSelectedTrack:(id)sender {
    NSInteger row = [_trackTable clickedRow];
    if (row < 0) row = [_trackTable selectedRow];
    if (row < 0 || row >= (NSInteger)[_visibleTracks count]) return;
    [[BTPlayer sharedPlayer] playTrack:[_visibleTracks objectAtIndex:(NSUInteger)row] inList:_visibleTracks];
}

#pragma mark - Delete

- (void)tableViewDeletePressed:(NSTableView *)tableView {
    [self deleteSelectedTracks];
}

- (void)deleteSelectedPlaylist {
    BTPlaylist *playlist = [_sources selectedPlaylist];
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
        [_sources sizeColumnToPane];
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
    BTPlaylist *playlist = [_sources selectedPlaylist];
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

// Both keys move the knob by the same step, so the two are one method with a
// direction. Written out twice, one of them could be given a different step and
// the volume would move further one way than the other.
- (void)moveVolumeBy:(float)step {
    BTPlayer *player = [BTPlayer sharedPlayer];
    float wanted = [player volume] + step;
    if (wanted > 1.0f) wanted = 1.0f;
    if (wanted < 0.0f) wanted = 0.0f;
    [player setVolume:wanted];
    [self updateTransport];
}

- (void)volumeUp:(id)sender { [self moveVolumeBy:BT_VOLUME_STEP]; }

- (void)volumeDown:(id)sender { [self moveVolumeBy:-BT_VOLUME_STEP]; }

- (BTPlaylist *)folderForNewPlaylist {
    BTPlaylist *selected = [_sources selectedPlaylist];
    if (selected == nil) return nil;
    return (selected.kind == BTPlaylistKindFolder) ? selected : selected.parent;
}

- (void)newPlaylist:(id)sender {
    BTPlaylist *playlist = [BTPlaylist playlistWithName:@"untitled playlist" kind:BTPlaylistKindStatic];
    [[BTLibrary sharedLibrary] addPlaylist:playlist toFolder:[self folderForNewPlaylist]];
    [_sources selectPlaylistForRenaming:playlist];
}

- (void)newPlaylistFolder:(id)sender {
    BTPlaylist *folder = [BTPlaylist playlistWithName:@"untitled folder" kind:BTPlaylistKindFolder];
    [[BTLibrary sharedLibrary] addPlaylist:folder toFolder:[self folderForNewPlaylist]];
    [_sources selectPlaylistForRenaming:folder];
}

- (void)newSmartPlaylist:(id)sender {
    BTPlaylist *playlist = [BTPlaylist playlistWithName:@"untitled smart playlist" kind:BTPlaylistKindSmart];
    BTPlaylist *folder = [self folderForNewPlaylist];

    _sheetController = [[BTSmartPlaylistController alloc] initWithPlaylist:playlist];
    [_sheetController beginSheetForWindow:[self window] completion:^(BOOL accepted) {
        if (accepted) {
            [[BTLibrary sharedLibrary] addPlaylist:playlist toFolder:folder];
            [self->_sources selectPlaylistForRenaming:playlist];
        }
        self->_sheetController = nil;
    }];
}

- (void)editSmartPlaylist:(id)sender {
    BTPlaylist *playlist = [_sources clickedPlaylist];
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
    BTPlaylist *playlist = [_sources selectedPlaylist];
    if (![BTBurnPlan canBurnPlaylist:playlist]) return;
    [BTBurnController burnPlaylist:playlist modalForWindow:[self window]];
}

// Taking a disc into the library.
//
// What it will be called is said before it starts, because that is the part
// worth changing your mind about. A disc that carried CD-Text arrives with its
// songs named; one that did not arrives as "Track 1" and the rest, and a dozen
// of those going into twelve thousand songs is worth being warned of rather than
// discovering afterwards.
- (void)importDisc:(id)sender {
    if (![_selectedSource isKindOfClass:[BTAudioDisc class]]) return;
    BTAudioDisc *disc = (BTAudioDisc *)_selectedSource;
    NSUInteger count = [[disc tracks] count];
    if (count == 0) return;

    BTPreferences *prefs = [BTPreferences sharedPreferences];
    NSString *form = [prefs importsLossless] ? @"Apple Lossless" : @"AAC";

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithFormat:@"Import %lu song%@ from \"%@\"?",
                           (unsigned long)count, (count == 1 ? @"" : @"s"), [disc name]]];

    NSMutableString *detail = [NSMutableString string];
    if (![disc named]) {
        [detail appendString:@"This disc does not say what its songs are called, so they "
                             @"would come across as \"Track 1\" and so on.\n\n"];
    }
    [detail appendFormat:@"They will be encoded as %@ and put in:\n%@\n\nThe disc is only read.",
                         form, [prefs btunesFolder]];
    [alert setInformativeText:detail];
    [alert addButtonWithTitle:@"Import"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    [_actionButton setEnabled:NO];
    [BTDiscImport importDisc:disc
                        into:[BTLibrary sharedLibrary]
                    progress:^(double fraction, NSString *what) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName:BTDisplayProgressNotification
                          object:nil
                        userInfo:@{@"title": @"Importing CD",
                                   @"message": (what ? what : @""),
                                   @"fraction": @(fraction)}];
    } completion:^(NSUInteger added, NSString *error) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName:BTDisplayProgressDidEndNotification object:nil];
        [self->_actionButton setEnabled:YES];
        [self reloadEverything];

        NSAlert *done = [[NSAlert alloc] init];
        if (error) {
            [done setMessageText:@"The import stopped."];
            [done setInformativeText:[NSString stringWithFormat:
                @"%@\n\n%lu song%@ came across before it did, and %@ been kept.",
                error, (unsigned long)added, (added == 1 ? @"" : @"s"),
                (added == 1 ? @"has" : @"have")]];
        } else {
            [done setMessageText:[NSString stringWithFormat:@"%lu song%@ came across.",
                                  (unsigned long)added, (added == 1 ? @"" : @"s")]];
            [done setInformativeText:@"Nothing was written to the disc, and it can be ejected."];
        }
        [done runModal];
    }];
}

- (void)deleteSelection:(id)sender {
    if ([[self window] firstResponder] == [_sources outlineView]) {
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
        BTPlaylist *selected = [_sources clickedPlaylist];
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
        return [BTBurnPlan canBurnPlaylist:[_sources selectedPlaylist]];
    }
    if (action == @selector(syncPlaylistOrder:)) {
        BTPlaylist *selected = [_sources selectedPlaylist];
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
