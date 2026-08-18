#import "BTLibrary.h"
#import "BTTrack.h"
#import "BTPlaylist.h"
#import "BTPreferences.h"
#import "BTSoundCheck.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <AudioToolbox/AudioToolbox.h>

NSString *const BTLibraryDidChangeNotification = @"BTLibraryDidChange";
NSString *const BTLibraryTrackDidChangeNotification = @"BTLibraryTrackDidChange";

// Set once the database has been brought under the BTunes home, so a folder
// chosen afterwards is not moved back out of it on the next launch.
static NSString *const BTMovedIntoTheHomeKey = @"BTMovedIntoTheHome";

@interface BTLibrary ()
@property (nonatomic, strong) NSMutableArray *tracks;
@property (nonatomic, strong) NSMutableArray *playlists;
@property (nonatomic, strong) NSMutableSet *knownPaths;
@property (nonatomic, strong) NSMutableSet *excluded;
@end

@implementation BTLibrary

+ (instancetype)sharedLibrary {
    static BTLibrary *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[BTLibrary alloc] init]; });
    return shared;
}

- (id)init {
    self = [super init];
    if (self) {
        _tracks = [NSMutableArray array];
        _playlists = [NSMutableArray array];
        _knownPaths = [NSMutableSet set];
        _excluded = [NSMutableSet set];
    }
    return self;
}

+ (NSArray *)supportedExtensions {
    // Everything Core Audio decodes on the target system. FLAC and Ogg are
    // deliberately absent: running on that system ranks above format coverage.
    return @[@"mp3", @"m4a", @"m4b", @"aac", @"aif", @"aiff", @"aifc", @"wav", @"caf"];
}

#pragma mark - Storage

// BTUNES_LIBRARY_DIR is what the command line tools and the checks point at a
// throwaway library. Setting HOME does not work for this, since the search path
// below comes from the user record rather than the environment.
static NSString *BTEnvironmentLibraryDirectory(void) {
    const char *override = getenv("BTUNES_LIBRARY_DIR");
    if (override == NULL || strlen(override) == 0) return nil;
    return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:override
                                                                       length:strlen(override)];
}

// Where a database may be sitting from before BTunes kept everything under one
// home, in the order those places used to be looked at: chosen in preferences,
// beside the application, then Application Support. The folder beside the
// application is how a copy was run on another machine without disturbing the
// library already there, so on the machine BTunes is exercised on it is the one
// holding the real database rather than the Application Support folder.
+ (NSArray *)formerDatabaseFolders {
    NSMutableArray *folders = [NSMutableArray array];

    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"BTDatabaseFolder"];
    if ([saved length] > 0) [folders addObject:saved];

    [folders addObject:[[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent]
                        stringByAppendingPathComponent:@"BTunes Library"]];

    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *base = [dirs count] > 0 ? [dirs objectAtIndex:0] : NSTemporaryDirectory();
    [folders addObject:[base stringByAppendingPathComponent:@"BTunes"]];

    return folders;
}

- (NSString *)supportDirectory {
    // The environment wins over everything, so a test run cannot be sent at a
    // real library by whatever happens to be saved in preferences or written in
    // the config file. Below that it is the settings' business, and they fall
    // back to the folder inside the home on their own.
    NSString *dir = BTEnvironmentLibraryDirectory();
    if (dir == nil) dir = [[BTPreferences sharedPreferences] databaseFolder];

    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:NULL];
    return dir;
}

- (NSString *)libraryFilePath {
    return [[self supportDirectory] stringByAppendingPathComponent:@"btunes_library.json"];
}

// What the database was called before it was given a name of its own. A folder
// holding one is carried over the first time it is opened, since walking past it
// and starting empty would look exactly like losing every rating in it.
- (NSString *)formerLibraryFilePath {
    return [[self supportDirectory] stringByAppendingPathComponent:@"library.json"];
}

// Renamed rather than copied, so there is one database afterwards and no second
// copy left to diverge from it or to be opened by mistake. A rename that fails
// is not fatal: the library is in hand either way and the next save writes it
// out under the name it should have.
- (void)adoptFormerLibraryFile {
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *former = [self formerLibraryFilePath];
    NSString *current = [self libraryFilePath];

    if ([files fileExistsAtPath:current]) return;
    if (![files fileExistsAtPath:former]) return;

    NSError *error = nil;
    if ([files moveItemAtPath:former toPath:current error:&error]) {
        NSLog(@"BTunes: carried the library over from %@", [former lastPathComponent]);
    } else {
        NSLog(@"BTunes: could not rename %@ (%@)", former, [error localizedDescription]);
    }
}

