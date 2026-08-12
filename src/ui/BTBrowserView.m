#import "BTBrowserView.h"
#import "BTStyle.h"
#import "BTControls.h"
#import "BTTrack.h"

@interface BTBrowserView () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation BTBrowserView {
    NSTableView *_genreTable;
    NSTableView *_artistTable;
    NSTableView *_albumTable;
    NSArray *_sourceTracks;
    NSArray *_genres;      // strings, without the leading All row
    NSArray *_artists;
    NSArray *_albums;
    NSString *_selectedGenre;
    NSString *_selectedArtist;
    NSString *_selectedAlbum;
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _sourceTracks = @[];
        _genres = @[];
        _artists = @[];
        _albums = @[];
        _genreTable = [self addColumnWithTitle:@"Genre"];
        _artistTable = [self addColumnWithTitle:@"Artist"];
        _albumTable = [self addColumnWithTitle:@"Album"];
        [_genreTable setNextKeyView:_artistTable];
        [_artistTable setNextKeyView:_albumTable];
        [self layoutColumns];
    }
    return self;
}

- (NSTableView *)addColumnWithTitle:(NSString *)title {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, NSHeight([self bounds]))];
    [scroll setHasVerticalScroller:YES];
    [scroll setAutohidesScrollers:YES];
    // No bezel. A bezel draws a dark line on all four sides, and the top one
    // lands directly under the toolbar where it reads as a black seam across
    // the window. The columns are separated by drawn lines instead.
    [scroll setBorderType:NSNoBorder];
    [scroll setFocusRingType:NSFocusRingTypeNone];

    NSTableView *table = [[BTListTableView alloc] initWithFrame:[[scroll contentView] bounds]];
    [table setFocusRingType:NSFocusRingTypeNone];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:title];
    [[column headerCell] setStringValue:title];
    [[column headerCell] setFont:[BTStyle uiFont]];
    [[column dataCell] setFont:[BTStyle uiFont]];
    [[column dataCell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [column setWidth:120];
    [column setEditable:NO];
    [table addTableColumn:column];
    [table setAllowsColumnSelection:NO];
    [table setRowHeight:16.0];
    [table setUsesAlternatingRowBackgroundColors:YES];
    [table setAllowsMultipleSelection:NO];
    [table setDataSource:self];
    [table setDelegate:self];
    [table setTarget:self];
    [scroll setDocumentView:table];
    [self addSubview:scroll];
    return table;
}

- (void)layoutColumns {
    NSArray *tables = @[_genreTable, _artistTable, _albumTable];
    CGFloat width = NSWidth([self bounds]) / 3.0;
    NSUInteger i;
    for (i = 0; i < 3; i++) {
        NSTableView *table = [tables objectAtIndex:i];
        NSScrollView *scroll = [table enclosingScrollView];
        NSRect frame = NSMakeRect(width * i, 0, (i == 2 ? NSWidth([self bounds]) - width * 2 : width), NSHeight([self bounds]));
        [scroll setFrame:frame];

        // The column fills the pane exactly. Any gap between the column and the
        // edge of the table shows up as a stray block of selection color on the
        // highlighted row.
        CGFloat contentWidth = [scroll contentSize].width;
        [table setFrameSize:NSMakeSize(contentWidth, NSHeight([table frame]))];
        [[[table tableColumns] objectAtIndex:0] setWidth:contentWidth];
    }
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutColumns];
}

- (void)drawRect:(NSRect)dirtyRect {
    // Hairlines between the columns and one along the bottom, in the gray the
    // rest of the window uses for divisions.
    NSRect bounds = [self bounds];
    [[NSColor colorWithCalibratedWhite:0.68 alpha:1.0] set];

    CGFloat width = NSWidth(bounds) / 3.0;
    NSUInteger i;
    for (i = 1; i < 3; i++) {
        NSRectFill(NSMakeRect(floor(width * i), NSMinY(bounds), 1.0, NSHeight(bounds)));
    }
    NSRectFill(NSMakeRect(NSMinX(bounds), NSMinY(bounds), NSWidth(bounds), 1.0));
}

- (NSView *)firstColumnView { return _genreTable; }
- (NSView *)lastColumnView { return _albumTable; }

#pragma mark - Data

// The three columns differ only in which of a track's fields they read, so the
// gathering and the narrowing are written once and told which field to use.
typedef NS_ENUM(NSInteger, BTBrowserField) {
    BTBrowserFieldGenre = 0,
    BTBrowserFieldArtist,
    BTBrowserFieldAlbum
};

static NSString *BTFieldOfTrack(BTTrack *track, BTBrowserField field) {
    switch (field) {
        case BTBrowserFieldGenre:  return [track displayGenre];
        case BTBrowserFieldArtist: return [track displayArtist];
        case BTBrowserFieldAlbum:  return [track displayAlbum];
    }
    return @"";
}

