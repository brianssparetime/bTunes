#import <Foundation/Foundation.h>

@class AVAudioUnitEQ;

// Posted when the equalizer is switched, moved, or given a different preset.
// The player listens so the sound follows the sliders while a song is playing,
// and the window listens so two of them would agree.
extern NSString *const BTEqualizerDidChangeNotification;

// Ten sliders and a preamp, the way iTunes had them.
//
// The bands are an octave apart from 32 Hz to 16 kHz, which is the spacing a
// graphic equalizer has always used: an octave is the interval hearing treats as
// one step, so evenly spaced sliders make evenly spaced changes.
#define BT_EQ_BANDS 10

@interface BTEqualizer : NSObject

+ (instancetype)sharedEqualizer;

// The middle frequency of each slider, and the short form written under it.
// Kilohertz are written 1K rather than 1000 for the same reason iTunes did it:
// five characters under a slider fourteen points wide do not fit.
+ (NSArray *)bandFrequencies;
+ (NSString *)labelForBand:(NSUInteger)band;

// How far a slider or the preamp runs, in decibels either way. Twelve, which is
// what the scale beside the sliders is drawn to.
+ (float)largestGain;

// The presets, in the order the menu shows them, and the name of the one that
// means the sliders are wherever they were put. Manual is first, since it is
// where a hand-moved equalizer ends up and a reader looking for the current
// state should not have to scan a list of twenty names to find it.
+ (NSArray *)presetNames;
+ (NSString *)manualPresetName;

// Whether the equalizer touches the sound at all. Off leaves the audio exactly
// as the file holds it, whatever the sliders say, so a curve can be kept while
// being switched out of the way.
@property (nonatomic, assign) BOOL on;

// Which preset the sliders came from, or Manual once one has been moved. The
// name is what is remembered between runs, along with the slider positions, so a
// preset that is edited comes back edited rather than snapping to the stored
// preset's shape.
@property (nonatomic, copy) NSString *presetName;

// Applied to everything alike, before the bands. What it is for is headroom:
// boosting eight bands and leaving the preamp alone is how an equalizer comes to
// clip, and pulling the preamp down makes room for the boost.
@property (nonatomic, assign) float preamp;

- (float)gainForBand:(NSUInteger)band;
// Moving a slider by hand is what makes a preset Manual, since the curve is no
// longer the one the preset names.
- (void)setGain:(float)gain forBand:(NSUInteger)band;

// The gains a named preset asks for, or nil for a name that is not one. Manual
// answers nil too: it is not a shape, it is the absence of one.
+ (NSArray *)gainsForPresetNamed:(NSString *)name;

// Points the audio unit at whatever the sliders currently say. Called whenever
// either changes, and again whenever the graph is rebuilt, since a rebuilt unit
// remembers nothing.
- (void)applyToUnit:(AVAudioUnitEQ *)unit;

@end
