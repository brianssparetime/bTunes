#import "BTSoundCheck.h"
#import "BTTrack.h"
#import <AVFoundation/AVFoundation.h>

// The name iTunes gave the tag, in both containers.
static NSString *const BTNormTagName = @"iTunNORM";

// What the loudness fields are measured against. A field reading 1000 is a song
// already at the level everything else is being brought to, and needs no move.
#define BT_NORM_REFERENCE 1000.0

// What a peak field is measured against: the largest sample a sixteen-bit
// recording can hold.
#define BT_NORM_FULL_SCALE 32768.0

@implementation BTSoundCheck

+ (double)largestBoost { return 12.0; }
+ (double)largestCut { return 30.0; }

// One eight-digit hexadecimal field, or a negative number when the text is not
// one. Refused rather than read as zero, since zero is a value the tag can hold
// and "unreadable" has to be told apart from it.
static double BTFieldValue(NSString *field) {
    if ([field length] == 0) return -1.0;

    NSUInteger i;
    for (i = 0; i < [field length]; i++) {
        unichar c = [field characterAtIndex:i];
        BOOL isHex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
        if (!isHex) return -1.0;
    }

    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:field];
    if (![scanner scanHexLongLong:&value]) return -1.0;
    return (double)value;
}

// The two channels as one number. The fields hold a measure of power, so the two
// are averaged before being turned into decibels rather than after: a song loud
// on one side and quiet on the other is as loud as the two together, not as loud
// as the average of two separate answers.
//
// Both have to be there. Accepting one and ignoring the other looks tolerant and
// is not: a and f are hexadecimal digits, so "not a tag at all" reads as a
// perfectly good second field, and a run of English words came out as a song
// asking to be turned up twelve decibels. A tag iTunes wrote always has both.
static double BTAverageOfChannels(double left, double right) {
    if (left <= 0 || right <= 0) return -1.0;
    return (left + right) / 2.0;
}

+ (BOOL)readTagText:(NSString *)text gain:(double *)outGain peak:(double *)outPeak {
    if (outGain) *outGain = 0.0;
    if (outPeak) *outPeak = 0.0;
    if ([text length] == 0) return NO;

    NSMutableArray *fields = [NSMutableArray array];
    NSArray *pieces = [text componentsSeparatedByCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSUInteger i;
    for (i = 0; i < [pieces count]; i++) {
        NSString *piece = [pieces objectAtIndex:i];
        if ([piece length] > 0) [fields addObject:piece];
    }
    if ([fields count] < 2) return NO;

    double left = BTFieldValue([fields objectAtIndex:0]);
    double right = BTFieldValue([fields objectAtIndex:1]);
    double loudness = BTAverageOfChannels(left, right);
    if (loudness <= 0) return NO;

    // Louder than the reference asks to be turned down, which is the common
    // case: nearly everything is mastered louder than iTunes aimed at.
    double gain = -10.0 * log10(loudness / BT_NORM_REFERENCE);
    if (isnan(gain) || isinf(gain)) return NO;
    if (gain > [self largestBoost]) gain = [self largestBoost];
    if (gain < -[self largestCut]) gain = -[self largestCut];
    if (outGain) *outGain = gain;

    if ([fields count] < 8 || outPeak == NULL) return YES;

    // The louder of the two channels, since it is the one that would clip. A
    // decoder can hand back a sample past full scale, so a peak that reads above
    // it is taken as being at it rather than thrown away.
    double peakLeft = BTFieldValue([fields objectAtIndex:6]);
    double peakRight = BTFieldValue([fields objectAtIndex:7]);
    double peak = (peakLeft > peakRight) ? peakLeft : peakRight;
    if (peak <= 0) return YES;

    peak = peak / BT_NORM_FULL_SCALE;
    *outPeak = (peak > 1.0) ? 1.0 : peak;
    return YES;
}

+ (float)multiplierForGain:(double)gainInDecibels peak:(double)peak {
    if (gainInDecibels > [self largestBoost]) gainInDecibels = [self largestBoost];
    if (gainInDecibels < -[self largestCut]) gainInDecibels = -[self largestCut];

    double multiplier = pow(10.0, gainInDecibels / 20.0);
    if (multiplier <= 1.0) return (float)multiplier;

    // Turning up is the only direction that can cost anything. With no peak
    // recorded there is no way to know what it would cost, so it is not done.
    if (peak <= 0.0) return 1.0f;

    double headroom = 1.0 / peak;
    if (multiplier > headroom) multiplier = headroom;
    return (float)multiplier;
}

// Whether this is the tag, asked of the two places its name can appear. An mp3
// carries the name as the description of an otherwise ordinary comment, so the
// key says only that it is a comment and the name is in the extra attributes. An
// MPEG-4 file names the atom itself.
static BOOL BTItemIsNormTag(AVMetadataItem *item) {
    NSString *key = [NSString stringWithFormat:@"%@", [item key]];
    if ([key rangeOfString:BTNormTagName].location != NSNotFound) return YES;

    id info = [[item extraAttributes] objectForKey:AVMetadataExtraAttributeInfoKey];
    if ([info isKindOfClass:[NSString class]] &&
        [(NSString *)info rangeOfString:BTNormTagName].location != NSNotFound) {
        return YES;
    }
    return NO;
}

+ (BOOL)fillInTrack:(BTTrack *)track {
    if (track == nil || track.soundCheckState != BTSoundCheckNotAsked) return NO;

    // A locked purchase is never opened. Nothing here can decode one, so it will
    // never be played, and asking would only be a file read that leads nowhere.
    if (track.isProtected) return NO;

    NSString *path = [track resolvedPath];
    if ([path length] == 0) return NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return NO;

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    return [self fillInTrack:track fromAsset:asset];
}

+ (BOOL)fillInTrack:(BTTrack *)track fromAsset:(AVURLAsset *)asset {
    if (track == nil || track.soundCheckState != BTSoundCheckNotAsked) return NO;

    double gain = 0.0;
    double peak = 0.0;
    NSString *text = [self tagTextInAsset:asset];
    if ([self readTagText:text gain:&gain peak:&peak]) {
        track.soundCheckGain = gain;
        track.soundCheckPeak = peak;
        track.soundCheckState = BTSoundCheckKnown;
    } else {
        track.soundCheckState = BTSoundCheckSaysNothing;
    }
    return YES;
}

+ (NSString *)tagTextInAsset:(AVURLAsset *)asset {
    if (asset == nil) return nil;

    // Every format the file has, rather than the one its extension suggests. The
    // tag lives in a different format in each container, and a file may carry
    // more than one.
    NSArray *formats = [asset availableMetadataFormats];
    NSUInteger f;
    for (f = 0; f < [formats count]; f++) {
        NSArray *items = [asset metadataForFormat:[formats objectAtIndex:f]];
        NSUInteger i;
        for (i = 0; i < [items count]; i++) {
            AVMetadataItem *item = [items objectAtIndex:i];
            if (!BTItemIsNormTag(item)) continue;
            id value = [item value];
            if ([value isKindOfClass:[NSString class]]) return value;
        }
    }
    return nil;
}

@end
