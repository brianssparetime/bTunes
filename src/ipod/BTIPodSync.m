#import "BTIPodSync.h"
#import "BTIPod.h"
#import "BTIPodDatabase.h"
#import "BTPlaylist.h"
#import "BTTrack.h"
#import "BTLibrary.h"

NSString *const BTIPodSyncProgressNotification = @"BTIPodSyncProgress";
NSString *const BTIPodSyncDidFinishNotification = @"BTIPodSyncDidFinish";

@interface BTIPodSync ()
@property (nonatomic, strong) BTIPod *iPod;
@property (nonatomic, strong) BTIPodDatabase *database;
@property (nonatomic, strong) NSMutableDictionary *placedFiles;   // BTunes track id to device location
@property (nonatomic, assign) BOOL running;
@end

@implementation BTIPodSync

+ (instancetype)syncWithIPod:(BTIPod *)iPod {
    BTIPodSync *sync = [[BTIPodSync alloc] init];
    sync.iPod = iPod;
    sync.database = [BTIPodDatabase databaseWithContentsOfFile:[iPod databasePath]];
    if (sync.database == nil) sync.database = [BTIPodDatabase emptyDatabase];
    sync.placedFiles = [NSMutableDictionary dictionaryWithContentsOfFile:[sync mapPath]];
    if (sync.placedFiles == nil) sync.placedFiles = [NSMutableDictionary dictionary];
    return sync;
}

- (NSString *)mapPath {
    return [[[self.iPod controlPath] stringByAppendingPathComponent:@"iTunes"]
            stringByAppendingPathComponent:@"BTunesSync.plist"];
}

- (NSSet *)playlistNamesOnDevice {
    return [self.database playlistNames];
}

- (void)report:(double)fraction message:(NSString *)message {
    NSDictionary *info = @{@"fraction": @(fraction), @"message": (message ? message : @"")};
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:BTIPodSyncProgressNotification
                                                            object:self
                                                          userInfo:info];
    });
}

// Files live in iPod_Control/Music/F00 through F49 with short names. The spread
// is what the device expects; it is not a hashing scheme.
- (NSString *)destinationForTrack:(BTTrack *)track index:(NSUInteger)index {
    NSString *folder = [NSString stringWithFormat:@"F%02lu", (unsigned long)(index % 50)];
    NSString *extension = [[track.path pathExtension] lowercaseString];
    if ([extension length] == 0) extension = @"mp3";

    NSString *directory = [[self.iPod musicPath] stringByAppendingPathComponent:folder];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:NULL];

    NSString *name;
    NSString *full;
    NSUInteger attempt = 0;
    do {
        name = [NSString stringWithFormat:@"BT%02lX%04lX.%@",
                (unsigned long)(index % 256), (unsigned long)(arc4random_uniform(0xFFFF)), extension];
        full = [directory stringByAppendingPathComponent:name];
        attempt++;
    } while ([[NSFileManager defaultManager] fileExistsAtPath:full] && attempt < 64);

    return full;
}

- (NSString *)deviceLocationForPath:(NSString *)path {
    NSString *relative = [path substringFromIndex:[[self.iPod mountPath] length]];
    relative = [relative stringByReplacingOccurrencesOfString:@"/" withString:@":"];
    return relative;
}

- (void)syncPlaylists:(NSArray *)playlists completion:(void (^)(NSError *error))completion {
    if (self.running) return;
    self.running = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        [self runSyncOfPlaylists:playlists error:&error];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.running = NO;
            NSDictionary *info = error ? @{@"error": error} : @{};
            [[NSNotificationCenter defaultCenter] postNotificationName:BTIPodSyncDidFinishNotification
                                                                object:self
                                                              userInfo:info];
            if (completion) completion(error);
        });
    });
}

