#import "BTBurnPlan.h"
#import "BTRedBook.h"
#import "BTPlaylist.h"
#import "BTTrack.h"
#import <DiscRecording/DiscRecording.h>
#import <AudioToolbox/AudioToolbox.h>

const NSUInteger BTBurnSectorsPerSecond = BT_CD_SECTORS_PER_SECOND;
const NSUInteger BTBurnNominalDiscSectors = 360000;   // 80 minutes, the standard blank

@interface BTBurnPlan ()
+ (BOOL)canBurnTrack:(BTTrack *)track;
@end

// What a song puts on the disc: the part BTunes plays, not the whole file. A
// start or end time is honoured, so a run-in nobody wants is not burned and a
// song sharing a file with another does not drag its neighbour along.
static NSTimeInterval BTBurnLengthOfSong(BTTrack *song) {
    NSTimeInterval length = [song playbackEnd] - [song playbackStart];
    return (length > 0) ? length : 0;
}

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
    // Where the trimmed copies were written, held so they can be thrown away
    // once the burn that reads them is over.
    NSString *_scratch;
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

- (NSTimeInterval)audioTime {
    NSTimeInterval total = 0;
    NSUInteger i;
    for (i = 0; i < [_songs count]; i++) {
        total += BTBurnLengthOfSong([_songs objectAtIndex:i]);
    }
    return total;
}

- (NSTimeInterval)gapTime {
    if ([_songs count] < 2) return 0;
    return (NSTimeInterval)(([_songs count] - 1) * _gapSeconds);
}

// Summed per song rather than off the total, since each song rounds up to a
// whole sector of its own.
- (NSUInteger)sectors {
    NSUInteger total = 0, i;
    for (i = 0; i < [_songs count]; i++) {
        total += BTSectorsForSeconds(BTBurnLengthOfSong([_songs objectAtIndex:i]));
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

#pragma mark - Writing out the part that plays

// The framework takes a file and burns all of it, so the only way to give the
// disc a start or an end time is to hand it a file that already has them: the
// played range decoded to an AIFF beside the burn.
//
// The copy keeps the source's own rate and channel count and changes nothing
// but the trim, because the framework converts to Red Book itself and it is
// better at that than a second conversion written here would be.
static NSString *BTWriteTrimmedCopy(BTTrack *song, NSString *directory,
                                    NSUInteger index, NSString **reason) {
    NSURL *source = [song fileURL];
    if (source == nil) {
        if (reason) *reason = @"has no file";
        return nil;
    }

    ExtAudioFileRef in = NULL, out = NULL;
    NSString *written = nil;
    SInt16 *buffer = NULL;
    NSString *trouble = nil;

    do {
        if (ExtAudioFileOpenURL((__bridge CFURLRef)source, &in) != noErr || in == NULL) {
            trouble = @"could not be opened";
            break;
        }

        AudioStreamBasicDescription sourceFormat;
        UInt32 size = sizeof(sourceFormat);
        if (ExtAudioFileGetProperty(in, kExtAudioFileProperty_FileDataFormat,
                                    &size, &sourceFormat) != noErr) {
            trouble = @"could not be read";
            break;
        }

        // A file that does not say what rate it is gets the disc's own, which is
        // the only rate worth guessing at here.
        double rate = (sourceFormat.mSampleRate > 0) ? sourceFormat.mSampleRate
                                                     : BT_CD_SAMPLE_RATE;
        UInt32 channels = sourceFormat.mChannelsPerFrame;
        if (channels < 1) channels = 2;
        if (channels > 2) channels = 2;

        // Sixteen-bit signed, which is what AIFF holds and what a CD is.
        // Native byte order on the way through, big-endian in the file, and
        // the framework swaps between the two.
        AudioStreamBasicDescription client;
        memset(&client, 0, sizeof(client));
        client.mSampleRate = rate;
        client.mFormatID = kAudioFormatLinearPCM;
        client.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        client.mChannelsPerFrame = channels;
        client.mBitsPerChannel = 16;
        client.mFramesPerPacket = 1;
        client.mBytesPerFrame = 2 * channels;
        client.mBytesPerPacket = client.mBytesPerFrame;

        AudioStreamBasicDescription file = client;
        file.mFormatFlags |= kAudioFormatFlagIsBigEndian;

        if (ExtAudioFileSetProperty(in, kExtAudioFileProperty_ClientDataFormat,
                                    sizeof(client), &client) != noErr) {
            trouble = @"is in a form that cannot be trimmed";
            break;
        }

        NSString *path = [directory stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"%02lu.aiff", (unsigned long)index]];
        if (ExtAudioFileCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],
                                      kAudioFileAIFFType, &file, NULL,
                                      kAudioFileFlags_EraseFile, &out) != noErr || out == NULL) {
            trouble = @"could not be written out";
            break;
        }
        if (ExtAudioFileSetProperty(out, kExtAudioFileProperty_ClientDataFormat,
                                    sizeof(client), &client) != noErr) {
            trouble = @"could not be written out";
            break;
        }

        SInt64 first = (SInt64)llround([song playbackStart] * rate);
        SInt64 left = (SInt64)llround(BTBurnLengthOfSong(song) * rate);
        if (first > 0 && ExtAudioFileSeek(in, first) != noErr) {
            trouble = @"could not be wound to its start time";
            break;
        }

        const UInt32 chunk = 16384;   // frames
        buffer = malloc((size_t)chunk * client.mBytesPerFrame);
        if (buffer == NULL) { trouble = @"could not be written out"; break; }

        AudioBufferList list;
        list.mNumberBuffers = 1;
        list.mBuffers[0].mNumberChannels = channels;

        while (left > 0) {
            UInt32 want = (left < (SInt64)chunk) ? (UInt32)left : chunk;
            list.mBuffers[0].mData = buffer;
            list.mBuffers[0].mDataByteSize = want * client.mBytesPerFrame;

            UInt32 got = want;
            if (ExtAudioFileRead(in, &got, &list) != noErr) {
                trouble = @"could not be read to its end time";
                break;
            }
            // The file ended early. What was read is what there is, and the
            // song is shorter than the library said rather than broken.
            if (got == 0) break;

            list.mBuffers[0].mDataByteSize = got * client.mBytesPerFrame;
            if (ExtAudioFileWrite(out, got, &list) != noErr) {
                trouble = @"could not be written out";
                break;
            }
            left -= got;
        }
        if (trouble != nil) break;

        written = path;
    } while (0);

    if (buffer) free(buffer);
    if (in) ExtAudioFileDispose(in);
    if (out) ExtAudioFileDispose(out);

    if (written == nil && reason) *reason = (trouble ? trouble : @"could not be trimmed");
    return written;
}

