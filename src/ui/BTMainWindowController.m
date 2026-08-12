#import "BTMainWindowController.h"
#import "BTStyle.h"
#import "BTControls.h"
#import "BTDisplayView.h"
#import "BTBrowserView.h"
#import "BTSmartPlaylistController.h"
#import "BTLibrary.h"
#import "BTITunesImport.h"
#import "BTPlaylist.h"
#import "BTIPod.h"
#import "BTSyncView.h"
#import "BTPreferences.h"
#import "BTTrack.h"
#import "BTPlayer.h"

static NSString *const BTTrackPasteboardType = @"com.btunes.tracks";
static NSString *const BTPlaylistPasteboardType = @"com.btunes.playlist";
static NSString *const BTLibrarySource = @"Library";

// Tall enough for two lines of text above the scrub bar without them meeting.
#define BT_CHROME_HEIGHT 54.0
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

#pragma mark - Chrome

@interface BTChromeView : NSView
// The readout and the search field are placed by hand on every resize, so the
// search field can take the slack rather than leaving a gap beside it.
@property (nonatomic, copy) void (^layoutHandler)(void);
@end

@implementation BTChromeView
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    [BTStyle drawChromeInRect:[self bounds]];
}
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    if (self.layoutHandler) self.layoutHandler();
}
@end

#pragma mark - Bottom bar

@interface BTBottomBarView : NSView
@property (nonatomic, copy) NSString *statusText;
@end

@implementation BTBottomBarView
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    [BTStyle drawVerticalGradientInRect:bounds from:[BTStyle chromeTop] to:[BTStyle chromeBottom]];
    [[BTStyle chromeEdge] set];
    NSRectFill(NSMakeRect(0, NSMaxY(bounds) - 1, NSWidth(bounds), 1));

    if ([self.statusText length] > 0) {
        NSMutableParagraphStyle *centered = [[NSMutableParagraphStyle alloc] init];
        [centered setAlignment:NSCenterTextAlignment];
        NSDictionary *attrs = @{NSFontAttributeName: [BTStyle uiFont],
                                NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.25 alpha:1.0],
                                NSParagraphStyleAttributeName: centered};
        // Leave the right end clear for the three buttons.
        CGFloat reserved = 84.0;
        [self.statusText drawInRect:NSMakeRect(reserved, NSMidY(bounds) - 7, NSWidth(bounds) - reserved * 2, 14)
                     withAttributes:attrs];
    }
}
@end

#pragma mark - Source list cell

@interface BTSourceCell : NSTextFieldCell
@property (nonatomic, strong) NSImage *icon;
@property (nonatomic, assign) BOOL showsEject;
@end

@implementation BTSourceCell

// Where the eject mark sits inside a row, so the row and the click test agree.
+ (NSRect)ejectRectInFrame:(NSRect)frame {
    return NSMakeRect(NSMaxX(frame) - 18, NSMidY(frame) - 6, 12, 12);
}

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view {
    if (self.showsEject) {
        [BTStyle drawEjectGlyphInRect:[BTSourceCell ejectRectInFrame:frame]
                                color:[NSColor colorWithCalibratedWhite:0.30 alpha:1.0]];
    }

    // A few points of air on the left, so the icon does not sit against the
    // disclosure triangle on rows that have one.
    NSRect content = frame;
    content.origin.x += 5.0;
    content.size.width -= 5.0;

    NSRect textFrame = content;
    if (self.showsEject) textFrame.size.width -= 20;
    if (self.icon) {
        NSRect iconFrame = NSMakeRect(NSMinX(content), NSMidY(content) - 7, 14, 14);
        [self.icon drawInRect:iconFrame
                     fromRect:NSZeroRect
                    operation:NSCompositeSourceOver
                     fraction:1.0
               respectFlipped:YES
                        hints:nil];
        textFrame.origin.x += 18;
        textFrame.size.width -= 18;
    }
    textFrame.origin.y += 1;
    [super drawInteriorWithFrame:textFrame inView:view];
}

@end

// Track number cell that shows the speaker instead of the number while its row
// is the one playing, so the indicator needs no column of its own.
@interface BTTrackNumberCell : NSTextFieldCell
@property (nonatomic, strong) NSImage *indicator;
@end

