#import "BTPlayer.h"
#import "BTTrack.h"
#import "BTLibrary.h"
#import <AVFoundation/AVFoundation.h>

NSString *const BTPlayerDidChangeNotification = @"BTPlayerDidChange";
NSString *const BTPlayerTimeDidChangeNotification = @"BTPlayerTimeDidChange";

@interface BTPlayer () <AVAudioPlayerDelegate>
@property (nonatomic, strong) AVAudioPlayer *audio;
@property (nonatomic, strong) BTTrack *currentTrack;
@property (nonatomic, strong) NSArray *queue;          // BTTrack, in list order
@property (nonatomic, strong) NSMutableArray *order;   // indexes into queue
@property (nonatomic, assign) NSInteger orderPosition;
@property (nonatomic, strong) NSTimer *tick;
@property (nonatomic, assign) float smoothedAverage;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) float volumeBeforeMute;
@end

@implementation BTPlayer

+ (instancetype)sharedPlayer {
    static BTPlayer *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[BTPlayer alloc] init]; });
    return shared;
}

- (id)init {
    self = [super init];
    if (self) {
        // Volume carries over between runs.
        NSNumber *saved = [[NSUserDefaults standardUserDefaults] objectForKey:@"BTVolume"];
        _volume = saved ? [saved floatValue] : 0.75f;
        _order = [NSMutableArray array];
        _orderPosition = -1;
    }
    return self;
}

- (void)dealloc {
    [_tick invalidate];
}

#pragma mark - Order

- (void)rebuildOrderStartingAtIndex:(NSInteger)startIndex {
    [self.order removeAllObjects];
    NSUInteger i;
    for (i = 0; i < [self.queue count]; i++) {
        [self.order addObject:@(i)];
    }

    if (self.shuffle) {
        // Fisher-Yates, then bring the starting track to the front so the
        // clicked song plays first and the rest follow in shuffled order.
        NSUInteger count = [self.order count];
        for (i = count; i > 1; i--) {
            NSUInteger j = (NSUInteger)arc4random_uniform((uint32_t)i);
            [self.order exchangeObjectAtIndex:(i - 1) withObjectAtIndex:j];
        }
        if (startIndex >= 0) {
            NSUInteger at = [self.order indexOfObject:@(startIndex)];
            if (at != NSNotFound) [self.order exchangeObjectAtIndex:0 withObjectAtIndex:at];
            self.orderPosition = 0;
            return;
        }
    }
    self.orderPosition = (startIndex >= 0) ? startIndex : 0;
}

- (void)setShuffle:(BOOL)shuffle {
    if (_shuffle == shuffle) return;
    _shuffle = shuffle;
    if ([self.queue count] > 0 && self.currentTrack) {
        NSInteger current = (NSInteger)[self.queue indexOfObject:self.currentTrack];
        [self rebuildOrderStartingAtIndex:(current == (NSInteger)NSNotFound ? 0 : current)];
    }
    [self postChange];
}

- (void)setRepeatMode:(BTRepeatMode)repeatMode {
    _repeatMode = repeatMode;
    [self postChange];
}

#pragma mark - Transport

- (void)playTrack:(BTTrack *)track inList:(NSArray *)tracks {
    if (track == nil) return;
    self.queue = tracks ? [NSArray arrayWithArray:tracks] : @[track];
    NSInteger index = (NSInteger)[self.queue indexOfObject:track];
    if (index == (NSInteger)NSNotFound) {
        self.queue = @[track];
        index = 0;
    }
    [self rebuildOrderStartingAtIndex:index];
    [self startTrackAtOrderPosition:self.orderPosition];
}

- (BOOL)startTrackAtOrderPosition:(NSInteger)position {
    if (position < 0 || position >= (NSInteger)[self.order count]) return NO;

    NSInteger queueIndex = [[self.order objectAtIndex:position] integerValue];
    if (queueIndex < 0 || queueIndex >= (NSInteger)[self.queue count]) return NO;

    BTTrack *track = [self.queue objectAtIndex:queueIndex];

    // Locked purchases are kept for their playlist membership but cannot be
    // decoded here. Pass over them rather than stalling the queue.
    if (track.isProtected) {
        self.orderPosition = position;
        return [self advanceBy:1 allowRepeat:NO];
    }

    NSError *error = nil;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:[track fileURL] error:&error];
    if (player == nil) {
        NSLog(@"BTunes: cannot open %@ (%@)", [track resolvedPath], [error localizedDescription]);
        // A missing or unreadable file should not stall the queue.
        self.orderPosition = position;
        return [self advanceBy:1 allowRepeat:NO];
    }

    [self.audio stop];
    player.delegate = self;
    player.volume = self.volume;
    player.meteringEnabled = YES;
    [player prepareToPlay];
    // A song set to begin partway in starts there rather than at nothing.
    NSTimeInterval from = [track playbackStart];
    if (from > 0 && from < [player duration]) [player setCurrentTime:from];
    [player play];

    self.audio = player;
    self.currentTrack = track;
    self.orderPosition = position;

    track.playCount += 1;
    track.lastPlayed = [NSDate date];
    [[BTLibrary sharedLibrary] noteChanged];

    [self startTick];
    [self postChange];
    return YES;
}