// The database file, under either name it has had.
+ (NSArray *)databaseFileNames {
    return @[@"btunes_library.json", @"library.json"];
}

// Moves a database out of the first of the given folders that holds one and
// into the destination, and answers where it came from. Nothing found, or a
// database already at the destination, answers nil and moves nothing.
//
// The first folder holding one wins and no later folder is looked at. The order
// they arrive in is the order they used to be resolved in, so the first is the
// one the application would have opened; a later one is an older copy, and
// preferring it would quietly restore a database from months ago.
//
// Moved rather than copied, so there is one database afterwards and no second
// copy left to diverge from it. A move that fails leaves everything where it
// was and answers nil, which is the reading that keeps working.
+ (NSString *)moveDatabaseIntoFolder:(NSString *)destination fromAnyOf:(NSArray *)folders {
    NSFileManager *files = [NSFileManager defaultManager];
    NSArray *names = [self databaseFileNames];
    NSString *standardDestination = [destination stringByStandardizingPath];
    NSUInteger i, n;

    for (i = 0; i < [names count]; i++) {
        NSString *there = [standardDestination stringByAppendingPathComponent:[names objectAtIndex:i]];
        if ([files fileExistsAtPath:there]) return nil;
    }

    for (i = 0; i < [folders count]; i++) {
        NSString *folder = [[folders objectAtIndex:i] stringByStandardizingPath];
        if ([folder isEqualToString:standardDestination]) continue;

        for (n = 0; n < [names count]; n++) {
            NSString *from = [folder stringByAppendingPathComponent:[names objectAtIndex:n]];
            if (![files fileExistsAtPath:from]) continue;

            NSError *error = nil;
            [files createDirectoryAtPath:standardDestination
            withIntermediateDirectories:YES attributes:nil error:NULL];

            // Under the current name whichever name it arrived under, so the
            // rename and the move do not have to happen in two steps.
            NSString *to = [standardDestination stringByAppendingPathComponent:
                            [names objectAtIndex:0]];
            if (![files moveItemAtPath:from toPath:to error:&error]) {
                NSLog(@"BTunes: could not move %@ to %@ (%@)",
                      from, to, [error localizedDescription]);
                return nil;
            }

            // The log is BTunes' own and belongs beside the database. It is
            // rewritten whenever anything is missing, so failing to bring it
            // over costs nothing and is not worth reporting.
            NSString *log = [folder stringByAppendingPathComponent:@"missing-files.log"];
            if ([files fileExistsAtPath:log]) {
                [files moveItemAtPath:log
                               toPath:[standardDestination stringByAppendingPathComponent:
                                       @"missing-files.log"]
                                error:NULL];
            }

            NSLog(@"BTunes: moved the library from %@ to %@", from, to);
            return folder;
        }
    }
    return nil;
}

// Brings the database under the BTunes home the first time a version that keeps
// it there runs, and forgets the folder that was chosen when it did not.
//
// Once, not on every launch. A database folder chosen after this has run is a
// deliberate choice and is left alone; moving it back every time would make the
// setting look as though it did nothing.
//
// A library pointed at by the environment is left exactly where it is. That
// override is what the headless tools and the checks use to work on a throwaway
// library, and a throwaway library is the last thing that should be moved
// somewhere permanent.
+ (void)moveDatabaseIntoTheHome {
    if (BTEnvironmentLibraryDirectory()) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:BTMovedIntoTheHomeKey]) return;

    BTPreferences *prefs = [BTPreferences sharedPreferences];
    NSString *destination = [prefs defaultDatabaseFolder];
    [self moveDatabaseIntoFolder:destination fromAnyOf:[self formerDatabaseFolders]];

    // The old choice is dropped only once the database is demonstrably at the
    // destination. A move that failed leaves the setting as the only thing
    // still pointing at the database, so clearing it there would lose the
    // library rather than consolidate it, and the next launch tries again.
    if (![self databaseIsInFolder:destination]) {
        NSLog(@"BTunes: nothing was moved into %@ and the old location still stands", destination);
        return;
    }

    [prefs forgetSavedDatabaseFolder];
    [defaults setBool:YES forKey:BTMovedIntoTheHomeKey];
}

