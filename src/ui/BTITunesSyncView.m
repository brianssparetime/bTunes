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

@interface BTITunesSyncView () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation BTITunesSyncView {
    BTITunesSync *_sync;
    BOOL _comparing;

    NSTextField *_summary;

    NSButton *_hideIneligible;
    NSButton *_hideAlreadySynced;
    NSButton *_checkAll;
    NSButton *_syncButton;

    NSTextField *_songsHeading;
    NSTextField *_playlistsHeading;
    NSScrollView *_songsScroll;
    NSScrollView *_playlistsScroll;
    NSTableView *_songsTable;
    NSTableView *_playlistsTable;

    NSArray *_songs;          // what the two lists are showing, after hiding
    NSArray *_lists;

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

    _checkAll = [[NSButton alloc] initWithFrame:NSZeroRect];
    [_checkAll setBezelStyle:NSRoundedBezelStyle];
    [_checkAll setFont:[BTStyle uiFont]];
    [_checkAll setTarget:self];
    [_checkAll setAction:@selector(checkAllOrNone:)];
    [self addSubview:_checkAll];

    _songsHeading = BTLabelWithText(@"Music", [BTStyle boldFont]);
    _playlistsHeading = BTLabelWithText(@"Playlists", [BTStyle boldFont]);
    [self addSubview:_songsHeading];
    [self addSubview:_playlistsHeading];

    _songsTable = [self tableWithColumns:@[@[@"check", @"", @20],
                                           @[@"title", @"Song Name", @180],
                                           @[@"artist", @"Artist", @130],
                                           @[@"album", @"Album", @130]]];
    _playlistsTable = [self tableWithColumns:@[@[@"check", @"", @20],
                                               @[@"name", @"Playlist", @220],
                                               @[@"what", @"", @90]]];
    _songsScroll = [_songsTable enclosingScrollView];
    _playlistsScroll = [_playlistsTable enclosingScrollView];

    _syncButton = [[NSButton alloc] initWithFrame:NSZeroRect];
    [_syncButton setTitle:@"Sync"];
    [_syncButton setBezelStyle:NSRoundedBezelStyle];
    [_syncButton setFont:[BTStyle uiFont]];
    [_syncButton setKeyEquivalent:@"\r"];
    [_syncButton setTarget:self];
    [_syncButton setAction:@selector(runSync:)];
    [self addSubview:_syncButton];

    [self showComparingState];
    // Laid out here as well as on resize. The pane is made at the size it is
    // going to be, so nothing ever resizes it, and waiting for that leaves
    // every one of these sitting at zero and the pane looking empty.
    [self layoutPane];
    return self;
}