@implementation BTTrackNumberCell

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view {
    if (self.indicator == nil) {
        [super drawInteriorWithFrame:frame inView:view];
        return;
    }
    NSSize size = [self.indicator size];
    NSRect box = NSMakeRect(NSMidX(frame) - size.width / 2,
                            NSMidY(frame) - size.height / 2,
                            size.width, size.height);
    [self.indicator drawInRect:box
                      fromRect:NSZeroRect
                     operation:NSCompositeSourceOver
                      fraction:1.0
                respectFlipped:YES
                         hints:nil];
}

@end

#pragma mark - Tables that answer the delete key

@protocol BTKeyTableDelegate <NSObject>
- (void)tableViewDeletePressed:(NSTableView *)tableView;
@end

// Transport keys, shared by every view that can hold focus.
//
// Left and right skip tracks, and the option-modified up and down arrows change
// volume from anywhere. Plain up and down change volume too, except in a list,
// where they still move the selection and would be missed if taken away.
static BOOL BTHandleTransportKey(NSEvent *event, id sender, BOOL plainArrowsAreVolume) {
    NSString *characters = [event charactersIgnoringModifiers];
    if ([characters length] == 0) return NO;

    unichar key = [characters characterAtIndex:0];
    BOOL option = ([event modifierFlags] & NSAlternateKeyMask) != 0;
    BOOL command = ([event modifierFlags] & NSCommandKeyMask) != 0;
    if (command) return NO;

    switch (key) {
        case NSLeftArrowFunctionKey:
            [NSApp sendAction:@selector(previousTrack:) to:nil from:sender];
            return YES;
        case NSRightArrowFunctionKey:
            [NSApp sendAction:@selector(nextTrack:) to:nil from:sender];
            return YES;
        case NSUpArrowFunctionKey:
            if (!option && !plainArrowsAreVolume) return NO;
            [NSApp sendAction:@selector(volumeUp:) to:nil from:sender];
            return YES;
        case NSDownArrowFunctionKey:
            if (!option && !plainArrowsAreVolume) return NO;
            [NSApp sendAction:@selector(volumeDown:) to:nil from:sender];
            return YES;
        case ' ':
            [NSApp sendAction:@selector(playPause:) to:nil from:sender];
            return YES;
        case 'm':
        case 'M':
            [NSApp sendAction:@selector(toggleMute:) to:nil from:sender];
            return YES;
        default:
            return NO;
    }
}

// The window catches transport keys that no view claimed.
@interface BTMainWindow : NSWindow
@end

@implementation BTMainWindow
- (void)keyDown:(NSEvent *)event {
    if (BTHandleTransportKey(event, self, YES)) return;
    [super keyDown:event];
}
@end

@interface BTKeyTableView : BTListTableView
@end

@implementation BTKeyTableView
- (void)keyDown:(NSEvent *)event {
    unichar key = [[event charactersIgnoringModifiers] length] > 0
        ? [[event charactersIgnoringModifiers] characterAtIndex:0] : 0;
    if (key == NSDeleteCharacter || key == NSBackspaceCharacter || key == NSDeleteFunctionKey) {
        id delegate = [self delegate];
        if ([delegate respondsToSelector:@selector(tableViewDeletePressed:)]) {
            [delegate performSelector:@selector(tableViewDeletePressed:) withObject:self];
            return;
        }
    }
    if (BTHandleTransportKey(event, self, NO)) return;
    [super keyDown:event];
}
@end

@interface BTKeyOutlineView : NSOutlineView
@end

@implementation BTKeyOutlineView

// A click on the eject mark ejects rather than selecting the row.
- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSInteger row = [self rowAtPoint:point];
    if (row >= 0) {
        NSCell *cell = [self preparedCellAtColumn:0 row:row];
        if ([cell isKindOfClass:[BTSourceCell class]] && [(BTSourceCell *)cell showsEject]) {
            NSRect frame = [self frameOfCellAtColumn:0 row:row];
            if (NSPointInRect(point, [BTSourceCell ejectRectInFrame:frame])) {
                [NSApp sendAction:@selector(ejectIPod:) to:nil from:self];
                return;
            }
        }
    }
    [super mouseDown:event];
}

