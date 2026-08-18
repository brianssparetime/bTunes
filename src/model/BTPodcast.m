#import "BTPodcast.h"

#import <AVFoundation/AVFoundation.h>

#import "BTLibrary.h"
#import "BTPreferences.h"
#import "BTTrack.h"

// The description file each show folder carries. Written by hand or by the
// tools; read here and never written.
static NSString *const BTPodcastFileName = @"podcast.json";

@implementation BTPodcast {
    NSString *_name;
    NSString *_author;
    NSString *_folderName;
    NSMutableArray *_episodes;
    // Keyed by track id, which is built from the filename and so is the one
    // thing the description file and the disk agree on.
    NSMutableDictionary *_synopses;
    NSMutableDictionary *_synopsisSources;
    NSMutableDictionary *_airDates;
    NSMutableDictionary *_numbers;
    BOOL _durationsAreKnown;
}

- (NSString *)name       { return _name; }
- (NSString *)author     { return _author; }
- (NSString *)folderName { return _folderName; }
- (NSArray *)episodes    { return _episodes; }
- (BOOL)durationsAreKnown { return _durationsAreKnown; }

#pragma mark - Reading a folder

// The id is built from the path rather than generated, so an episode keeps the
// same identity across launches. Anything later recording a play count or a
// rating against an episode needs that to be true.
static NSString *BTEpisodeID(NSString *folderName, NSString *fileName) {
    return [NSString stringWithFormat:@"podcast:%@/%@", folderName, fileName];
}

// The number a show writes at the front of a filename: "029 - ", "003a - ",
// "01 - ". The letter belongs to the number, because it is the whole of what
// tells one part from the next. A name starting with a word, such as a bonus
// episode, has no number and says so.
static NSString *BTNumberFromFileName(NSString *fileName) {
    NSUInteger i = 0, length = [fileName length];
    while (i < length && [[NSCharacterSet decimalDigitCharacterSet]
                          characterIsMember:[fileName characterAtIndex:i]]) {
        i++;
    }
    if (i == 0) return nil;

    if (i < length) {
        unichar next = [fileName characterAtIndex:i];
        if ([[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:next]) i++;
    }
    return [fileName substringToIndex:i];
}

+ (NSDateFormatter *)airDateFormatter {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        // Fixed format and fixed locale: the dates in the file are ISO, and a
        // formatter left on the user's locale reads them differently depending
        // on where the machine thinks it is.
        [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
        [formatter setDateFormat:@"yyyy-MM-dd"];
        [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
    });
    return formatter;
}

- (instancetype)initWithFolder:(NSString *)folderPath {
    self = [super init];
    if (self == nil) return nil;

    NSFileManager *fm = [NSFileManager defaultManager];
    _folderName = [folderPath lastPathComponent];
    _name = _folderName;
    _author = @"";
    _episodes = [NSMutableArray array];
    _synopses = [NSMutableDictionary dictionary];
    _synopsisSources = [NSMutableDictionary dictionary];
    _airDates = [NSMutableDictionary dictionary];
    _numbers = [NSMutableDictionary dictionary];

    NSDictionary *described = [self describedEpisodesInFolder:folderPath];

    // The disk decides which episodes exist. The description file only says
    // more about the ones that are there: a file listed but missing is not an
    // episode, and a file present but unlisted still is.
    NSArray *names = [fm contentsOfDirectoryAtPath:folderPath error:NULL];
    NSArray *audioExtensions = [BTLibrary supportedExtensions];
    NSArray *sorted = [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];

    NSUInteger i;
    for (i = 0; i < [sorted count]; i++) {
        NSString *fileName = [sorted objectAtIndex:i];
        if ([fileName hasPrefix:@"."]) continue;
        NSString *extension = [[fileName pathExtension] lowercaseString];
        if (![audioExtensions containsObject:extension]) continue;

        NSDictionary *described1 = [described objectForKey:fileName];
        [_episodes addObject:[self episodeWithFileName:fileName described:described1]];
    }

    return ([_episodes count] > 0) ? self : nil;
}

// The description file, turned into a lookup by filename. Anything malformed
// reads as a show with no description file rather than stopping the scan: one
// unreadable folder should not cost the others.
- (NSDictionary *)describedEpisodesInFolder:(NSString *)folderPath {
    NSString *path = [folderPath stringByAppendingPathComponent:BTPodcastFileName];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil) return @{};

    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![parsed isKindOfClass:[NSDictionary class]]) return @{};

    NSString *name = [parsed objectForKey:@"name"];
    if ([name isKindOfClass:[NSString class]] && [name length] > 0) _name = [name copy];
    NSString *author = [parsed objectForKey:@"author"];
    if ([author isKindOfClass:[NSString class]]) _author = [author copy];

    id episodes = [parsed objectForKey:@"episodes"];
    if (![episodes isKindOfClass:[NSArray class]]) return @{};

    NSMutableDictionary *byFile = [NSMutableDictionary dictionary];
    NSUInteger i;
    for (i = 0; i < [episodes count]; i++) {
        id entry = [episodes objectAtIndex:i];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *file = [entry objectForKey:@"file"];
        if (![file isKindOfClass:[NSString class]] || [file length] == 0) continue;
        [byFile setObject:entry forKey:file];
    }
    return byFile;
}

