#import "BTBurnPlan.h"
#import "BTPlaylist.h"
#import "BTTrack.h"
#import <DiscRecording/DiscRecording.h>

const NSUInteger BTBurnSectorsPerSecond = 75;
const NSUInteger BTBurnNominalDiscSectors = 360000;   // 80 minutes, the standard blank

@interface BTBurnPlan ()
+ (BOOL)canBurnTrack:(BTTrack *)track;
@end

// A CD track is a whole number of sectors, so a song always costs at least the
// sector its last fraction of a second lands in.
static NSUInteger BTSectorsForSeconds(NSTimeInterval seconds) {
    if (seconds <= 0) return 0;
    return (NSUInteger)ceil(seconds * (double)BTBurnSectorsPerSecond);
}

@implementation BTBurnPlan {
    NSMutableArray *_songs;
    NSMutableArray *_unreadable;
    NSMutableArray *_trimmed;
}

@synthesize name = _name;
@synthesize gapSeconds = _gapSeconds;

+ (BOOL)canBurnPlaylist:(BTPlaylist *)playlist {
    if (playlist == nil) return NO;
    return (playlist.kind == BTPlaylistKindStatic || playlist.kind == BTPlaylistKindSmart);
}

+ (instancetype)planForPlaylist:(BTPlaylist *)playlist tracks:(NSArray *)allTracks {
    BTBurnPlan *plan = [[BTBurnPlan alloc] init];
    if (plan == nil) return nil;

    plan->_name = [playlist.name copy];
    plan->_gapSeconds = 2;
    plan->_songs = [NSMutableArray array];
    plan->_unreadable = [NSMutableArray array];
    plan->_trimmed = [NSMutableArray array];

    NSArray *resolved = [playlist resolveTracks:allTracks];
    NSUInteger i;
    for (i = 0; i < [resolved count]; i++) {
        BTTrack *track = [resolved objectAtIndex:i];
        if (![BTBurnPlan canBurnTrack:track]) {
            [plan->_unreadable addObject:track];
            continue;
        }
        [plan->_songs addObject:track];
        if (track.usesStartTime || track.usesEndTime) [plan->_trimmed addObject:track];
    }
    return plan;
}