- (void)keyDown:(NSEvent *)event {
    unichar key = [[event charactersIgnoringModifiers] length] > 0
        ? [[event charactersIgnoringModifiers] characterAtIndex:0] : 0;
    if (key == NSDeleteCharacter || key == NSBackspaceCharacter || key == NSDeleteFunctionKey) {
        id delegate = [self delegate];
        if ([delegate respondsToSelector:@selector(tableViewDeletePressed:)]) {
            [delegate performSelector:@selector(tableViewDeletePressed:) withObject:self];
            return;
        }
    }
    if (BTHandleTransportKey(event, self, NO)) return;
    [super keyDown:event];
}
@end

#pragma mark - Controller

@interface BTMainWindowController () <NSOutlineViewDataSource, NSOutlineViewDelegate,
                                      NSTableViewDataSource, NSTableViewDelegate,
                                      NSSplitViewDelegate, BTBrowserViewDelegate,
                                      BTKeyTableDelegate>
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

    id _selectedSource;              // BTLibrarySource or a BTPlaylist
    NSArray *_visibleTracks;
    NSString *_sortColumn;
    BOOL _sortAscending;
    BOOL _browserHidden;
    BOOL _renameRequested;
    BTIPod *_iPod;
    BTSyncView *_syncView;
    NSImage *_speakerImage;
    BTSmartPlaylistController *_sheetController;
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

    _selectedSource = BTLibrarySource;
    _sortColumn = @"artist";
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
    [nc addObserver:self selector:@selector(playerChanged:) name:BTPlayerDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(iPodChanged:) name:BTIPodDidChangeNotification object:nil];

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

    NSColor *blue = [NSColor colorWithCalibratedRed:0.24 green:0.44 blue:0.78 alpha:1.0];
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
                ? [NSColor colorWithCalibratedRed:0.45 green:0.30 blue:0.70 alpha:1.0] : blue;
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

    _display = [[BTDisplayView alloc] initWithFrame:NSMakeRect(230, 6, 340, 42)];
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

    _miniButton = [BTRoundButton buttonWithFrame:NSMakeRect(NSWidth(bounds) - 42, 14, 27, 27)
                                           glyph:BTGlyphShrink
                                          target:nil
                                          action:@selector(toggleMiniMode:)];
    [_miniButton setToolTip:@"Mini player"];
    [_chrome addSubview:_miniButton];

    __weak BTMainWindowController *weakSelf = self;
    _chrome.layoutHandler = ^{ [weakSelf layoutChrome]; };
    [self layoutChrome];
    [_searchField setTarget:self];
    [_searchField setAction:@selector(searchChanged:)];
    [(NSSearchFieldCell *)[_searchField cell] setSendsWholeSearchString:NO];
    [_chrome addSubview:_searchField];
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
    [sourceColumn setWidth:150];
    BTSourceCell *sourceCell = [[BTSourceCell alloc] init];
    [sourceCell setFont:[BTStyle uiFont]];
    [sourceCell setEditable:YES];
    [sourceColumn setDataCell:sourceCell];
    [_sourceList addTableColumn:sourceColumn];
    [_sourceList setOutlineTableColumn:sourceColumn];
    [_sourceList setHeaderView:nil];
    [_sourceList setRowHeight:18.0];
    [_sourceList setIndentationPerLevel:14.0];
    [_sourceList setDataSource:self];
    [_sourceList setDelegate:self];
    [_sourceList setAllowsMultipleSelection:NO];
    [_sourceList setAllowsColumnSelection:NO];
    [_sourceList setTarget:self];
    [_sourceList setDoubleAction:@selector(renameSelectedPlaylist:)];
    [_sourceList registerForDraggedTypes:@[BTTrackPasteboardType, BTPlaylistPasteboardType]];
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
    [self addTrackColumns];
    [_trackTable setRowHeight:17.0];
    [_trackTable setUsesAlternatingRowBackgroundColors:YES];
    [_trackTable setAllowsMultipleSelection:YES];
    [_trackTable setAllowsColumnSelection:NO];
    [_trackTable setDataSource:self];
    [_trackTable setDelegate:self];
    [_trackTable setTarget:self];
    [_trackTable setDoubleAction:@selector(playSelectedTrack:)];
    [_trackTable setColumnAutoresizingStyle:NSTableViewLastColumnOnlyAutoresizingStyle];
    [_trackTable setDraggingSourceOperationMask:NSDragOperationCopy forLocal:YES];
    [trackScroll setDocumentView:_trackTable];
    [_innerSplit addSubview:trackScroll];

    [_outerSplit addSubview:_innerSplit];
}