- (BTTrack *)episodeWithFileName:(NSString *)fileName described:(NSDictionary *)described {
    BTTrack *track = [[BTTrack alloc] init];
    NSString *episodeID = BTEpisodeID(_folderName, fileName);
    track.trackID = episodeID;
    [track setPath:[_folderName stringByAppendingPathComponent:fileName]
              root:BTPathRootPodcasts];

    NSString *title = [described objectForKey:@"title"];
    if (![title isKindOfClass:[NSString class]] || [title length] == 0) {
        title = [fileName stringByDeletingPathExtension];
    }
    track.title = title;
    track.artist = _author;
    track.album = _name;
    track.genre = @"Podcast";

    NSString *number = BTNumberFromFileName(fileName);
    if (number) [_numbers setObject:number forKey:episodeID];

    NSString *airDate = [described objectForKey:@"airDate"];
    if ([airDate isKindOfClass:[NSString class]] && [airDate length] > 0) {
        NSDate *date = [[[self class] airDateFormatter] dateFromString:airDate];
        if (date) {
            [_airDates setObject:date forKey:episodeID];
            // The year column is the only place the library already has to put
            // a date that belongs to the recording rather than to this machine.
            NSDateComponents *parts =
                [[NSCalendar currentCalendar] components:NSCalendarUnitYear fromDate:date];
            track.year = [parts year];
        }
    }

    NSString *synopsis = [described objectForKey:@"synopsis"];
    if ([synopsis isKindOfClass:[NSString class]] && [synopsis length] > 0) {
        [_synopses setObject:synopsis forKey:episodeID];
        NSString *source = [described objectForKey:@"synopsisSource"];
        if ([source isKindOfClass:[NSString class]]) {
            [_synopsisSources setObject:source forKey:episodeID];
        }
    }

    NSDictionary *attributes =
        [[NSFileManager defaultManager] attributesOfItemAtPath:[track resolvedPath] error:NULL];
    track.fileSize = (long long)[[attributes objectForKey:NSFileSize] longLongValue];

    return track;
}

+ (NSArray *)podcastsOnDisk {
    NSString *root = [[BTPreferences sharedPreferences] podcastsFolder];
    if ([root length] == 0) return @[];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [fm contentsOfDirectoryAtPath:root error:NULL];
    if (names == nil) return @[];

    NSMutableArray *found = [NSMutableArray array];
    NSArray *sorted = [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    NSUInteger i;
    for (i = 0; i < [sorted count]; i++) {
        NSString *folderName = [sorted objectAtIndex:i];
        if ([folderName hasPrefix:@"."]) continue;

        NSString *folderPath = [root stringByAppendingPathComponent:folderName];
        BOOL isFolder = NO;
        if (![fm fileExistsAtPath:folderPath isDirectory:&isFolder] || !isFolder) continue;

        BTPodcast *podcast = [[BTPodcast alloc] initWithFolder:folderPath];
        if (podcast) [found addObject:podcast];
    }
    return found;
}

#pragma mark - What the description file said

- (NSString *)synopsisForEpisode:(BTTrack *)episode {
    return [_synopses objectForKey:episode.trackID];
}

- (BOOL)synopsisIsLocalForEpisode:(BTTrack *)episode {
    NSString *source = [_synopsisSources objectForKey:episode.trackID];
    return [source isEqualToString:@"local"];
}

- (NSDate *)airDateForEpisode:(BTTrack *)episode {
    return [_airDates objectForKey:episode.trackID];
}

- (NSString *)episodeNumberForEpisode:(BTTrack *)episode {
    return [_numbers objectForKey:episode.trackID];
}

#pragma mark - Lengths

- (void)readDurations {
    if (_durationsAreKnown) return;

    NSUInteger i;
    for (i = 0; i < [_episodes count]; i++) {
        BTTrack *track = [_episodes objectAtIndex:i];
        if (track.duration > 0) continue;

        NSString *path = [track resolvedPath];
        if ([path length] == 0) continue;

        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
        NSTimeInterval seconds = CMTimeGetSeconds([asset duration]);
        if (isnan(seconds) || seconds < 0) seconds = 0;
        track.duration = seconds;
    }
    _durationsAreKnown = YES;
}

@end