- (NSButton *)checkboxTitled:(NSString *)title action:(SEL)action on:(BOOL)on {
    NSButton *box = [[NSButton alloc] initWithFrame:NSZeroRect];
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
- (NSTableView *)tableWithColumns:(NSArray *)specs {
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
            NSButtonCell *cell = [[NSButtonCell alloc] init];
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
    [self addSubview:scroll];
    return table;
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
    [_checkAll setFrame:NSMakeRect(NSMaxX(bounds) - margin - 110, y - 2, 110, 22)];

    y -= 22;
    CGFloat halves = (width - 12) / 2.0;
    [_songsHeading setFrame:NSMakeRect(margin, y, halves, 16)];
    [_playlistsHeading setFrame:NSMakeRect(margin + halves + 12, y, halves, 16)];

    CGFloat footer = 44.0;
    CGFloat listTop = y - 4;
    CGFloat listHeight = listTop - footer;
    if (listHeight < 40) listHeight = 40;

    [_songsScroll setFrame:NSMakeRect(margin, footer, halves, listHeight)];
    [_playlistsScroll setFrame:NSMakeRect(margin + halves + 12, footer, halves, listHeight)];
    [_syncButton setFrame:NSMakeRect(NSMaxX(bounds) - margin - 92, 12, 92, 22)];

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
    [_songsHeading setStringValue:[NSString stringWithFormat:@"Music (%lu)", (unsigned long)[songs count]]];
    [_playlistsHeading setStringValue:[NSString stringWithFormat:@"Playlists (%lu)", (unsigned long)[lists count]]];

    [_songsTable reloadData];
    [_playlistsTable reloadData];
    [self updateButtons];
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

// A playlist follows its songs: ticked when all of them are, empty when none
// are, and dashed in between. Turning one off by hand turns it off outright.
- (NSInteger)stateOfPlaylist:(BTITunesSyncPlaylist *)playlist {
    if (![playlist eligible]) return NSOffState;
    if ([_uncheckedLists containsObject:playlist.persistentID]) return NSOffState;

    NSArray *choosable = [self choosableSongsOf:playlist];
    if ([choosable count] == 0) return NSOnState;

    NSUInteger i, chosen = 0;
    for (i = 0; i < [choosable count]; i++) {
        if (![_uncheckedSongs containsObject:[choosable objectAtIndex:i]]) chosen++;
    }
    if (chosen == 0) return NSOffState;
    return (chosen == [choosable count]) ? NSOnState : NSMixedState;
}

- (void)setPlaylist:(BTITunesSyncPlaylist *)playlist chosen:(BOOL)chosen {
    if (chosen) {
        [_uncheckedLists removeObject:playlist.persistentID];
    } else {
        [_uncheckedLists addObject:playlist.persistentID];
    }

    // Ticking a playlist ticks its music, which is the whole point of the two
    // panes standing side by side.
    NSArray *choosable = [self choosableSongsOf:playlist];
    if (chosen) {
        [_uncheckedSongs minusSet:[NSSet setWithArray:choosable]];
    } else {
        [_uncheckedSongs addObjectsFromArray:choosable];
    }
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
    [self updateButtons];
}

#pragma mark - The lists

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)[(tableView == _songsTable ? _songs : _lists) count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                          row:(NSInteger)row {
    NSString *identifier = [tableColumn identifier];

    if (tableView == _songsTable) {
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

    if (row < 0 || row >= (NSInteger)[_lists count]) return nil;
    BTITunesSyncPlaylist *playlist = [_lists objectAtIndex:(NSUInteger)row];
    if ([identifier isEqualToString:@"check"]) return @([self stateOfPlaylist:playlist]);
    if ([identifier isEqualToString:@"name"]) {
        if ([playlist.folderNames count] == 0) return playlist.name;
        return [NSString stringWithFormat:@"%@ / %@",
                [playlist.folderNames componentsJoinedByString:@" / "], playlist.name];
    }
    return [self wordForPlaylist:playlist];
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
    BOOL blocked = NO, here = NO;
    NSInteger reason = 0;

    if (tableView == _songsTable) {
        if (row < 0 || row >= (NSInteger)[_songs count]) return;
        BTITunesSyncTrack *track = [_songs objectAtIndex:(NSUInteger)row];
        blocked = (track.blocked != BTITunesBlockNone);
        here = track.alreadyHere;
        reason = track.blocked;
    } else {
        if (row < 0 || row >= (NSInteger)[_lists count]) return;
        BTITunesSyncPlaylist *playlist = [_lists objectAtIndex:(NSUInteger)row];
        blocked = (playlist.blocked != BTITunesBlockNone);
        here = playlist.alreadyHere;
        reason = playlist.blocked;
    }

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

    if (tableView == _songsTable) {
        if (row < 0 || row >= (NSInteger)[_songs count]) return;
        BTITunesSyncTrack *track = [_songs objectAtIndex:(NSUInteger)row];
        if (![track eligible]) return;

        if ([self songIsChosen:track]) {
            [_uncheckedSongs addObject:track.persistentID];
        } else {
            [_uncheckedSongs removeObject:track.persistentID];
        }
        // A playlist holding it now reads as partly chosen, so both lists are
        // redrawn rather than only the one that was clicked.
        [_playlistsTable reloadData];
    } else {
        if (row < 0 || row >= (NSInteger)[_lists count]) return;
        BTITunesSyncPlaylist *playlist = [_lists objectAtIndex:(NSUInteger)row];
        if (![playlist eligible]) return;

        // A dash means partly chosen, and the next click takes all of it.
        [self setPlaylist:playlist chosen:([self stateOfPlaylist:playlist] != NSOnState)];
        [_songsTable reloadData];
    }

    [tableView reloadData];
    [self updateButtons];
}

#pragma mark - Doing it

- (void)runSync:(id)sender {
    if (_sync == nil || _sync.error) return;

    NSMutableSet *songs = [NSMutableSet set];
    NSMutableSet *lists = [NSMutableSet set];
    NSMutableArray *leftBehind = [NSMutableArray array];

    NSUInteger i;
    for (i = 0; i < [_sync.incomingTracks count]; i++) {
        BTITunesSyncTrack *track = [_sync.incomingTracks objectAtIndex:i];
        if (![track eligible]) continue;
        if ([self songIsChosen:track]) {
            [songs addObject:track.persistentID];
        } else if (track.persistentID) {
            [leftBehind addObject:track.persistentID];
        }
    }
    for (i = 0; i < [_sync.playlists count]; i++) {
        BTITunesSyncPlaylist *playlist = [_sync.playlists objectAtIndex:i];
        if (![playlist eligible]) continue;
        if ([self stateOfPlaylist:playlist] != NSOffState) [lists addObject:playlist.persistentID];
    }

    BTLibrary *library = [BTLibrary sharedLibrary];
    NSDictionary *result = [_sync importInto:library chosenSongs:songs chosenPlaylists:lists];

    // A song turned down stays turned down, so the next sync does not ask again.
    [library setExcluded:YES forPersistentIDs:leftBehind];

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