- (void)addTrackColumns {
    NSArray *specs = @[@[@"track", @"#", @34],
                       @[@"title", @"Song Name", @240],
                       @[@"time", @"Time", @52],
                       @[@"artist", @"Artist", @160],
                       @[@"album", @"Album", @160],
                       @[@"genre", @"Genre", @110],
                       @[@"playCount", @"Play Count", @80]];
    NSUInteger i;
    for (i = 0; i < [specs count]; i++) {
        NSArray *spec = [specs objectAtIndex:i];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:[spec objectAtIndex:0]];
        [[column headerCell] setStringValue:[spec objectAtIndex:1]];
        [[column headerCell] setFont:[BTStyle uiFont]];
        [column setWidth:[[spec objectAtIndex:2] doubleValue]];
        [column setEditable:NO];

        if ([[spec objectAtIndex:0] isEqualToString:@"track"]) {
            BTTrackNumberCell *cell = [[BTTrackNumberCell alloc] init];
            [cell setFont:[BTStyle uiFont]];
            [cell setAlignment:NSRightTextAlignment];
            [[column headerCell] setAlignment:NSRightTextAlignment];
            [column setDataCell:cell];
        } else {
            NSTextFieldCell *cell = [[NSTextFieldCell alloc] init];
            [cell setFont:[BTStyle uiFont]];
            if ([[spec objectAtIndex:0] isEqualToString:@"time"] ||
                [[spec objectAtIndex:0] isEqualToString:@"playCount"]) {
                [cell setAlignment:NSRightTextAlignment];
                [[column headerCell] setAlignment:NSRightTextAlignment];
            }
            [column setDataCell:cell];
        }
        [_trackTable addTableColumn:column];
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

    // The eject button lives in the gray at the bottom right, and only appears
    // while a device is attached.
    _ejectButton = [BTToggleButton buttonWithFrame:NSMakeRect(NSWidth(bounds) - 30, 2, 22, 20)
                                             glyph:BTGlyphEject
                                            target:self
                                            action:@selector(ejectIPod:)];
    [_ejectButton setToolTip:@"Eject iPod"];
    [_ejectButton setAutoresizingMask:NSViewMinXMargin];
    [_ejectButton setHidden:YES];
    [_bottomBar addSubview:_ejectButton];
}

