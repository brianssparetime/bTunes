#import "BTDiscImport.h"
#import "BTAudioDisc.h"
#import "BTLibrary.h"
#import "BTTrack.h"
#import "BTPreferences.h"
#import "BTRedBook.h"
#import <AudioToolbox/AudioToolbox.h>

// Everything written here keeps the disc's own rate and channel count; only how
// the samples are packed changes.
//
// AAC at this rate is about a tenth of the disc. Apple Lossless is about a half
// and is exact. Neither is a setting worth putting in front of anyone beyond the
// choice between them.
#define BT_AAC_BITRATE 256000

@implementation BTDiscImport

#pragma mark - Where a song goes

// Anything that would confuse a path, taken out rather than replaced with a
// look-alike. A song called "AC/DC" makes a folder called "AC" and one called
// "DC" otherwise, which is two mistakes rather than one.
static NSString *BTSafeName(NSString *name, NSString *fallback) {
    if ([name length] == 0) return fallback;
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    NSString *clean = [[name componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"-"];
    clean = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    // A name that is nothing but punctuation, and a leading dot, both make a
    // folder nobody can see.
    while ([clean hasPrefix:@"."]) clean = [clean substringFromIndex:1];
    return [clean length] > 0 ? clean : fallback;
}

+ (NSString *)relativePathForTitle:(NSString *)title
                            artist:(NSString *)artist
                             album:(NSString *)album
                            number:(NSInteger)number
                          lossless:(BOOL)lossless {
    NSString *folderArtist = BTSafeName(artist, @"Unknown Artist");
    NSString *folderAlbum = BTSafeName(album, @"Unknown Album");
    NSString *songName = BTSafeName(title, [NSString stringWithFormat:@"Track %ld", (long)number]);

    // Numbered so the songs sit in disc order in any folder listing, which is
    // what the folder beside this one does.
    NSString *file = [NSString stringWithFormat:@"%02ld %@.m4a", (long)number, songName];
    return [[folderArtist stringByAppendingPathComponent:folderAlbum]
            stringByAppendingPathComponent:file];
}

#pragma mark - Encoding one track

// Decodes the track off the disc and writes it again in the chosen form.
//
// Both halves go through ExtAudioFile, which is the same road the burn takes to
// trim a song: it reads whatever the file is, hands over plain samples, and
// packs them into whatever the destination wants.
static BOOL BTEncodeTrack(NSString *source, NSString *destination, BOOL lossless,
                          NSString **outError) {
    ExtAudioFileRef in = NULL, out = NULL;
    AudioStreamBasicDescription client;
    BOOL ok = NO;
    SInt16 *buffer = NULL;

    do {
        NSURL *sourceURL = [NSURL fileURLWithPath:source];
        if (ExtAudioFileOpenURL((__bridge CFURLRef)sourceURL, &in) != noErr || in == NULL) {
            *outError = @"the track could not be read off the disc";
            break;
        }

        memset(&client, 0, sizeof(client));
        client.mSampleRate = BT_CD_SAMPLE_RATE;
        client.mFormatID = kAudioFormatLinearPCM;
        client.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        client.mChannelsPerFrame = BT_CD_CHANNELS;
        client.mBitsPerChannel = BT_CD_BYTES_PER_SAMPLE * 8;
        client.mFramesPerPacket = 1;
        client.mBytesPerFrame = BT_CD_BYTES_PER_SAMPLE * BT_CD_CHANNELS;
        client.mBytesPerPacket = client.mBytesPerFrame;

        if (ExtAudioFileSetProperty(in, kExtAudioFileProperty_ClientDataFormat,
                                    sizeof(client), &client) != noErr) {
            *outError = @"the track is in a form that cannot be read";
            break;
        }

        // What is written. The encoder fills in the rest of the description
        // itself, which is why so little is set here.
        AudioStreamBasicDescription written;
        memset(&written, 0, sizeof(written));
        written.mSampleRate = BT_CD_SAMPLE_RATE;
        written.mChannelsPerFrame = BT_CD_CHANNELS;
        written.mFormatID = lossless ? kAudioFormatAppleLossless : kAudioFormatMPEG4AAC;
        if (lossless) written.mFormatFlags = kAppleLosslessFormatFlag_16BitSourceData;

        NSURL *destinationURL = [NSURL fileURLWithPath:destination];
        if (ExtAudioFileCreateWithURL((__bridge CFURLRef)destinationURL, kAudioFileM4AType,
                                      &written, NULL, kAudioFileFlags_EraseFile, &out) != noErr
            || out == NULL) {
            *outError = @"the song could not be written";
            break;
        }
        if (ExtAudioFileSetProperty(out, kExtAudioFileProperty_ClientDataFormat,
                                    sizeof(client), &client) != noErr) {
            *outError = @"the song could not be written";
            break;
        }

        // Asked for after the file exists, because the converter it belongs to
        // does not exist until then.
        if (!lossless) {
            AudioConverterRef converter = NULL;
            UInt32 size = sizeof(converter);
            if (ExtAudioFileGetProperty(out, kExtAudioFileProperty_AudioConverter,
                                        &size, &converter) == noErr && converter) {
                UInt32 rate = BT_AAC_BITRATE;
                AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate,
                                          sizeof(rate), &rate);
                // The converter was changed behind the file's back, so it has to
                // be told to pick the change up.
                CFArrayRef config = NULL;
                ExtAudioFileSetProperty(out, kExtAudioFileProperty_ConverterConfig,
                                        sizeof(config), &config);
            }
        }

        const UInt32 chunk = 16384;   // frames
        buffer = malloc((size_t)chunk * client.mBytesPerFrame);
        if (buffer == NULL) { *outError = @"there was no room to work in"; break; }

        AudioBufferList list;
        list.mNumberBuffers = 1;
        list.mBuffers[0].mNumberChannels = BT_CD_CHANNELS;

        BOOL failed = NO;
        for (;;) {
            list.mBuffers[0].mData = buffer;
            list.mBuffers[0].mDataByteSize = chunk * client.mBytesPerFrame;
            UInt32 got = chunk;
            if (ExtAudioFileRead(in, &got, &list) != noErr) {
                *outError = @"the disc could not be read to the end of the track";
                failed = YES;
                break;
            }
            if (got == 0) break;
            list.mBuffers[0].mDataByteSize = got * client.mBytesPerFrame;
            if (ExtAudioFileWrite(out, got, &list) != noErr) {
                *outError = @"the song could not be written";
                failed = YES;
                break;
            }
        }
        ok = !failed;
    } while (0);

    if (buffer) free(buffer);
    if (in) ExtAudioFileDispose(in);
    if (out) ExtAudioFileDispose(out);
    // A half-written song is worse than none: it plays, badly, and looks
    // finished.
    if (!ok) [[NSFileManager defaultManager] removeItemAtPath:destination error:NULL];
    return ok;
}

