#import "BTSyncModificationsController.h"
#import "BTControls.h"
#import "BTStyle.h"
#import "BTITunesSync.h"

// Around the list, and how much of the window the two name columns share once
// the tick and the status have taken what they need.
#define BT_MOD_MARGIN        12.0
#define BT_MOD_TICK_WIDTH    20.0
#define BT_MOD_PLAYLIST_SHARE 0.42

@interface BTSyncModificationsController () <NSTableViewDataSource, NSTableViewDelegate,
                                             NSWindowDelegate>
@end

@implementation BTSyncModificationsController {
    __weak id <BTSyncModificationsSource> _source;
    NSArray *_additions;
    NSTableView *_list;
    NSScrollView *_scroll;
}

- (instancetype)initWithSource:(id <BTSyncModificationsSource>)source {
    NSRect frame = NSMakeRect(0, 0, 560, 320);
    BTPanelWindow *window = [[BTPanelWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:@"Playlist Modifications"];
    [window setReleasedWhenClosed:NO];
    [window setMinSize:NSMakeSize(400, 200)];
    [window center];
    // Where it was last put and how big it was last made, remembered the same
    // way the ticks inside it are.
    [window setFrameAutosaveName:@"BTSyncModifications"];

    self = [super initWithWindow:window];
    if (self == nil) return nil;

    _source = source;
    _additions = @[];
    [window setDelegate:self];
    [self buildList];
    [self refresh];
    return self;
}

- (void)buildList {
    NSView *content = [[self window] contentView];

    _list = [[BTListTableView alloc] initWithFrame:NSZeroRect];
    [_list setFocusRingType:NSFocusRingTypeNone];
    [_list setRowHeight:[BTStyle listRowHeight]];
    [_list setUsesAlternatingRowBackgroundColors:YES];
    [_list setAllowsMultipleSelection:NO];
    [_list setAllowsColumnSelection:NO];
    [_list setDataSource:self];
    [_list setDelegate:self];
    // A click anywhere in the row ticks it, as in the two lists this came from.
    [_list setTarget:self];
    [_list setAction:@selector(rowClicked:)];

    NSArray *specs = @[@[@"check", @""],
                       @[@"playlist", @"Playlist"],
                       @[@"song", @"Song added"],
                       @[@"what", @""]];
    NSUInteger i;
    for (i = 0; i < [specs count]; i++) {
        NSArray *spec = [specs objectAtIndex:i];
        NSString *identifier = [spec objectAtIndex:0];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
        [[column headerCell] setStringValue:[spec objectAtIndex:1]];
        [[column headerCell] setFont:[BTStyle uiFont]];

        if ([identifier isEqualToString:@"check"]) {
            NSButtonCell *cell = [[BTCheckboxCell alloc] init];
            [cell setButtonType:NSSwitchButton];
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
        [_list addTableColumn:column];
    }

    _scroll = [[NSScrollView alloc] initWithFrame:NSInsetRect([content bounds],
                                                              BT_MOD_MARGIN, BT_MOD_MARGIN)];
    [_scroll setHasVerticalScroller:YES];
    [_scroll setAutohidesScrollers:YES];
    [_scroll setBorderType:NSBezelBorder];
    [_scroll setFocusRingType:NSFocusRingTypeNone];
    [_scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_scroll setDocumentView:_list];
    [content addSubview:_scroll];

    // The columns follow the room inside the scroller rather than the window,
    // so the width a scroll bar takes is gone before they are divided up.
    NSClipView *clip = [_scroll contentView];
    [clip setPostsFrameChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(roomChanged:)
                                                name:NSViewFrameDidChangeNotification
                                              object:clip];
    [self sizeColumns];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)roomChanged:(NSNotification *)note {
    [self sizeColumns];
}

// Everything the status column can ever say, kept beside the words themselves so
// the list cannot go stale when one of them is reworded.
+ (NSArray *)statusVocabulary {
    return @[@"playlist not checked", @"song not checked"];
}

static CGFloat BTWidestOf(NSArray *words) {
    NSDictionary *attrs = @{NSFontAttributeName: [BTStyle uiFont]};
    CGFloat widest = 0;
    NSUInteger i;
    for (i = 0; i < [words count]; i++) {
        CGFloat w = ceil([[words objectAtIndex:i] sizeWithAttributes:attrs].width);
        if (w > widest) widest = w;
    }
    return widest + 12.0;
}

- (void)sizeColumns {
    CGFloat available = NSWidth([[_scroll contentView] bounds]) - 2.0;
    CGFloat status = BTWidestOf([[self class] statusVocabulary]);
    CGFloat room = available - BT_MOD_TICK_WIDTH - status;
    if (room < 160) room = 160;

    [[_list tableColumnWithIdentifier:@"check"] setWidth:BT_MOD_TICK_WIDTH];
    [[_list tableColumnWithIdentifier:@"what"] setWidth:status];
    [[_list tableColumnWithIdentifier:@"playlist"] setWidth:floor(room * BT_MOD_PLAYLIST_SHARE)];
    [[_list tableColumnWithIdentifier:@"song"] setWidth:ceil(room * (1.0 - BT_MOD_PLAYLIST_SHARE))];
}

#pragma mark - What it shows

- (void)refresh {
    _additions = [_source syncModifications];
    if (_additions == nil) _additions = @[];
    [[self window] setTitle:[NSString stringWithFormat:@"Playlist Modifications (%lu)",
                             (unsigned long)[_additions count]]];
    [_list reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)[_additions count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                          row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)[_additions count]) return nil;
    BTITunesSyncModification *addition = [_additions objectAtIndex:(NSUInteger)row];
    NSString *identifier = [tableColumn identifier];

    if ([identifier isEqualToString:@"check"]) {
        return @([_source modificationIsChosen:addition] ? NSOnState : NSOffState);
    }
    if ([identifier isEqualToString:@"playlist"]) {
        return addition.playlistName ? addition.playlistName : @"";
    }
    if ([identifier isEqualToString:@"song"]) {
        return [addition.songTitle length] > 0 ? addition.songTitle : @"(untitled)";
    }
    return [_source wordForModification:addition];
}

- (void)tableView:(NSTableView *)tableView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn
                row:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)[_additions count]) return;
    BTITunesSyncModification *addition = [_additions objectAtIndex:(NSUInteger)row];
    BOOL available = [_source modificationCanBeChosen:addition];

    // One that cannot happen says so by going gray, the same as a song or a
    // playlist that cannot come across.
    if ([cell isKindOfClass:[NSButtonCell class]]) {
        [(NSButtonCell *)cell setEnabled:available];
        return;
    }
    if (![cell isKindOfClass:[NSTextFieldCell class]]) return;
    [(NSTextFieldCell *)cell setHighlighted:NO];
    [(NSTextFieldCell *)cell setTextColor:(available ? [NSColor blackColor]
                                                     : [BTStyle ineligibleTextForReason:0])];
}

