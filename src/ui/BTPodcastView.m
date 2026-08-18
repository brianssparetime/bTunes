#import "BTPodcastView.h"

#import "BTControls.h"
#import "BTMainWindowViews.h"
#import "BTPlayer.h"
#import "BTPodcast.h"
#import "BTStyle.h"
#import "BTTrackColumns.h"
#import "BTTrack.h"

// How wide the list of shows starts, and how far it can be dragged. The same
// width the source list beside it uses, so the two columns of names line up
// rather than sitting at two arbitrary widths.
static const CGFloat BTShowListWidth = 190.0;
static const CGFloat BTShowListMinWidth = 140.0;
static const CGFloat BTShowListMaxWidth = 340.0;

// A row in either list carries two lines. The second is the quieter one: the
// author under a show, the synopsis under an episode. Both are given their own
// band and their own size, because a row that says two things at one weight
// makes the reader work out which is the name.
static const CGFloat BTSecondLineHeight = 15.0;

// A little air above and below the pair, so two lines in a row do not touch the
// rows either side of them.
static const CGFloat BTRowPadding = 3.0;

static const CGFloat BTTextInset = 3.0;

// Truncating with an ellipsis, and doing it by dropping words rather than by
// squeezing them. AppKit tightens a line before it truncates one, which closes
// the spaces between words until a synopsis reads as one long word. Turning
// that off costs a few characters at the end and keeps the sentence legible.
static NSParagraphStyle *BTClippingStyle(void) {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    [style setLineBreakMode:NSLineBreakByTruncatingTail];
    if ([style respondsToSelector:@selector(setAllowsDefaultTighteningForTruncation:)]) {
        [style setAllowsDefaultTighteningForTruncation:NO];
    }
    return style;
}

static CGFloat BTFirstLineHeight(void) { return [BTStyle listRowHeight]; }
static CGFloat BTTwoLineRowHeight(void) {
    return BTFirstLineHeight() + BTSecondLineHeight + BTRowPadding;
}

#pragma mark - A show, named over its author

// Two lines drawn straight rather than handed to the cell's own layout. A cell
// centres whatever line it is given inside the rect it is given, so the way to
// place two lines is to give each one a band of its own height and let the
// centring inside that band be the thing that puts it right.
@interface BTPodcastShowCell : NSTextFieldCell
@property (nonatomic, copy) NSString *author;
@property (nonatomic, strong) NSColor *secondaryColor;
@end

@implementation BTPodcastShowCell

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view {
    NSRect body = NSInsetRect(frame, BTTextInset, 0.0);
    CGFloat first = BTFirstLineHeight();

    NSRect nameRect = NSMakeRect(NSMinX(body), NSMinY(body) + BTRowPadding * 0.5,
                                 NSWidth(body), first);
    NSParagraphStyle *clip = BTClippingStyle();

    [[self stringValue] drawInRect:nameRect withAttributes:@{
        NSFontAttributeName: [self font] ? [self font] : [BTStyle uiFont],
        NSForegroundColorAttributeName: [self textColor] ? [self textColor] : [NSColor blackColor],
        NSParagraphStyleAttributeName: clip,
    }];

    if ([self.author length] == 0) return;

    NSRect authorRect = NSMakeRect(NSMinX(body), NSMaxY(nameRect),
                                   NSWidth(body), BTSecondLineHeight);
    [self.author drawInRect:authorRect withAttributes:@{
        NSFontAttributeName: [BTStyle smallFont],
        NSForegroundColorAttributeName: self.secondaryColor ? self.secondaryColor
                                                            : [BTStyle secondaryText],
        NSParagraphStyleAttributeName: clip,
    }];
}

@end

#pragma mark - An episode, with its synopsis beneath the columns

// The columns occupy the top band of the row and the synopsis runs the whole
// width underneath them. Shrinking the cell frame is what keeps the two apart:
// the table draws its cells wherever this says they are, so the band below is
// left clear for a line that belongs to no column.
@interface BTEpisodeTableView : BTListTableView
@property (nonatomic, copy) NSString *(^synopsisForRow)(NSInteger row);
@end

@implementation BTEpisodeTableView

