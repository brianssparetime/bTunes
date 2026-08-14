#import "BTSourceList.h"
#import "BTMainWindowViews.h"
#import "BTSourceIcon.h"
#import "BTDragTypes.h"
#import "BTStyle.h"
#import "BTControls.h"
#import "BTLibrary.h"
#import "BTPlaylist.h"
#import "BTIPod.h"
#import "BTAudioDisc.h"

NSString *const BTLibrarySource = @"Library";
// The same songs as the library, held in the order iTunes recorded them being
// added. Deliberately not the order BTunes learned of them, which for anything
// a sync brings is one moment for thousands of songs and says nothing at all.
NSString *const BTRecentlyAddedSource = @"Recently Added";

// Air above the first row, taken inside the list rather than between the panels.
// A gap between them exposes the window's own background as a band of flat gray
// running across the window.
#define BT_SOURCE_TOP_INSET 6.0

BTPlaylist *BTPlaylistFromSource(id item) {
    return [item isKindOfClass:[BTPlaylist class]] ? (BTPlaylist *)item : nil;
}

@interface BTSourceList () <NSOutlineViewDataSource, NSOutlineViewDelegate, BTKeyTableDelegate>
@end

@implementation BTSourceList {
    __weak id<BTSourceListDelegate> _delegate;
    BTKeyOutlineView *_outline;
    NSScrollView *_scroll;
    NSMutableSet *_closedFolders;
    // Renaming is offered on a double click and when a playlist has just been
    // made, and refused every other time. Without the gate, tabbing through the
    // window opens an editor on whatever row it lands on.
    BOOL _renameRequested;
}

- (instancetype)initWithDelegate:(id<BTSourceListDelegate>)delegate {
    self = [super init];
    if (self == nil) return nil;

    _delegate = delegate;
    _closedFolders = [NSMutableSet set];

    _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 170, 300)];
    [_scroll setHasVerticalScroller:YES];
    [_scroll setAutohidesScrollers:YES];
    [_scroll setBorderType:NSNoBorder];
    [_scroll setDrawsBackground:YES];
    [_scroll setBackgroundColor:[BTStyle listBackground]];
    [_scroll setFocusRingType:NSFocusRingTypeNone];
    [_scroll setAutomaticallyAdjustsContentInsets:NO];
    [_scroll setContentInsets:NSEdgeInsetsMake(BT_SOURCE_TOP_INSET, 0, 0, 0)];

    _outline = [[BTKeyOutlineView alloc] initWithFrame:[[_scroll contentView] bounds]];
    [_outline setFocusRingType:NSFocusRingTypeNone];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"source"];
    // A starting width only. It follows the pane from here on, or a name wider
    // than this stays cut short however far the pane is dragged open.
    [column setWidth:150];
    BTSourceCell *cell = [[BTSourceCell alloc] init];
    [cell setFont:[BTStyle uiFont]];
    [cell setLineBreakMode:NSLineBreakByTruncatingTail];
    [cell setEditable:YES];
    [column setDataCell:cell];
    [_outline addTableColumn:column];
    [_outline setOutlineTableColumn:column];
    [_outline setHeaderView:nil];
    [_outline setRowHeight:[BTStyle sourceRowHeight]];
    [_outline setIndentationPerLevel:14.0];
    [_outline setDataSource:self];
    [_outline setDelegate:self];
    [_outline setAllowsMultipleSelection:NO];
    [_outline setAllowsColumnSelection:NO];
    [_outline setTarget:self];
    [_outline setAction:@selector(rowClicked:)];
    [_outline setDoubleAction:@selector(renameClickedPlaylist:)];
    [_outline registerForDraggedTypes:@[BTTrackPasteboardType, BTPlaylistPasteboardType]];

    [_scroll setDocumentView:_outline];
    return self;
}

- (NSScrollView *)scrollView { return _scroll; }
- (NSOutlineView *)outlineView { return _outline; }

#pragma mark - What the tree holds

- (void)setIPod:(BTIPod *)iPod {
    _iPod = iPod;
    [self reload];
}

- (void)setDisc:(BTAudioDisc *)disc {
    _disc = disc;
    [self reload];
}

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

