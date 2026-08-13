#import "BTITunesSync.h"
#import "BTLibrary.h"
#import "BTTrack.h"
#import "BTPlaylist.h"

@implementation BTITunesSyncTrack
- (BOOL)eligible { return self.blocked == BTITunesBlockNone && !self.excludedBefore; }
@end

@implementation BTITunesSyncPlaylist
- (BOOL)eligible { return self.blocked == BTITunesBlockNone; }
@end


@interface BTITunesSync ()
@property (nonatomic, copy) NSString *error;
@end

// Held mutable and handed out as plain arrays, so nothing outside can add to
// what the comparison found.
@implementation BTITunesSync {
    NSMutableArray *_incomingTracks;
    NSMutableArray *_playlists;
}

- (id)init {
    self = [super init];
    if (self) {
        _incomingTracks = [NSMutableArray array];
        _playlists = [NSMutableArray array];
    }
    return self;
}

- (NSArray *)incomingTracks { return _incomingTracks; }
- (NSArray *)playlists { return _playlists; }

#pragma mark - Reading the file

static NSString *BTStringFrom(NSDictionary *d, NSString *key) {
    id value = [d objectForKey:key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSString *BTPathFromLocation(NSString *location) {
    if ([location length] == 0) return nil;
    NSURL *url = [NSURL URLWithString:location];
    if (url == nil || ![url isFileURL]) return nil;
    return [[url path] stringByStandardizingPath];
}

// A locked purchase. Recognised three ways because iTunes has spelled it
// differently over the years and one library spans all of them.
static BOOL BTEntryIsProtected(NSDictionary *entry, NSString *path) {
    if ([[entry objectForKey:@"Protected"] boolValue]) return YES;
    if ([[[path pathExtension] lowercaseString] isEqualToString:@"m4p"]) return YES;
    NSString *kind = BTStringFrom(entry, @"Kind");
    return kind && [kind rangeOfString:@"Protected"
                               options:NSCaseInsensitiveSearch].location != NSNotFound;
}

#pragma mark - Comparing

+ (instancetype)syncWithLibraryAtPath:(NSString *)path against:(BTLibrary *)library {
    BTITunesSync *sync = [[BTITunesSync alloc] init];

    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:path];
    if (root == nil) {
        sync.error = [NSString stringWithFormat:@"Cannot read an iTunes library at %@", path];
        return sync;
    }
    NSDictionary *entries = [root objectForKey:@"Tracks"];
    if (![entries isKindOfClass:[NSDictionary class]]) {
        sync.error = @"That file has no Tracks section.";
        return sync;
    }

    [sync compareTracks:entries against:library];
    [sync comparePlaylists:[root objectForKey:@"Playlists"] entries:entries against:library];
    return sync;
}

// What BTunes already holds, keyed both ways. A dictionary rather than a scan:
// eleven thousand songs against a library of the same size is minutes of work
// as a nested loop and no time at all as a lookup.
- (void)compareTracks:(NSDictionary *)entries against:(BTLibrary *)library {
    NSMutableDictionary *haveByITunesID = [NSMutableDictionary dictionary];
    NSMutableSet *havePaths = [NSMutableSet set];

    NSUInteger i;
    for (i = 0; i < [library.tracks count]; i++) {
        BTTrack *track = [library.tracks objectAtIndex:i];
        if ([track.persistentID length] > 0) {
            [haveByITunesID setObject:track forKey:track.persistentID];
        }
        NSString *resolved = [track resolvedPath];
        if ([resolved length] > 0) [havePaths addObject:resolved];
    }

    NSSet *excluded = [library excludedFromImport];

    // Sorted numerically so the listing comes out in the order iTunes numbered
    // them, which is roughly the order they were added.
    NSArray *keys = [[entries allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [a compare:b options:NSNumericSearch];
    }];

    for (i = 0; i < [keys count]; i++) {
        NSDictionary *entry = [entries objectForKey:[keys objectAtIndex:i]];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;

        NSString *path = BTPathFromLocation(BTStringFrom(entry, @"Location"));
        if (path == nil) continue;          // not a local file, so nothing to reference

        NSString *persistentID = BTStringFrom(entry, @"Persistent ID");
        if ([persistentID length] > 0 && [haveByITunesID objectForKey:persistentID]) continue;
        if ([havePaths containsObject:path]) continue;

        BTITunesSyncTrack *incoming = [[BTITunesSyncTrack alloc] init];
        incoming.persistentID = persistentID;
        incoming.path = path;
        incoming.title = BTStringFrom(entry, @"Name");
        incoming.artist = BTStringFrom(entry, @"Artist");
        incoming.album = BTStringFrom(entry, @"Album");
        incoming.blocked = BTEntryIsProtected(entry, path) ? BTITunesBlockProtected
                                                           : BTITunesBlockNone;
        incoming.excludedBefore = ([persistentID length] > 0 &&
                                   [excluded containsObject:persistentID]);
        [_incomingTracks addObject:incoming];
    }
}

// Playlists, in two passes: name the folders first, then place each playlist
// under the folders it belongs to.
- (void)comparePlaylists:(NSArray *)playlistEntries
                 entries:(NSDictionary *)entries
                 against:(BTLibrary *)library {
    if (![playlistEntries isKindOfClass:[NSArray class]]) return;

    // iTunes track id to its persistent id, and to whether it is locked.
    NSMutableDictionary *persistentForTrackID = [NSMutableDictionary dictionary];
    NSMutableSet *lockedTrackIDs = [NSMutableSet set];
    NSArray *trackKeys = [entries allKeys];
    NSUInteger i, j;
    for (i = 0; i < [trackKeys count]; i++) {
        NSString *key = [trackKeys objectAtIndex:i];
        NSDictionary *entry = [entries objectForKey:key];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *path = BTPathFromLocation(BTStringFrom(entry, @"Location"));
        if (path == nil) continue;
        NSString *persistentID = BTStringFrom(entry, @"Persistent ID");
        if ([persistentID length] > 0) [persistentForTrackID setObject:persistentID forKey:key];
        if (BTEntryIsProtected(entry, path)) [lockedTrackIDs addObject:key];
    }

    // Folder names by their own persistent id, so a playlist can name its path.
    NSMutableDictionary *folderNames = [NSMutableDictionary dictionary];
    NSMutableDictionary *folderParents = [NSMutableDictionary dictionary];
    for (i = 0; i < [playlistEntries count]; i++) {
        NSDictionary *entry = [playlistEntries objectAtIndex:i];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        if (![[entry objectForKey:@"Folder"] boolValue]) continue;
        NSString *own = BTStringFrom(entry, @"Playlist Persistent ID");
        if ([own length] == 0) continue;
        [folderNames setObject:(BTStringFrom(entry, @"Name") ?: @"") forKey:own];
        NSString *parent = BTStringFrom(entry, @"Parent Persistent ID");
        if ([parent length] > 0) [folderParents setObject:parent forKey:own];
    }

    // What BTunes already holds, by source id and by name.
    NSMutableDictionary *haveByPersistent = [NSMutableDictionary dictionary];
    NSMutableDictionary *haveByName = [NSMutableDictionary dictionary];
    [self collectPlaylists:library.playlists intoBySource:haveByPersistent byName:haveByName];

    for (i = 0; i < [playlistEntries count]; i++) {
        NSDictionary *entry = [playlistEntries objectAtIndex:i];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        if ([[entry objectForKey:@"Master"] boolValue]) continue;
        if ([entry objectForKey:@"Distinguished Kind"] != nil) continue;
        if ([[entry objectForKey:@"Folder"] boolValue]) continue;

        NSString *name = BTStringFrom(entry, @"Name");
        if ([name length] == 0) continue;

        NSString *persistentID = BTStringFrom(entry, @"Playlist Persistent ID");
        BOOL isSmart = ([entry objectForKey:@"Smart Info"] != nil ||
                        [entry objectForKey:@"Smart Criteria"] != nil);

        // Membership in iTunes order, and whether any of it is locked.
        NSArray *items = [entry objectForKey:@"Playlist Items"];
        NSMutableArray *members = [NSMutableArray array];
        BOOL holdsLocked = NO;
        for (j = 0; [items isKindOfClass:[NSArray class]] && j < [items count]; j++) {
            id trackID = [[items objectAtIndex:j] objectForKey:@"Track ID"];
            if (trackID == nil) continue;
            NSString *key = [trackID description];
            if ([lockedTrackIDs containsObject:key]) holdsLocked = YES;
            NSString *persistent = [persistentForTrackID objectForKey:key];
            if ([persistent length] > 0) [members addObject:persistent];
        }
        if ([members count] == 0 && !holdsLocked) continue;   // nothing to bring across

        BTPlaylist *existing = nil;
        if ([persistentID length] > 0) existing = [haveByPersistent objectForKey:persistentID];
        if (existing == nil) existing = [haveByName objectForKey:[name lowercaseString]];

        // Only what this playlist would add. A song already in it is not a
        // change, and neither is one already imported and placed here by hand.
        NSMutableArray *incoming = [NSMutableArray array];
        NSSet *alreadyIn = existing ? [self persistentIDsOfPlaylist:existing inLibrary:library] : nil;
        for (j = 0; j < [members count]; j++) {
            NSString *persistent = [members objectAtIndex:j];
            if (alreadyIn && [alreadyIn containsObject:persistent]) continue;
            [incoming addObject:persistent];
        }
        if (existing && [incoming count] == 0) continue;      // unchanged since last time

        BTITunesSyncPlaylist *change = [[BTITunesSyncPlaylist alloc] init];
        change.name = name;
        change.persistentID = persistentID;
        change.folderNames = [self folderPathFor:BTStringFrom(entry, @"Parent Persistent ID")
                                           names:folderNames
                                         parents:folderParents];
        change.change = existing ? BTITunesPlaylistGrew : BTITunesPlaylistIsNew;
        change.incomingTrackIDs = incoming;
        change.blocked = isSmart ? BTITunesBlockSmart
                       : (holdsLocked ? BTITunesBlockHoldsProtected : BTITunesBlockNone);
        [_playlists addObject:change];
    }
}

// The folders above a playlist, outermost first.
- (NSArray *)folderPathFor:(NSString *)parentID
                     names:(NSDictionary *)names
                   parents:(NSDictionary *)parents {
    NSMutableArray *path = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSString *current = parentID;
    while ([current length] > 0 && ![seen containsObject:current]) {
        [seen addObject:current];                 // a cycle would otherwise hang
        NSString *name = [names objectForKey:current];
        if ([name length] == 0) break;
        [path insertObject:name atIndex:0];
        current = [parents objectForKey:current];
    }
    return path;
}

- (void)collectPlaylists:(NSArray *)playlists
            intoBySource:(NSMutableDictionary *)bySource
                  byName:(NSMutableDictionary *)byName {
    NSUInteger i;
    for (i = 0; i < [playlists count]; i++) {
        BTPlaylist *playlist = [playlists objectAtIndex:i];
        if ([playlist.sourcePersistentID length] > 0) {
            [bySource setObject:playlist forKey:playlist.sourcePersistentID];
        }
        if ([playlist.name length] > 0) {
            [byName setObject:playlist forKey:[playlist.name lowercaseString]];
        }
        [self collectPlaylists:playlist.children intoBySource:bySource byName:byName];
    }
}

// The iTunes ids of what a BTunes playlist already holds, so a song placed here
// by an earlier sync does not show up as a change again.
- (NSSet *)persistentIDsOfPlaylist:(BTPlaylist *)playlist inLibrary:(BTLibrary *)library {
    NSMutableDictionary *byTrackID = [NSMutableDictionary dictionary];
    NSUInteger i;
    for (i = 0; i < [library.tracks count]; i++) {
        BTTrack *track = [library.tracks objectAtIndex:i];
        if ([track.persistentID length] > 0) {
            [byTrackID setObject:track.persistentID forKey:track.trackID];
        }
    }

    NSMutableSet *held = [NSMutableSet set];
    for (i = 0; i < [playlist.trackIDs count]; i++) {
        NSString *persistent = [byTrackID objectForKey:[playlist.trackIDs objectAtIndex:i]];
        if (persistent) [held addObject:persistent];
    }
    return held;
}

#pragma mark - Summary

- (NSString *)summary {
    NSUInteger songs = 0, added = 0, grown = 0;
    NSUInteger i;
    for (i = 0; i < [self.incomingTracks count]; i++) {
        if ([[self.incomingTracks objectAtIndex:i] eligible]) songs++;
    }
    for (i = 0; i < [self.playlists count]; i++) {
        BTITunesSyncPlaylist *playlist = [self.playlists objectAtIndex:i];
        if (![playlist eligible]) continue;
        if (playlist.change == BTITunesPlaylistIsNew) added++; else grown++;
    }

    if (songs == 0 && added == 0 && grown == 0) return @"Nothing new in iTunes.";

    NSMutableArray *parts = [NSMutableArray array];
    if (songs > 0) {
        [parts addObject:[NSString stringWithFormat:@"%lu new song%@ to import",
                          (unsigned long)songs, (songs == 1 ? @"" : @"s")]];
    }
    if (added > 0) {
        [parts addObject:[NSString stringWithFormat:@"%lu new playlist%@",
                          (unsigned long)added, (added == 1 ? @"" : @"s")]];
    }
    if (grown > 0) {
        [parts addObject:[NSString stringWithFormat:@"%lu playlist modification%@",
                          (unsigned long)grown, (grown == 1 ? @"" : @"s")]];
    }
    return [parts componentsJoinedByString:@", "];
}

@end