- (NSRect)frameOfCellAtColumn:(NSInteger)column row:(NSInteger)row {
    NSRect frame = [super frameOfCellAtColumn:column row:row];
    // The table is flipped, so the top of the row is its smallest y.
    frame.origin.y += BTRowPadding * 0.5;
    frame.size.height = BTFirstLineHeight();
    return frame;
}

- (void)drawRow:(NSInteger)row clipRect:(NSRect)clip {
    [super drawRow:row clipRect:clip];
    if (self.synopsisForRow == nil) return;

    NSString *synopsis = self.synopsisForRow(row);
    if ([synopsis length] == 0) return;

    NSRect rect = [self rectOfRow:row];
    NSRect band = NSMakeRect(NSMinX(rect) + BTTextInset + 2.0,
                             NSMinY(rect) + BTRowPadding * 0.5 + BTFirstLineHeight(),
                             NSWidth(rect) - (BTTextInset + 2.0) * 2.0,
                             BTSecondLineHeight);
    if (!NSIntersectsRect(band, clip)) return;

    BOOL selected = [[self selectedRowIndexes] containsIndex:(NSUInteger)row];
    NSColor *color = (selected && BTListHasFocus(self)) ? [NSColor whiteColor]
                                                        : [BTStyle secondaryText];

    [synopsis drawInRect:band withAttributes:@{
        NSFontAttributeName: [BTStyle smallFont],
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: BTClippingStyle(),
    }];
}

@end

#pragma mark - The pane

@interface BTPodcastView () <NSTableViewDataSource, NSTableViewDelegate, NSSplitViewDelegate>
@end

@implementation BTPodcastView {
    NSSplitView *_split;
    BTListTableView *_showTable;
    BTEpisodeTableView *_episodeTable;
    NSImage *_speakerImage;

    NSArray *_podcasts;         // BTPodcast
    BTPodcast *_selectedShow;
    NSArray *_episodes;         // BTTrack, in the order the table shows them

    NSString *_sortColumn;
    BOOL _sortAscending;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) return nil;

    _podcasts = @[];
    _episodes = @[];
    _sortColumn = @"number";
    _sortAscending = YES;
    _speakerImage = [self buildSpeakerImage];

    _split = [[NSSplitView alloc] initWithFrame:[self bounds]];
    [_split setVertical:YES];
    [_split setDividerStyle:NSSplitViewDividerStyleThin];
    [_split setDelegate:self];
    [_split setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [self addSubview:_split];

    [_split addSubview:[self buildShowList]];
    [_split addSubview:[self buildEpisodeList]];
    [_split setPosition:BTShowListWidth ofDividerAtIndex:0];

    return self;
}

#pragma mark - Layout

// Both of these, because the split view resizes the pane by one route and the
// window by the other. An autoresizing mask alone is not enough: a pane built
// at the size it is first given is never resized at all when the frame it is
// handed later arrives by setFrame:, and it sits at its original width with the
// rest of the window bare beside it.
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutPane];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self layoutPane];
}

- (void)layoutPane {
    if (_split == nil) return;
    if (!NSEqualRects([_split frame], [self bounds])) [_split setFrame:[self bounds]];
    // Through the delegate rather than adjustSubviews. adjustSubviews is the
    // split view's own proportional division and does not consult a delegate,
    // so calling it shares the new width out between the two panes and widens
    // the list of shows every time the window grows.
    [self splitView:_split resizeSubviewsWithOldSize:[_split bounds].size];
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

// Returns the scroll view rather than the table: ARC keeps a view alive through
// its superview, so handing back the table would free the scroller around it the
// moment this method returned.
- (NSScrollView *)buildShowList {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:
                            NSMakeRect(0, 0, BTShowListWidth, NSHeight([self bounds]))];
    [scroll setHasVerticalScroller:YES];
    [scroll setAutohidesScrollers:YES];
    [scroll setBorderType:NSNoBorder];
    [scroll setFocusRingType:NSFocusRingTypeNone];
    [scroll setDrawsBackground:YES];
    [scroll setBackgroundColor:[BTStyle listBackground]];

    _showTable = [[BTListTableView alloc] initWithFrame:[[scroll contentView] bounds]];
    [_showTable setFocusRingType:NSFocusRingTypeNone];
    [_showTable setRowHeight:BTTwoLineRowHeight()];
    [_showTable setBackgroundColor:[BTStyle listBackground]];
    [_showTable setAllowsMultipleSelection:NO];
    [_showTable setAllowsColumnSelection:NO];

    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"show"];
    [[column headerCell] setStringValue:@"Podcast"];
    [[column headerCell] setFont:[BTStyle uiFont]];
    [column setEditable:NO];
    [column setWidth:BTShowListWidth];
    [column setMinWidth:BTShowListMinWidth];
    [column setMaxWidth:BTShowListMaxWidth];
    // The one column is the whole pane, so it takes whatever the pane is given
    // rather than sitting at a width of its own and leaving the rest empty.
    [column setResizingMask:NSTableColumnAutoresizingMask];

    BTPodcastShowCell *cell = [[BTPodcastShowCell alloc] init];
    [cell setFont:[BTStyle uiFont]];
    [cell setLineBreakMode:NSLineBreakByTruncatingTail];
    [column setDataCell:cell];
    [_showTable addTableColumn:column];
    [_showTable setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];

    // Without this the table stays as wide as its columns and the rest of the
    // pane is left bare, header and all. The clip view resizes a document view
    // that asks for it, and the column marked as taking the slack then spreads
    // into the width that arrives.
    [_showTable setAutoresizingMask:NSViewWidthSizable];

    [_showTable setDataSource:self];
    [_showTable setDelegate:self];

    [scroll setDocumentView:_showTable];
    return scroll;
}