#pragma mark - The disc

+ (void)importDisc:(BTAudioDisc *)disc
              into:(BTLibrary *)library
          progress:(void (^)(double, NSString *))progress
        completion:(void (^)(NSUInteger, NSString *))completion {
    NSArray *tracks = [disc tracks];
    BOOL lossless = [[BTPreferences sharedPreferences] importsLossless];
    NSString *root = [[BTPreferences sharedPreferences] btunesFolder];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray *made = [NSMutableArray array];
        NSString *failure = nil;

        NSUInteger i;
        for (i = 0; i < [tracks count]; i++) {
            BTTrack *source = [tracks objectAtIndex:i];
            NSString *relative = [self relativePathForTitle:source.title
                                                     artist:source.artist
                                                      album:source.album
                                                     number:source.trackNumber
                                                   lossless:lossless];
            NSString *full = [root stringByAppendingPathComponent:relative];

            double done = (double)i / (double)MAX((NSUInteger)1, [tracks count]);
            NSString *what = [source displayTitle];
            dispatch_async(dispatch_get_main_queue(), ^{ if (progress) progress(done, what); });

            if (![fm createDirectoryAtPath:[full stringByDeletingLastPathComponent]
               withIntermediateDirectories:YES attributes:nil error:NULL]) {
                failure = @"the BTunes music folder could not be made";
                break;
            }

            NSString *why = nil;
            if (!BTEncodeTrack([source resolvedPath], full, lossless, &why)) {
                failure = [NSString stringWithFormat:@"\"%@\" stopped it: %@",
                           [source displayTitle], (why ? why : @"it could not be copied")];
                break;
            }

            BTTrack *kept = [[BTTrack alloc] init];
            kept.trackID = [[NSUUID UUID] UUIDString];
            [kept setPath:full root:BTPathRootBTunes];
            kept.title = source.title;
            kept.artist = source.artist;
            kept.album = source.album;
            kept.trackNumber = source.trackNumber;
            kept.duration = source.duration;
            kept.kind = lossless ? @"Apple Lossless audio file" : @"AAC audio file";
            kept.dateAdded = [NSDate date];
            NSDictionary *attrs = [fm attributesOfItemAtPath:full error:NULL];
            kept.fileSize = [[attrs objectForKey:NSFileSize] longLongValue];
            [made addObject:kept];
        }

        // Back on the main thread, because this is where the library is changed
        // and where everything else reads it.
        dispatch_async(dispatch_get_main_queue(), ^{
            NSUInteger j;
            for (j = 0; j < [made count]; j++) {
                [library addTrack:[made objectAtIndex:j]];
            }
            if ([made count] > 0) [library noteChanged];
            if (completion) completion([made count], failure);
        });
    });
}

@end