// The readout keeps a fixed width and the search field grows into whatever is
// left, so there is no dead gap between them at any window size. When the
// window is too narrow for that, the readout gives up width instead.
- (void)layoutChrome {
    NSRect bounds = [_chrome bounds];
    CGFloat rightMargin = 15.0;
    CGFloat miniWidth = 27.0;
    CGFloat minimumSearch = 110.0;

    // The space either side of the readout is the same: whatever sits between
    // the volume control and the readout on the left is repeated on the right.
    CGFloat gap = 230.0 - NSMaxX([_volumeView frame]);
    if (gap < 8.0) gap = 8.0;

    CGFloat miniX = NSWidth(bounds) - rightMargin - miniWidth;
    [_miniButton setFrame:NSMakeRect(miniX, 14, miniWidth, miniWidth)];

    CGFloat searchRight = miniX - gap;
    CGFloat displayLeft = 230.0;
    CGFloat displayWidth = 340.0;

    CGFloat searchLeft = displayLeft + displayWidth + gap;
    if (searchRight - searchLeft < minimumSearch) {
        displayWidth = MAX(160.0, searchRight - minimumSearch - gap - displayLeft);
        searchLeft = displayLeft + displayWidth + gap;
    }

    [_display setFrame:NSMakeRect(displayLeft, 6, displayWidth, 42)];
    [_searchField setFrame:NSMakeRect(searchLeft, 17, MAX(40.0, searchRight - searchLeft), 21)];
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

    [_outerSplit setPosition:170 ofDividerAtIndex:0];
    [_innerSplit setPosition:150 ofDividerAtIndex:0];
    [_outerSplit adjustSubviews];
    [_innerSplit adjustSubviews];

    // Same reason as the browser columns: no gap between the last column and
    // the edge of the table.
    [_trackTable sizeLastColumnToFit];
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    // The window may have been resized from its saved frame before it appeared.
    [self layoutContent];
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
- (void)updateRightPane {
    BOOL wantsSync = [_selectedSource isKindOfClass:[BTIPod class]];
    NSArray *subviews = [_outerSplit subviews];
    if ([subviews count] != 2) return;

    NSView *current = [subviews objectAtIndex:1];
    if (wantsSync) {
        if (_syncView == nil) _syncView = [[BTSyncView alloc] initWithFrame:[current frame]];
        _syncView.iPod = (BTIPod *)_selectedSource;
        if (current != _syncView) {
            [_outerSplit replaceSubview:current with:_syncView];
            [_syncView setFrame:[current frame]];
        }
    } else if (current != _innerSplit) {
        [_outerSplit replaceSubview:current with:_innerSplit];
        [_innerSplit setFrame:[current frame]];
    }
    [_outerSplit adjustSubviews];
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

    NSError *error = nil;
    if (![_iPod eject:&error]) {
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
        // Give it back the height it had before it was put away.
        NSRect frame = [_browser frame];
        if (NSHeight(frame) < 60.0) {
            frame.size.height = 150.0;
            [_browser setFrame:frame];
        }
    }
    [_innerSplit adjustSubviews];
}

#pragma mark - Reloading

- (NSArray *)baseTracks {
    BTLibrary *library = [BTLibrary sharedLibrary];
    if ([_selectedSource isKindOfClass:[BTIPod class]]) return @[];
    if (_selectedSource == BTLibrarySource || _selectedSource == nil) return library.tracks;
    return [(BTPlaylist *)_selectedSource resolveTracks:library.tracks];
}

- (NSArray *)sortTracks:(NSArray *)tracks {
    NSString *key = _sortColumn;
    BOOL ascending = _sortAscending;
    return [tracks sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        BTTrack *left = a, *right = b;
        NSComparisonResult result = NSOrderedSame;

        if ([key isEqualToString:@"track"]) {
            // Sorting by number only makes sense within an album, so keep
            // albums together and order by disc and track inside them.
            result = [[left displayAlbum] caseInsensitiveCompare:[right displayAlbum]];
            if (result == NSOrderedSame) {
                result = (left.discNumber < right.discNumber) ? NSOrderedAscending
                       : (left.discNumber > right.discNumber) ? NSOrderedDescending : NSOrderedSame;
            }
            if (result == NSOrderedSame) {
                result = (left.trackNumber < right.trackNumber) ? NSOrderedAscending
                       : (left.trackNumber > right.trackNumber) ? NSOrderedDescending : NSOrderedSame;
            }
        } else if ([key isEqualToString:@"title"]) {
            result = [[left displayTitle] caseInsensitiveCompare:[right displayTitle]];
        } else if ([key isEqualToString:@"album"]) {
            result = [[left displayAlbum] caseInsensitiveCompare:[right displayAlbum]];
            if (result == NSOrderedSame) {
                result = (left.trackNumber < right.trackNumber) ? NSOrderedAscending
                       : (left.trackNumber > right.trackNumber) ? NSOrderedDescending : NSOrderedSame;
            }
        } else if ([key isEqualToString:@"genre"]) {
            result = [[left displayGenre] caseInsensitiveCompare:[right displayGenre]];
        } else if ([key isEqualToString:@"time"]) {
            result = (left.duration < right.duration) ? NSOrderedAscending
                   : (left.duration > right.duration) ? NSOrderedDescending : NSOrderedSame;
        } else if ([key isEqualToString:@"playCount"]) {
            result = (left.playCount < right.playCount) ? NSOrderedAscending
                   : (left.playCount > right.playCount) ? NSOrderedDescending : NSOrderedSame;
        } else {
            // Artist, then album, then track number: the order iTunes falls back to.
            result = [[left displayArtist] caseInsensitiveCompare:[right displayArtist]];
            if (result == NSOrderedSame) result = [[left displayAlbum] caseInsensitiveCompare:[right displayAlbum]];
            if (result == NSOrderedSame) {
                result = (left.trackNumber < right.trackNumber) ? NSOrderedAscending
                       : (left.trackNumber > right.trackNumber) ? NSOrderedDescending : NSOrderedSame;
            }
        }

        if (result == NSOrderedSame) result = [[left displayTitle] caseInsensitiveCompare:[right displayTitle]];
        return ascending ? result : -result;
    }];
}