// What each column of the episode list is. Only the number and the date can be
// sorted: a title sort of a numbered show scatters it, and the mark has nothing
// to sort by at all.
typedef struct {
    __unsafe_unretained NSString *identifier;
    __unsafe_unretained NSString *heading;
    CGFloat width, minimum, maximum;
    BOOL sortable;
    BOOL takesSlack;
} BTEpisodeColumnSpec;

- (NSScrollView *)buildEpisodeList {
    NSRect bounds = NSMakeRect(0, 0, MAX(NSWidth([self bounds]) - BTShowListWidth, 200.0),
                               NSHeight([self bounds]));

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:bounds];
    [scroll setHasVerticalScroller:YES];
    [scroll setAutohidesScrollers:YES];
    [scroll setBorderType:NSNoBorder];
    [scroll setFocusRingType:NSFocusRingTypeNone];
    [scroll setDrawsBackground:YES];
    [scroll setBackgroundColor:[BTStyle listBackground]];
    [scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

    _episodeTable = [[BTEpisodeTableView alloc] initWithFrame:[[scroll contentView] bounds]];
    [_episodeTable setFocusRingType:NSFocusRingTypeNone];
    [_episodeTable setRowHeight:BTTwoLineRowHeight()];
    [_episodeTable setBackgroundColor:[BTStyle listBackground]];
    [_episodeTable setUsesAlternatingRowBackgroundColors:YES];
    [_episodeTable setAllowsMultipleSelection:NO];
    [_episodeTable setAllowsColumnSelection:NO];

    const BTEpisodeColumnSpec specs[] = {
        { @"playing", @"",      18,  18,   18, NO,  NO  },
        { @"number",  @"#",     52,  40,   70, YES, NO  },
        { @"date",    @"Date",  96,  76,  140, YES, NO  },
        { @"title",   @"Title", 320, 140, 4000, NO, YES },
    };

    NSUInteger i;
    for (i = 0; i < sizeof(specs) / sizeof(specs[0]); i++) {
        const BTEpisodeColumnSpec *spec = &specs[i];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec->identifier];
        [[column headerCell] setStringValue:spec->heading];
        [[column headerCell] setFont:[BTStyle uiFont]];
        [column setWidth:spec->width];
        [column setMinWidth:spec->minimum];
        [column setMaxWidth:spec->maximum];
        [column setEditable:NO];

        // The mark has no width worth choosing, and only the title grows with
        // the window: a date or a number stretched to fill the pane reads as a
        // mistake.
        NSUInteger mask = NSTableColumnUserResizingMask;
        if (spec->takesSlack) mask |= NSTableColumnAutoresizingMask;
        if ([spec->identifier isEqualToString:@"playing"]) mask = 0;
        [column setResizingMask:mask];

        NSTextFieldCell *cell;
        if ([spec->identifier isEqualToString:@"playing"]) {
            cell = [[BTTrackNumberCell alloc] init];
        } else if ([spec->identifier isEqualToString:@"number"]) {
            cell = [[BTNumberCell alloc] init];
        } else {
            cell = [[NSTextFieldCell alloc] init];
            [cell setLineBreakMode:NSLineBreakByTruncatingTail];
        }
        [cell setFont:[BTStyle uiFont]];
        [column setDataCell:cell];
        [_episodeTable addTableColumn:column];
    }
    [_episodeTable setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];

    __weak BTPodcastView *weakSelf = self;
    [_episodeTable setSynopsisForRow:^NSString *(NSInteger row) {
        BTPodcastView *strongSelf = weakSelf;
        return strongSelf ? [strongSelf synopsisForRow:row] : nil;
    }];

    [_episodeTable setAutoresizingMask:NSViewWidthSizable];

    [_episodeTable setDataSource:self];
    [_episodeTable setDelegate:self];
    [_episodeTable setTarget:self];
    [_episodeTable setDoubleAction:@selector(playClickedEpisode:)];

    [scroll setDocumentView:_episodeTable];
    [self showSortIndicator];
    return scroll;
}

