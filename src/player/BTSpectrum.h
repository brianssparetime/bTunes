#import <Foundation/Foundation.h>

// How many bands the analyzer reports, and so how many bars the mini-mode
// display draws. Bands are spaced logarithmically, the way hearing is.
#define BT_ANALYZER_BANDS 31

// A running Fourier transform of whatever is being played, reduced to a handful
// of bands for display.
//
// Samples arrive from the audio render thread and the bands are read from the
// main thread. Nothing is locked: the results are a float per band, a torn read
// costs one frame of one bar, and taking a lock on the render thread would risk
// a great deal more than that to fix it.
@interface BTSpectrum : NSObject

- (instancetype)initWithSampleRate:(double)sampleRate;

// Mono samples, in whatever lengths the render thread supplies them. Cheap
// enough to call from an audio tap: a transform runs once per window filled.
- (void)consumeSamples:(const float *)samples count:(NSUInteger)count;

// The bands, each 0 to 1. Fills BT_ANALYZER_BANDS floats.
- (void)getBands:(float *)bands;

// Overall loudness, 0 to 1, on the same scale as the bands.
- (float)averageLevel;

// Back to silence, for a stop or a change of song.
- (void)reset;

@end
