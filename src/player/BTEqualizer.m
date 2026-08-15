#import "BTEqualizer.h"
#import <AVFoundation/AVFoundation.h>

NSString *const BTEqualizerDidChangeNotification = @"BTEqualizerDidChange";

// How the equalizer was left, which carries over between runs the way the
// volume, the shuffle and the repeat do. All of them are a way of listening that
// somebody chose and did not expect to have to choose again.
//
// The slider positions are kept alongside the preset name rather than derived
// from it, so a preset that has been adjusted comes back adjusted.
static NSString *const BTEqualizerOnKey = @"BTEqualizerOn";
static NSString *const BTEqualizerPresetKey = @"BTEqualizerPreset";
static NSString *const BTEqualizerPreampKey = @"BTEqualizerPreamp";
static NSString *const BTEqualizerGainsKey = @"BTEqualizerGains";

// How wide each band reaches, in octaves. The sliders are an octave apart, so a
// band an octave wide meets its neighbours at their edges: narrower leaves gaps
// the sliders cannot reach, wider makes each slider drag its neighbours' ranges
// with it and a curve drawn on the sliders comes out flatter than it looks.
#define BT_EQ_BANDWIDTH 1.0f

@implementation BTEqualizer {
    float _gains[BT_EQ_BANDS];
}

+ (instancetype)sharedEqualizer {
    static BTEqualizer *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[BTEqualizer alloc] initFromDefaults]; });
    return shared;
}

+ (NSArray *)bandFrequencies {
    return @[@32, @64, @125, @250, @500, @1000, @2000, @4000, @8000, @16000];
}

+ (NSString *)labelForBand:(NSUInteger)band {
    NSArray *frequencies = [self bandFrequencies];
    if (band >= [frequencies count]) return @"";

    NSInteger hz = [[frequencies objectAtIndex:band] integerValue];
    if (hz < 1000) return [NSString stringWithFormat:@"%ld", (long)hz];
    return [NSString stringWithFormat:@"%ldK", (long)(hz / 1000)];
}

+ (float)largestGain { return 12.0f; }

+ (NSString *)manualPresetName { return @"Manual"; }

