#import "BTPlayer.h"
#import "BTTrack.h"
#import "BTLibrary.h"
#import <AVFoundation/AVFoundation.h>

NSString *const BTPlayerDidChangeNotification = @"BTPlayerDidChange";
NSString *const BTPlayerTimeDidChangeNotification = @"BTPlayerTimeDidChange";
NSString *const BTPlayerCouldNotPlayNotification = @"BTPlayerCouldNotPlay";

// Playback runs through an engine rather than AVAudioPlayer because the
// analyzer needs the samples, and AVAudioPlayer hands out a loudness figure and
// nothing else. What that costs is here: elapsed time has to be worked out from
// the render clock, seeking means rescheduling the file, and the end of a song
// is noticed by watching the clock rather than by being told.
@interface BTPlayer ()
@property (nonatomic, strong) AVAudioEngine *engine;
@property (nonatomic, strong) AVAudioPlayerNode *node;
@property (nonatomic, strong) AVAudioFile *file;
@property (nonatomic, strong) BTSpectrum *spectrum;
@property (nonatomic, strong) AVAudioFormat *connectedFormat;
@property (nonatomic, assign) BOOL tapInstalled;

// Where the current scheduling began, and how far in it had reached when last
// asked. The render clock counts from each scheduling, and answers nothing at
// all once the node is paused, so both are needed to give a steady answer.
@property (nonatomic, assign) AVAudioFramePosition seekFrame;
@property (nonatomic, assign) NSTimeInterval lastKnownTime;
@property (nonatomic, assign) BOOL playing;

@property (nonatomic, strong) BTTrack *currentTrack;
@property (nonatomic, strong) NSArray *queue;          // BTTrack, in list order
@property (nonatomic, strong) NSMutableArray *order;   // indexes into queue
@property (nonatomic, assign) NSInteger orderPosition;
@property (nonatomic, strong) NSTimer *tick;
@property (nonatomic, assign) float smoothedAverage;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) float volumeBeforeMute;
// Whether this pass through the song has already been counted. Armed as a song
// starts, so winding back over the mark and forward again counts once, and a
// song on repeat counts each whole pass.
@property (nonatomic, assign) BOOL countedThisPlay;
@end

// A song long enough that half of it is a wait rather than a listen. A
// seventy-minute live set should not need thirty-five minutes to count.
#define BT_COUNTS_AFTER_AT_MOST 240.0

@implementation BTPlayer

+ (instancetype)sharedPlayer {
    static BTPlayer *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[BTPlayer alloc] init]; });
    return shared;
}

// What the transport is set to carries over between runs. Volume, shuffle and
// repeat are all the same kind of thing: a way of listening that somebody chose
// and did not expect to have to choose again.
//
// Which song was playing and how far into it deliberately do not carry over.
// The knob, which is what is written now. The older key held the multiplier
// itself and is read once to carry a setting across, since a number that meant
// a third of the way up would otherwise mean almost silence.
static NSString *const BTVolumeKnobKey = @"BTVolumeKnob";
static NSString *const BTVolumeGainKey = @"BTVolume";
static NSString *const BTShuffleKey = @"BTShuffle";
static NSString *const BTRepeatKey = @"BTRepeatMode";

- (id)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSNumber *knob = [defaults objectForKey:BTVolumeKnobKey];
        NSNumber *oldGain = [defaults objectForKey:BTVolumeGainKey];
        if (knob) {
            _volume = [knob floatValue];
        } else if (oldGain) {
            _volume = [BTPlayer volumeForGain:[oldGain floatValue]];
        } else {
            _volume = 0.75f;
        }
        _shuffle = [defaults boolForKey:BTShuffleKey];
        // Read through the enum rather than trusting the number on disk: a
        // value from some later version would otherwise leave the transport in
        // a state none of the buttons can describe.
        NSInteger mode = [defaults integerForKey:BTRepeatKey];
        _repeatMode = (mode == BTRepeatModeAll || mode == BTRepeatModeOne)
            ? (BTRepeatMode)mode : BTRepeatModeOff;
        _order = [NSMutableArray array];
        _orderPosition = -1;

        // The queue is a snapshot of a list as it stood, so it has to be told
        // when the library behind it changes.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(libraryChanged:)
                                                     name:BTLibraryDidChangeNotification
                                                   object:nil];
    }
    return self;
}