+ (BOOL)databaseIsInFolder:(NSString *)folder {
    NSFileManager *files = [NSFileManager defaultManager];
    NSArray *names = [self databaseFileNames];
    NSUInteger i;
    for (i = 0; i < [names count]; i++) {
        if ([files fileExistsAtPath:[folder stringByAppendingPathComponent:
                                     [names objectAtIndex:i]]]) return YES;
    }
    return NO;
}

- (NSString *)missingFilesLogPath {
    return [[self supportDirectory] stringByAppendingPathComponent:@"missing-files.log"];
}

- (NSArray *)tracksWithMissingFiles {
    NSFileManager *files = [NSFileManager defaultManager];
    NSMutableArray *gone = [NSMutableArray array];
    NSUInteger i;
    for (i = 0; i < [self.tracks count]; i++) {
        BTTrack *track = [self.tracks objectAtIndex:i];
        NSString *path = [track resolvedPath];
        if ([path length] == 0 || ![files fileExistsAtPath:path]) [gone addObject:track];
    }
    return gone;
}

// Every one of them, however many, with the path each was looked for at. The
// dialog names a handful; this is what to read when the handful is not enough.
- (NSString *)writeMissingFilesLog:(NSArray *)tracks {
    NSDateFormatter *stamp = [[NSDateFormatter alloc] init];
    [stamp setDateFormat:@"yyyy-MM-dd HH:mm:ss"];

    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"BTunes, %@\n", [stamp stringFromDate:[NSDate date]]];
    [text appendFormat:@"%lu of %lu songs are not where the library says they are.\n\n",
                       (unsigned long)[tracks count], (unsigned long)[self.tracks count]];
    [text appendString:@"Nothing has been removed from the library. The ratings, play counts\n"
                       @"and playlist membership are all still here, waiting for the files.\n\n"];

    NSUInteger i;
    for (i = 0; i < [tracks count]; i++) {
        BTTrack *track = [tracks objectAtIndex:i];
        [text appendFormat:@"%@ - %@\n    %@\n",
                           [track displayArtist], [track displayTitle],
                           ([track resolvedPath] ?: @"(no path recorded)")];
    }

    NSString *path = [self missingFilesLogPath];
    NSError *error = nil;
    if (![text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"BTunes: could not write %@ (%@)", path, [error localizedDescription]);
        return nil;
    }
    return path;
}

- (void)loadFromDisk {
    [self adoptFormerLibraryFile];

    NSData *data = [NSData dataWithContentsOfFile:[self libraryFilePath]];
    // The rename is the ordinary path and this is the one where it failed, so
    // the database is read from wherever it actually is.
    if (data == nil) data = [NSData dataWithContentsOfFile:[self formerLibraryFilePath]];
    if (data == nil) return;

    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![root isKindOfClass:[NSDictionary class]]) return;

    [self.tracks removeAllObjects];
    [self.playlists removeAllObjects];
    [self.knownPaths removeAllObjects];
    [self.excluded removeAllObjects];

    NSArray *left = [root objectForKey:@"excludedFromImport"];
    if ([left isKindOfClass:[NSArray class]]) [self.excluded addObjectsFromArray:left];

    NSUInteger i;
    NSArray *trackDicts = [root objectForKey:@"tracks"];
    if ([trackDicts isKindOfClass:[NSArray class]]) {
        for (i = 0; i < [trackDicts count]; i++) {
            [self addTrack:[BTTrack trackWithDictionary:[trackDicts objectAtIndex:i]]];
        }
    }

    NSArray *playlistDicts = [root objectForKey:@"playlists"];
    if ([playlistDicts isKindOfClass:[NSArray class]]) {
        for (i = 0; i < [playlistDicts count]; i++) {
            [self.playlists addObject:[BTPlaylist playlistWithDictionary:[playlistDicts objectAtIndex:i]]];
        }
    }
}

- (void)saveToDisk {
    NSUInteger i;
    NSMutableArray *trackDicts = [NSMutableArray arrayWithCapacity:[self.tracks count]];
    for (i = 0; i < [self.tracks count]; i++) {
        [trackDicts addObject:[[self.tracks objectAtIndex:i] dictionaryRepresentation]];
    }
    NSMutableArray *playlistDicts = [NSMutableArray arrayWithCapacity:[self.playlists count]];
    for (i = 0; i < [self.playlists count]; i++) {
        [playlistDicts addObject:[[self.playlists objectAtIndex:i] dictionaryRepresentation]];
    }

    NSDictionary *root = @{@"version": @1,
                           @"tracks": trackDicts,
                           @"playlists": playlistDicts,
                           @"excludedFromImport": [self.excluded allObjects]};
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:NULL];
    if (data) [data writeToFile:[self libraryFilePath] atomically:YES];
}