#pragma mark - Reading the folder

- (void)reload {
    NSString *wasShowing = [_selectedShow folderName];

    _podcasts = [BTPodcast podcastsOnDisk];
    [_showTable reloadData];

    NSUInteger wanted = NSNotFound;
    NSUInteger i;
    for (i = 0; i < [_podcasts count]; i++) {
        if ([[[_podcasts objectAtIndex:i] folderName] isEqualToString:wasShowing]) {
            wanted = i;
            break;
        }
    }
    // Falling back to the first show rather than to nothing: an empty right half
    // beside a list with shows in it reads as a pane that failed to load.
    if (wanted == NSNotFound && [_podcasts count] > 0) wanted = 0;

    if (wanted == NSNotFound) {
        [self showEpisodesOf:nil];
    } else {
        [_showTable selectRowIndexes:[NSIndexSet indexSetWithIndex:wanted]
                byExtendingSelection:NO];
        [self showEpisodesOf:[_podcasts objectAtIndex:wanted]];
    }
}

- (void)showEpisodesOf:(BTPodcast *)podcast {
    _selectedShow = podcast;
    _episodes = [self sorted:[podcast episodes]];
    [_episodeTable reloadData];
    [_episodeTable deselectAll:nil];
    [self reportStatus];
    [self readDurationsOf:podcast];
}

// The same three figures the song list gives, in the same order and the same
// words, counting episodes instead of songs. The running time is nothing until
// the lengths have been read, which is why this is said again when they arrive.
- (void)reportStatusNow { [self reportStatus]; }

- (void)reportStatus {
    if (self.statusDidChange == nil) return;

    NSTimeInterval total = 0;
    long long bytes = 0;
    NSUInteger i;
    for (i = 0; i < [_episodes count]; i++) {
        BTTrack *episode = [_episodes objectAtIndex:i];
        total += episode.duration;
        bytes += episode.fileSize;
    }

    NSUInteger count = [_episodes count];
    self.statusDidChange([NSString stringWithFormat:@"%lu episode%@, %@, %@",
                          (unsigned long)count, (count == 1 ? @"" : @"s"),
                          [BTTrack runningTimeStringFromInterval:total],
                          BTSizeString(bytes)]);
}

// Opening two hundred files to ask how long each runs takes long enough to be
// seen, so it happens off the main thread and the list is redrawn when it comes
// back. The show is checked again on the way back, because the reader may have
// picked a different one while it ran.
- (void)readDurationsOf:(BTPodcast *)podcast {
    if (podcast == nil || [podcast durationsAreKnown]) return;

    __weak BTPodcastView *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [podcast readDurations];
        dispatch_async(dispatch_get_main_queue(), ^{
            BTPodcastView *strongSelf = weakSelf;
            if (strongSelf == nil) return;
            if (podcast != strongSelf->_selectedShow) return;
            [strongSelf->_episodeTable reloadData];
            [strongSelf reportStatus];
        });
    });
}

#pragma mark - Order

