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
@property (nonatomic, assign) float volume;             // 0 to 1
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