// The presets iTunes offered, drawn to the shape each name describes rather than
// copied number for number, which is not something the application can be asked
// for. A reader wanting the exact curve iTunes used will not find it here; a
// listener wanting the record to sound like more bass will.
//
// Kept as one table so a preset is a row of numbers rather than a branch of
// code, and adding one means adding a row.
+ (NSDictionary *)presetTable {
    static NSDictionary *table = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            //                 32     64    125    250    500     1K     2K     4K     8K    16K
            @"Acoustic":      @[@4.0,  @4.0,  @3.0,  @1.0,  @1.5,  @1.5,  @3.0,  @3.5,  @3.0,  @1.5],
            @"Bass Booster":  @[@6.0,  @5.0,  @4.0,  @2.5,  @1.0,  @0.0,  @0.0,  @0.0,  @0.0,  @0.0],
            @"Bass Reducer":  @[@-6.0, @-5.0, @-4.0, @-2.5, @-1.0, @0.0,  @0.0,  @0.0,  @0.0,  @0.0],
            @"Classical":     @[@5.0,  @4.0,  @3.0,  @2.5,  @-1.5, @-1.5, @0.0,  @2.0,  @3.0,  @4.0],
            @"Dance":         @[@6.0,  @4.5,  @2.0,  @0.0,  @1.5,  @3.0,  @4.0,  @4.0,  @2.5,  @0.0],
            @"Deep":          @[@5.0,  @4.0,  @2.5,  @1.0,  @3.0,  @2.0,  @1.0,  @-2.0, @-3.5, @-4.5],
            @"Electronic":    @[@4.5,  @4.0,  @1.5,  @0.0,  @-2.0, @2.0,  @1.0,  @1.0,  @4.0,  @5.0],
            @"Flat":          @[@0.0,  @0.0,  @0.0,  @0.0,  @0.0,  @0.0,  @0.0,  @0.0,  @0.0,  @0.0],
            @"Hip-Hop":       @[@5.5,  @5.0,  @2.5,  @3.5,  @-1.0, @-0.5, @1.5,  @-0.5, @2.0,  @3.0],
            @"Jazz":          @[@4.0,  @3.0,  @1.5,  @2.0,  @-1.5, @-1.5, @0.0,  @1.5,  @3.0,  @4.0],
            @"Latin":         @[@5.0,  @3.5,  @0.0,  @0.0,  @-1.5, @-1.5, @-1.5, @0.0,  @3.5,  @5.0],
            @"Loudness":      @[@6.0,  @4.5,  @0.0,  @0.0,  @-2.0, @0.0,  @-1.0, @-5.0, @5.0,  @1.0],
            @"Lounge":        @[@-3.0, @-1.5, @-0.5, @1.5,  @4.0,  @3.0,  @0.0,  @-1.5, @2.0,  @1.0],
            @"Piano":         @[@3.0,  @2.0,  @0.0,  @2.5,  @3.0,  @1.5,  @3.5,  @4.0,  @3.0,  @2.5],
            @"Pop":           @[@-1.5, @-1.0, @0.0,  @2.0,  @4.0,  @4.0,  @2.0,  @0.0,  @-1.0, @-1.5],
            @"R&B":           @[@3.0,  @6.5,  @5.5,  @1.5,  @-2.5, @-1.5, @2.0,  @2.5,  @3.0,  @3.5],
            @"Rock":          @[@5.0,  @4.0,  @3.0,  @1.5,  @-0.5, @-1.0, @0.5,  @3.0,  @3.5,  @4.0],
            @"Small Speakers":@[@5.5,  @4.5,  @3.5,  @2.0,  @0.5,  @-0.5, @-1.5, @-2.5, @-3.0, @-3.5],
            @"Spoken Word":   @[@-3.5, @0.0,  @0.0,  @0.5,  @3.5,  @4.0,  @4.5,  @4.0,  @2.5,  @0.0],
            @"Treble Booster":@[@0.0,  @0.0,  @0.0,  @0.0,  @0.0,  @1.0,  @2.5,  @4.0,  @5.0,  @6.0],
            @"Treble Reducer":@[@0.0,  @0.0,  @0.0,  @0.0,  @0.0,  @-1.0, @-2.5, @-4.0, @-5.0, @-6.0],
            @"Vocal Booster": @[@-1.5, @-3.0, @-3.0, @1.5,  @4.0,  @4.0,  @3.0,  @1.5,  @0.0,  @-1.5]
        };
    });
    return table;
}