- (NSArray *)sorted:(NSArray *)episodes {
    if ([episodes count] == 0) return @[];

    BTPodcast *show = _selectedShow;
    BOOL ascending = _sortAscending;
    BOOL byDate = [_sortColumn isEqualToString:@"date"];

    return [episodes sortedArrayUsingComparator:^NSComparisonResult(BTTrack *a, BTTrack *b) {
        NSComparisonResult result;
        if (byDate) {
            NSDate *first = [show airDateForEpisode:a];
            NSDate *second = [show airDateForEpisode:b];
            // An episode with no date sorts to the end whichever way the column
            // points, because it is missing rather than early.
            if (first == nil && second == nil) result = NSOrderedSame;
            else if (first == nil) return NSOrderedDescending;
            else if (second == nil) return NSOrderedAscending;
            else result = [first compare:second];
        } else {
            // By the filename, which is where the number lives and which orders
            // 003a before 003b and 9 before 10 without any parsing.
            result = [[[a.path lastPathComponent] stringByDeletingPathExtension]
                      localizedStandardCompare:
                      [[b.path lastPathComponent] stringByDeletingPathExtension]];
        }
        if (result == NSOrderedSame) return NSOrderedSame;
        return ascending ? result : (result == NSOrderedAscending ? NSOrderedDescending
                                                                  : NSOrderedAscending);
    }];
}

- (void)showSortIndicator {
    NSArray *columns = [_episodeTable tableColumns];
    NSUInteger i;
    for (i = 0; i < [columns count]; i++) {
        NSTableColumn *column = [columns objectAtIndex:i];
        BOOL isSorted = [[column identifier] isEqualToString:_sortColumn];
        [_episodeTable setIndicatorImage:(isSorted
            ? [NSImage imageNamed:(_sortAscending ? @"NSAscendingSortIndicator"
                                                  : @"NSDescendingSortIndicator")]
            : nil)
                           inTableColumn:column];
        if (isSorted) [_episodeTable setHighlightedTableColumn:column];
    }
}

#pragma mark - What the show said

- (NSString *)synopsisForRow:(NSInteger)row {
    if (_selectedShow == nil) return nil;
    if (row < 0 || row >= (NSInteger)[_episodes count]) return nil;
    return [_selectedShow synopsisForEpisode:[_episodes objectAtIndex:(NSUInteger)row]];
}

- (NSString *)dateStringForEpisode:(BTTrack *)episode {
    NSDate *aired = [_selectedShow airDateForEpisode:episode];
    if (aired == nil) return @"";

    static NSDateFormatter *formatter = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateStyle:NSDateFormatterMediumStyle];
        [formatter setTimeStyle:NSDateFormatterNoStyle];
        // Read as a date rather than a moment: the file records the day a show
        // was published, and a time zone applied to it can move it a day.
        [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
    });
    return [formatter stringFromDate:aired];
}

#pragma mark - Playing

- (void)playClickedEpisode:(id)sender {
    NSInteger row = [_episodeTable clickedRow];
    if (row < 0) row = [_episodeTable selectedRow];
    if (row < 0 || row >= (NSInteger)[_episodes count]) return;

    [[BTPlayer sharedPlayer] playTrack:[_episodes objectAtIndex:(NSUInteger)row]
                                inList:_episodes];
}

