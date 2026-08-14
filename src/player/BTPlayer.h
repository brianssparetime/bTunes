#import <Foundation/Foundation.h>
#import "BTSpectrum.h"

@class BTTrack;

typedef NS_ENUM(NSInteger, BTRepeatMode) {
    BTRepeatModeOff = 0,
    BTRepeatModeAll,
    BTRepeatModeOne
};

// Posted when the current track, play or pause state, shuffle, or repeat changes.
extern NSString *const BTPlayerDidChangeNotification;
// Posted several times a second while playing, for the time readout.
extern NSString *const BTPlayerTimeDidChangeNotification;

@interface BTPlayer : NSObject

// Nothing in the list would play, and here is why: a short line in userInfo
// under "reason". The readout shows it for a moment. Pressing play on a
// playlist of locked purchases used to do nothing at all and say nothing, which
// on screen is indistinguishable from a player that has stopped working.
extern NSString *const BTPlayerCouldNotPlayNotification;

// Walks a queue looking for a place that will play, from where it is told and
// in the direction it is given, passing over what will not. Answers where it
// stopped, or -1 when nothing would play, and says how many it passed over.
//
// Kept apart from the playing itself so the walking can be checked on a machine
// with no sound in it: hand it a block that says which places would play. The
// block does the starting when it succeeds, which is why it is a try rather
// than a question.
//
// It takes no more turns than there are places, so a queue where nothing at all
// plays comes to an end rather than going round for ever.
NSInteger BTWalkForPlayable(NSInteger count, NSInteger from, NSInteger step,
                            BOOL wrapping, NSUInteger *outPassedOver,
                            BOOL (^tryAt)(NSInteger place));

+ (instancetype)sharedPlayer;

// How far into a song counts as having listened to it: half of whatever
// actually plays, or four minutes, whichever comes first. Past that mark the
// play count goes up once, and not before.
//
// Counted at a mark rather than at the start because the play counts here are
// twenty-five years old and cannot be rebuilt from the audio. Raising one the
// moment a file opened meant skimming a playlist for something added a play to
// everything passed over, and left "last played" recording when a song was
// skipped rather than when it was heard.
//
// The span is what plays, not what the file holds, so a song trimmed to its
// last thirty seconds counts fifteen seconds in. Answered as a class method
// over two times so the rule can be checked without a sound card. A negative
// answer means the length is not known and nothing should be counted.
+ (NSTimeInterval)countingMarkBetween:(NSTimeInterval)start and:(NSTimeInterval)end;

@property (nonatomic, readonly) BTTrack *currentTrack;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, assign) BOOL shuffle;
@property (nonatomic, assign) BTRepeatMode repeatMode;
// Where the knob sits, 0 to 1, which is not the same as how much the sound is
// multiplied by. The two are related by gainForVolume: below, and everything
// outside the player deals in the knob.
@property (nonatomic, assign) float volume;

// What the knob position multiplies the sound by.
//
// Even in decibels rather than in amplitude, so a step of the knob is the same
// step in loudness wherever it is taken. Sent straight through as a multiplier,
// half the knob was six decibels down and a twentieth of it was twenty-six, so
// everything worth hearing lived in the first few points of the travel and a
// single press near the bottom nearly tripled the volume.
//
// The top is above the level of the file itself, because a quiet recording
// played at the level of the room around it has nowhere else to go. Quiet
// recordings leave headroom unused, so this is usually room that is there.
+ (float)gainForVolume:(float)volume;
+ (float)volumeForGain:(float)gain;

// How far the knob runs, and how far past the file's own level it reaches.
+ (float)volumeRangeInDecibels;
+ (float)volumeCeiling;
// Silence, or the last level that could be heard. There is no muted flag: a
// flag beside the volume is a second answer to a question the volume already
// answers, and the two came apart the moment either was written down without
// the other. Silence is a volume of nothing.
- (void)toggleMute;
@property (nonatomic, readonly) NSTimeInterval currentTime;
@property (nonatomic, readonly) NSTimeInterval duration;

// Plays one track and remembers the surrounding list for next and previous.
- (void)playTrack:(BTTrack *)track inList:(NSArray *)tracks;
- (void)togglePlayPause;
- (void)pause;
- (void)resume;
- (void)stop;
- (void)next;
- (void)previous;      // restarts the track if more than three seconds in
- (void)seekToTime:(NSTimeInterval)time;

// Playback level, smoothed, in the range 0 to 1. Silent when nothing is
// sounding, so a paused song does not leave a reading standing.
- (float)averageLevel;

// The analyzer's latest reading: BT_ANALYZER_BANDS levels, each 0 to 1, low
// frequencies first. Taken from the audio as it is rendered, so the mini-mode
// bars show what is actually being played. All silence when nothing is playing.
- (void)getBandLevels:(float *)bands;

@end
