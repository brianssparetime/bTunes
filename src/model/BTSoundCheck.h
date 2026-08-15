#import <Foundation/Foundation.h>

@class AVURLAsset;
@class BTTrack;

// How loud a recording actually is, and what to do about it.
//
// Recordings are not mastered at the same level as each other. A pop record
// ripped from CD sits around nine decibels below full scale, a quiet solo piano
// recording nearer twenty-five, and no one position of the volume knob is right
// for both. Evening them out means knowing how loud each one is.
//
// The measuring is not done here, because for this library it is already done.
// iTunes measured these songs when it imported them and wrote the answer into
// the file as a tag called iTunNORM: five sixths of the music on the target
// machine carries one. Reading a tag costs milliseconds where measuring costs a
// full decode, so the tag is read and only a song without one goes unadjusted.
//
// Two numbers come out of it. The gain is what the recording asks to be moved
// by, against the same reference iTunes used, so nothing here has to choose a
// target level. The peak is the loudest sample in the song, and it is what stops
// a quiet recording being turned up into clipping.
@interface BTSoundCheck : NSObject

// The tag as iTunes wrote it: ten eight-digit hexadecimal fields. The first two
// are the loudness of the left and right channels against a reference of 1000,
// and the seventh and eighth are the peak sample of each out of 32768. The rest
// are restatements against other references and are not used.
//
// Answers NO for anything that cannot be read as that, so a garbled tag leaves a
// song unadjusted rather than moved by an invented number. The peak is optional:
// a tag holding only the loudness fields still gives a gain, and outPeak is left
// at nothing to say the peak is not known.
+ (BOOL)readTagText:(NSString *)text gain:(double *)outGain peak:(double *)outPeak;

// The tag out of whichever container the file is in. An mp3 carries it as an ID3
// comment whose description is the tag name, an MPEG-4 file as a freeform iTunes
// atom named for it, and the two arrive under different keys in different
// metadata formats. Nothing else about the file is read.
//
// Nil when the file has no such tag, which is the ordinary case for anything
// iTunes did not import.
+ (NSString *)tagTextInAsset:(AVURLAsset *)asset;

// What to multiply the sound by, given what the song asked for and how loud its
// peak is.
//
// A song quieter than the reference has to be turned up, and turning it up can
// push its loudest moment past full scale, where it would clip. So the boost is
// held back to whatever the peak leaves room for. A song with no peak recorded
// is never boosted at all, since there is nothing to say what boosting it would
// cost; cuts are always safe and are applied whatever the peak.
+ (float)multiplierForGain:(double)gainInDecibels peak:(double)peak;

// How far the adjustment is allowed to run either way. A tag that has been
// damaged can hold any number at all, and a song that reads as needing eighty
// decibels of cut is a bad tag rather than a very loud recording.
+ (double)largestBoost;
+ (double)largestCut;

// What the file says about a song, written onto the song. A file that says
// nothing is recorded as having said nothing, so it is asked once rather than
// once per play.
//
// Answers YES when the song changed and the library therefore has something new
// to save. A song already asked is left alone and answers NO.
//
// The two forms differ only in who opens the file. Importing has the file open
// already and hands it over; playing does not, and asking costs a metadata read
// rather than a decode, which is why it can happen as a song starts.
+ (BOOL)fillInTrack:(BTTrack *)track;
+ (BOOL)fillInTrack:(BTTrack *)track fromAsset:(AVURLAsset *)asset;

@end