// Songs taken out of the library leave the queue with them. Without this a song
// removed while it was playing went on playing, and stayed in what next and
// previous walked through, for as long as the queue lasted.
- (void)libraryChanged:(NSNotification *)note {
    if ([self.queue count] == 0) return;

    // By identity rather than by id: these are the very objects the library
    // holds, and a track carries no equality of its own.
    NSSet *held = [NSSet setWithArray:[BTLibrary sharedLibrary].tracks];
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:[self.queue count]];
    NSUInteger i;
    for (i = 0; i < [self.queue count]; i++) {
        BTTrack *one = [self.queue objectAtIndex:i];
        if ([held containsObject:one]) [kept addObject:one];
    }
    if ([kept count] == [self.queue count]) return;

    BTTrack *playing = self.currentTrack;
    BOOL playingWent = (playing != nil && ![held containsObject:playing]);

    self.queue = kept;
    NSInteger where = 0;
    if (!playingWent && playing) {
        NSUInteger found = [kept indexOfObject:playing];
        if (found != NSNotFound) where = (NSInteger)found;
    }
    // Rebuilt whatever happens, since the order holds places in the queue and
    // the queue has just changed shape underneath it.
    [self rebuildOrderStartingAtIndex:where];

    // The song playing is not in the library any more, so it stops. Carrying on
    // would be playing something the library says it does not have.
    if (playingWent) [self stop];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_tick invalidate];
    if (_tapInstalled) [_node removeTapOnBus:0];
    [_engine stop];
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
    [[NSUserDefaults standardUserDefaults] setBool:shuffle forKey:BTShuffleKey];
    if ([self.queue count] > 0 && self.currentTrack) {
        NSInteger current = (NSInteger)[self.queue indexOfObject:self.currentTrack];
        [self rebuildOrderStartingAtIndex:(current == (NSInteger)NSNotFound ? 0 : current)];
    }
    [self postChange];
}

- (void)setRepeatMode:(BTRepeatMode)repeatMode {
    _repeatMode = repeatMode;
    [[NSUserDefaults standardUserDefaults] setInteger:repeatMode forKey:BTRepeatKey];
    [self postChange];
}

#pragma mark - Engine

// Built once, and rewired only when the next song is shaped differently from
// the one the graph was built for. Tearing the graph down between two ordinary
// tracks would put a silence between them that the music does not call for.
- (BOOL)prepareEngineForFile:(AVAudioFile *)file error:(NSError **)error {
    if (self.engine == nil) {
        self.engine = [[AVAudioEngine alloc] init];
        self.node = [[AVAudioPlayerNode alloc] init];
        [self.engine attachNode:self.node];
    }

    [self.node stop];

    AVAudioFormat *format = [file processingFormat];
    if (![format isEqual:self.connectedFormat]) {
        [self teardownTap];
        [self.engine stop];
        [self.engine connect:self.node to:[self.engine mainMixerNode] format:format];
        self.connectedFormat = format;
        self.spectrum = [[BTSpectrum alloc] initWithSampleRate:[format sampleRate]];
        [self installTapWithFormat:format];
        [self.engine prepare];
    } else {
        [self.spectrum reset];
    }

    // Set again here because rewiring the node loses it, and it is the gain that
    // goes in rather than the knob.
    [self.node setVolume:[BTPlayer gainForVolume:self.volume]];

    if (![self.engine isRunning] && ![self.engine startAndReturnError:error]) return NO;
    return YES;
}

- (BOOL)ensureEngineRunning {
    if (self.engine == nil) return NO;
    if ([self.engine isRunning]) return YES;
    NSError *error = nil;
    if ([self.engine startAndReturnError:&error]) return YES;
    NSLog(@"BTunes: cannot start audio (%@)", [error localizedDescription]);
    return NO;
}

