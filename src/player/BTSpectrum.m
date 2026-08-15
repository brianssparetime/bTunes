#import "BTSpectrum.h"
#import <Accelerate/Accelerate.h>

// Two windows, because one cannot do both jobs.
//
// A window is a look at the recent past, and its length decides two things
// against each other. Long tells frequencies apart: the bars are spaced by ear,
// so the lowest of them are only a few hertz wide, and a short window reads
// several of them off the same bin and moves the bottom of the display as one
// piece. Short answers quickly: every reading is an average over the whole
// window, so a long one is still reporting a drum hit long after it has gone.
//
// Measured, one window of 4096 samples took 69 ms to get a bar up and 91 ms to
// bring it down, which at fifty frames a second is three and a half frames
// spent climbing. Halving it took that to 22 and 45. But halving it also put a
// 60 Hz tone on the third bar instead of the first, and quartering it put the
// same tone on the fifth. Faster bars that lie about which note is playing are
// not a better display.
//
// So the choice is refused. The bottom bars are read from a long window and the
// rest from a short one taken over the newest half of the same samples. That is
// not a compromise between the two, it is both, and it costs one more transform
// on a thread that has room for it.
//
// The split is honest rather than convenient: a 45 Hz note takes 22 ms to
// complete one cycle, so no analysis of any kind can place it sooner. Bass is
// slow to identify because bass is slow. Above a couple of hundred hertz that
// stops being true and the eye starts noticing, which is where the short window
// takes over.
#define BT_LONG_LOG2 12
#define BT_LONG_SIZE (1 << BT_LONG_LOG2)
#define BT_LONG_BINS (BT_LONG_SIZE / 2)

#define BT_SHORT_LOG2 11
#define BT_SHORT_SIZE (1 << BT_SHORT_LOG2)
#define BT_SHORT_BINS (BT_SHORT_SIZE / 2)

// The first bar taken from the short window. Bar 7 covers 170 to 205 Hz, and
// below that a band is narrower than the short window can resolve.
#define BT_SHORT_FROM_BAND 7

// How often a reading is taken, which is a separate question from how long a
// window is. Every 512 samples is a new reading every twelve milliseconds, so
// the display always has something newer than the frame it last drew.
#define BT_FFT_HOP 512

// The span the display covers. Below the low end is rumble and above the high
// end is mostly nothing, and neither earns a bar.
//
// The top stops at 12 kHz rather than 16 because this library is lossy. An mp3
// or an AAC file is filtered off somewhere around 15 or 16 kHz by the encoder,
// so a bar drawn above that is showing the encoder rather than the music.
// Measured over six records off the target machine, the topmost bar lit 41 per
// cent of frames reaching to 16 kHz and 50 per cent reaching to 12, and the
// bottom bars were unmoved by the change. Pulling it further in to 10 kHz bought
// two more points at the top and cost the bass seven, since the tilt pivots on
// the middle band and moving the span moves the pivot with it.
#define BT_BAND_LOW_HZ 45.0
#define BT_BAND_HIGH_HZ 12000.0

// Where the bars bottom out and where they top out. The display applies its own
// scaling on top of this, so the span matters more than the exact calibration.
// The top sits at full scale rather than below it because a band pinned to the
// ceiling has lost its place in the picture, and a picture is the whole point.
#define BT_FLOOR_DB (-66.0f)
#define BT_REF_DB (0.0f)

// Recorded music holds far more energy in the bass than anywhere else, so an
// unweighted transform draws a ramp sloping down to the right whatever is
// playing. Tilting the bands a few decibels an octave is what makes the display
// show the music instead of showing that fact. The tilt pivots about the middle
// band rather than lifting the top, so it changes the shape of the picture
// without raising the whole of it towards the ceiling.
#define BT_TILT_DB_PER_OCTAVE 4.0
#define BT_TILT_LIMIT_DB 14.0

@implementation BTSpectrum {
    // One setup serves both transforms: a setup made for a given size will run
    // any smaller power of two as well.
    FFTSetup _setup;
    double _sampleRate;

    float _longWindow[BT_LONG_SIZE];
    float _shortWindow[BT_SHORT_SIZE];
    float _accum[BT_LONG_SIZE];
    NSUInteger _fill;

    float _real[BT_LONG_BINS];
    float _imag[BT_LONG_BINS];
    float _longMagnitudes[BT_LONG_BINS];
    float _shortMagnitudes[BT_SHORT_BINS];

    NSUInteger _firstBin[BT_ANALYZER_BANDS];
    NSUInteger _lastBin[BT_ANALYZER_BANDS];
    float _tilt[BT_ANALYZER_BANDS];

    float _bands[BT_ANALYZER_BANDS];
    float _level;
}

