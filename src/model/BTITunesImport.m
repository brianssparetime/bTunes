#import "BTITunesImport.h"
#import "BTTrack.h"
#import "BTPlaylist.h"
#import "BTDetuneMap.h"

@implementation BTLibrary (ITunesImport)

+ (NSArray *)iTunesLibraryPathsForHome:(NSString *)home {
    NSString *music = [home stringByAppendingPathComponent:@"Music/iTunes"];
    return @[[music stringByAppendingPathComponent:@"iTunes Music Library.xml"],
             [music stringByAppendingPathComponent:@"iTunes Library.xml"]];
}

static NSInteger BTIntFor(NSDictionary *d, NSString *key) {
    id v = [d objectForKey:key];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
}

static NSDate *BTDateFor(NSDictionary *d, NSString *key) {
    id v = [d objectForKey:key];
    return [v isKindOfClass:[NSDate class]] ? v : nil;
}

- (BTTrack *)trackFromEntry:(BTITunesEntry *)source {
    NSDictionary *entry = source.entry;
    if (entry == nil || [source.path length] == 0) return nil;

    BTTrack *track = [[BTTrack alloc] init];
    track.trackID = [[NSUUID UUID] UUIDString];
    // Both at once, so a substituted song is measured against the folder it
    // actually lives in rather than against the music root it does not.
    [track setPath:source.path root:source.pathRoot];
    track.persistentID = BTITunesString(entry, @"Persistent ID");
    track.title = BTITunesString(entry, @"Name");
    track.artist = BTITunesString(entry, @"Artist");
    track.albumArtist = BTITunesString(entry, @"Album Artist");
    track.album = BTITunesString(entry, @"Album");
    track.genre = BTITunesString(entry, @"Genre");
    track.composer = BTITunesString(entry, @"Composer");
    // A substituted song is a plain recording whatever iTunes called the
    // purchase it replaces, and saying otherwise would put "Protected" beside a
    // song that plays.
    track.kind = source.fromDetune ? @"AAC audio file" : BTITunesString(entry, @"Kind");
    track.trackNumber = BTIntFor(entry, @"Track Number");
    track.discNumber = BTIntFor(entry, @"Disc Number");
    track.year = BTIntFor(entry, @"Year");
    track.playCount = BTIntFor(entry, @"Play Count");
    track.duration = (NSTimeInterval)BTIntFor(entry, @"Total Time") / 1000.0;
    track.fileSize = (long long)BTIntFor(entry, @"Size");
    track.dateAdded = BTDateFor(entry, @"Date Added");
    track.lastPlayed = BTDateFor(entry, @"Play Date UTC");
    track.isProtected = source.isProtected;

    // iTunes stores a rating out of 100; BTunes shows stars.
    NSInteger rating = BTIntFor(entry, @"Rating");
    track.rating = (rating + 10) / 20;
    if (track.rating > 5) track.rating = 5;

    return track;
}

- (NSDictionary *)placesForMissingFiles:(NSArray *)missing
                fromITunesLibraryAtPath:(NSString *)xmlPath {
    NSMutableDictionary *wanted = [NSMutableDictionary dictionary];
    NSUInteger i;
    for (i = 0; i < [missing count]; i++) {
        BTTrack *track = [missing objectAtIndex:i];
        // No persistent id, no way to ask after it. A song added by scanning a
        // folder was never an iTunes entry and cannot be looked up here.
        if ([track.persistentID length] > 0) [wanted setObject:track forKey:track.persistentID];
    }
    if ([wanted count] == 0 || [xmlPath length] == 0) return @{};

    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:xmlPath];
    NSDictionary *entries = [root objectForKey:@"Tracks"];
    if (![entries isKindOfClass:[NSDictionary class]]) return @{};

    BTDetuneMap *detune = [BTDetuneMap currentMap];
    NSFileManager *files = [NSFileManager defaultManager];
    NSMutableDictionary *places = [NSMutableDictionary dictionary];

    NSArray *keys = [entries allKeys];
    for (i = 0; i < [keys count]; i++) {
        NSDictionary *entry = [entries objectForKey:[keys objectAtIndex:i]];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;

        NSString *persistentID = BTITunesString(entry, @"Persistent ID");
        BTTrack *track = ([persistentID length] > 0) ? [wanted objectForKey:persistentID] : nil;
        if (track == nil) continue;

        BTITunesEntry *read = [BTITunesEntry readEntry:entry detune:detune files:files];
        if (read == nil || [read.resolvedPath length] == 0) continue;

        // Somewhere the file actually is, and somewhere new. Repointing one dead
        // path at another dead path is not a repair, and repointing a path at
        // itself says the file is simply gone.
        if (![files fileExistsAtPath:read.resolvedPath]) continue;
        if ([read.resolvedPath isEqualToString:[track resolvedPath]]) continue;

        [places setObject:read forKey:track.trackID];
    }
    return places;
}