// A locked purchase cannot be decoded, and a file that has gone cannot be read.
// Where detune has re-recorded a locked purchase the track already points at
// the recording, so nothing here has to know that happened.
+ (BOOL)canBurnTrack:(BTTrack *)track {
    if (track.isProtected) return NO;
    NSString *path = [track resolvedPath];
    if ([path length] == 0) return NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (NSArray *)songs { return _songs; }
- (NSArray *)unreadable { return _unreadable; }
- (NSArray *)trimmed { return _trimmed; }

#pragma mark - What it would take on a disc

// The whole file, not the part BTunes plays. A start or end time is a BTunes
// idea; the framework is handed a file and burns all of it.
- (NSTimeInterval)audioTime {
    NSTimeInterval total = 0;
    NSUInteger i;
    for (i = 0; i < [_songs count]; i++) {
        total += [[_songs objectAtIndex:i] duration];
    }
    return total;
}

- (NSTimeInterval)gapTime {
    if ([_songs count] < 2) return 0;
    return (NSTimeInterval)(([_songs count] - 1) * _gapSeconds);
}

- (NSTimeInterval)totalTime {
    return [self audioTime] + [self gapTime];
}

// Summed per song rather than off the total, since each song rounds up to a
// whole sector of its own.
- (NSUInteger)sectors {
    NSUInteger total = 0, i;
    for (i = 0; i < [_songs count]; i++) {
        total += BTSectorsForSeconds([[_songs objectAtIndex:i] duration]);
    }
    return total + BTSectorsForSeconds([self gapTime]);
}

#pragma mark - Whether it can be burned at all

- (BTBurnRefusal)refusal {
    if ([_unreadable count] > 0) return BTBurnRefusalUnreadable;
    if ([_songs count] == 0) return BTBurnRefusalEmpty;
    if ([self sectors] > BTBurnNominalDiscSectors) return BTBurnRefusalTooLong;
    return BTBurnRefusalNone;
}

- (NSString *)refusalText {
    switch ([self refusal]) {
        case BTBurnRefusalNone:
            return nil;

        case BTBurnRefusalEmpty:
            return @"There is nothing in this playlist to burn.";

        // A disc missing three songs is not the playlist, so the whole thing is
        // refused rather than quietly burning what is left.
        case BTBurnRefusalUnreadable: {
            NSUInteger count = [_unreadable count];
            BTTrack *first = [_unreadable objectAtIndex:0];
            if (count == 1) {
                return [NSString stringWithFormat:
                        @"\"%@\" cannot be read, so this playlist cannot be burned.",
                        [first displayTitle]];
            }
            return [NSString stringWithFormat:
                    @"%lu songs cannot be read, beginning with \"%@\", so this playlist "
                    @"cannot be burned.",
                    (unsigned long)count, [first displayTitle]];
        }

        case BTBurnRefusalTooLong:
            return [NSString stringWithFormat:
                    @"This playlist runs %@ with the gaps, and a disc holds %@.",
                    [BTBurnPlan stringFromSectors:[self sectors]],
                    [BTBurnPlan stringFromSectors:BTBurnNominalDiscSectors]];
    }
    return nil;
}

#pragma mark - Handing the framework the files

// Built fresh on every burn rather than kept from when the dialog opened. The
// window between the two is small, but a burn that starts and cannot finish
// wastes a disc.
- (NSArray *)buildTracks:(NSString **)reason {
    if (reason) *reason = nil;

    NSMutableArray *tracks = [NSMutableArray arrayWithCapacity:[_songs count]];
    NSUInteger i;
    for (i = 0; i < [_songs count]; i++) {
        BTTrack *song = [_songs objectAtIndex:i];
        NSURL *url = [song fileURL];

        DRAudioTrackRef ref = (url != nil)
            ? DRAudioTrackCreateWithURL((__bridge CFURLRef)url) : NULL;
        if (ref == NULL) {
            if (reason) {
                *reason = [NSString stringWithFormat:
                           @"\"%@\" could not be read as audio, so nothing has been written.",
                           [song displayTitle]];
            }
            return nil;
        }

        // ARC takes the reference the C call handed out, so the array owns the
        // tracks and nothing has to be released by hand.
        DRTrack *track = (__bridge_transfer DRTrack *)ref;

        // The gap sits between songs. The first track's pre-gap belongs to the
        // lead-in rather than to the playlist, so it is left as the framework
        // set it.
        if (i > 0) {
            [track setPreGap:[DRMSF msfWithFrames:(UInt32)(_gapSeconds * BTBurnSectorsPerSecond)]];
        }
        [tracks addObject:track];
    }

    if ([tracks count] == 0) {
        if (reason) *reason = @"There is nothing in this playlist to burn.";
        return nil;
    }
    return tracks;
}

// Index 0 is the disc, and the tracks follow in the order they are burned.
// Nearly free, since every value is already in hand.
- (DRCDTextBlock *)cdText {
    if ([_songs count] == 0) return nil;

    // CD-Text carries single-byte characters, so the block is built in Latin-1
    // and the framework converts what it is given.
    DRCDTextBlock *block = [DRCDTextBlock cdTextBlockWithLanguage:@"en"
                                                         encoding:NSISOLatin1StringEncoding];
    if (block == nil) return nil;

    if ([_name length] > 0) [block setObject:_name forKey:DRCDTextTitleKey ofTrack:0];

    NSUInteger i;
    for (i = 0; i < [_songs count]; i++) {
        BTTrack *song = [_songs objectAtIndex:i];
        NSString *title = [song displayTitle];
        NSString *artist = [song displayArtist];
        if ([title length] > 0) [block setObject:title forKey:DRCDTextTitleKey ofTrack:(i + 1)];
        if ([artist length] > 0) [block setObject:artist forKey:DRCDTextPerformerKey ofTrack:(i + 1)];
    }

    // Anything past the block's own limit would be truncated by the framework
    // without saying so. Names on the disc are not worth a surprise, so the
    // whole block is dropped rather than written half right.
    if ([block flatten] > 0) return nil;
    return block;
}

#pragma mark - The drive and the disc in it

+ (NSArray *)writableDevices {
    NSMutableArray *out = [NSMutableArray array];
    NSArray *devices = [DRDevice devices];
    NSUInteger i;
    for (i = 0; i < [devices count]; i++) {
        DRDevice *device = [devices objectAtIndex:i];
        NSDictionary *info = [device info];
        NSDictionary *writes = [info objectForKey:DRDeviceWriteCapabilitiesKey];
        if ([[writes objectForKey:DRDeviceCanWriteCDRKey] boolValue]) [out addObject:device];
    }
    return out;
}

// The nominal 80 minutes decides whether to offer the burn; this decides
// whether the disc actually in the tray can take it.
- (NSString *)problemWithDisc:(DRDevice *)device {
    if (device == nil) return @"There is no drive that writes CDs.";

    NSString *drive = [device displayName];
    if ([drive length] == 0) drive = @"the drive";

    if ([device mediaIsTransitioning]) {
        return [NSString stringWithFormat:@"%@ is still reading the disc.", drive];
    }
    if (![device mediaIsPresent]) {
        return [NSString stringWithFormat:@"There is no disc in %@.", drive];
    }
    NSString *media = [device mediaType];
    if (![media isEqualToString:DRDeviceMediaTypeCDR] &&
        ![media isEqualToString:DRDeviceMediaTypeCDRW]) {
        return [NSString stringWithFormat:@"The disc in %@ is not a CD-R or CD-RW.", drive];
    }
    // A CD-RW that has been used is erasable, not blank. Erasing is a separate
    // act and is not something a burn should do on its own.
    if (![device mediaIsBlank]) {
        return [NSString stringWithFormat:@"The disc in %@ is not blank.", drive];
    }

    NSUInteger free = (NSUInteger)[[device mediaSpaceFree] sectors];
    NSUInteger needed = [self sectors];
    if (free < needed) {
        return [NSString stringWithFormat:
                @"The disc in %@ holds %@, and this playlist needs %@.",
                drive,
                [BTBurnPlan stringFromSectors:free],
                [BTBurnPlan stringFromSectors:needed]];
    }
    return nil;
}

// Rounded up, not down. A playlist of 80:00.4 that reads as "80:00" beside a
// disc that also reads as "80:00" is refused for no reason the reader can see.
+ (NSString *)stringFromSectors:(NSUInteger)sectors {
    NSUInteger seconds = (sectors + BTBurnSectorsPerSecond - 1) / BTBurnSectorsPerSecond;
    return [NSString stringWithFormat:@"%lu:%02lu",
            (unsigned long)(seconds / 60), (unsigned long)(seconds % 60)];
}

@end