+ (double)lowestFrequency { return BT_BAND_LOW_HZ; }
+ (double)highestFrequency { return BT_BAND_HIGH_HZ; }
+ (float)decibelSpan { return BT_REF_DB - BT_FLOOR_DB; }

- (instancetype)initWithSampleRate:(double)sampleRate {
    self = [super init];
    if (self == nil) return nil;

    _sampleRate = sampleRate > 0 ? sampleRate : 44100.0;
    _setup = vDSP_create_fftsetup(BT_LONG_LOG2, kFFTRadix2);
    if (_setup == NULL) return nil;

    vDSP_hann_window(_longWindow, BT_LONG_SIZE, vDSP_HANN_NORM);
    vDSP_hann_window(_shortWindow, BT_SHORT_SIZE, vDSP_HANN_NORM);
    [self buildBandTable];
    return self;
}

// Which window a bar is read from. The bottom bars need the long one to be told
// apart at all; everything above answers faster with the short one.
static BOOL BTBandUsesShortWindow(NSUInteger band) {
    return band >= BT_SHORT_FROM_BAND;
}

- (void)dealloc {
    if (_setup) vDSP_destroy_fftsetup(_setup);
}

// Bands share bins at the bottom, where the transform cannot separate one
// semitone of bass from the next. Spreading them apart by force would put a
// frequency on a bar that the bar is not measuring.
- (void)buildBandTable {
    double nyquist = _sampleRate / 2.0;
    double high = BT_BAND_HIGH_HZ < nyquist * 0.95 ? BT_BAND_HIGH_HZ : nyquist * 0.95;
    double span = high / BT_BAND_LOW_HZ;

    NSUInteger i;
    for (i = 0; i < BT_ANALYZER_BANDS; i++) {
        double lowF = BT_BAND_LOW_HZ * pow(span, (double)i / (double)BT_ANALYZER_BANDS);
        double highF = BT_BAND_LOW_HZ * pow(span, (double)(i + 1) / (double)BT_ANALYZER_BANDS);

        // Bins are wider in the short window, so a bar's bins depend on which
        // window it is read from. Working them out against the wrong one is how
        // a bar comes to report a frequency it is not measuring.
        BOOL shortWindow = BTBandUsesShortWindow(i);
        double binHz = _sampleRate / (double)(shortWindow ? BT_SHORT_SIZE : BT_LONG_SIZE);
        NSInteger topBin = (shortWindow ? BT_SHORT_BINS : BT_LONG_BINS) - 1;

        NSInteger first = (NSInteger)floor(lowF / binHz);
        NSInteger last = (NSInteger)floor(highF / binHz);
        if (first < 1) first = 1;                       // bin zero is the offset, not a note
        if (last < first) last = first;
        if (last > topBin) last = topBin;
        if (first > last) first = last;

        _firstBin[i] = (NSUInteger)first;
        _lastBin[i] = (NSUInteger)last;

        double center = sqrt(lowF * highF);
        double db = BT_TILT_DB_PER_OCTAVE * log2(center / BT_BAND_LOW_HZ);
        _tilt[i] = (float)db;
    }

    // Pivot about the middle so the tilt redistributes rather than lifts, then
    // hold the ends in check: an octave of tilt compounds over the display's
    // nine of them and would otherwise bury the bass entirely.
    float middle = _tilt[BT_ANALYZER_BANDS / 2];
    for (i = 0; i < BT_ANALYZER_BANDS; i++) {
        float db = _tilt[i] - middle;
        if (db > BT_TILT_LIMIT_DB) db = BT_TILT_LIMIT_DB;
        if (db < -BT_TILT_LIMIT_DB) db = -BT_TILT_LIMIT_DB;
        _tilt[i] = db;
    }
}

- (void)reset {
    NSUInteger i;
    for (i = 0; i < BT_ANALYZER_BANDS; i++) _bands[i] = 0.0f;
    _level = 0.0f;
    _fill = 0;
}

- (void)getBands:(float *)bands {
    NSUInteger i;
    for (i = 0; i < BT_ANALYZER_BANDS; i++) bands[i] = _bands[i];
}