- (NSArray *)arranged:(NSArray *)playlists {
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

- (NSArray *)childrenOf:(id)item {
    if (item == nil) {
        // A disc sits directly under the library, because it is another place
        // songs come from. Recently Added is a second view of the library rather
        // than a source of its own, so it follows.
        NSMutableArray *roots = [NSMutableArray arrayWithObject:BTLibrarySource];
        if (self.disc) [roots addObject:self.disc];
        [roots addObject:BTRecentlyAddedSource];
        // The iPod sits under the library views, above the playlists.
        if (self.iPod) [roots addObject:self.iPod];
        [roots addObjectsFromArray:[self arranged:[BTLibrary sharedLibrary].playlists]];
        return roots;
    }
    BTPlaylist *playlist = BTPlaylistFromSource(item);
    if (playlist == nil || playlist.kind != BTPlaylistKindFolder) return @[];
    return [self arranged:playlist.children];
}

#pragma mark - Rows

- (void)reload {
    [_outline reloadData];
    [self openFolders];
}

// Folders come up open, since a closed one hides the playlists it holds. One
// you have closed yourself stays closed: the list is rebuilt on every library
// change, and without remembering that, playing a song would open it again.
// Both ways, not only open. A folder left closed last time has to be closed
// here, and the list is built with every folder open before the record of which
// ones were closed has even been read.
- (void)openFolders {
    NSInteger row;
    for (row = 0; row < [_outline numberOfRows]; row++) {
        id item = [_outline itemAtRow:row];
        if (item == nil || ![_outline isExpandable:item]) continue;
        BTPlaylist *folder = BTPlaylistFromSource(item);
        if (folder && [_closedFolders containsObject:folder.playlistID]) {
            [_outline collapseItem:item];
            continue;
        }
        [_outline expandItem:item];
    }
}

- (NSArray *)closedFolderIDs {
    return [_closedFolders allObjects];
}

- (void)setClosedFolderIDs:(NSArray *)ids {
    [_closedFolders removeAllObjects];
    if (ids) [_closedFolders addObjectsFromArray:ids];
}

- (void)sizeColumnToPane {
    CGFloat width = [_scroll contentSize].width;
    if (width < 20.0) return;

    [_outline setFrameSize:NSMakeSize(width, NSHeight([_outline frame]))];
    NSArray *columns = [_outline tableColumns];
    if ([columns count] > 0) [[columns objectAtIndex:0] setWidth:width];
}

#pragma mark - What is chosen

- (id)selectedSource {
    NSInteger row = [_outline selectedRow];
    return (row >= 0) ? [_outline itemAtRow:row] : nil;
}

- (BTPlaylist *)selectedPlaylist {
    return BTPlaylistFromSource([self selectedSource]);
}

- (id)clickedSource {
    NSInteger row = [_outline clickedRow];
    return (row >= 0) ? [_outline itemAtRow:row] : nil;
}

- (BTPlaylist *)clickedPlaylist {
    BTPlaylist *clicked = BTPlaylistFromSource([self clickedSource]);
    return clicked ? clicked : [self selectedPlaylist];
}

// Opens whatever folders it takes to bring a playlist into view, outermost
// first, since the list can only place a row whose folders are all open. A
// folder that was closed by hand is reopened, because a selection nothing can
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
        [_outline expandItem:[ancestors objectAtIndex:i]];
    }
}

- (void)selectSource:(id)source {
    BTPlaylist *playlist = BTPlaylistFromSource(source);
    if (playlist) [self revealPlaylist:playlist];

    NSInteger row = [_outline rowForItem:source];
    if (row < 0) return;
    [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
          byExtendingSelection:NO];
}

- (void)selectPlaylistForRenaming:(BTPlaylist *)playlist {
    [self reload];
    [self selectSource:playlist];
    [self beginRenamingRow:[_outline rowForItem:playlist]];
}

- (void)beginRenamingRow:(NSInteger)row {
    if (row < 0) return;
    if (BTPlaylistFromSource([_outline itemAtRow:row]) == nil) return;

    _renameRequested = YES;
    [_outline editColumn:0 row:row withEvent:nil select:YES];
    _renameRequested = NO;
}

- (void)renameClickedPlaylist:(id)sender {
    NSInteger row = [_outline clickedRow];
    if (row < 0) row = [_outline selectedRow];
    [self beginRenamingRow:row];
}