// The library is written on a delay so a run of edits costs one write. Both
// kinds of change schedule it the same way; they differ only in what they tell
// the window to do about it.
- (void)scheduleSave {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(saveToDisk) object:nil];
    [self performSelector:@selector(saveToDisk) withObject:nil afterDelay:2.0];
}

- (void)noteChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:BTLibraryDidChangeNotification object:self];
    [self scheduleSave];
}

- (void)noteTrackChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:BTLibraryTrackDidChangeNotification object:self];
    [self scheduleSave];
}

#pragma mark - Left behind on purpose

- (NSSet *)excludedFromImport {
    return [NSSet setWithSet:self.excluded];
}

- (void)setExcluded:(BOOL)excluded forPersistentIDs:(NSArray *)persistentIDs {
    if ([persistentIDs count] == 0) return;
    if (excluded) {
        [self.excluded addObjectsFromArray:persistentIDs];
    } else {
        [self.excluded minusSet:[NSSet setWithArray:persistentIDs]];
    }
    [self noteChanged];
}

#pragma mark - Lookup

// The one way in. A track whose path does not resolve is still held, since a
// missing file is not a reason to lose the ratings hanging off it; it simply
// contributes nothing to the record of what is already here.
- (void)addTrack:(BTTrack *)track {
    if (track == nil) return;
    [self.tracks addObject:track];
    NSString *resolved = [track resolvedPath];
    if ([resolved length] > 0) [self.knownPaths addObject:resolved];
}

- (BTTrack *)trackWithFileAtPath:(NSString *)path {
    if ([path length] == 0) return nil;
    // Only worth walking the library when the set says the file is in it, which
    // it usually is not.
    if (![self.knownPaths containsObject:path]) return nil;

    NSUInteger i;
    for (i = 0; i < [self.tracks count]; i++) {
        BTTrack *track = [self.tracks objectAtIndex:i];
        if ([[track resolvedPath] isEqualToString:path]) return track;
    }
    return nil;
}

- (void)removeTracks:(NSArray *)tracks {
    NSMutableArray *goneIDs = [NSMutableArray arrayWithCapacity:[tracks count]];
    NSUInteger i;
    for (i = 0; i < [tracks count]; i++) {
        BTTrack *t = [tracks objectAtIndex:i];
        NSString *resolved = [t resolvedPath];
        if ([resolved length] > 0) [self.knownPaths removeObject:resolved];
        [self.tracks removeObject:t];
        if (t.trackID) [goneIDs addObject:t.trackID];
    }

    // Out of every playlist that holds them, folders included.
    [BTPlaylist enumerate:self.playlists usingBlock:^(BTPlaylist *playlist, BOOL *stop) {
        [playlist.trackIDs removeObjectsInArray:goneIDs];
    }];
    [self noteChanged];
}

#pragma mark - Playlists

- (void)addPlaylist:(BTPlaylist *)playlist toFolder:(BTPlaylist *)folder {
    if (folder && folder.kind == BTPlaylistKindFolder) {
        playlist.parent = folder;
        [folder.children addObject:playlist];
    } else {
        playlist.parent = nil;
        [self.playlists addObject:playlist];
    }
    [self noteChanged];
}

- (void)removePlaylist:(BTPlaylist *)playlist {
    if (playlist.parent) {
        [playlist.parent.children removeObject:playlist];
    } else {
        [self.playlists removeObject:playlist];
    }
    [self noteChanged];
}

- (void)movePlaylist:(BTPlaylist *)playlist toFolder:(BTPlaylist *)folder atIndex:(NSInteger)index {
    if (folder == playlist || [folder isDescendantOf:playlist]) return;

    NSMutableArray *source = playlist.parent ? playlist.parent.children : self.playlists;
    NSMutableArray *destination = folder ? folder.children : self.playlists;
    NSInteger current = (NSInteger)[source indexOfObject:playlist];
    if (current == (NSInteger)NSNotFound) return;

    if (source == destination && index > current) index -= 1;
    [source removeObjectAtIndex:current];

    if (index < 0 || index > (NSInteger)[destination count]) index = (NSInteger)[destination count];
    [destination insertObject:playlist atIndex:index];
    playlist.parent = folder;
    [self noteChanged];
}