+ (NSArray *)presetNames {
    NSArray *named = [[[self presetTable] allKeys]
                      sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    return [@[[self manualPresetName]] arrayByAddingObjectsFromArray:named];
}

+ (NSArray *)gainsForPresetNamed:(NSString *)name {
    if (name == nil) return nil;
    return [[self presetTable] objectForKey:name];
}

- (instancetype)initFromDefaults {
    self = [super init];
    if (self == nil) return nil;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    _on = [defaults boolForKey:BTEqualizerOnKey];

    NSString *saved = [defaults stringForKey:BTEqualizerPresetKey];
    // A name from some later version, or one whose preset has since been
    // dropped, leaves the sliders where they are rather than being kept as a
    // name nothing can look up.
    _presetName = ([BTEqualizer gainsForPresetNamed:saved] != nil)
        ? [saved copy] : [[BTEqualizer manualPresetName] copy];

    _preamp = [self clamped:[defaults floatForKey:BTEqualizerPreampKey]];

    NSArray *gains = [defaults arrayForKey:BTEqualizerGainsKey];
    NSUInteger i;
    for (i = 0; i < BT_EQ_BANDS; i++) {
        id value = ([gains count] > i) ? [gains objectAtIndex:i] : nil;
        _gains[i] = [value respondsToSelector:@selector(floatValue)]
            ? [self clamped:[value floatValue]] : 0.0f;
    }
    return self;
}

- (float)clamped:(float)gain {
    float largest = [BTEqualizer largestGain];
    if (isnan(gain)) return 0.0f;
    if (gain > largest) return largest;
    if (gain < -largest) return -largest;
    return gain;
}

#pragma mark - Settings

- (void)setOn:(BOOL)on {
    if (_on == on) return;
    _on = on;
    [self save];
}

- (void)setPreamp:(float)preamp {
    preamp = [self clamped:preamp];
    if (_preamp == preamp) return;
    _preamp = preamp;
    [self save];
}

// Choosing a preset moves the sliders to it. Choosing Manual moves nothing: it
// is what the sliders already are once one has been touched, so selecting it
// from the menu is a statement rather than an instruction.
- (void)setPresetName:(NSString *)presetName {
    NSArray *gains = [BTEqualizer gainsForPresetNamed:presetName];
    _presetName = [(gains ? presetName : [BTEqualizer manualPresetName]) copy];

    if (gains) {
        NSUInteger i;
        for (i = 0; i < BT_EQ_BANDS && i < [gains count]; i++) {
            _gains[i] = [self clamped:[[gains objectAtIndex:i] floatValue]];
        }
    }
    [self save];
}

- (float)gainForBand:(NSUInteger)band {
    if (band >= BT_EQ_BANDS) return 0.0f;
    return _gains[band];
}

- (void)setGain:(float)gain forBand:(NSUInteger)band {
    if (band >= BT_EQ_BANDS) return;
    gain = [self clamped:gain];
    if (_gains[band] == gain) return;

    _gains[band] = gain;
    _presetName = [[BTEqualizer manualPresetName] copy];
    [self save];
}

- (void)save {
    NSMutableArray *gains = [NSMutableArray arrayWithCapacity:BT_EQ_BANDS];
    NSUInteger i;
    for (i = 0; i < BT_EQ_BANDS; i++) [gains addObject:@(_gains[i])];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:_on forKey:BTEqualizerOnKey];
    [defaults setObject:(_presetName ?: [BTEqualizer manualPresetName])
                 forKey:BTEqualizerPresetKey];
    [defaults setFloat:_preamp forKey:BTEqualizerPreampKey];
    [defaults setObject:gains forKey:BTEqualizerGainsKey];

    [[NSNotificationCenter defaultCenter] postNotificationName:BTEqualizerDidChangeNotification
                                                        object:self];
}

#pragma mark - The audio unit

- (void)applyToUnit:(AVAudioUnitEQ *)unit {
    if (unit == nil) return;

    // Switched off means out of the way entirely rather than set flat. A flat
    // set of filters still costs the arithmetic and still rings a little at the
    // edges; a bypassed unit passes the samples through untouched.
    [unit setBypass:!self.on];
    [unit setGlobalGain:(self.on ? self.preamp : 0.0f)];

    NSArray *bands = [unit bands];
    NSArray *frequencies = [BTEqualizer bandFrequencies];
    NSUInteger i;
    for (i = 0; i < [bands count] && i < BT_EQ_BANDS; i++) {
        AVAudioUnitEQFilterParameters *band = [bands objectAtIndex:i];
        [band setFilterType:AVAudioUnitEQFilterTypeParametric];
        [band setFrequency:[[frequencies objectAtIndex:i] floatValue]];
        [band setBandwidth:BT_EQ_BANDWIDTH];
        [band setGain:_gains[i]];
        // A band sitting at nothing is switched out for the same reason the
        // whole unit is: no filter at all is cheaper and quieter than a filter
        // set to do nothing.
        [band setBypass:(_gains[i] == 0.0f)];
    }
}

@end
