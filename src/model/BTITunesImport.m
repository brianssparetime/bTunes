#import "BTITunesImport.h"
#import "BTTrack.h"
#import "BTPlaylist.h"

@implementation BTLibrary (ITunesImport)

+ (NSArray *)iTunesLibraryPathsForHome:(NSString *)home {
    NSString *music = [home stringByAppendingPathComponent:@"Music/iTunes"];
    return @[[music stringByAppendingPathComponent:@"iTunes Music Library.xml"],
             [music stringByAppendingPathComponent:@"iTunes Library.xml"]];
}

static NSString *BTPathFromLocation(NSString *location) {
    if ([location length] == 0) return nil;
    NSURL *url = [NSURL URLWithString:location];
    if (url == nil) return nil;
    if (![url isFileURL]) return nil;
    // Standardized so a path from the XML compares equal to the same file found
    // by a folder scan.
    return [[url path] stringByStandardizingPath];
}

static NSInteger BTIntFor(NSDictionary *d, NSString *key) {
    id v = [d objectForKey:key];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
}

static NSString *BTStringFor(NSDictionary *d, NSString *key) {
    id v = [d objectForKey:key];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

static NSDate *BTDateFor(NSDictionary *d, NSString *key) {
    id v = [d objectForKey:key];
    return [v isKindOfClass:[NSDate class]] ? v : nil;
}

- (BTTrack *)trackFromITunesEntry:(NSDictionary *)entry protected:(BOOL *)outProtected {
    NSString *path = BTPathFromLocation(BTStringFor(entry, @"Location"));
    if (path == nil) return nil;

    NSString *kind = BTStringFor(entry, @"Kind");
    BOOL isProtected = [[entry objectForKey:@"Protected"] boolValue] ||
                       [[[path pathExtension] lowercaseString] isEqualToString:@"m4p"] ||
                       ([kind rangeOfString:@"Protected" options:NSCaseInsensitiveSearch].location != NSNotFound);
    if (outProtected) *outProtected = isProtected;

    BTTrack *track = [[BTTrack alloc] init];
    track.trackID = [[NSUUID UUID] UUIDString];
    track.path = path;
    track.persistentID = BTStringFor(entry, @"Persistent ID");
    track.title = BTStringFor(entry, @"Name");
    track.artist = BTStringFor(entry, @"Artist");
    track.albumArtist = BTStringFor(entry, @"Album Artist");
    track.album = BTStringFor(entry, @"Album");
    track.genre = BTStringFor(entry, @"Genre");
    track.composer = BTStringFor(entry, @"Composer");
    track.kind = kind;
    track.trackNumber = BTIntFor(entry, @"Track Number");
    track.discNumber = BTIntFor(entry, @"Disc Number");
    track.year = BTIntFor(entry, @"Year");
    track.playCount = BTIntFor(entry, @"Play Count");
    track.duration = (NSTimeInterval)BTIntFor(entry, @"Total Time") / 1000.0;
    track.fileSize = (long long)BTIntFor(entry, @"Size");
    track.dateAdded = BTDateFor(entry, @"Date Added");
    track.lastPlayed = BTDateFor(entry, @"Play Date UTC");
    track.isProtected = isProtected;

    // iTunes stores a rating out of 100; BTunes shows stars.
    NSInteger rating = BTIntFor(entry, @"Rating");
    track.rating = (rating + 10) / 20;
    if (track.rating > 5) track.rating = 5;

    return track;
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

    for (i = 0; i < [keys count]; i++) {
        NSString *key = [keys objectAtIndex:i];
        NSDictionary *entry = [entries objectForKey:key];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;

        NSString *filePath = BTPathFromLocation(BTStringFor(entry, @"Location"));
        if (filePath == nil) { skipped++; continue; }

        BTTrack *existing = [byExistingPath objectForKey:filePath];
        if (existing) {
            [byITunesID setObject:existing forKey:key];
            skipped++;
            continue;
        }

        if (trackLimit > 0 && (NSInteger)added >= trackLimit) { skipped++; continue; }

        BOOL isProtected = NO;
        BTTrack *track = [self trackFromITunesEntry:entry protected:&isProtected];
        if (track == nil) { skipped++; continue; }

        [self.tracks addObject:track];
        [byExistingPath setObject:track forKey:[track resolvedPath]];
        [byITunesID setObject:track forKey:key];
        added++;
        if (isProtected) protectedCount++;
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

        NSString *name = BTStringFor(entry, @"Name");
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

        NSString *persistentID = BTStringFor(entry, @"Playlist Persistent ID");
        playlist.sourcePersistentID = persistentID;
        if (persistentID) [playlistsByPersistentID setObject:playlist forKey:persistentID];
        [ordered addObject:@[playlist, (BTStringFor(entry, @"Parent Persistent ID")
                                        ? BTStringFor(entry, @"Parent Persistent ID") : @"")]];
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
