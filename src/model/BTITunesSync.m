#import "BTITunesSync.h"
#import "BTLibrary.h"
#import "BTTrack.h"
#import "BTPlaylist.h"
#import "BTITunesImport.h"
#import "BTDetuneMap.h"
#import "BTITunesTwins.h"

@implementation BTITunesSyncTrack
- (BOOL)fillsInDetails { return [self.fillsInTrackID length] > 0; }

// Whether this sync could do anything for the song at all: bring it across, or
// fill in what iTunes knows about one already here under no name.
//
// Being left behind before is deliberately not part of this: that sets which way
// the box starts, and a box can be ticked.
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


@implementation BTITunesSyncModification

+ (NSString *)keyForPlaylist:(NSString *)playlistID song:(NSString *)songID {
    if ([playlistID length] == 0 || [songID length] == 0) return nil;
    return [NSString stringWithFormat:@"%@/%@", playlistID, songID];
}

- (NSString *)key {
    return [[self class] keyForPlaylist:self.playlistID song:self.songID];
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
    NSMutableArray *_modifications;
}

- (id)init {
    self = [super init];
    if (self) {
        _incomingTracks = [NSMutableArray array];
        _playlists = [NSMutableArray array];
        _modifications = [NSMutableArray array];
    }
    return self;
}

- (NSArray *)incomingTracks { return _incomingTracks; }
- (NSArray *)playlists { return _playlists; }
- (NSArray *)modifications { return _modifications; }

#pragma mark - Reading the file

