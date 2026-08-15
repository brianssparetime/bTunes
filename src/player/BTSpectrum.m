#import "BTSpectrum.h"
#import <Accelerate/Accelerate.h>

// Bands are spaced by ear, so the lowest of them are only a few hertz apart and
// a short window cannot tell them apart at all: several bars end up reading the
// same bin and the bottom of the display moves as one piece. The window is long
// enough to separate them, and taken far more often than its own length so the
// display still answers a drum hit promptly. At the usual sampling rate that is
// a bin every eleven hertz and a new reading every twenty-three milliseconds.
#define BT_FFT_LOG2 12
#define BT_FFT_SIZE (1 << BT_FFT_LOG2)
#define BT_FFT_HOP 1024
#define BT_FFT_BINS (BT_FFT_SIZE / 2)

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
    FFTSetup _setup;
    double _sampleRate;

    float _hann[BT_FFT_SIZE];
    float _accum[BT_FFT_SIZE];
    NSUInteger _fill;

    float _real[BT_FFT_BINS];
    float _imag[BT_FFT_BINS];

    NSUInteger _firstBin[BT_ANALYZER_BANDS];
    NSUInteger _lastBin[BT_ANALYZER_BANDS];
    float _tilt[BT_ANALYZER_BANDS];

    float _bands[BT_ANALYZER_BANDS];
    float _level;
}

+ (double)lowestFrequency { return BT_BAND_LOW_HZ; }
+ (double)highestFrequency { return BT_BAND_HIGH_HZ; }

- (instancetype)initWithSampleRate:(double)sampleRate {
    self = [super init];
    if (self == nil) return nil;

    _sampleRate = sampleRate > 0 ? sampleRate : 44100.0;
    _setup = vDSP_create_fftsetup(BT_FFT_LOG2, kFFTRadix2);
    if (_setup == NULL) return nil;

    vDSP_hann_window(_hann, BT_FFT_SIZE, vDSP_HANN_NORM);
    [self buildBandTable];
    return self;
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
    double binHz = _sampleRate / (double)BT_FFT_SIZE;
    double span = high / BT_BAND_LOW_HZ;

    NSUInteger i;
    for (i = 0; i < BT_ANALYZER_BANDS; i++) {
        double lowF = BT_BAND_LOW_HZ * pow(span, (double)i / (double)BT_ANALYZER_BANDS);
        double highF = BT_BAND_LOW_HZ * pow(span, (double)(i + 1) / (double)BT_ANALYZER_BANDS);

        NSInteger first = (NSInteger)floor(lowF / binHz);
        NSInteger last = (NSInteger)floor(highF / binHz);
        if (first < 1) first = 1;                       // bin zero is the offset, not a note
        if (last < first) last = first;
        if (last > BT_FFT_BINS - 1) last = BT_FFT_BINS - 1;
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
        NSUInteger room = BT_FFT_SIZE - _fill;
        NSUInteger take = count - offset;
        if (take > room) take = room;
        memcpy(_accum + _fill, samples + offset, take * sizeof(float));
        _fill += take;
        offset += take;

        if (_fill < BT_FFT_SIZE) return;

        [self transformAccumulated];

        // Most of the window is kept, so the next reading overlaps this one and
        // arrives a hop later rather than a whole window later.
        memmove(_accum, _accum + BT_FFT_HOP, (BT_FFT_SIZE - BT_FFT_HOP) * sizeof(float));
        _fill = BT_FFT_SIZE - BT_FFT_HOP;
    }
}

- (void)transformAccumulated {
    float windowed[BT_FFT_SIZE];
    float magnitudes[BT_FFT_BINS];

    // Loudness comes off the raw window. Taken after the taper it would report
    // the taper as much as the music.
    float meanSquare = 0.0f;
    vDSP_measqv(_accum, 1, &meanSquare, BT_FFT_SIZE);
    float rms = sqrtf(meanSquare);
    _level = BTScaleDecibels(rms > 0.0f ? 20.0f * log10f(rms) : BT_FLOOR_DB);

    // Tapering the ends of the window keeps a note that does not fit a whole
    // number of cycles from smearing itself across every bar.
    vDSP_vmul(_accum, 1, _hann, 1, windowed, 1, BT_FFT_SIZE);

    DSPSplitComplex split;
    split.realp = _real;
    split.imagp = _imag;
    vDSP_ctoz((const DSPComplex *)windowed, 2, &split, 1, BT_FFT_BINS);
    vDSP_fft_zrip(_setup, &split, 1, BT_FFT_LOG2, kFFTDirection_Forward);

    // The packed form keeps the topmost frequency in the imaginary part of the
    // first bin, where it would be read as part of the offset.
    _imag[0] = 0.0f;

    vDSP_zvabs(&split, 1, magnitudes, 1, BT_FFT_BINS);
    float scale = 1.0f / (float)BT_FFT_SIZE;
    vDSP_vsmul(magnitudes, 1, &scale, magnitudes, 1, BT_FFT_BINS);

    NSUInteger i, bin;
    for (i = 0; i < BT_ANALYZER_BANDS; i++) {
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