- (BOOL)advanceBy:(NSInteger)delta allowRepeat:(BOOL)allowRepeat {
    NSInteger next = self.orderPosition + delta;

    if (next >= (NSInteger)[self.order count]) {
        if (allowRepeat && self.repeatMode == BTRepeatModeAll) {
            next = 0;
        } else {
            [self stop];
            return NO;
        }
    }
    if (next < 0) {
        if (self.repeatMode == BTRepeatModeAll && [self.order count] > 0) {
            next = (NSInteger)[self.order count] - 1;
        } else {
            next = 0;
        }
    }
    return [self startTrackAtOrderPosition:next];
}

- (void)togglePlayPause {
    if (self.audio == nil) return;
    if ([self.audio isPlaying]) {
        [self pause];
    } else {
        [self resume];
    }
}

- (void)pause {
    [self.audio pause];
    [self stopTick];
    [self postChange];
}

- (void)resume {
    if (self.audio == nil) return;
    [self.audio play];
    [self startTick];
    [self postChange];
}

- (void)stop {
    [self.audio stop];
    self.audio = nil;
    self.currentTrack = nil;
    [self stopTick];
    self.smoothedAverage = 0;
    [self postChange];
}

- (void)next {
    if ([self.order count] == 0) return;
    [self advanceBy:1 allowRepeat:YES];
}

- (void)previous {
    if (self.audio && [self.audio currentTime] > 3.0) {
        [self.audio setCurrentTime:0];
        [self postTime];
        return;
    }
    if ([self.order count] == 0) return;
    [self advanceBy:-1 allowRepeat:YES];
}

- (void)seekToTime:(NSTimeInterval)time {
    if (self.audio == nil) return;
    if (time < 0) time = 0;
    if (time > [self.audio duration]) time = [self.audio duration];
    [self.audio setCurrentTime:time];
    [self postTime];
}

#pragma mark - State

- (BOOL)isPlaying {
    return self.audio != nil && [self.audio isPlaying];
}

- (NSTimeInterval)currentTime {
    return self.audio ? [self.audio currentTime] : 0;
}

- (NSTimeInterval)duration {
    if (self.audio) return [self.audio duration];
    return self.currentTrack ? self.currentTrack.duration : 0;
}

- (void)setVolume:(float)volume {
    _volume = volume;
    self.audio.volume = volume;
    [[NSUserDefaults standardUserDefaults] setFloat:volume forKey:@"BTVolume"];
    // Moving the volume off zero by any route ends the mute.
    if (volume > 0.0f) _muted = NO;
    [self postChange];
}

- (void)toggleMute {
    if (self.muted) {
        self.muted = NO;
        float restored = self.volumeBeforeMute > 0.0f ? self.volumeBeforeMute : 0.5f;
        [self setVolume:restored];
        return;
    }
    self.volumeBeforeMute = self.volume;
    [self setVolume:0.0f];
    self.muted = YES;
    [self postChange];
}

- (float)averageLevel { return self.smoothedAverage; }

#pragma mark - Timer

- (void)startTick {
    if (self.tick) return;
    self.tick = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 20.0)
                                                 target:self
                                               selector:@selector(tickFired:)
                                               userInfo:nil
                                                repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:self.tick forMode:NSRunLoopCommonModes];
}

- (void)stopTick {
    [self.tick invalidate];
    self.tick = nil;
}

static float BTLevelFromDecibels(float db) {
    // -60 dB and quieter reads as silence; 0 dB is full scale.
    if (db < -60.0f) return 0.0f;
    if (db > 0.0f) db = 0.0f;
    return powf(10.0f, db / 40.0f);
}

// A song set to stop early is stopped here rather than by the file running out,
// which is the only moment AVAudioPlayer tells anyone about. Twenty times a
// second is close enough that no one hears the difference.
- (BOOL)passedItsEnd {
    BTTrack *track = self.currentTrack;
    if (track == nil || !track.usesEndTime || self.audio == nil) return NO;
    NSTimeInterval end = [track playbackEnd];
    return end > 0 && [self.audio currentTime] >= end;
}

- (void)tickFired:(NSTimer *)timer {
    if ([self passedItsEnd]) {
        [self reachedTheEnd];
        return;
    }
    if (self.audio) {
        [self.audio updateMeters];
        NSUInteger channels = [self.audio numberOfChannels];
        float averageSum = 0;
        NSUInteger c;
        for (c = 0; c < channels; c++) {
            averageSum += BTLevelFromDecibels([self.audio averagePowerForChannel:c]);
        }
        float average = channels > 0 ? averageSum / channels : 0;

        // Rise quickly, fall slowly, the way an analyzer reads.
        self.smoothedAverage = (average > self.smoothedAverage)
            ? average : self.smoothedAverage * 0.75f + average * 0.25f;
    }
    [self postTime];
}

- (void)postTime {
    [[NSNotificationCenter defaultCenter] postNotificationName:BTPlayerTimeDidChangeNotification object:self];
}

- (void)postChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:BTPlayerDidChangeNotification object:self];
}

#pragma mark - AVAudioPlayerDelegate

// Reached however it was reached: the file ran out, or the song's own end time
// came round. Both mean the same thing to whatever comes next.
- (void)reachedTheEnd {
    if (self.repeatMode == BTRepeatModeOne) {
        [self startTrackAtOrderPosition:self.orderPosition];
        return;
    }
    [self advanceBy:1 allowRepeat:YES];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    [self reachedTheEnd];
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error {
    NSLog(@"BTunes: decode error (%@)", [error localizedDescription]);
    [self advanceBy:1 allowRepeat:YES];
}

@end
