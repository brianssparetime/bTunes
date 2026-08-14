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

+ (instancetype)sharedPlayer;

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
@property (nonatomic, readonly) BOOL muted;
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