// Every entry read once, keyed by the iTunes track id playlists refer to.
//
// One pass rather than two. The songs and the playlists each used to work out
// for themselves whether a track could come across, which asked the filesystem
// about every file twice over, and asking is nearly all the time a sync takes.
// It also left two answers free to disagree, and one of them decided what could
// be ticked while the other decided what was actually imported.
- (NSDictionary *)readEntries:(NSDictionary *)entries
                       detune:(BTDetuneMap *)detune
                        twins:(BTITunesTwins *)twins {
    NSFileManager *files = [NSFileManager defaultManager];
    NSMutableDictionary *read = [NSMutableDictionary dictionaryWithCapacity:[entries count]];
    NSArray *keys = [entries allKeys];
    NSUInteger i;
    for (i = 0; i < [keys count]; i++) {
        id key = [keys objectAtIndex:i];
        BTITunesEntry *one = [BTITunesEntry readEntry:[entries objectForKey:key]
                                               detune:detune
                                                twins:twins
                                                files:files];
        if (one) [read setObject:one forKey:key];
    }
    return read;
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

    NSDictionary *read = [sync readEntries:entries
                                          detune:[BTDetuneMap currentMap]
                                           twins:[BTITunesTwins twinsInEntries:entries]];
    [sync compareTracks:read against:library];
    [sync comparePlaylists:[root objectForKey:@"Playlists"] read:read against:library];
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
            report(0.20, @"Looking for the songs on disk");
            NSDictionary *read = [sync readEntries:entries
                                          detune:[BTDetuneMap currentMap]
                                           twins:[BTITunesTwins twinsInEntries:entries]];
            report(0.70, @"Comparing songs");
            [sync compareTracks:read against:library];
            report(0.85, @"Comparing playlists");
            [sync comparePlaylists:[root objectForKey:@"Playlists"] read:read against:library];
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
- (void)compareTracks:(NSDictionary *)read against:(BTLibrary *)library {
    NSMutableDictionary *haveByITunesID = [NSMutableDictionary dictionary];
    // Kept as the track rather than as a set of paths, because matching a file
    // is only half the question: what matters next is whether the track sitting
    // there carries an iTunes identity or arrived by a folder scan with none.
    NSMutableDictionary *haveByPath = [NSMutableDictionary dictionary];

    NSUInteger i;
    for (i = 0; i < [library.tracks count]; i++) {
        BTTrack *track = [library.tracks objectAtIndex:i];
        if ([track.persistentID length] > 0) {
            [haveByITunesID setObject:track forKey:track.persistentID];
        }
        NSString *resolved = [track resolvedPath];
        if ([resolved length] > 0 && [haveByPath objectForKey:resolved] == nil) {
            [haveByPath setObject:track forKey:resolved];
        }
    }

    NSSet *excluded = [library excludedFromImport];

    // Sorted numerically so the listing comes out in the order iTunes numbered
    // them, which is roughly the order they were added.
    NSArray *keys = [[read allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [a compare:b options:NSNumericSearch];
    }];

    for (i = 0; i < [keys count]; i++) {
        BTITunesEntry *source = [read objectForKey:[keys objectAtIndex:i]];
        NSString *persistentID = source.persistentID;

        // Matched on the file BTunes would actually record, which for a
        // substituted song is the free recording rather than the locked
        // original, so a second sync does not offer it all over again.
        BTTrack *sameID = ([persistentID length] > 0)
            ? [haveByITunesID objectForKey:persistentID] : nil;
        BTTrack *sameFile = (source.resolvedPath != nil)
            ? [haveByPath objectForKey:source.resolvedPath] : nil;
        BOOL here = (sameID != nil || sameFile != nil);

        // The file is here and the song is not: a folder scan put it in the
        // library, so it carries no iTunes id and none of what iTunes knows
        // about it. Left as "already here" that would never change, because
        // every later sync would find the same file and stop at the same place.
        NSString *fillsIn = nil;
        if (sameID == nil && sameFile != nil && [persistentID length] > 0 &&
            [sameFile.persistentID length] == 0 && source.blocked == BTITunesBlockNone) {
            fillsIn = sameFile.trackID;
        }

        BTITunesSyncTrack *incoming = [[BTITunesSyncTrack alloc] init];
        incoming.fillsInTrackID = fillsIn;
        incoming.persistentID = persistentID;
        incoming.path = source.iTunesPath;
        incoming.title = BTITunesString(source.entry, @"Name");
        incoming.artist = BTITunesString(source.entry, @"Artist");
        incoming.album = BTITunesString(source.entry, @"Album");
        incoming.source = source;
        incoming.fromDetune = source.fromDetune;
        incoming.fromTwin = source.fromTwin;
        // One whose details can still be filled in is not finished with, so it
        // is not "already here" however much of it is.
        incoming.alreadyHere = (here && fillsIn == nil);
        // A song already here is not asked about again, whatever else is true
        // of it, so the reason it could not come across is not worked out.
        incoming.blocked = here ? BTITunesBlockNone : source.blocked;
        incoming.excludedBefore = (!incoming.alreadyHere && [persistentID length] > 0 &&
                                   [excluded containsObject:persistentID]);
        [_incomingTracks addObject:incoming];
    }
}

// Playlists, in two passes: name the folders first, then place each playlist
// under the folders it belongs to.
- (void)comparePlaylists:(NSArray *)playlistEntries
                    read:(NSDictionary *)read
                 against:(BTLibrary *)library {
    if (![playlistEntries isKindOfClass:[NSArray class]]) return;

    NSUInteger i, j;

    // Folder names by their own persistent id, so a playlist can name its path.
    NSMutableDictionary *folderNames = [NSMutableDictionary dictionary];
    NSMutableDictionary *folderParents = [NSMutableDictionary dictionary];
    for (i = 0; i < [playlistEntries count]; i++) {
        NSDictionary *entry = [playlistEntries objectAtIndex:i];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        if (![[entry objectForKey:@"Folder"] boolValue]) continue;
        NSString *own = BTITunesString(entry, @"Playlist Persistent ID");
        if ([own length] == 0) continue;
        [folderNames setObject:(BTITunesString(entry, @"Name") ?: @"") forKey:own];
        NSString *parent = BTITunesString(entry, @"Parent Persistent ID");
        if ([parent length] > 0) [folderParents setObject:parent forKey:own];
    }

    // What BTunes already holds, by the iTunes playlist it came from.
    NSDictionary *haveByPersistent = [self playlistsBySourceIn:library];

    // The songs by their persistent id, so a song joining a playlist can be
    // named. The entries are keyed by track id, which is a number meaning one
    // thing inside a single library file and nothing between two.
    NSArray *readKeys = [read allKeys];
    NSMutableDictionary *entriesByPersistent = [NSMutableDictionary dictionary];
    for (i = 0; i < [readKeys count]; i++) {
        BTITunesEntry *entry = [read objectForKey:[readKeys objectAtIndex:i]];
        if ([entry.persistentID length] > 0) {
            [entriesByPersistent setObject:entry forKey:entry.persistentID];
        }
    }

    NSSet *excluded = [library excludedFromImport];

    for (i = 0; i < [playlistEntries count]; i++) {
        NSDictionary *entry = [playlistEntries objectAtIndex:i];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        if ([[entry objectForKey:@"Master"] boolValue]) continue;
        if ([entry objectForKey:@"Distinguished Kind"] != nil) continue;
        if ([[entry objectForKey:@"Folder"] boolValue]) continue;

        NSString *name = BTITunesString(entry, @"Name");
        if ([name length] == 0) continue;

        NSString *persistentID = BTITunesString(entry, @"Playlist Persistent ID");
        BOOL isSmart = ([entry objectForKey:@"Smart Info"] != nil ||
                        [entry objectForKey:@"Smart Criteria"] != nil);

        // Membership in iTunes order, and whether any of it is blocked. Read
        // from the same entries the songs were judged from, so a playlist is
        // never grey for holding a song the list above says is fine to bring
        // across. A locked song with a free recording behind it blocks nothing.
        NSArray *items = [entry objectForKey:@"Playlist Items"];
        NSMutableArray *members = [NSMutableArray array];
        BOOL holdsLocked = NO, holdsMissing = NO;
        for (j = 0; [items isKindOfClass:[NSArray class]] && j < [items count]; j++) {
            id trackID = [[items objectAtIndex:j] objectForKey:@"Track ID"];
            if (trackID == nil) continue;
            BTITunesEntry *member = [read objectForKey:[trackID description]];
            if ([member.persistentID length] == 0) continue;

            switch (member.blocked) {
                case BTITunesBlockProtected:  holdsLocked = YES;  break;
                case BTITunesBlockNotOnDisk:  holdsMissing = YES; break;
                default: break;
            }
            [members addObject:member.persistentID];
        }
        if ([members count] == 0) continue;   // nothing in it worth reporting

        // By id and by nothing else. Matching on name as well meant a playlist
        // made here by hand was quietly grown by an iTunes one that shared its
        // name, adding songs nobody chose to put in it.
        BTPlaylist *existing = ([persistentID length] > 0)
            ? [haveByPersistent objectForKey:persistentID] : nil;

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
        change.folderNames = [self folderPathFor:BTITunesString(entry, @"Parent Persistent ID")
                                           names:folderNames
                                         parents:folderParents];
        if (existing == nil) {
            change.change = BTITunesPlaylistIsNew;
        } else {
            change.change = ([incoming count] > 0) ? BTITunesPlaylistGrew
                                                   : BTITunesPlaylistUnchanged;
        }
        change.incomingTrackIDs = incoming;
        change.excludedBefore = ([persistentID length] > 0 &&
                                 [[library excludedFromImport] containsObject:persistentID]);
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

        // Only for a playlist that could actually grow. A new playlist's songs
        // are the playlist rather than a change to one, and a playlist nothing
        // can be done to has nothing to offer.
        if (change.change != BTITunesPlaylistGrew || change.blocked != BTITunesBlockNone) continue;
        for (j = 0; j < [incoming count]; j++) {
            NSString *songID = [incoming objectAtIndex:j];
            BTITunesEntry *song = [entriesByPersistent objectForKey:songID];
            BTITunesSyncModification *addition = [[BTITunesSyncModification alloc] init];
            addition.playlistID = persistentID;
            addition.playlistName = name;
            addition.songID = songID;
            addition.songTitle = song ? BTITunesString(song.entry, @"Name") : nil;
            addition.songArtist = song ? BTITunesString(song.entry, @"Artist") : nil;
            addition.excludedBefore = ([addition.key length] > 0 &&
                                       [excluded containsObject:addition.key]);
            [_modifications addObject:addition];
        }
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

- (NSDictionary *)playlistsBySourceIn:(BTLibrary *)library {
    NSMutableDictionary *bySource = [NSMutableDictionary dictionary];
    [BTPlaylist enumerate:library.playlists usingBlock:^(BTPlaylist *playlist, BOOL *stop) {
        if ([playlist.sourcePersistentID length] > 0) {
            [bySource setObject:playlist forKey:playlist.sourcePersistentID];
        }
    }];
    return bySource;
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
             chosenPlaylists:(NSSet *)playlistIDs
           skippedAdditions:(NSSet *)skippedKeys {
    NSUInteger i, j, songsAdded = 0, songsFilledIn = 0;
    NSUInteger playlistsAdded = 0, playlistsGrown = 0;

    // The songs already here, by their own id, so one being filled in can be
    // found without walking the library for each.
    NSMutableDictionary *heldByTrackID = [NSMutableDictionary dictionary];
    for (i = 0; i < [library.tracks count]; i++) {
        BTTrack *track = [library.tracks objectAtIndex:i];
        if (track.trackID) [heldByTrackID setObject:track forKey:track.trackID];
    }

    for (i = 0; i < [_incomingTracks count]; i++) {
        BTITunesSyncTrack *incoming = [_incomingTracks objectAtIndex:i];
        if (![incoming eligible]) continue;
        if (![songIDs containsObject:incoming.persistentID]) continue;

        // Already in the library under no iTunes name: it gets the name and
        // everything hanging off it, and no second copy of the song.
        if ([incoming fillsInDetails]) {
            BTTrack *held = [heldByTrackID objectForKey:incoming.fillsInTrackID];
            if (held == nil) continue;
            if ([library fillInTrack:held fromEntry:incoming.source]) songsFilledIn++;
            continue;
        }

        // Built from the entry as it was read, so the file imported is the file
        // eligibility was decided about, substitution and all.
        BTTrack *track = [library trackFromEntry:incoming.source];
        if (track == nil) continue;
        [library addTrack:track];
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
            // A song turned down one playlist at a time. Only a playlist already
            // here has these, since only there is a song joining a playlist a
            // separate thing from the playlist arriving.
            if (incoming.change == BTITunesPlaylistGrew) {
                NSString *key = [BTITunesSyncModification keyForPlaylist:incoming.persistentID
                                                                    song:persistent];
                if (key && [skippedKeys containsObject:key]) continue;
            }
            BTTrack *track = [heldByITunesID objectForKey:persistent];
            if (track && ![joining containsObject:track.trackID]) [joining addObject:track.trackID];
        }
        if ([joining count] == 0) continue;

        // The one this playlist came from before, if it has been here before.
        // Nothing is matched by name: a playlist made here by hand that happens
        // to share a name is somebody else's playlist.
        BTPlaylist *existing = ([incoming.persistentID length] > 0)
            ? [[self playlistsBySourceIn:library] objectForKey:incoming.persistentID] : nil;
        if (existing) {
            // At the end, so an arrangement made by hand is left alone.
            for (j = 0; j < [joining count]; j++) {
                NSString *trackID = [joining objectAtIndex:j];
                if (![existing.trackIDs containsObject:trackID]) [existing.trackIDs addObject:trackID];
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
             @"songsFilledIn": @(songsFilledIn),
             @"playlistsAdded": @(playlistsAdded),
             @"playlistsGrown": @(playlistsGrown)};
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
    NSUInteger songs = 0, fillIns = 0, added = 0, grown = 0;
    NSUInteger i;
    for (i = 0; i < [self.incomingTracks count]; i++) {
        BTITunesSyncTrack *track = [self.incomingTracks objectAtIndex:i];
        if (![track eligible]) continue;
        if ([track fillsInDetails]) fillIns++; else songs++;
    }
    for (i = 0; i < [self.playlists count]; i++) {
        BTITunesSyncPlaylist *playlist = [self.playlists objectAtIndex:i];
        if (![playlist eligible]) continue;
        if (playlist.change == BTITunesPlaylistIsNew) added++; else grown++;
    }

    if (songs == 0 && fillIns == 0 && added == 0 && grown == 0) {
        return @"Nothing new in iTunes.";
    }

    NSMutableArray *parts = [NSMutableArray array];
    if (songs > 0) {
        [parts addObject:[NSString stringWithFormat:@"%lu new song%@ to import",
                          (unsigned long)songs, (songs == 1 ? @"" : @"s")]];
    }
    // Said apart from the new songs, because nothing is copied or added for
    // these: what arrives is the rating and the play count for a song already
    // sitting in the library.
    if (fillIns > 0) {
        [parts addObject:[NSString stringWithFormat:@"%lu song%@ to fill in",
                          (unsigned long)fillIns, (fillIns == 1 ? @"" : @"s")]];
    }
    if (added > 0) {
        [parts addObject:[NSString stringWithFormat:@"%lu new playlist%@",
                          (unsigned long)added, (added == 1 ? @"" : @"s")]];
    }
    // Counted in songs and in playlists both, because one number without the
    // other says nothing useful. "1 playlist modification" was the whole of what
    // this line used to say, and forty-four songs joining one playlist and one
    // song joining it read exactly alike.
    if (grown > 0) {
        NSUInteger joining = [self.modifications count];
        [parts addObject:[NSString stringWithFormat:@"%lu song%@ added to %lu playlist%@",
                          (unsigned long)joining, (joining == 1 ? @"" : @"s"),
                          (unsigned long)grown, (grown == 1 ? @"" : @"s")]];
    }
    return [parts componentsJoinedByString:@", "];
}

@end
