#import "BTITunesImport.h"
#import "BTTrack.h"
#import "BTDetuneMap.h"

@implementation BTLibrary (ITunesImport)

static NSInteger BTIntFor(NSDictionary *d, NSString *key) {
    id v = [d objectForKey:key];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
}

static NSDate *BTDateFor(NSDictionary *d, NSString *key) {
    id v = [d objectForKey:key];
    return [v isKindOfClass:[NSDate class]] ? v : nil;
}

// iTunes stores a rating out of 100 and BTunes shows stars, so five stars is
// anything from 91 to 100 and nothing at all is a genuine nought.
static NSInteger BTStarsFromITunes(NSDictionary *entry) {
    NSInteger stars = (BTIntFor(entry, @"Rating") + 10) / 20;
    return (stars > 5) ? 5 : stars;
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

    track.rating = BTStarsFromITunes(entry);

    return track;
}

- (BOOL)fillInTrack:(BTTrack *)track fromEntry:(BTITunesEntry *)source {
    NSDictionary *entry = source.entry;
    if (track == nil || entry == nil) return NO;

    NSString *persistentID = BTITunesString(entry, @"Persistent ID");
    if ([persistentID length] == 0) return NO;

    // Recognised by id from here on, which is what stops every later sync
    // reaching this same point and stopping.
    track.persistentID = persistentID;

    NSInteger stars = BTStarsFromITunes(entry);
    if (stars > track.rating) track.rating = stars;

    // Both counts are real listening: what iTunes saw over the years, and
    // whatever has been played here since the folder was scanned.
    track.playCount += BTIntFor(entry, @"Play Count");

    NSDate *added = BTDateFor(entry, @"Date Added");
    if (added && (track.dateAdded == nil ||
                  [added compare:track.dateAdded] == NSOrderedAscending)) {
        track.dateAdded = added;
    }

    NSDate *played = BTDateFor(entry, @"Play Date UTC");
    if (played && (track.lastPlayed == nil ||
                   [played compare:track.lastPlayed] == NSOrderedDescending)) {
        track.lastPlayed = played;
    }

    // Only what a scan could not have known. The tags on the file are what the
    // file says it is, and iTunes reading them differently is not a reason to
    // overwrite them.
    if ([track.albumArtist length] == 0) {
        track.albumArtist = BTITunesString(entry, @"Album Artist");
    }
    if (track.discNumber <= 0) track.discNumber = BTIntFor(entry, @"Disc Number");
    return YES;
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

@end