- (void)reloadEverything {
    NSArray *base = [self baseTracks];

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
    _visibleTracks = [self sortTracks:[_browser filteredTracks]];

    [_sourceList reloadData];
    [_trackTable reloadData];
    [self updateStatus];
    [self updateTransport];
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

    NSString *sizeText;
    double megabytes = (double)bytes / (1024.0 * 1024.0);
    if (megabytes >= 1024.0) {
        sizeText = [NSString stringWithFormat:@"%.2f GB", megabytes / 1024.0];
    } else {
        sizeText = [NSString stringWithFormat:@"%.1f MB", megabytes];
    }

    NSUInteger count = [_visibleTracks count];
    _bottomBar.statusText = [NSString stringWithFormat:@"%lu song%@, %@, %@",
                             (unsigned long)count,
                             (count == 1 ? @"" : @"s"),
                             [BTStyle longTimeStringFromInterval:total],
                             sizeText];
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

- (void)playerChanged:(NSNotification *)note {
    [self updateTransport];
    [_trackTable setNeedsDisplay:YES];
}

#pragma mark - Source list data

- (NSArray *)childrenOfSourceItem:(id)item {
    if (item == nil) {
        NSMutableArray *roots = [NSMutableArray arrayWithObject:BTLibrarySource];
        // The iPod sits under the library, above the playlists.
        if (_iPod) [roots addObject:_iPod];
        [roots addObjectsFromArray:[BTLibrary sharedLibrary].playlists];
        return roots;
    }
    if (item == BTLibrarySource || [item isKindOfClass:[BTIPod class]]) return @[];
    BTPlaylist *playlist = (BTPlaylist *)item;
    return (playlist.kind == BTPlaylistKindFolder) ? playlist.children : @[];
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
    if ([item isKindOfClass:[BTIPod class]]) return [(BTIPod *)item name];
    return [(BTPlaylist *)item name];
}

- (void)outlineView:(NSOutlineView *)outlineView
     setObjectValue:(id)object
     forTableColumn:(NSTableColumn *)tableColumn
             byItem:(id)item {
    if (item == BTLibrarySource || [item isKindOfClass:[BTIPod class]]) return;
    if ([object isKindOfClass:[NSString class]] && [(NSString *)object length] > 0) {
        [(BTPlaylist *)item setName:object];
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
        [sourceCell setTextColor:(selected ? [NSColor whiteColor] : [NSColor blackColor])];
    }
}

// Renaming happens on a double click, or right after a playlist is created.
// Without this gate, tabbing through the window opens an editor on whatever
// row it lands on.
- (BOOL)outlineView:(NSOutlineView *)outlineView
shouldEditTableColumn:(NSTableColumn *)tableColumn
               item:(id)item {
    return _renameRequested && item != BTLibrarySource;
}

- (void)beginRenamingRow:(NSInteger)row {
    if (row < 0) return;
    id item = [_sourceList itemAtRow:row];
    if (item == nil || item == BTLibrarySource) return;

    _renameRequested = YES;
    [_sourceList editColumn:0 row:row withEvent:nil select:YES];
    _renameRequested = NO;
}

- (void)renameSelectedPlaylist:(id)sender {
    NSInteger row = [_sourceList clickedRow];
    if (row < 0) row = [_sourceList selectedRow];
    [self beginRenamingRow:row];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = [_sourceList selectedRow];
    id item = (row >= 0) ? [_sourceList itemAtRow:row] : BTLibrarySource;
    if (item == nil) item = BTLibrarySource;
    _selectedSource = item;
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
    id item = [items objectAtIndex:0];
    if (item == BTLibrarySource) return NO;

    [pasteboard declareTypes:@[BTPlaylistPasteboardType] owner:self];
    [pasteboard setString:[(BTPlaylist *)item playlistID] forType:BTPlaylistPasteboardType];
    return YES;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView
                  validateDrop:(id<NSDraggingInfo>)info
                  proposedItem:(id)item
            proposedChildIndex:(NSInteger)index {
    NSPasteboard *pasteboard = [info draggingPasteboard];

    if ([[pasteboard types] containsObject:BTTrackPasteboardType]) {
        // Songs land on a static playlist, never on the library or a folder.
        if (item == nil || item == BTLibrarySource) return NSDragOperationNone;
        BTPlaylist *target = (BTPlaylist *)item;
        if (target.kind != BTPlaylistKindStatic) return NSDragOperationNone;
        if (index != NSOutlineViewDropOnItemIndex) return NSDragOperationNone;
        return NSDragOperationCopy;
    }

    if ([[pasteboard types] containsObject:BTPlaylistPasteboardType]) {
        if (item == BTLibrarySource) return NSDragOperationNone;
        if (item != nil && [(BTPlaylist *)item kind] != BTPlaylistKindFolder) return NSDragOperationNone;
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

    if ([[pasteboard types] containsObject:BTTrackPasteboardType]) {
        BTPlaylist *target = (BTPlaylist *)item;
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
        [library movePlaylist:moving toFolder:(BTPlaylist *)item atIndex:index];
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
    BTTrack *track = [_visibleTracks objectAtIndex:(NSUInteger)row];
    NSString *identifier = [tableColumn identifier];

    if ([identifier isEqualToString:@"track"]) {
        return track.trackNumber > 0 ? [NSString stringWithFormat:@"%ld", (long)track.trackNumber] : @"";
    }
    if ([identifier isEqualToString:@"title"]) return [track displayTitle];
    if ([identifier isEqualToString:@"time"]) return [track durationString];
    if ([identifier isEqualToString:@"artist"]) return [track displayArtist];
    if ([identifier isEqualToString:@"album"]) return [track displayAlbum];
    if ([identifier isEqualToString:@"genre"]) return (track.genre ? track.genre : @"");
    if ([identifier isEqualToString:@"playCount"]) {
        return track.playCount > 0 ? [NSString stringWithFormat:@"%ld", (long)track.playCount] : @"";
    }
    return nil;
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
        BOOL playing = (track == [[BTPlayer sharedPlayer] currentTrack]);
        [(BTTrackNumberCell *)cell setIndicator:(playing ? _speakerImage : nil)];
    }
    NSColor *color = track.isProtected ? [NSColor colorWithCalibratedWhite:0.55 alpha:1.0]
                                       : [NSColor blackColor];
    [(NSTextFieldCell *)cell setTextColor:(selected ? [NSColor whiteColor] : color)];
}

- (void)tableView:(NSTableView *)tableView
    didClickTableColumn:(NSTableColumn *)tableColumn {
    NSString *identifier = [tableColumn identifier];
    if ([identifier isEqualToString:@"playing"]) return;

    if ([identifier isEqualToString:_sortColumn]) {
        _sortAscending = !_sortAscending;
    } else {
        _sortColumn = identifier;
        _sortAscending = YES;
    }
    NSUInteger i;
    for (i = 0; i < [[tableView tableColumns] count]; i++) {
        [tableView setIndicatorImage:nil inTableColumn:[[tableView tableColumns] objectAtIndex:i]];
    }
    [tableView setHighlightedTableColumn:tableColumn];
    [tableView setIndicatorImage:[NSImage imageNamed:(_sortAscending ? @"NSAscendingSortIndicator"
                                                                     : @"NSDescendingSortIndicator")]
                   inTableColumn:tableColumn];
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
    NSInteger row = [_sourceList selectedRow];
    if (row < 0) return;
    id item = [_sourceList itemAtRow:row];
    if (item == nil || item == BTLibrarySource) return;

    BTPlaylist *playlist = (BTPlaylist *)item;
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
    if (_selectedSource != BTLibrarySource && [(BTPlaylist *)_selectedSource kind] == BTPlaylistKindStatic) {
        BTPlaylist *playlist = (BTPlaylist *)_selectedSource;
        NSUInteger i;
        for (i = 0; i < [tracks count]; i++) {
            [playlist.trackIDs removeObject:[[tracks objectAtIndex:i] trackID]];
        }
        [library noteChanged];
        return;
    }
    if (_selectedSource != BTLibrarySource) return;   // smart playlists have no manual removal

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
    _visibleTracks = [self sortTracks:[browser filteredTracks]];
    [_trackTable reloadData];
    [self updateStatus];
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
    if ([player currentTrack] == nil) {
        NSInteger row = [_trackTable selectedRow];
        if (row < 0 && [_visibleTracks count] > 0) row = 0;
        if (row >= 0 && row < (NSInteger)[_visibleTracks count]) {
            [player playTrack:[_visibleTracks objectAtIndex:(NSUInteger)row] inList:_visibleTracks];
        }
        return;
    }
    [player togglePlayPause];
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
    NSInteger row = [_sourceList selectedRow];
    if (row < 0) return nil;
    id item = [_sourceList itemAtRow:row];
    if (item == nil || item == BTLibrarySource) return nil;
    BTPlaylist *selected = (BTPlaylist *)item;
    if (selected.kind == BTPlaylistKindFolder) return selected;
    return selected.parent;
}

- (void)selectPlaylist:(BTPlaylist *)playlist {
    BTPlaylist *parent = playlist.parent;
    while (parent) {
        [_sourceList expandItem:parent];
        parent = parent.parent;
    }
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
    NSInteger row = [_sourceList selectedRow];
    if (row < 0) return;
    id item = [_sourceList itemAtRow:row];
    if (item == nil || item == BTLibrarySource) return;
    BTPlaylist *playlist = (BTPlaylist *)item;
    if (playlist.kind != BTPlaylistKindSmart) return;

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

- (void)importITunesLibrary:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setAllowedFileTypes:@[@"xml"]];
    [panel setPrompt:@"Import"];
    [panel setMessage:@"Choose an iTunes library XML file. It is read, never written."];

    NSArray *guesses = [BTLibrary iTunesLibraryPathsForHome:NSHomeDirectory()];
    NSUInteger i;
    for (i = 0; i < [guesses count]; i++) {
        NSString *guess = [guesses objectAtIndex:i];
        if ([[NSFileManager defaultManager] fileExistsAtPath:guess]) {
            [panel setDirectoryURL:[NSURL fileURLWithPath:[guess stringByDeletingLastPathComponent]]];
            break;
        }
    }

    if ([panel runModal] != NSFileHandlingPanelOKButton) return;

    NSString *path = [[[panel URLs] objectAtIndex:0] path];
    NSDictionary *result = [[BTLibrary sharedLibrary] importITunesLibraryAtPath:path trackLimit:0];

    NSAlert *alert = [[NSAlert alloc] init];
    if ([result objectForKey:@"error"]) {
        [alert setMessageText:@"Nothing was imported."];
        [alert setInformativeText:[result objectForKey:@"error"]];
    } else {
        [alert setMessageText:@"Import finished."];
        NSMutableString *detail = [NSMutableString string];
        [detail appendFormat:@"%@ songs added, %@ already present.\n",
         [result objectForKey:@"tracksAdded"], [result objectForKey:@"tracksSkipped"]];
        [detail appendFormat:@"%@ playlists and %@ folders rebuilt.\n",
         [result objectForKey:@"playlistsAdded"], [result objectForKey:@"foldersAdded"]];
        if ([[result objectForKey:@"smartAsStatic"] integerValue] > 0) {
            [detail appendFormat:@"%@ smart playlists came across as ordinary playlists holding their current songs.\n",
             [result objectForKey:@"smartAsStatic"]];
        }
        if ([[result objectForKey:@"protectedTracks"] integerValue] > 0) {
            [detail appendFormat:@"%@ locked purchases are listed but cannot play until they are converted.",
             [result objectForKey:@"protectedTracks"]];
        }
        [alert setInformativeText:detail];
    }
    [alert runModal];
    [self reloadEverything];
}

- (void)deleteSelection:(id)sender {
    if ([[self window] firstResponder] == _sourceList) {
        [self deleteSelectedPlaylist];
    } else {
        [self deleteSelectedTracks];
    }
}

#pragma mark - Menu validation

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = [item action];
    if (action == @selector(editSmartPlaylist:)) {
        NSInteger row = [_sourceList selectedRow];
        if (row < 0) return NO;
        id selected = [_sourceList itemAtRow:row];
        return (selected != nil && selected != BTLibrarySource &&
                [(BTPlaylist *)selected kind] == BTPlaylistKindSmart);
    }
    return YES;
}

@end