#pragma mark - Answering the list

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    return (NSInteger)[[self childrenOf:item] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return [[self childrenOf:item] objectAtIndex:(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [[self childrenOf:item] count] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                       byItem:(id)item {
    if (item == BTLibrarySource) return @"Library";
    if (item == BTRecentlyAddedSource) return @"Recently Added";
    if ([item isKindOfClass:[BTIPod class]]) return [(BTIPod *)item name];
    if ([item isKindOfClass:[BTAudioDisc class]]) return [(BTAudioDisc *)item name];
    return [(BTPlaylist *)item name];
}

- (void)outlineView:(NSOutlineView *)outlineView
     setObjectValue:(id)object
     forTableColumn:(NSTableColumn *)tableColumn
             byItem:(id)item {
    BTPlaylist *playlist = BTPlaylistFromSource(item);
    if (playlist == nil) return;
    if (![object isKindOfClass:[NSString class]] || [(NSString *)object length] == 0) return;
    if ([object isEqualToString:playlist.name]) return;

    [_delegate sourceList:self renamePlaylist:playlist to:object];
}

// Which of the seven marks a row wears. The only place that has to know what a
// source is; the drawing itself is told the kind.
- (BTSourceIconKind)iconKindFor:(id)item {
    if ([item isKindOfClass:[BTIPod class]]) return BTSourceIconIPod;
    if ([item isKindOfClass:[BTAudioDisc class]]) return BTSourceIconDisc;
    if (item == BTRecentlyAddedSource) return BTSourceIconRecentlyAdded;
    if (item == BTLibrarySource) return BTSourceIconLibrary;

    BTPlaylist *playlist = BTPlaylistFromSource(item);
    if (playlist.kind == BTPlaylistKindFolder) return BTSourceIconFolder;
    return (playlist.kind == BTPlaylistKindSmart) ? BTSourceIconSmartPlaylist
                                                  : BTSourceIconPlaylist;
}

- (void)outlineView:(NSOutlineView *)outlineView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn
               item:(id)item {
    if ([cell isKindOfClass:[BTSourceCell class]]) {
        BTSourceCell *sourceCell = cell;
        sourceCell.icon = [BTSourceIcon iconOfKind:[self iconKindFor:item]];
        sourceCell.showsEject = ([item isKindOfClass:[BTIPod class]] ||
                                 [item isKindOfClass:[BTAudioDisc class]]);

        BOOL selected = ([outlineView selectedRow] == [outlineView rowForItem:item]);
        [sourceCell setHighlighted:NO];
        // White words on the gray fill are barely words, so the text follows
        // the fill rather than the selection.
        BOOL strong = (selected && BTListHasFocus(outlineView));
        [sourceCell setTextColor:(strong ? [NSColor whiteColor] : [NSColor blackColor])];
    }
}

- (BOOL)outlineView:(NSOutlineView *)outlineView
shouldEditTableColumn:(NSTableColumn *)tableColumn
               item:(id)item {
    return _renameRequested && BTPlaylistFromSource(item) != nil;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)note {
    [_delegate sourceListSelectionDidChange:self];
}

// A click that lands on the row already selected sends no selection change, so
// anything standing in front of the songs would sit there looking as though it
// had been answered.
- (void)rowClicked:(id)sender {
    [_delegate sourceListWasClicked:self];
}

- (void)tableViewDeletePressed:(NSTableView *)tableView {
    [_delegate sourceListDeletePressed:self];
}

- (void)outlineViewItemDidCollapse:(NSNotification *)note {
    BTPlaylist *folder = BTPlaylistFromSource([[note userInfo] objectForKey:@"NSObject"]);
    if (folder == nil) return;
    [_closedFolders addObject:folder.playlistID];
    [_delegate sourceListFoldersDidChange:self];
}

- (void)outlineViewItemDidExpand:(NSNotification *)note {
    BTPlaylist *folder = BTPlaylistFromSource([[note userInfo] objectForKey:@"NSObject"]);
    if (folder == nil) return;
    [_closedFolders removeObject:folder.playlistID];
    [_delegate sourceListFoldersDidChange:self];
}

#pragma mark - Drag and drop

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
    BTPlaylist *target = BTPlaylistFromSource(item);

    if ([[pasteboard types] containsObject:BTTrackPasteboardType]) {
        if (target == nil) return NO;
        NSArray *ids = [NSKeyedUnarchiver unarchiveObjectWithData:[pasteboard dataForType:BTTrackPasteboardType]];
        if ([ids count] == 0) return NO;
        [_delegate sourceList:self addTrackIDs:ids toPlaylist:target];
        return YES;
    }

    if ([[pasteboard types] containsObject:BTPlaylistPasteboardType]) {
        NSString *playlistID = [pasteboard stringForType:BTPlaylistPasteboardType];
        BTPlaylist *moving = [[BTLibrary sharedLibrary] playlistWithID:playlistID];
        if (moving == nil) return NO;
        [_delegate sourceList:self movePlaylist:moving toFolder:target];
        return YES;
    }
    return NO;
}

@end