- (void)teardownTap {
    if (!self.tapInstalled) return;
    [self.node removeTapOnBus:0];
    self.tapInstalled = NO;
}

- (void)installTapWithFormat:(AVAudioFormat *)format {
    __weak BTPlayer *weakSelf = self;
    [self.node installTapOnBus:0
                    bufferSize:1024
                        format:format
                         block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        [weakSelf analyzeBuffer:buffer];
    }];
    self.tapInstalled = YES;
}

// Runs on the render thread, so it allocates nothing and takes no locks. The
// channels are averaged because the analyzer shows one picture, not one a side.
- (void)analyzeBuffer:(AVAudioPCMBuffer *)buffer {
    BTSpectrum *spectrum = self.spectrum;
    if (spectrum == nil || buffer == nil) return;

    float * const *channels = [buffer floatChannelData];
    if (channels == NULL) return;

    NSUInteger channelCount = [[buffer format] channelCount];
    NSUInteger stride = [buffer stride];
    AVAudioFrameCount frames = [buffer frameLength];
    if (channelCount == 0 || frames == 0) return;

    float mono[1024];
    AVAudioFrameCount done = 0;
    while (done < frames) {
        NSUInteger take = frames - done;
        if (take > 1024) take = 1024;

        NSUInteger i, c;
        for (i = 0; i < take; i++) {
            float sum = 0.0f;
            for (c = 0; c < channelCount; c++) {
                sum += channels[c][(done + i) * stride];
            }
            mono[i] = sum / (float)channelCount;
        }
        [spectrum consumeSamples:mono count:take];
        done += (AVAudioFrameCount)take;
    }
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

// The song at one place in the order, started, or NO if it cannot be. Nothing
// here looks anywhere else: passing over what cannot play is the loop's job
// below, and keeping the two apart is what stops them calling each other.
- (BOOL)openTrackAtOrderPosition:(NSInteger)position wasLocked:(BOOL *)outLocked {
    if (outLocked) *outLocked = NO;
    if (position < 0 || position >= (NSInteger)[self.order count]) return NO;

    NSInteger queueIndex = [[self.order objectAtIndex:position] integerValue];
    if (queueIndex < 0 || queueIndex >= (NSInteger)[self.queue count]) return NO;

    BTTrack *track = [self.queue objectAtIndex:queueIndex];

    // Locked purchases are kept for their playlist membership but cannot be
    // decoded here.
    if (track.isProtected) {
        if (outLocked) *outLocked = YES;
        return NO;
    }

    NSError *error = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:[track fileURL] error:&error];
    if (file == nil || ![self prepareEngineForFile:file error:&error]) {
        NSLog(@"BTunes: cannot open %@ (%@)", [track resolvedPath], [error localizedDescription]);
        return NO;
    }

    self.file = file;

    // A song set to begin partway in starts there rather than at nothing.
    double rate = [[file processingFormat] sampleRate];
    AVAudioFramePosition from = (AVAudioFramePosition)([track playbackStart] * rate);
    if (from < 0 || from >= [file length]) from = 0;

    [self scheduleFromFrame:from];
    [self.node play];
    self.playing = YES;

    self.currentTrack = track;
    self.orderPosition = position;
    // Nothing has been listened to yet. The count goes up once this pass
    // reaches the mark, which the tick watches for.
    self.countedThisPlay = NO;

    [self startTick];
    [self postChange];
    return YES;
}

// The node's clock counts from each scheduling, so where the scheduling started
// is recorded alongside it.
- (void)scheduleFromFrame:(AVAudioFramePosition)frame {
    AVAudioFile *file = self.file;
    if (file == nil) return;
    if (frame < 0) frame = 0;
    if (frame > [file length]) frame = [file length];

    self.seekFrame = frame;
    self.lastKnownTime = (NSTimeInterval)frame / [[file processingFormat] sampleRate];

    AVAudioFrameCount remaining = (AVAudioFrameCount)([file length] - frame);
    if (remaining == 0) return;

    [self.node scheduleSegment:file
                 startingFrame:frame
                    frameCount:remaining
                        atTime:nil
             completionHandler:nil];
}