- (float)averageLevel {
    return _level;
}

// Decibels onto the nought-to-one the display works in.
static inline float BTScaleDecibels(float db) {
    float f = (db - BT_FLOOR_DB) / (BT_REF_DB - BT_FLOOR_DB);
    if (f < 0.0f) return 0.0f;
    if (f > 1.0f) return 1.0f;
    return f;
}

- (void)consumeSamples:(const float *)samples count:(NSUInteger)count {
    if (samples == NULL || _setup == NULL) return;

    NSUInteger offset = 0;
    while (offset < count) {
        NSUInteger room = BT_LONG_SIZE - _fill;
        NSUInteger take = count - offset;
        if (take > room) take = room;
        memcpy(_accum + _fill, samples + offset, take * sizeof(float));
        _fill += take;
        offset += take;

        if (_fill < BT_LONG_SIZE) return;

        [self transformAccumulated];

        // Most of the window is kept, so the next reading overlaps this one and
        // arrives a hop later rather than a whole window later.
        memmove(_accum, _accum + BT_FFT_HOP, (BT_LONG_SIZE - BT_FFT_HOP) * sizeof(float));
        _fill = BT_LONG_SIZE - BT_FFT_HOP;
    }
}

// One transform, from samples to magnitudes. Both windows go through here, so
// they are scaled the same way and a bar either side of the split reads the same
// height for the same sound.
- (void)transformSamples:(const float *)samples
                    log2:(vDSP_Length)log2n
                  window:(const float *)window
                    into:(float *)magnitudes {
    float windowed[BT_LONG_SIZE];
    NSUInteger size = (NSUInteger)1 << log2n;
    NSUInteger bins = size / 2;

    // Tapering the ends of the window keeps a note that does not fit a whole
    // number of cycles from smearing itself across every bar.
    vDSP_vmul(samples, 1, window, 1, windowed, 1, size);

    DSPSplitComplex split;
    split.realp = _real;
    split.imagp = _imag;
    vDSP_ctoz((const DSPComplex *)windowed, 2, &split, 1, bins);
    vDSP_fft_zrip(_setup, &split, 1, log2n, kFFTDirection_Forward);

    // The packed form keeps the topmost frequency in the imaginary part of the
    // first bin, where it would be read as part of the offset.
    _imag[0] = 0.0f;

    vDSP_zvabs(&split, 1, magnitudes, 1, bins);
    float scale = 1.0f / (float)size;
    vDSP_vsmul(magnitudes, 1, &scale, magnitudes, 1, bins);
}

- (void)transformAccumulated {
    // Loudness comes off the raw window. Taken after the taper it would report
    // the taper as much as the music.
    float meanSquare = 0.0f;
    vDSP_measqv(_accum, 1, &meanSquare, BT_LONG_SIZE);
    float rms = sqrtf(meanSquare);
    _level = BTScaleDecibels(rms > 0.0f ? 20.0f * log10f(rms) : BT_FLOOR_DB);

    [self transformSamples:_accum
                      log2:BT_LONG_LOG2
                    window:_longWindow
                      into:_longMagnitudes];

    // The newest half of the same samples, which is what makes the upper bars
    // answer in half the time without a second accumulator to keep in step.
    [self transformSamples:(_accum + BT_LONG_SIZE - BT_SHORT_SIZE)
                      log2:BT_SHORT_LOG2
                    window:_shortWindow
                      into:_shortMagnitudes];

    NSUInteger i, bin;
    for (i = 0; i < BT_ANALYZER_BANDS; i++) {
        const float *magnitudes = BTBandUsesShortWindow(i) ? _shortMagnitudes : _longMagnitudes;

        // The loudest bin in the band, which reads as an analyzer. An average
        // buries a single strong note among its quiet neighbours.
        float peak = 0.0f;
        for (bin = _firstBin[i]; bin <= _lastBin[i]; bin++) {
            if (magnitudes[bin] > peak) peak = magnitudes[bin];
        }
        // The tilt weights signal, never the floor. Adding it before the floor
        // is tested would light the upper bars on digital silence, which is a
        // long way from what a stopped song should look like.
        float db = (peak > 0.0f) ? 20.0f * log10f(peak) : BT_FLOOR_DB;
        _bands[i] = (db <= BT_FLOOR_DB) ? 0.0f : BTScaleDecibels(db + _tilt[i]);
    }
}

@end
