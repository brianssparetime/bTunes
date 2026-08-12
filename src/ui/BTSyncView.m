#import "BTSyncView.h"
#import "BTStyle.h"
#import "BTControls.h"
#import "BTIPod.h"
#import "BTIPodSync.h"
#import "BTLibrary.h"
#import "BTPlaylist.h"
#import "BTTrack.h"

@interface BTSyncView () <NSOutlineViewDataSource, NSOutlineViewDelegate>
@end

@implementation BTSyncView {
    NSOutlineView *_outline;
    NSScrollView *_scroll;
    NSTextField *_headline;
    NSTextField *_detail;
    NSButton *_syncButton;
    BTRoundButton *_ejectButton;
    NSMutableSet *_checked;          // playlist ids of the checked playlists
    BTIPodSync *_sync;
    BOOL _loadedFromDevice;
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) return nil;

    _checked = [NSMutableSet set];

    _headline = [self labelWithFont:[BTStyle boldFont]];
    _detail = [self labelWithFont:[BTStyle uiFont]];
    [self addSubview:_headline];
    [self addSubview:_detail];

    _scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    [_scroll setHasVerticalScroller:YES];
    [_scroll setAutohidesScrollers:YES];
    [_scroll setBorderType:NSBezelBorder];
    [_scroll setFocusRingType:NSFocusRingTypeNone];

    _outline = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
    [_outline setFocusRingType:NSFocusRingTypeNone];
    [_outline setRowHeight:18.0];
    [_outline setIndentationPerLevel:14.0];
    [_outline setHeaderView:nil];
    [_outline setAllowsColumnSelection:NO];
    [_outline setDataSource:self];
    [_outline setDelegate:self];

    NSTableColumn *nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    [[nameColumn dataCell] setFont:[BTStyle uiFont]];
    [nameColumn setEditable:NO];
    [nameColumn setWidth:320];
    [_outline addTableColumn:nameColumn];
    [_outline setOutlineTableColumn:nameColumn];

    NSTableColumn *checkColumn = [[NSTableColumn alloc] initWithIdentifier:@"check"];
    NSButtonCell *checkCell = [[NSButtonCell alloc] init];
    [checkCell setButtonType:NSSwitchButton];
    [checkCell setAllowsMixedState:YES];
    [checkCell setTitle:@""];
    [checkCell setControlSize:NSSmallControlSize];
    [checkColumn setDataCell:checkCell];
    [checkColumn setWidth:22];
    [checkColumn setEditable:YES];
    [_outline addTableColumn:checkColumn];

    [_scroll setDocumentView:_outline];
    [self addSubview:_scroll];

    _syncButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [_syncButton setTitle:@"Sync"];
    [_syncButton setBezelStyle:NSRoundedBezelStyle];
    [_syncButton setFont:[BTStyle uiFont]];
    [_syncButton setTarget:self];
    [_syncButton setAction:@selector(startSync:)];
    [self addSubview:_syncButton];

    _ejectButton = [BTRoundButton buttonWithFrame:NSZeroRect
                                            glyph:BTGlyphEject
                                           target:self
                                           action:@selector(eject:)];
    [_ejectButton setToolTip:@"Eject iPod"];
    [self addSubview:_ejectButton];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(syncFinished:) name:BTIPodSyncDidFinishNotification object:nil];
    [nc addObserver:self selector:@selector(libraryChanged:) name:BTLibraryDidChangeNotification object:nil];

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSTextField *)labelWithFont:(NSFont *)font {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setFont:font];
    return label;
}

- (BOOL)isOpaque { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    [[BTStyle windowBackground] set];
    NSRectFill([self bounds]);
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self layoutPane];
}

- (void)layoutPane {
    NSRect bounds = [self bounds];
    CGFloat margin = 14.0;
    CGFloat footer = 44.0;

    [_headline setFrame:NSMakeRect(margin, NSMaxY(bounds) - 28, NSWidth(bounds) - margin * 2, 17)];
    [_detail setFrame:NSMakeRect(margin, NSMaxY(bounds) - 46, NSWidth(bounds) - margin * 2, 15)];
    [_scroll setFrame:NSMakeRect(margin, footer + 8,
                                 NSWidth(bounds) - margin * 2,
                                 NSHeight(bounds) - 56 - footer)];

    [_syncButton setFrame:NSMakeRect(NSWidth(bounds) - margin - 92, 10, 92, 28)];
    [_ejectButton setFrame:NSMakeRect(NSWidth(bounds) - margin - 92 - 38, 11, 26, 26)];

    // The checkbox column stays pinned to the right edge of the list.
    CGFloat width = [_scroll contentSize].width;
    [_outline setFrameSize:NSMakeSize(width, NSHeight([_outline frame]))];
    [[[_outline tableColumns] objectAtIndex:0] setWidth:width - 26];
    [[[_outline tableColumns] objectAtIndex:1] setWidth:22];
}

#pragma mark - Contents

- (void)setIPod:(BTIPod *)iPod {
    _iPod = iPod;
    _loadedFromDevice = NO;
    [self reload];
}

- (void)libraryChanged:(NSNotification *)note {
    [_outline reloadData];
}