- (void)togglePlayPause {
    if (self.file == nil) return;
    if (self.playing) {
        [self pause];
    } else {
        [self resume];
    }
}

- (void)pause {
    // Read before pausing: once the node stops, its clock answers nothing and
    // the last reading is all there is to go on.
    [self currentTime];
    [self.node pause];
    self.playing = NO;
    [self stopTick];
    self.smoothedAverage = 0;
    [self.spectrum reset];
    [self postChange];
}

- (void)resume {
    if (self.file == nil) return;
    if (![self ensureEngineRunning]) return;
    [self.node play];
    self.playing = YES;
    [self startTick];
    [self postChange];
}

- (void)stop {
    [self.node stop];
    [self teardownTap];
    [self.engine stop];

    self.file = nil;
    self.spectrum = nil;
    self.connectedFormat = nil;
    self.currentTrack = nil;
    self.playing = NO;
    self.seekFrame = 0;
    self.lastKnownTime = 0;
    self.smoothedAverage = 0;

    [self stopTick];
    [self postChange];
}

- (void)next {
    if ([self.order count] == 0) return;
    [self advanceBy:1 allowRepeat:YES];
}

- (void)previous {
    if (self.file && [self currentTime] > 3.0) {
        [self seekToTime:0];
        return;
    }
    if ([self.order count] == 0) return;
    [self advanceBy:-1 allowRepeat:YES];
}

// The first song from here that will actually play, walking whichever way it was
// asked to. Songs that cannot play are passed over.
//
// A loop, not a method that calls itself. Passing over a song used to mean
// calling back into the advance, which put a stack frame on for every song
// skipped: a playlist of the library's eight hundred locked purchases put on
// eight hundred. It also always stepped forward when it skipped, whichever way
// it had been going, so Previous onto a locked song walked forward again and
// landed back where it started, which reads as a button that does not work.
NSInteger BTWalkForPlayable(NSInteger count, NSInteger from, NSInteger step,
                            BOOL wrapping, NSUInteger *outPassedOver,
                            BOOL (^tryAt)(NSInteger place)) {
    if (outPassedOver) *outPassedOver = 0;
    if (count <= 0 || tryAt == nil) return -1;

    NSInteger at = from;
    NSUInteger passedOver = 0;
    NSInteger turn;
    for (turn = 0; turn < count; turn++) {
        if (at < 0 || at >= count) {
            if (!wrapping) break;
            at = (at < 0) ? count - 1 : 0;
        }
        if (tryAt(at)) {
            if (outPassedOver) *outPassedOver = passedOver;
            return at;
        }
        passedOver++;
        at += step;
    }
    if (outPassedOver) *outPassedOver = passedOver;
    return -1;
}

- (BOOL)startPlayableFrom:(NSInteger)position
                 stepping:(NSInteger)step
                 wrapping:(BOOL)wrapping {
    __block NSUInteger locked = 0;
    NSUInteger passedOver = 0;

    NSInteger landed = BTWalkForPlayable((NSInteger)[self.order count], position, step,
                                         wrapping, &passedOver, ^BOOL(NSInteger place) {
        BOOL wasLocked = NO;
        BOOL started = [self openTrackAtOrderPosition:place wasLocked:&wasLocked];
        if (wasLocked) locked++;
        return started;
    });
    if (landed >= 0) return YES;

    [self stop];
    if (passedOver > 0) [self sayNothingPlayed:passedOver locked:locked];
    return NO;
}

// Said in the readout rather than left to silence. Pressing play on a playlist
// of locked purchases did nothing at all and explained nothing, which is the
// same thing on screen as a player that is broken.
- (void)sayNothingPlayed:(NSUInteger)passedOver locked:(NSUInteger)locked {
    NSString *why = (locked == passedOver)
        ? [NSString stringWithFormat:@"%lu locked song%@", (unsigned long)locked,
           (locked == 1 ? @"" : @"s")]
        : [NSString stringWithFormat:@"%lu song%@ could not be read",
           (unsigned long)passedOver, (passedOver == 1 ? @"" : @"s")];

    [[NSNotificationCenter defaultCenter] postNotificationName:BTPlayerCouldNotPlayNotification
                                                        object:self
                                                      userInfo:@{@"reason": why}];
}

