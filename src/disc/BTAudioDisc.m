#import "BTAudioDisc.h"
#import "BTTrack.h"
#import <AppKit/AppKit.h>
#import <sys/param.h>
#import <sys/mount.h>

NSString *const BTAudioDiscDidChangeNotification = @"BTAudioDiscDidChange";

// What cddafs falls back to when the disc says nothing about itself. Taken from
// the filesystem's own strings, so these are the words it will actually use.
static NSString *const BTUnnamedTrack = @"Audio Track";
static NSString *const BTUnnamedDisc = @"Audio CD";
static NSString *const BTNameSeparator = @" - ";

// Red Book: 44100 samples a second, two channels, two bytes each. A track's
// length is its size, because there is nothing else in the file worth counting.
#define BT_CD_BYTES_PER_SECOND 176400.0

@interface BTAudioDisc ()
@property (nonatomic, copy) NSString *mountPath;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, strong) NSArray *tracks;
@property (nonatomic, assign) BOOL named;
@end

@implementation BTAudioDisc

#pragma mark - Reading a disc

// "7 Peter Gabriel - Solsbury Hill.aiff" comes apart into the number, the
// artist and the title. "7 Audio Track.aiff" comes apart into the number and
// nothing, which is what a disc with no CD-Text gives.
//
// The title is whatever is left after the artist, rather than the last piece, so
// a song with a dash in its name keeps it.
static void BTReadTrackName(NSString *filename, NSInteger *outNumber,
                            NSString **outArtist, NSString **outTitle) {
    *outNumber = 0;
    *outArtist = nil;
    *outTitle = nil;

    NSString *stem = [filename stringByDeletingPathExtension];
    NSScanner *scanner = [NSScanner scannerWithString:stem];
    NSInteger number = 0;
    if (![scanner scanInteger:&number]) return;
    *outNumber = number;

    NSString *rest = [[stem substringFromIndex:[scanner scanLocation]]
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([rest length] == 0 || [rest isEqualToString:BTUnnamedTrack]) return;

    NSRange split = [rest rangeOfString:BTNameSeparator];
    if (split.location == NSNotFound) {
        *outTitle = rest;
        return;
    }
    *outArtist = [rest substringToIndex:split.location];
    *outTitle = [rest substringFromIndex:NSMaxRange(split)];
}

+ (BTAudioDisc *)discAtMountPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *entries = [fm contentsOfDirectoryAtPath:path error:NULL];
    if (entries == nil) return nil;

    NSMutableArray *files = [NSMutableArray array];
    NSUInteger i;
    for (i = 0; i < [entries count]; i++) {
        NSString *entry = [entries objectAtIndex:i];
        if ([[entry pathExtension] caseInsensitiveCompare:@"aiff"] == NSOrderedSame) {
            [files addObject:entry];
        }
    }
    if ([files count] == 0) return nil;

    BTAudioDisc *disc = [[BTAudioDisc alloc] init];
    disc.mountPath = path;

    NSString *volume = [path lastPathComponent];
    disc.name = volume;
    if (![volume isEqualToString:BTUnnamedDisc]) disc.album = volume;

    NSMutableArray *tracks = [NSMutableArray array];
    NSMutableSet *artists = [NSMutableSet set];
    BOOL anyNamed = NO;

    for (i = 0; i < [files count]; i++) {
        NSString *filename = [files objectAtIndex:i];
        NSInteger number = 0;
        NSString *artist = nil, *title = nil;
        BTReadTrackName(filename, &number, &artist, &title);
        if (number <= 0) continue;

        NSString *full = [path stringByAppendingPathComponent:filename];

        BTTrack *track = [[BTTrack alloc] init];
        // Not a library id: nothing keeps these, and a playlist cannot hold one.
        // It only has to tell one row of the list from another.
        track.trackID = [NSString stringWithFormat:@"disc:%@:%ld", volume, (long)number];
        track.path = full;
        track.trackNumber = number;
        track.kind = @"AIFF audio file";
        track.album = disc.album;
        track.artist = artist;
        if ([title length] > 0) {
            track.title = title;
            anyNamed = YES;
        } else {
            track.title = [NSString stringWithFormat:@"Track %ld", (long)number];
        }
        if ([artist length] > 0) [artists addObject:artist];

        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:NULL];
        long long size = [[attrs objectForKey:NSFileSize] longLongValue];
        track.fileSize = size;
        track.duration = (size > 0) ? (NSTimeInterval)(size / BT_CD_BYTES_PER_SECOND) : 0;

        [tracks addObject:track];
    }
    if ([tracks count] == 0) return nil;

    [tracks sortUsingComparator:^NSComparisonResult(BTTrack *a, BTTrack *b) {
        if (a.trackNumber < b.trackNumber) return NSOrderedAscending;
        if (a.trackNumber > b.trackNumber) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    // One artist across the disc is the disc's artist. Several is a compilation,
    // and naming one of them for the whole thing would be wrong.
    if ([artists count] == 1) disc.artist = [artists anyObject];

    disc.tracks = tracks;
    disc.named = anyNamed;
    return disc;
}

#pragma mark - Finding one

// Only cddafs means an audio CD. A data CD, a DVD and a memory stick are all
// volumes too, and none of them is this.
+ (BOOL)isAudioCDVolume:(NSString *)path {
    struct statfs info;
    if (statfs([path fileSystemRepresentation], &info) != 0) return NO;
    return strcmp(info.f_fstypename, "cddafs") == 0;
}

+ (BTAudioDisc *)insertedDisc {
    // A folder standing in for a disc, so the whole of this can be looked at
    // without one in the drive. The same seam BTUNES_LIBRARY_DIR is, and read
    // the same way: only ever set by a harness.
    NSString *standIn = [[[NSProcessInfo processInfo] environment] objectForKey:@"BTUNES_DISC_PATH"];
    if ([standIn length] > 0) return [self discAtMountPath:standIn];

    NSArray *volumes = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Volumes" error:NULL];
    NSUInteger i;
    for (i = 0; i < [volumes count]; i++) {
        NSString *path = [@"/Volumes" stringByAppendingPathComponent:[volumes objectAtIndex:i]];
        if (![self isAudioCDVolume:path]) continue;
        BTAudioDisc *disc = [self discAtMountPath:path];
        if (disc) return disc;
    }
    return nil;
}

+ (void)startWatching {
    NSNotificationCenter *nc = [[NSWorkspace sharedWorkspace] notificationCenter];
    void (^changed)(NSNotification *) = ^(NSNotification *note) {
        [[NSNotificationCenter defaultCenter] postNotificationName:BTAudioDiscDidChangeNotification
                                                            object:nil];
    };
    [nc addObserverForName:NSWorkspaceDidMountNotification object:nil queue:nil usingBlock:changed];
    [nc addObserverForName:NSWorkspaceDidUnmountNotification object:nil queue:nil usingBlock:changed];
}

- (BOOL)eject {
    return [[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtPath:self.mountPath];
}

@end