- (BTPlaylist *)playlistWithID:(NSString *)playlistID {
    __block BTPlaylist *found = nil;
    [BTPlaylist enumerate:self.playlists usingBlock:^(BTPlaylist *p, BOOL *stop) {
        if ([p.playlistID isEqualToString:playlistID]) {
            found = p;
            *stop = YES;
        }
    }];
    return found;
}

#pragma mark - Import

- (NSString *)kindForURL:(NSURL *)url asset:(AVURLAsset *)asset {
    NSString *ext = [[url pathExtension] lowercaseString];
    if ([ext isEqualToString:@"mp3"]) return @"MPEG audio file";
    if ([ext isEqualToString:@"wav"]) return @"WAV audio file";
    if ([ext isEqualToString:@"caf"]) return @"CAF audio file";
    if ([ext hasPrefix:@"aif"]) return @"AIFF audio file";

    // Inside an MPEG-4 container, tell Apple Lossless from AAC.
    NSArray *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    if ([audioTracks count] > 0) {
        AVAssetTrack *at = [audioTracks objectAtIndex:0];
        NSArray *descs = [at formatDescriptions];
        if ([descs count] > 0) {
            CMAudioFormatDescriptionRef desc = (__bridge CMAudioFormatDescriptionRef)[descs objectAtIndex:0];
            const AudioStreamBasicDescription *absd = CMAudioFormatDescriptionGetStreamBasicDescription(desc);
            if (absd) {
                if (absd->mFormatID == kAudioFormatAppleLossless) return @"Apple Lossless audio file";
                if (absd->mFormatID == kAudioFormatMPEG4AAC) return @"AAC audio file";
            }
        }
    }
    return @"AAC audio file";
}

- (NSString *)stringFromMetadata:(NSArray *)items key:(NSString *)key keySpace:(NSString *)space {
    NSArray *found = [AVMetadataItem metadataItemsFromArray:items withKey:key keySpace:space];
    if ([found count] == 0) return nil;
    AVMetadataItem *item = [found objectAtIndex:0];
    id value = [item value];
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return nil;
}

- (NSString *)firstStringForKeys:(NSDictionary *)keysBySpace inAsset:(AVURLAsset *)asset {
    NSArray *spaces = [keysBySpace allKeys];
    NSUInteger i;
    for (i = 0; i < [spaces count]; i++) {
        NSString *space = [spaces objectAtIndex:i];
        NSArray *items = [asset metadataForFormat:space];
        if ([items count] == 0) continue;
        NSArray *keys = [keysBySpace objectForKey:space];
        NSUInteger j;
        for (j = 0; j < [keys count]; j++) {
            NSString *s = [self stringFromMetadata:items key:[keys objectAtIndex:j] keySpace:space];
            if ([s length] > 0) return s;
        }
    }
    return nil;
}