- (BOOL)startTrackAtOrderPosition:(NSInteger)position {
    return [self startPlayableFrom:position stepping:1 wrapping:NO];
}

- (BOOL)advanceBy:(NSInteger)delta allowRepeat:(BOOL)allowRepeat {
    NSInteger count = (NSInteger)[self.order count];
    if (count == 0) return NO;

    BOOL roundAgain = (self.repeatMode == BTRepeatModeAll);
    NSInteger next = self.orderPosition + delta;
    NSInteger step = (delta < 0) ? -1 : 1;

    if (next >= count) {
        if (!(allowRepeat && roundAgain)) {
            [self stop];
            return NO;
        }
        next = 0;
    }
    if (next < 0) {
        // Nothing sits before the first song. With repeat on, Previous there
        // means the last one; without it, the first, and the search for one
        // that plays has to look forward from there since there is no back.
        next = roundAgain ? count - 1 : 0;
        if (!roundAgain) step = 1;
    }
    return [self startPlayableFrom:next stepping:step wrapping:(allowRepeat && roundAgain)];
}

// Seeking means scheduling the file again from the new place, and stopping the
// node first so its clock starts over from there.
- (void)seekToTime:(NSTimeInterval)time {
    AVAudioFile *file = self.file;
    if (file == nil) return;

    NSTimeInterval total = [self duration];
    if (time < 0) time = 0;
    if (time > total) time = total;

    BOOL wasPlaying = self.playing;
    [self.node stop];
    [self.spectrum reset];
    [self scheduleFromFrame:(AVAudioFramePosition)(time * [[file processingFormat] sampleRate])];
    if (wasPlaying) {
        [self ensureEngineRunning];
        [self.node play];
    }
    [self postTime];
}

#pragma mark - State

- (BOOL)isPlaying {
    return self.file != nil && self.playing;
}

// Where the scheduling began plus what the node has rendered since. While the
// node is paused it reports nothing, and the last good reading stands.
- (NSTimeInterval)currentTime {
    AVAudioFile *file = self.file;
    if (file == nil) return 0;

    AVAudioTime *nodeTime = [self.node lastRenderTime];
    AVAudioTime *playerTime = nodeTime ? [self.node playerTimeForNodeTime:nodeTime] : nil;
    if (playerTime == nil || [playerTime sampleRate] <= 0) return self.lastKnownTime;

    NSTimeInterval base = (NSTimeInterval)self.seekFrame / [[file processingFormat] sampleRate];
    NSTimeInterval elapsed = (NSTimeInterval)[playerTime sampleTime] / [playerTime sampleRate];
    if (elapsed < 0) elapsed = 0;

    NSTimeInterval now = base + elapsed;
    NSTimeInterval total = [self duration];
    if (now < 0) now = 0;
    if (total > 0 && now > total) now = total;

    self.lastKnownTime = now;
    return now;
}

- (NSTimeInterval)duration {
    AVAudioFile *file = self.file;
    if (file) {
        double rate = [[file processingFormat] sampleRate];
        if (rate > 0) return (NSTimeInterval)[file length] / rate;
    }
    return self.currentTrack ? self.currentTrack.duration : 0;
}

+ (float)volumeRangeInDecibels { return 60.0f; }

// Twice the level of the file, which is six decibels above it. BriansFlix stops
// at one and a half for the same reason; a little more here because the quietest
// thing in this library is a good deal quieter than the loudest.
+ (float)volumeCeiling { return 2.0f; }

+ (float)gainForVolume:(float)volume {
    if (volume <= 0.0f) return 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    return (float)([self volumeCeiling] *
                   pow(10.0, (volume - 1.0f) * [self volumeRangeInDecibels] / 20.0));
}