- (void)reload {
    if (self.iPod == nil) return;

    _sync = [BTIPodSync syncWithIPod:self.iPod];

    // What is already on the device starts out checked, so what you are looking
    // at is the difference rather than the whole library.
    if (!_loadedFromDevice) {
        NSSet *onDevice = [_sync playlistNamesOnDevice];
        [_checked removeAllObjects];
        [self markPlaylistsIn:[BTLibrary sharedLibrary].playlists whoseNamesAreIn:onDevice];
        _loadedFromDevice = YES;
    }

    double used = (double)(self.iPod.capacity - self.iPod.freeSpace) / 1073741824.0;
    double total = (double)self.iPod.capacity / 1073741824.0;
    [_headline setStringValue:(self.iPod.name ? self.iPod.name : @"iPod")];
    [_detail setStringValue:[NSString stringWithFormat:@"%.1f GB of %.1f GB used. Choose the playlists to keep on it.",
                             used, total]];

    [_outline reloadData];
    [_outline expandItem:nil expandChildren:YES];
    [self layoutPane];
}

- (void)markPlaylistsIn:(NSArray *)playlists whoseNamesAreIn:(NSSet *)names {
    NSUInteger i;
    for (i = 0; i < [playlists count]; i++) {
        BTPlaylist *playlist = [playlists objectAtIndex:i];
        if (playlist.kind == BTPlaylistKindFolder) {
            [self markPlaylistsIn:playlist.children whoseNamesAreIn:names];
        } else if ([names containsObject:playlist.name]) {
            [_checked addObject:playlist.playlistID];
        }
    }
}

- (NSArray *)childrenOf:(id)item {
    if (item == nil) return [BTLibrary sharedLibrary].playlists;
    BTPlaylist *playlist = (BTPlaylist *)item;
    return (playlist.kind == BTPlaylistKindFolder) ? playlist.children : @[];
}

#pragma mark - Check state

// A folder shows a check when everything inside is checked, a dash when only
// some of it is, and nothing when none of it is.
- (NSInteger)stateOfItem:(BTPlaylist *)playlist {
    if (playlist.kind != BTPlaylistKindFolder) {
        return [_checked containsObject:playlist.playlistID] ? NSOnState : NSOffState;
    }

    NSArray *children = playlist.children;
    if ([children count] == 0) return NSOffState;

    BOOL anyOn = NO, anyOff = NO;
    NSUInteger i;
    for (i = 0; i < [children count]; i++) {
        NSInteger state = [self stateOfItem:[children objectAtIndex:i]];
        if (state == NSMixedState) return NSMixedState;
        if (state == NSOnState) anyOn = YES; else anyOff = YES;
        if (anyOn && anyOff) return NSMixedState;
    }
    return anyOn ? NSOnState : NSOffState;
}

- (void)setItem:(BTPlaylist *)playlist checked:(BOOL)checked {
    if (playlist.kind == BTPlaylistKindFolder) {
        NSUInteger i;
        for (i = 0; i < [playlist.children count]; i++) {
            [self setItem:[playlist.children objectAtIndex:i] checked:checked];
        }
        return;
    }
    if (checked) {
        [_checked addObject:playlist.playlistID];
    } else {
        [_checked removeObject:playlist.playlistID];
    }
}

- (NSArray *)selectedLeafPlaylists {
    NSMutableArray *out = [NSMutableArray array];
    [self collectLeavesIn:[BTLibrary sharedLibrary].playlists into:out];
    return out;
}

- (void)collectLeavesIn:(NSArray *)playlists into:(NSMutableArray *)out {
    NSUInteger i;
    for (i = 0; i < [playlists count]; i++) {
        BTPlaylist *playlist = [playlists objectAtIndex:i];
        if (playlist.kind == BTPlaylistKindFolder) {
            [self collectLeavesIn:playlist.children into:out];
        } else if ([_checked containsObject:playlist.playlistID]) {
            [out addObject:playlist];
        }
    }
}

#pragma mark - Outline

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
    BTPlaylist *playlist = (BTPlaylist *)item;
    if ([[tableColumn identifier] isEqualToString:@"check"]) {
        return @([self stateOfItem:playlist]);
    }

    if (playlist.kind == BTPlaylistKindFolder) return playlist.name;

    NSUInteger count = [[playlist resolveTracks:[BTLibrary sharedLibrary].tracks] count];
    return [NSString stringWithFormat:@"%@  (%lu)", playlist.name, (unsigned long)count];
}

- (void)outlineView:(NSOutlineView *)outlineView
     setObjectValue:(id)object
     forTableColumn:(NSTableColumn *)tableColumn
             byItem:(id)item {
    if (![[tableColumn identifier] isEqualToString:@"check"]) return;

    BTPlaylist *playlist = (BTPlaylist *)item;
    // A folder that is partly checked becomes fully checked on the next click.
    NSInteger current = [self stateOfItem:playlist];
    [self setItem:playlist checked:(current != NSOnState)];
    [outlineView reloadData];
    [self updateSyncButton];
}

- (void)updateSyncButton {
    NSUInteger count = [[self selectedLeafPlaylists] count];
    [_syncButton setEnabled:(count > 0 && !_sync.running)];
    [_syncButton setTitle:(count > 0 ? [NSString stringWithFormat:@"Sync %lu", (unsigned long)count] : @"Sync")];
}

#pragma mark - Actions

- (void)startSync:(id)sender {
    NSArray *playlists = [self selectedLeafPlaylists];
    if ([playlists count] == 0 || self.iPod == nil) return;

    [_syncButton setEnabled:NO];
    [_sync syncPlaylists:playlists tracksBy:nil completion:nil];
}

- (void)syncFinished:(NSNotification *)note {
    [self updateSyncButton];

    NSError *error = [[note userInfo] objectForKey:@"error"];
    if (error == nil) return;

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"The sync stopped."];
    [alert setInformativeText:[error localizedDescription]];
    [alert runModal];
}

- (void)eject:(id)sender {
    [NSApp sendAction:@selector(ejectIPod:) to:nil from:self];
}

@end