- (BTTrack *)trackByReadingFileAtURL:(NSURL *)url {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    if (asset == nil) return nil;

    BTTrack *t = [[BTTrack alloc] init];
    t.trackID = [[NSUUID UUID] UUIDString];
    t.path = [[url path] stringByStandardizingPath];
    t.duration = CMTimeGetSeconds([asset duration]);
    if (isnan(t.duration) || t.duration < 0) t.duration = 0;
    t.kind = [self kindForURL:url asset:asset];
    t.dateAdded = [NSDate date];

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:NULL];
    t.fileSize = (long long)[[attrs objectForKey:NSFileSize] longLongValue];

    NSArray *common = [asset commonMetadata];
    t.title = [self stringFromMetadata:common key:AVMetadataCommonKeyTitle keySpace:AVMetadataKeySpaceCommon];
    t.artist = [self stringFromMetadata:common key:AVMetadataCommonKeyArtist keySpace:AVMetadataKeySpaceCommon];
    t.album = [self stringFromMetadata:common key:AVMetadataCommonKeyAlbumName keySpace:AVMetadataKeySpaceCommon];

    t.genre = [self firstStringForKeys:@{
        AVMetadataFormatiTunesMetadata: @[AVMetadataiTunesMetadataKeyUserGenre, AVMetadataiTunesMetadataKeyPredefinedGenre],
        AVMetadataFormatID3Metadata: @[AVMetadataID3MetadataKeyContentType]
    } inAsset:asset];

    t.composer = [self firstStringForKeys:@{
        AVMetadataFormatiTunesMetadata: @[AVMetadataiTunesMetadataKeyComposer],
        AVMetadataFormatID3Metadata: @[AVMetadataID3MetadataKeyComposer]
    } inAsset:asset];

    t.albumArtist = [self firstStringForKeys:@{
        AVMetadataFormatiTunesMetadata: @[AVMetadataiTunesMetadataKeyAlbumArtist],
        AVMetadataFormatID3Metadata: @[AVMetadataID3MetadataKeyBand]
    } inAsset:asset];

    NSString *yearString = [self firstStringForKeys:@{
        AVMetadataFormatiTunesMetadata: @[AVMetadataiTunesMetadataKeyReleaseDate],
        AVMetadataFormatID3Metadata: @[AVMetadataID3MetadataKeyYear, AVMetadataID3MetadataKeyRecordingTime]
    } inAsset:asset];
    if ([yearString length] >= 4) t.year = [[yearString substringToIndex:4] integerValue];

    NSString *trackString = [self firstStringForKeys:@{
        AVMetadataFormatID3Metadata: @[AVMetadataID3MetadataKeyTrackNumber]
    } inAsset:asset];
    if ([trackString length] > 0) t.trackNumber = [trackString integerValue];

    // The iTunes track-number tag is binary: a short vector of index and count.
    NSArray *itunesItems = [asset metadataForFormat:AVMetadataFormatiTunesMetadata];
    NSArray *trackItems = [AVMetadataItem metadataItemsFromArray:itunesItems
                                                        withKey:AVMetadataiTunesMetadataKeyTrackNumber
                                                       keySpace:AVMetadataKeySpaceiTunes];
    if ([trackItems count] > 0) {
        AVMetadataItem *trackItem = [trackItems objectAtIndex:0];
        id value = [trackItem value];
        if ([value isKindOfClass:[NSData class]] && [(NSData *)value length] >= 4) {
            const unsigned char *bytes = [(NSData *)value bytes];
            t.trackNumber = (NSInteger)((bytes[2] << 8) | bytes[3]);
        } else if ([value respondsToSelector:@selector(integerValue)]) {
            t.trackNumber = [value integerValue];
        }
    }

    // How loud the recording is, while the file is open anyway. Songs that
    // arrive through the iTunes sync never come past here, since that reads the
    // XML rather than the files, and are asked as they are first played.
    [BTSoundCheck fillInTrack:t fromAsset:asset];

    return t;
}

- (void)importPaths:(NSArray *)paths completion:(void (^)(NSUInteger added))completion {
    NSArray *extensions = [BTLibrary supportedExtensions];
    NSSet *existing = [NSSet setWithSet:self.knownPaths];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *files = [NSMutableArray array];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSUInteger i;

        for (i = 0; i < [paths count]; i++) {
            NSString *path = [paths objectAtIndex:i];
            BOOL isDirectory = NO;
            if (![fm fileExistsAtPath:path isDirectory:&isDirectory]) continue;

            if (isDirectory) {
                NSDirectoryEnumerator *e = [fm enumeratorAtPath:path];
                NSString *sub;
                while ((sub = [e nextObject]) != nil) {
                    NSString *full = [path stringByAppendingPathComponent:sub];
                    if ([extensions containsObject:[[full pathExtension] lowercaseString]]) {
                        [files addObject:full];
                    }
                }
            } else if ([extensions containsObject:[[path pathExtension] lowercaseString]]) {
                [files addObject:path];
            }
        }

        NSMutableArray *newTracks = [NSMutableArray array];
        for (i = 0; i < [files count]; i++) {
            NSString *file = [[files objectAtIndex:i] stringByStandardizingPath];
            if ([existing containsObject:file]) continue;

            BTTrack *t = [self trackByReadingFileAtURL:[NSURL fileURLWithPath:file]];
            if (t == nil) continue;
            [newTracks addObject:t];

        }

        dispatch_async(dispatch_get_main_queue(), ^{
            NSUInteger j;
            for (j = 0; j < [newTracks count]; j++) {
                [self addTrack:[newTracks objectAtIndex:j]];
            }
            [self noteChanged];
            if (completion) completion([newTracks count]);
        });
    });
}

@end