- (BOOL)runSyncOfPlaylists:(NSArray *)playlists error:(NSError **)outError {
    NSFileManager *fm = [NSFileManager defaultManager];
    BTLibrary *library = [BTLibrary sharedLibrary];
    NSUInteger i, j;

    // Every song the selection needs, in order, without repeats.
    NSMutableArray *wanted = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (i = 0; i < [playlists count]; i++) {
        BTPlaylist *playlist = [playlists objectAtIndex:i];
        NSArray *tracks = [playlist resolveTracks:library.tracks];
        for (j = 0; j < [tracks count]; j++) {
            BTTrack *track = [tracks objectAtIndex:j];
            if (track.isProtected) continue;          // cannot be decoded anywhere
            if ([seen containsObject:track.trackID]) continue;
            [seen addObject:track.trackID];
            [wanted addObject:track];
        }
    }

    [self report:0.0 message:@"Checking what is already on the iPod"];

    // Anything already placed by an earlier sync, still present, is left alone.
    NSMutableArray *toCopy = [NSMutableArray array];
    for (i = 0; i < [wanted count]; i++) {
        BTTrack *track = [wanted objectAtIndex:i];
        NSString *location = [self.placedFiles objectForKey:track.trackID];
        NSString *onDevice = nil;
        if (location) {
            NSString *relative = [[location stringByReplacingOccurrencesOfString:@":" withString:@"/"]
                                  substringFromIndex:1];
            onDevice = [[self.iPod mountPath] stringByAppendingPathComponent:relative];
        }
        if (onDevice == nil || ![fm fileExistsAtPath:onDevice]) {
            [toCopy addObject:track];
        }
    }

    // Copy what is missing.
    long long freeSpace = [[[fm attributesOfFileSystemForPath:[self.iPod mountPath] error:NULL]
                            objectForKey:NSFileSystemFreeSize] longLongValue];
    long long needed = 0;
    for (i = 0; i < [toCopy count]; i++) needed += [[toCopy objectAtIndex:i] fileSize];

    if (needed > freeSpace - (5LL * 1024 * 1024)) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"BTunes" code:1 userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"The iPod does not have room. %.1f MB of songs, %.1f MB free.",
                    needed / 1048576.0, freeSpace / 1048576.0]}];
        }
        return NO;
    }

    for (i = 0; i < [toCopy count]; i++) {
        BTTrack *track = [toCopy objectAtIndex:i];
        NSString *destination = [self destinationForTrack:track index:[self.database.tracks count] + i];

        NSError *copyError = nil;
        if (![fm copyItemAtPath:track.path toPath:destination error:&copyError]) {
            if (outError) *outError = copyError;
            return NO;
        }

        NSString *location = [self deviceLocationForPath:destination];
        [self.placedFiles setObject:location forKey:track.trackID];

        [self report:(double)(i + 1) / (double)MAX(1, [toCopy count])
             message:[NSString stringWithFormat:@"Copying %@", [track displayTitle]]];
    }

    [self report:1.0 message:@"Writing the iPod database"];

    // Rebuild the database: songs already on the device that BTunes did not put
    // there are carried across untouched.
    BTIPodDatabase *rebuilt = [BTIPodDatabase emptyDatabase];
    NSMutableDictionary *idForLocation = [NSMutableDictionary dictionary];
    uint32_t nextID = 1;

    for (i = 0; i < [self.database.tracks count]; i++) {
        BTIPodTrackRef *existing = [self.database.tracks objectAtIndex:i];
        NSString *path = [existing filesystemPathUnderMount:[self.iPod mountPath]];
        if (path == nil || ![fm fileExistsAtPath:path]) continue;
        if ([idForLocation objectForKey:existing.location]) continue;

        existing.trackID = nextID++;
        [rebuilt.tracks addObject:existing];
        [idForLocation setObject:@(existing.trackID) forKey:existing.location];
    }

    for (i = 0; i < [wanted count]; i++) {
        BTTrack *track = [wanted objectAtIndex:i];
        NSString *location = [self.placedFiles objectForKey:track.trackID];
        if (location == nil) continue;
        if ([idForLocation objectForKey:location]) continue;

        BTIPodTrackRef *ref = [[BTIPodTrackRef alloc] init];
        ref.trackID = nextID++;
        ref.location = location;
        ref.title = [track displayTitle];
        ref.artist = [track displayArtist];
        ref.album = [track displayAlbum];
        ref.genre = track.genre;
        ref.fileType = track.kind;
        ref.sizeInBytes = (uint32_t)track.fileSize;
        ref.durationMilliseconds = (uint32_t)(track.duration * 1000.0);
        ref.trackNumber = (uint32_t)track.trackNumber;
        ref.year = (uint32_t)track.year;
        ref.persistentID = (uint64_t)[track.trackID hash];

        [rebuilt.tracks addObject:ref];
        [idForLocation setObject:@(ref.trackID) forKey:location];
    }

    for (i = 0; i < [playlists count]; i++) {
        BTPlaylist *playlist = [playlists objectAtIndex:i];
        BTIPodPlaylistRef *ref = [[BTIPodPlaylistRef alloc] init];
        ref.name = playlist.name;

        NSArray *tracks = [playlist resolveTracks:library.tracks];
        for (j = 0; j < [tracks count]; j++) {
            BTTrack *track = [tracks objectAtIndex:j];
            NSString *location = [self.placedFiles objectForKey:track.trackID];
            NSNumber *deviceID = location ? [idForLocation objectForKey:location] : nil;
            if (deviceID) [ref.trackIDs addObject:deviceID];
        }
        [rebuilt.playlists addObject:ref];
    }

    // Back up whatever is there before replacing it.
    NSString *databasePath = [self.iPod databasePath];
    if ([fm fileExistsAtPath:databasePath]) {
        NSString *backup = [databasePath stringByAppendingPathExtension:@"btunes-backup"];
        [fm removeItemAtPath:backup error:NULL];
        [fm copyItemAtPath:databasePath toPath:backup error:NULL];
    }

    NSData *serialized = [rebuilt serializedDataWithDeviceName:self.iPod.name];
    if (![serialized writeToFile:databasePath atomically:YES]) {
        if (outError) {
            *outError = [NSError errorWithDomain:@"BTunes" code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"The iPod database could not be written."}];
        }
        return NO;
    }

    [self.placedFiles writeToFile:[self mapPath] atomically:YES];
    self.database = rebuilt;
    [self report:1.0 message:@"Sync finished"];
    return YES;
}

@end