- (NSDictionary *)importITunesLibraryAtPath:(NSString *)path trackLimit:(NSInteger)trackLimit {
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:path];
    if (root == nil) {
        return @{@"error": [NSString stringWithFormat:@"Cannot read an iTunes library at %@", path]};
    }

    NSDictionary *entries = [root objectForKey:@"Tracks"];
    NSArray *playlistEntries = [root objectForKey:@"Playlists"];
    if (![entries isKindOfClass:[NSDictionary class]]) {
        return @{@"error": @"That file has no Tracks section."};
    }

    NSMutableDictionary *byExistingPath = [NSMutableDictionary dictionary];
    NSUInteger i, j;
    for (i = 0; i < [self.tracks count]; i++) {
        BTTrack *t = [self.tracks objectAtIndex:i];
        [byExistingPath setObject:t forKey:[t resolvedPath]];
    }

    // iTunes track id (as a string) to the BTunes track it became, so playlist
    // membership can be rebuilt afterwards.
    NSMutableDictionary *byITunesID = [NSMutableDictionary dictionary];
    NSUInteger added = 0, skipped = 0, protectedCount = 0;

    NSArray *keys = [[entries allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [a compare:b options:NSNumericSearch];
    }];

    // The same reading the sync uses, including the substitution of free
    // recordings for locked purchases, so both ways of bringing music over point
    // at the same file for the same song.
    BTDetuneMap *detune = [BTDetuneMap currentMap];
    NSFileManager *files = [NSFileManager defaultManager];

    for (i = 0; i < [keys count]; i++) {
        NSString *key = [keys objectAtIndex:i];
        BTITunesEntry *source = [BTITunesEntry readEntry:[entries objectForKey:key]
                                                  detune:detune
                                                   files:files];
        if (source == nil || [source.resolvedPath length] == 0) { skipped++; continue; }

        BTTrack *existing = [byExistingPath objectForKey:source.resolvedPath];
        if (existing) {
            [byITunesID setObject:existing forKey:key];
            skipped++;
            continue;
        }

        if (trackLimit > 0 && (NSInteger)added >= trackLimit) { skipped++; continue; }

        BTTrack *track = [self trackFromEntry:source];
        if (track == nil) { skipped++; continue; }

        [self.tracks addObject:track];
        [byExistingPath setObject:track forKey:[track resolvedPath]];
        [byITunesID setObject:track forKey:key];
        added++;
        if (track.isProtected) protectedCount++;
    }

    // Playlists, in two passes: build them all, then hang them off their parents.
    NSMutableDictionary *playlistsByPersistentID = [NSMutableDictionary dictionary];
    NSMutableArray *ordered = [NSMutableArray array];
    NSUInteger playlistCount = 0, folderCount = 0, smartAsStatic = 0;

    for (i = 0; playlistEntries != nil && i < [playlistEntries count]; i++) {
        NSDictionary *entry = [playlistEntries objectAtIndex:i];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;

        // The master library and the built-in category lists are not user playlists.
        if ([[entry objectForKey:@"Master"] boolValue]) continue;
        if ([entry objectForKey:@"Distinguished Kind"] != nil) continue;

        NSString *name = BTITunesString(entry, @"Name");
        if ([name length] == 0) continue;

        BOOL isFolder = [[entry objectForKey:@"Folder"] boolValue];
        BOOL wasSmart = ([entry objectForKey:@"Smart Info"] != nil ||
                         [entry objectForKey:@"Smart Criteria"] != nil);

        BTPlaylist *playlist = [BTPlaylist playlistWithName:name
                                                       kind:(isFolder ? BTPlaylistKindFolder
                                                                      : BTPlaylistKindStatic)];
        if (isFolder) {
            folderCount++;
        } else {
            playlistCount++;
            if (wasSmart) smartAsStatic++;

            NSArray *items = [entry objectForKey:@"Playlist Items"];
            for (j = 0; [items isKindOfClass:[NSArray class]] && j < [items count]; j++) {
                NSDictionary *item = [items objectAtIndex:j];
                id trackID = [item objectForKey:@"Track ID"];
                if (trackID == nil) continue;
                BTTrack *track = [byITunesID objectForKey:[trackID description]];
                if (track && ![playlist.trackIDs containsObject:track.trackID]) {
                    [playlist.trackIDs addObject:track.trackID];
                }
            }
        }

        NSString *persistentID = BTITunesString(entry, @"Playlist Persistent ID");
        playlist.sourcePersistentID = persistentID;
        if (persistentID) [playlistsByPersistentID setObject:playlist forKey:persistentID];
        [ordered addObject:@[playlist, (BTITunesString(entry, @"Parent Persistent ID")
                                        ? BTITunesString(entry, @"Parent Persistent ID") : @"")]];
    }

    for (i = 0; i < [ordered count]; i++) {
        NSArray *pair = [ordered objectAtIndex:i];
        BTPlaylist *playlist = [pair objectAtIndex:0];
        NSString *parentID = [pair objectAtIndex:1];
        BTPlaylist *parent = [parentID length] > 0 ? [playlistsByPersistentID objectForKey:parentID] : nil;

        if (parent && parent.kind == BTPlaylistKindFolder && parent != playlist) {
            playlist.parent = parent;
            [parent.children addObject:playlist];
        } else {
            [self.playlists addObject:playlist];
        }
    }

    [self noteChanged];

    return @{@"tracksAdded": @(added),
             @"tracksSkipped": @(skipped),
             @"protectedTracks": @(protectedCount),
             @"playlistsAdded": @(playlistCount),
             @"foldersAdded": @(folderCount),
             @"smartAsStatic": @(smartAsStatic)};
}

@end