#pragma mark - Ticking

- (void)tableView:(NSTableView *)tableView
   setObjectValue:(id)object
   forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row {
    if (![[tableColumn identifier] isEqualToString:@"check"]) return;
    [self toggleRow:row];
}

// Anywhere in the row, except on the box itself: the cell has already turned
// that one over, and turning it over again would put it back.
- (void)rowClicked:(id)sender {
    NSInteger column = [_list clickedColumn];
    if (column >= 0) {
        NSString *identifier = [[[_list tableColumns] objectAtIndex:(NSUInteger)column] identifier];
        if ([identifier isEqualToString:@"check"]) return;
    }
    [self toggleRow:[_list clickedRow]];
}

- (void)toggleRow:(NSInteger)row {
    if (row < 0 || row >= (NSInteger)[_additions count]) return;
    BTITunesSyncModification *addition = [_additions objectAtIndex:(NSUInteger)row];
    if (![_source modificationCanBeChosen:addition]) return;
    [_source setModification:addition chosen:![_source modificationIsChosen:addition]];
    // The pane behind redraws this window as part of taking the tick, since a
    // playlist reads as partly chosen the moment one of its songs is turned down.
}

#pragma mark - Going away

- (void)windowWillClose:(NSNotification *)note {
    [_source modificationsWindowClosed];
}

@end
