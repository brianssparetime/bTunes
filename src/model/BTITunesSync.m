#import "BTITunesSync.h"
#import "BTLibrary.h"
#import "BTTrack.h"
#import "BTPlaylist.h"
#import "BTITunesImport.h"

@implementation BTITunesSyncTrack
// Whether it could come across at all. Being left behind before is deliberately
// not part of this: that sets which way the box starts, and a box can be ticked.
- (BOOL)eligible {
    return self.blocked == BTITunesBlockNone && !self.alreadyHere;
}
@end

@implementation BTITunesSyncPlaylist
- (BOOL)alreadyHere { return self.change == BTITunesPlaylistUnchanged; }
- (BOOL)eligible {
    return self.blocked == BTITunesBlockNone && self.change != BTITunesPlaylistUnchanged;
}
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

// A song is blocked if it is locked, or if there is no file here to point at.
// Not being on disk covers both a cloud copy and a file that has since gone:
// either way there is nothing to play.
static BTITunesBlock BTBlockForEntry(NSDictionary *entry, NSString *path, NSFileManager *files) {
    if (path == nil) return BTITunesBlockNotOnDisk;
    if (BTEntryIsProtected(entry, path)) return BTITunesBlockProtected;
    if (![files fileExistsAtPath:path]) return BTITunesBlockNotOnDisk;
    return BTITunesBlockNone;
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

+ (void)syncWithLibraryAtPath:(NSString *)path
                      against:(BTLibrary *)library
                     progress:(void (^)(double fraction, NSString *stage))progress
                   completion:(void (^)(BTITunesSync *sync))completion {
    // The stages are named rather than counted, because the reading and the
    // comparing take unlike amounts of time and a single bar creeping unevenly
    // says less than a line saying which part is slow.
    void (^report)(double, NSString *) = ^(double fraction, NSString *stage) {
        if (progress == nil) return;
        dispatch_async(dispatch_get_main_queue(), ^{ progress(fraction, stage); });
    };

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        report(0.05, @"Reading the iTunes library");
        BTITunesSync *sync = [[BTITunesSync alloc] init];

        NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:path];
        NSDictionary *entries = [root objectForKey:@"Tracks"];
        if (root == nil) {
            sync.error = [NSString stringWithFormat:@"Cannot read an iTunes library at %@", path];
        } else if (![entries isKindOfClass:[NSDictionary class]]) {
            sync.error = @"That file has no Tracks section.";
        } else {
            report(0.25, @"Looking for the songs on disk");
            [sync compareTracks:entries against:library];
            report(0.80, @"Comparing playlists");
            [sync comparePlaylists:[root objectForKey:@"Playlists"] entries:entries against:library];
        }

        report(1.0, @"Finished");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(sync);
        });
    });
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
    NSFileManager *files = [NSFileManager defaultManager];

    // Sorted numerically so the listing comes out in the order iTunes numbered
    // them, which is roughly the order they were added.
    NSArray *keys = [[entries allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [a compare:b options:NSNumericSearch];
    }];

    for (i = 0; i < [keys count]; i++) {
        NSDictionary *entry = [entries objectForKey:[keys objectAtIndex:i]];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;

        NSString *location = BTStringFrom(entry, @"Location");
        if ([location length] == 0) continue;      // no file and no cloud copy either

        // Nil for a cloud copy, which BTunes has nothing to point at.
        NSString *path = BTPathFromLocation(location);

        NSString *persistentID = BTStringFrom(entry, @"Persistent ID");
        BOOL here = ([persistentID length] > 0 && [haveByITunesID objectForKey:persistentID]) ||
                    (path != nil && [havePaths containsObject:path]);

        BTITunesSyncTrack *incoming = [[BTITunesSyncTrack alloc] init];
        incoming.persistentID = persistentID;
        incoming.path = path;
        incoming.title = BTStringFrom(entry, @"Name");
        incoming.artist = BTStringFrom(entry, @"Artist");
        incoming.album = BTStringFrom(entry, @"Album");
        incoming.entry = entry;
        incoming.alreadyHere = here;
        // A song already here is not asked about again, whatever else is true
        // of it, so the reason it could not come across is not worked out.
        incoming.blocked = here ? BTITunesBlockNone : BTBlockForEntry(entry, path, files);
        incoming.excludedBefore = (!here && [persistentID length] > 0 &&
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

    // iTunes track id to its persistent id, and to why it cannot come across.
    // Every entry with a location is kept, including the ones that are blocked,
    // because a playlist has to know it holds them.
    NSMutableDictionary *persistentForTrackID = [NSMutableDictionary dictionary];
    NSMutableDictionary *blockForTrackID = [NSMutableDictionary dictionary];
    NSFileManager *files = [NSFileManager defaultManager];
    NSArray *trackKeys = [entries allKeys];
    NSUInteger i, j;
    for (i = 0; i < [trackKeys count]; i++) {
        NSString *key = [trackKeys objectAtIndex:i];
        NSDictionary *entry = [entries objectForKey:key];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *location = BTStringFrom(entry, @"Location");
        if ([location length] == 0) continue;

        NSString *persistentID = BTStringFrom(entry, @"Persistent ID");
        if ([persistentID length] == 0) continue;
        [persistentForTrackID setObject:persistentID forKey:key];
        [blockForTrackID setObject:@(BTBlockForEntry(entry, BTPathFromLocation(location), files))
                            forKey:key];
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
        BOOL holdsLocked = NO, holdsMissing = NO;
        for (j = 0; [items isKindOfClass:[NSArray class]] && j < [items count]; j++) {
            id trackID = [[items objectAtIndex:j] objectForKey:@"Track ID"];
            if (trackID == nil) continue;
            NSString *key = [trackID description];
            NSString *persistent = [persistentForTrackID objectForKey:key];
            if ([persistent length] == 0) continue;

            switch ((BTITunesBlock)[[blockForTrackID objectForKey:key] integerValue]) {
                case BTITunesBlockProtected:  holdsLocked = YES;  break;
                case BTITunesBlockNotOnDisk:  holdsMissing = YES; break;
                default: break;
            }
            [members addObject:persistent];
        }
        if ([members count] == 0) continue;   // nothing in it worth reporting

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

        BTITunesSyncPlaylist *change = [[BTITunesSyncPlaylist alloc] init];
        change.name = name;
        change.persistentID = persistentID;
        change.folderNames = [self folderPathFor:BTStringFrom(entry, @"Parent Persistent ID")
                                           names:folderNames
                                         parents:folderParents];
        if (existing == nil) {
            change.change = BTITunesPlaylistIsNew;
        } else {
            change.change = ([incoming count] > 0) ? BTITunesPlaylistGrew
                                                   : BTITunesPlaylistUnchanged;
        }
        change.incomingTrackIDs = incoming;
        // Named in the order a reader would want to hear it: what iTunes will
        // never give up, then what is merely not downloaded yet.
        if (isSmart) {
            change.blocked = BTITunesBlockSmart;
        } else if (holdsLocked) {
            change.blocked = BTITunesBlockHoldsProtected;
        } else if (holdsMissing) {
            change.blocked = BTITunesBlockHoldsNotOnDisk;
        } else {
            change.blocked = BTITunesBlockNone;
        }
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

#pragma mark - Bringing it across

- (NSDictionary *)importInto:(BTLibrary *)library
                 chosenSongs:(NSSet *)songIDs
             chosenPlaylists:(NSSet *)playlistIDs {
    NSUInteger i, j, songsAdded = 0, playlistsAdded = 0, playlistsGrown = 0;

    // Every song that is coming, made once and remembered by its iTunes id, so
    // a song in three chosen playlists is imported once and joins all three.
    NSMutableDictionary *importedByITunesID = [NSMutableDictionary dictionary];
    for (i = 0; i < [_incomingTracks count]; i++) {
        BTITunesSyncTrack *incoming = [_incomingTracks objectAtIndex:i];
        if (![incoming eligible]) continue;
        if (![songIDs containsObject:incoming.persistentID]) continue;

        // The same reading of an entry the one-shot import uses, so both ways
        // of bringing music over agree about what a song's fields are.
        BTTrack *track = [library trackFromITunesEntry:incoming.entry protected:NULL];
        if (track == nil) continue;
        [library.tracks addObject:track];
        [importedByITunesID setObject:track forKey:incoming.persistentID];
        songsAdded++;
    }

    // Songs already here, so a chosen playlist can hold them alongside the new
    // ones rather than arriving half empty.
    NSMutableDictionary *heldByITunesID = [NSMutableDictionary dictionary];
    for (i = 0; i < [library.tracks count]; i++) {
        BTTrack *track = [library.tracks objectAtIndex:i];
        if ([track.persistentID length] > 0) {
            [heldByITunesID setObject:track forKey:track.persistentID];
        }
    }

    for (i = 0; i < [_playlists count]; i++) {
        BTITunesSyncPlaylist *incoming = [_playlists objectAtIndex:i];
        if (![incoming eligible]) continue;
        if (![playlistIDs containsObject:incoming.persistentID]) continue;

        // Only the songs that actually came across. One left behind simply is
        // not in the playlist, and arrives in its place on a later sync.
        NSMutableArray *joining = [NSMutableArray array];
        for (j = 0; j < [incoming.incomingTrackIDs count]; j++) {
            NSString *persistent = [incoming.incomingTrackIDs objectAtIndex:j];
            BTTrack *track = [heldByITunesID objectForKey:persistent];
            if (track && ![joining containsObject:track.trackID]) [joining addObject:track.trackID];
        }
        if ([joining count] == 0) continue;

        BTPlaylist *existing = [self playlistIn:library
                                   matchingName:incoming.name
                                         source:incoming.persistentID];
        if (existing) {
            // At the end, so an arrangement made by hand is left alone.
            for (j = 0; j < [joining count]; j++) {
                NSString *trackID = [joining objectAtIndex:j];
                if (![existing.trackIDs containsObject:trackID]) [existing.trackIDs addObject:trackID];
            }
            if ([existing.sourcePersistentID length] == 0) {
                existing.sourcePersistentID = incoming.persistentID;
            }
            playlistsGrown++;
            continue;
        }

        BTPlaylist *made = [BTPlaylist playlistWithName:incoming.name kind:BTPlaylistKindStatic];
        made.sourcePersistentID = incoming.persistentID;
        [made.trackIDs addObjectsFromArray:joining];
        [library addPlaylist:made toFolder:[self folderIn:library named:incoming.folderNames]];
        playlistsAdded++;
    }

    [library noteChanged];
    return @{@"songsAdded": @(songsAdded),
             @"playlistsAdded": @(playlistsAdded),
             @"playlistsGrown": @(playlistsGrown)};
}

- (BTPlaylist *)playlistIn:(BTLibrary *)library
              matchingName:(NSString *)name
                    source:(NSString *)persistentID {
    NSMutableDictionary *bySource = [NSMutableDictionary dictionary];
    NSMutableDictionary *byName = [NSMutableDictionary dictionary];
    [self collectPlaylists:library.playlists intoBySource:bySource byName:byName];

    BTPlaylist *found = [persistentID length] > 0 ? [bySource objectForKey:persistentID] : nil;
    return found ? found : [byName objectForKey:[name lowercaseString]];
}

// The folder a playlist belongs in, made if it is not here yet. Folders already
// present are joined rather than duplicated.
- (BTPlaylist *)folderIn:(BTLibrary *)library named:(NSArray *)folderNames {
    BTPlaylist *parent = nil;
    NSUInteger i, j;
    for (i = 0; i < [folderNames count]; i++) {
        NSString *name = [folderNames objectAtIndex:i];
        NSArray *siblings = parent ? parent.children : library.playlists;

        BTPlaylist *found = nil;
        for (j = 0; j < [siblings count] && found == nil; j++) {
            BTPlaylist *candidate = [siblings objectAtIndex:j];
            if (candidate.kind == BTPlaylistKindFolder &&
                [candidate.name caseInsensitiveCompare:name] == NSOrderedSame) {
                found = candidate;
            }
        }
        if (found == nil) {
            found = [BTPlaylist playlistWithName:name kind:BTPlaylistKindFolder];
            [library addPlaylist:found toFolder:parent];
        }
        parent = found;
    }
    return parent;
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