#pragma mark - The two lists

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == _showTable) return (NSInteger)[_podcasts count];
    return (NSInteger)[_episodes count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                          row:(NSInteger)row {
    if (tableView == _showTable) {
        if (row < 0 || row >= (NSInteger)[_podcasts count]) return nil;
        return [[_podcasts objectAtIndex:(NSUInteger)row] name];
    }

    if (row < 0 || row >= (NSInteger)[_episodes count]) return nil;
    BTTrack *episode = [_episodes objectAtIndex:(NSUInteger)row];
    NSString *identifier = [tableColumn identifier];

    if ([identifier isEqualToString:@"playing"]) return @"";
    if ([identifier isEqualToString:@"number"]) {
        NSString *number = [_selectedShow episodeNumberForEpisode:episode];
        return number ? number : @"";
    }
    if ([identifier isEqualToString:@"date"]) return [self dateStringForEpisode:episode];
    return [episode displayTitle];
}

- (void)tableView:(NSTableView *)tableView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn
                row:(NSInteger)row {
    if (![cell isKindOfClass:[NSTextFieldCell class]]) return;

    // The row fill is drawn once, by the table. A cell drawing its own highlight
    // on top of that comes out as a patchwork of two different blues.
    [(NSTextFieldCell *)cell setHighlighted:NO];

    BOOL selected = [[tableView selectedRowIndexes] containsIndex:(NSUInteger)row];
    BOOL lit = (selected && BTListHasFocus(tableView));
    NSColor *primary = lit ? [NSColor whiteColor] : [NSColor blackColor];
    [(NSTextFieldCell *)cell setTextColor:primary];

    if (tableView == _showTable) {
        if (row < 0 || row >= (NSInteger)[_podcasts count]) return;
        BTPodcast *podcast = [_podcasts objectAtIndex:(NSUInteger)row];
        BTPodcastShowCell *showCell = (BTPodcastShowCell *)cell;
        [showCell setAuthor:[podcast author]];
        [showCell setSecondaryColor:(lit ? [NSColor whiteColor] : [BTStyle secondaryText])];
        return;
    }

    if ([cell isKindOfClass:[BTTrackNumberCell class]]) {
        if (row < 0 || row >= (NSInteger)[_episodes count]) return;
        BTTrack *episode = [_episodes objectAtIndex:(NSUInteger)row];
        BOOL playing = (episode == [[BTPlayer sharedPlayer] currentTrack]);
        [(BTTrackNumberCell *)cell setIndicator:(playing ? _speakerImage : nil)];
        [(BTTrackNumberCell *)cell setShowsPlay:NO];
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)note {
    if ([note object] != _showTable) return;

    NSInteger row = [_showTable selectedRow];
    BTPodcast *podcast = (row >= 0 && row < (NSInteger)[_podcasts count])
                       ? [_podcasts objectAtIndex:(NSUInteger)row] : nil;
    if (podcast != _selectedShow) [self showEpisodesOf:podcast];
}

// Only the number and the date answer a click. Clicking the title or the mark
// does nothing at all rather than sorting by something that means nothing.
- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)column {
    if (tableView != _episodeTable) return;

    NSString *identifier = [column identifier];
    if (!([identifier isEqualToString:@"number"] || [identifier isEqualToString:@"date"])) {
        return;
    }

    if ([identifier isEqualToString:_sortColumn]) {
        _sortAscending = !_sortAscending;
    } else {
        _sortColumn = [identifier copy];
        _sortAscending = YES;
    }
    [self showSortIndicator];

    BTTrack *wasSelected = nil;
    NSInteger row = [_episodeTable selectedRow];
    if (row >= 0 && row < (NSInteger)[_episodes count]) {
        wasSelected = [_episodes objectAtIndex:(NSUInteger)row];
    }

    _episodes = [self sorted:[_selectedShow episodes]];
    [_episodeTable reloadData];

    // The episode that was selected keeps its selection through a sort, rather
    // than the row number keeping it and landing on something unrelated.
    if (wasSelected) {
        NSUInteger moved = [_episodes indexOfObject:wasSelected];
        if (moved != NSNotFound) {
            [_episodeTable selectRowIndexes:[NSIndexSet indexSetWithIndex:moved]
                       byExtendingSelection:NO];
            [_episodeTable scrollRowToVisible:(NSInteger)moved];
        }
    }
}

#pragma mark - The divider

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMinCoordinate:(CGFloat)proposed
               ofSubviewAt:(NSInteger)index {
    return BTShowListMinWidth;
}

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMaxCoordinate:(CGFloat)proposed
               ofSubviewAt:(NSInteger)index {
    return BTShowListMaxWidth;
}

// The show list keeps its width and the episodes take the slack, which is how
// the source list beside it behaves.
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
    NSArray *subviews = [splitView subviews];
    if ([subviews count] != 2) return;

    NSView *left = [subviews objectAtIndex:0];
    NSView *right = [subviews objectAtIndex:1];
    CGFloat divider = [splitView dividerThickness];
    NSSize size = [splitView bounds].size;

    CGFloat leftWidth = NSWidth([left frame]);
    if (leftWidth < BTShowListMinWidth) leftWidth = BTShowListMinWidth;
    if (leftWidth > size.width - divider - BTShowListMinWidth) {
        leftWidth = size.width - divider - BTShowListMinWidth;
    }
    if (leftWidth < 0) leftWidth = 0;

    [left setFrame:NSMakeRect(0, 0, leftWidth, size.height)];
    [right setFrame:NSMakeRect(leftWidth + divider, 0,
                               size.width - leftWidth - divider, size.height)];
}

@end