#pragma mark - Handing the framework the files

- (BOOL)needsPreparation {
    return [_trimmed count] > 0;
}

// Sixteen bits a sample, so a minute of stereo is about ten megabytes. Asked
// before the reader is left waiting on a conversion that runs out of room
// halfway through.
- (NSString *)problemWithScratchSpace {
    if (![self needsPreparation]) return nil;

    long long needed = 0;
    NSUInteger i;
    for (i = 0; i < [_trimmed count]; i++) {
        needed += (long long)(BTBurnLengthOfSong([_trimmed objectAtIndex:i]) *
                              BT_CD_BYTES_PER_SECOND);
    }

    NSString *temp = NSTemporaryDirectory();
    NSDictionary *fs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:temp error:NULL];
    long long free = [[fs objectForKey:NSFileSystemFreeSize] longLongValue];
    if (fs == nil || free == 0) return nil;   // nothing said is better than a guess

    if (free < needed) {
        return [NSString stringWithFormat:
                @"Trimming %lu song%@ needs about %lld MB of scratch space and there is %lld MB.",
                (unsigned long)[_trimmed count], ([_trimmed count] == 1 ? @"" : @"s"),
                needed / (1024 * 1024), free / (1024 * 1024)];
    }
    return nil;
}

- (void)removeScratch {
    if (_scratch == nil) return;
    [[NSFileManager defaultManager] removeItemAtPath:_scratch error:NULL];
    _scratch = nil;
}

// Built fresh on every burn rather than kept from when the dialog opened. The
// window between the two is small, but a burn that starts and cannot finish
// wastes a disc.
- (NSArray *)buildTracks:(NSString **)reason {
    if (reason) *reason = nil;
    [self removeScratch];

    if ([self needsPreparation]) {
        _scratch = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"BTunes Burn %@",
                     [[NSProcessInfo processInfo] globallyUniqueString]]];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:_scratch
                                      withIntermediateDirectories:YES
                                                       attributes:nil error:NULL]) {
            _scratch = nil;
            if (reason) *reason = @"There is nowhere to write the trimmed songs.";
            return nil;
        }
    }

    NSMutableArray *tracks = [NSMutableArray arrayWithCapacity:[_songs count]];
    NSUInteger i;
    for (i = 0; i < [_songs count]; i++) {
        BTTrack *song = [_songs objectAtIndex:i];
        NSURL *url = [song fileURL];

        // A song with a start or end time is burned from a copy holding only
        // the part that plays, since the framework has no way to be told a
        // range of a file.
        if (song.usesStartTime || song.usesEndTime) {
            NSString *why = nil;
            NSString *copy = BTWriteTrimmedCopy(song, _scratch, i, &why);
            if (copy == nil) {
                [self removeScratch];
                if (reason) {
                    *reason = [NSString stringWithFormat:
                               @"\"%@\" %@, so nothing has been written.",
                               [song displayTitle], why];
                }
                return nil;
            }
            url = [NSURL fileURLWithPath:copy];
        }

        DRAudioTrackRef ref = (url != nil)
            ? DRAudioTrackCreateWithURL((__bridge CFURLRef)url) : NULL;
        if (ref == NULL) {
            [self removeScratch];
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
        [self removeScratch];
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

// Minutes and seconds, and minutes never roll into hours: a disc holds eighty
// minutes, and "1:20:00" is not how anyone says that. This is why the clock
// BTTrack keeps is not used here, close as the two look.
//
// Rounded up, not down. A playlist of 80:00.4 that reads as "80:00" beside a
// disc that also reads as "80:00" is refused for no reason the reader can see.
+ (NSString *)stringFromSectors:(NSUInteger)sectors {
    NSUInteger seconds = (sectors + BTBurnSectorsPerSecond - 1) / BTBurnSectorsPerSecond;
    return [NSString stringWithFormat:@"%lu:%02lu",
            (unsigned long)(seconds / 60), (unsigned long)(seconds % 60)];
}

@end