+ (float)volumeForGain:(float)gain {
    if (gain <= 0.0f) return 0.0f;
    float knob = (float)(1.0 + 20.0 * log10(gain / [self volumeCeiling]) /
                               [self volumeRangeInDecibels]);
    if (knob < 0.0f) knob = 0.0f;
    if (knob > 1.0f) knob = 1.0f;
    return knob;
}

- (void)setVolume:(float)volume {
    _volume = volume;
    [self.node setVolume:[BTPlayer gainForVolume:volume]];
    [[NSUserDefaults standardUserDefaults] setFloat:volume forKey:BTVolumeKnobKey];
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

// Nothing sounding reads as silence, so a paused song does not leave the last
// reading standing for the display to go on showing.
- (float)averageLevel {
    return [self isPlaying] ? self.smoothedAverage : 0.0f;
}

- (void)getBandLevels:(float *)bands {
    if (bands == NULL) return;
    BTSpectrum *spectrum = self.spectrum;
    if (spectrum != nil && [self isPlaying]) {
        [spectrum getBands:bands];
        return;
    }
    NSUInteger i;
    for (i = 0; i < BT_ANALYZER_BANDS; i++) bands[i] = 0.0f;
}

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

// A song set to stop early is stopped here, and so is one that simply runs out:
// the node reports the end of a file only after the fact, and both endings mean
// the same thing to whatever comes next.
- (BOOL)passedItsEnd {
    if (self.file == nil || !self.playing) return NO;

    NSTimeInterval now = [self currentTime];
    BTTrack *track = self.currentTrack;
    if (track && track.usesEndTime) {
        NSTimeInterval end = [track playbackEnd];
        if (end > 0 && now >= end) return YES;
    }

    NSTimeInterval total = [self duration];
    return total > 0 && now >= total - 0.02;
}

+ (NSTimeInterval)countingMarkBetween:(NSTimeInterval)start and:(NSTimeInterval)end {
    NSTimeInterval span = end - start;
    if (span <= 0 || isnan(span)) return -1.0;

    NSTimeInterval half = span / 2.0;
    return start + (half < BT_COUNTS_AFTER_AT_MOST ? half : BT_COUNTS_AFTER_AT_MOST);
}

// Where the mark falls for the song playing now. What plays is the song's own
// range when it has one, and the whole file otherwise; the file is asked rather
// than the tag, since the tag is what iTunes believed and the file is what there
// is.
- (NSTimeInterval)countingMark {
    BTTrack *track = self.currentTrack;
    if (track == nil) return -1.0;

    NSTimeInterval end = track.usesEndTime ? [track playbackEnd] : [self duration];
    return [BTPlayer countingMarkBetween:[track playbackStart] and:end];
}

// A play, once this pass has reached the mark. The date moves with it, so "last
// played" means the last time the song was heard rather than the last time it
// was passed over.
- (void)countThePlayIfItIsEarned {
    if (self.countedThisPlay || self.currentTrack == nil) return;

    NSTimeInterval mark = [self countingMark];
    if (mark < 0 || [self currentTime] < mark) return;

    self.countedThisPlay = YES;
    self.currentTrack.playCount += 1;
    self.currentTrack.lastPlayed = [NSDate date];
    // The song recorded something about itself. Nothing joined or left a list,
    // so the window redraws the count where it stands rather than rebuilding.
    [[BTLibrary sharedLibrary] noteTrackChanged];
}

- (void)tickFired:(NSTimer *)timer {
    // Asked before the end is noticed, or a song shorter than one turn of the
    // timer would reach its end and be counted by neither.
    [self countThePlayIfItIsEarned];

    if ([self passedItsEnd]) {
        [self reachedTheEnd];
        return;
    }
    if (self.file) {
        float average = [self.spectrum averageLevel];
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

// Reached however it was reached: the file ran out, or the song's own end time
// came round. Both mean the same thing to whatever comes next.
- (void)reachedTheEnd {
    if (self.repeatMode == BTRepeatModeOne) {
        [self startTrackAtOrderPosition:self.orderPosition];
        return;
    }
    [self advanceBy:1 allowRepeat:YES];
}

@end