static NSArray *BTSortedUniqueValues(NSArray *tracks, BTBrowserField field) {
    NSMutableSet *set = [NSMutableSet set];
    NSUInteger i;
    for (i = 0; i < [tracks count]; i++) {
        [set addObject:BTFieldOfTrack([tracks objectAtIndex:i], field)];
    }
    return [[set allObjects] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
}

// A nil value is the All row, which narrows nothing.
static NSArray *BTTracksMatching(NSArray *tracks, BTBrowserField field, NSString *value) {
    if (value == nil) return tracks;
    NSMutableArray *out = [NSMutableArray array];
    NSUInteger i;
    for (i = 0; i < [tracks count]; i++) {
        BTTrack *t = [tracks objectAtIndex:i];
        if ([BTFieldOfTrack(t, field) isEqualToString:value]) [out addObject:t];
    }
    return out;
}

- (void)setSourceTracks:(NSArray *)tracks {
    _sourceTracks = tracks ? tracks : @[];
    [self rebuild];
}

- (void)resetSelection {
    _selectedGenre = nil;
    _selectedArtist = nil;
    _selectedAlbum = nil;
    [self rebuild];
}

// Each column narrows the one to its right, so the three run in a chain.
- (NSArray *)tracksMatchingGenre {
    return BTTracksMatching(_sourceTracks, BTBrowserFieldGenre, _selectedGenre);
}

- (NSArray *)tracksMatchingGenreAndArtist {
    return BTTracksMatching([self tracksMatchingGenre], BTBrowserFieldArtist, _selectedArtist);
}

- (NSArray *)filteredTracks {
    return BTTracksMatching([self tracksMatchingGenreAndArtist], BTBrowserFieldAlbum, _selectedAlbum);
}

// A selection that the new set of tracks no longer offers is dropped, which
// puts that column back on its All row.
- (void)rebuild {
    _genres = BTSortedUniqueValues(_sourceTracks, BTBrowserFieldGenre);
    if (_selectedGenre && ![_genres containsObject:_selectedGenre]) _selectedGenre = nil;

    _artists = BTSortedUniqueValues([self tracksMatchingGenre], BTBrowserFieldArtist);
    if (_selectedArtist && ![_artists containsObject:_selectedArtist]) _selectedArtist = nil;

    _albums = BTSortedUniqueValues([self tracksMatchingGenreAndArtist], BTBrowserFieldAlbum);
    if (_selectedAlbum && ![_albums containsObject:_selectedAlbum]) _selectedAlbum = nil;

    [_genreTable reloadData];
    [_artistTable reloadData];
    [_albumTable reloadData];
    [self restoreSelectionRows];
}

- (void)selectRow:(NSInteger)row inTable:(NSTableView *)table {
    [table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
}

- (void)restoreSelectionRows {
    NSInteger row = _selectedGenre ? (NSInteger)[_genres indexOfObject:_selectedGenre] + 1 : 0;
    [self selectRow:(row > 0 ? row : 0) inTable:_genreTable];
    row = _selectedArtist ? (NSInteger)[_artists indexOfObject:_selectedArtist] + 1 : 0;
    [self selectRow:(row > 0 ? row : 0) inTable:_artistTable];
    row = _selectedAlbum ? (NSInteger)[_albums indexOfObject:_selectedAlbum] + 1 : 0;
    [self selectRow:(row > 0 ? row : 0) inTable:_albumTable];
}

#pragma mark - Table data source

- (NSArray *)valuesForTable:(NSTableView *)table {
    if (table == _genreTable) return _genres;
    if (table == _artistTable) return _artists;
    return _albums;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)[[self valuesForTable:tableView] count] + 1;
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                          row:(NSInteger)row {
    NSArray *values = [self valuesForTable:tableView];
    if (row == 0) {
        NSString *noun = (tableView == _genreTable) ? @"Genre" : ((tableView == _artistTable) ? @"Artist" : @"Album");
        NSUInteger count = [values count];
        return [NSString stringWithFormat:@"All (%lu %@%@)", (unsigned long)count, noun, (count == 1 ? @"" : @"s")];
    }
    return [values objectAtIndex:(NSUInteger)(row - 1)];
}

- (void)tableView:(NSTableView *)tableView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn
                row:(NSInteger)row {
    if (![cell isKindOfClass:[NSTextFieldCell class]]) return;

    // The table paints the selected row itself, so the cell must not paint its
    // own highlight over the top of it.
    BOOL selected = [[tableView selectedRowIndexes] containsIndex:(NSUInteger)row];
    [(NSTextFieldCell *)cell setHighlighted:NO];
    [(NSTextFieldCell *)cell setTextColor:(selected ? [NSColor whiteColor] : [NSColor blackColor])];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *table = [notification object];
    NSInteger row = [table selectedRow];
    NSArray *values = [self valuesForTable:table];
    NSString *value = (row > 0 && row - 1 < (NSInteger)[values count]) ? [values objectAtIndex:(NSUInteger)(row - 1)] : nil;

    if (table == _genreTable) {
        _selectedGenre = value;
        _selectedArtist = nil;
        _selectedAlbum = nil;
    } else if (table == _artistTable) {
        _selectedArtist = value;
        _selectedAlbum = nil;
    } else {
        _selectedAlbum = value;
    }

    [self rebuild];
    if (self.browserDelegate) [self.browserDelegate browserViewSelectionDidChange:self];
}

@end
