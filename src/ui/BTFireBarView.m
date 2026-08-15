#import "BTFireBarView.h"
#import "BTPlayer.h"

// One bar per band the analyzer reports. Tied together so the two cannot drift
// apart and leave bars standing for bands that do not exist.
#define BT_BAR_COUNT BT_ANALYZER_BANDS

// How often the display is redrawn. Fifty a second rather than twenty-five: the
// analyzer behind it now answers the upper bands in twenty-two milliseconds, so
// at twenty-five frames the timer was throwing away every other thing it had to
// say.
#define BT_BAR_FPS 50.0
#define BT_BAR_INTERVAL (1.0 / BT_BAR_FPS)

// Everything below is written per second and converted to the frame rate above,
// which is the only reason the frame rate could be changed at all. Held as
// per-frame numbers, doubling the rate silently halved the time a cap waited and
// quartered how far it fell, so a display that was only meant to be smoother
// would have come out twice as twitchy as well.

// What is left of a bar after a second of the band being silent. The bass hangs
// and the treble snaps back, which is what gives an analyzer its texture.
#define BT_BAR_LEFT_AFTER_A_SECOND_LOW  0.030
#define BT_BAR_LEFT_AFTER_A_SECOND_HIGH 0.0008

// How long a cap waits where the bar left it, and how hard it falls afterwards,
// in heights of the display per second squared. It accelerates rather than
// sliding at a constant rate because a marker that eases away reads as a
// measurement being released, where one that drops at a fixed speed reads as a
// second bar.
#define BT_CAP_HOLD_SECONDS 0.48
#define BT_CAP_ACCELERATION 0.6875

// How far under the loudest band a bar has to be before it reads as empty.
//
// This is the number that decides whether the display has any life in it, and
// it was previously not a number at all. The bar height was the band divided by
// the ceiling, but both of those are already logarithmic, so the division was
// not a ratio of loudnesses and meant nothing: a band thirty decibels under the
// loudest still drew half the display. Between beats a band falls perhaps
// fifteen or twenty decibels, which moved a bar by two or three blocks out of
// fourteen, so every record drew the same shivering plateau. Measured on a
// four-minute track, the bars stood at seven blocks of fourteen nine frames in
// ten and swung four.
//
// Subtracting instead makes it a real scale in decibels, and thirty-five is
// where the sweep settled. Wider and the plateau comes back; narrower and a
// quiet recording bottoms out, a Chopin nocturne resting at a tenth of a block
// at thirty. At thirty-five the same track rests at five blocks and swings
// five, and every record tried improved.
//
// What this cannot do is put dynamics into a record that has none. A heavily
// limited one is a plateau, and an honest display of a plateau is a plateau.
#define BT_BAR_RANGE_DB 35.0

// What is left of the ceiling after a second of quieter material. It follows the
// loudest band up at once and sags back slowly, so the display keeps its range
// on any recording without one band flattening another.
//
// Slowly is the point, and it is the opposite of what seems reasonable. A
// ceiling that hurries down follows the music into every quiet moment, and bars
// measured against it stand just as tall in the quiet part as in the loud one:
// the dip the eye was waiting for is subtracted before it is drawn. Held up, the
// quiet moments read as quiet. Swept against the same record, holding the
// ceiling took the bars from resting at four blocks to resting at three and a
// half while swinging half a block further.
#define BT_CEILING_LEFT_AFTER_A_SECOND 0.95

@implementation BTFireBarView {
    NSTimer *_timer;
    CGFloat _values[BT_BAR_COUNT];
    CGFloat _peaks[BT_BAR_COUNT];
    CGFloat _capFall[BT_BAR_COUNT];
    NSInteger _capHold[BT_BAR_COUNT];
    CGFloat _ceiling;
    BOOL _settled;
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _barWidth = 3.0;
        _barGap = 1.0;
        NSInteger i;
        for (i = 0; i < BT_BAR_COUNT; i++) {
            _values[i] = 0;
            _peaks[i] = 0;
        }
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)startAnimating {
    if (_timer) return;
    _timer = [NSTimer scheduledTimerWithTimeInterval:BT_BAR_INTERVAL
                                              target:self
                                            selector:@selector(step:)
                                            userInfo:nil
                                             repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)stopAnimating {
    [_timer invalidate];
    _timer = nil;
}

// What a bar keeps from one frame to the next once its band has gone quiet,
// worked out from how much it should keep over a whole second. Asking the
// question in seconds is what keeps the fall the same speed whatever the frame
// rate is set to.
static CGFloat BTBandDecay(NSInteger index) {
    CGFloat t = (CGFloat)index / (CGFloat)(BT_BAR_COUNT - 1);
    double perSecond = BT_BAR_LEFT_AFTER_A_SECOND_LOW
        + (BT_BAR_LEFT_AFTER_A_SECOND_HIGH - BT_BAR_LEFT_AFTER_A_SECOND_LOW) * (double)t;
    return (CGFloat)pow(perSecond, BT_BAR_INTERVAL);
}

// Everything down and nothing left to fall.
- (BOOL)atRest {
    NSInteger i;
    for (i = 0; i < BT_BAR_COUNT; i++) {
        if (_values[i] > 0.001f || _peaks[i] > 0.001f) return NO;
    }
    return YES;
}

- (void)step:(NSTimer *)timer {
    float bands[BT_ANALYZER_BANDS];
    [[BTPlayer sharedPlayer] getBandLevels:bands];

    CGFloat loudest = 0.0f;
    NSInteger band;
    for (band = 0; band < BT_BAR_COUNT; band++) {
        if ((CGFloat)bands[band] > loudest) loudest = (CGFloat)bands[band];
    }

    // A pause reads as silence, so the bars fall away and the caps drop after
    // them. Once the display is empty it is left alone rather than repainted
    // twenty-five times a second for as long as the window is open.
    if (loudest <= 0.0f && [self atRest]) {
        if (!_settled) {
            NSInteger i;
            for (i = 0; i < BT_BAR_COUNT; i++) {
                _values[i] = 0;
                _peaks[i] = 0;
                _capHold[i] = 0;
                _capFall[i] = 0;
            }
            _settled = YES;
            [self setNeedsDisplay:YES];
        }
        return;
    }
    _settled = NO;

    // Recordings differ in loudness by far more than the display has height, so
    // a fixed scale either pegs on a loud track or barely lifts on a quiet one.
    // The bars are measured against a ceiling that follows the loudest recent
    // band and sags back down, which keeps the whole range in use on any
    // material without flattening one band against another.
    if (loudest > _ceiling) {
        _ceiling = loudest;
    } else {
        CGFloat held = (CGFloat)pow(BT_CEILING_LEFT_AFTER_A_SECOND, BT_BAR_INTERVAL);
        _ceiling = _ceiling * held + loudest * (1.0f - held);
    }
    if (_ceiling < 0.12f) _ceiling = 0.12f;

    // How far under the ceiling a band is, in decibels, turned into how far up
    // its bar stands. A band level is evenly spaced in decibels, so the distance
    // between two of them is a subtraction; dividing one by the other is what
    // drew every record as the same plateau.
    CGFloat perUnit = (CGFloat)([BTSpectrum decibelSpan] / BT_BAR_RANGE_DB);

    NSInteger i;
    for (i = 0; i < BT_BAR_COUNT; i++) {
        CGFloat value = 1.0f - (_ceiling - (CGFloat)bands[i]) * perUnit;
        if (value > 1.0f) value = 1.0f;
        if (value < 0.0f) value = 0.0f;

        // Straight up to whatever the band is doing, and down in its own time.
        // A bar that fell on its own schedule regardless would read as slower
        // than the music it is drawn from.
        if (value >= _values[i]) {
            _values[i] = value;
        } else {
            _values[i] *= BTBandDecay(i);
            if (_values[i] < value) _values[i] = value;
        }

        // The cap holds where the bar last reached, waits, then falls away
        // picking up speed, the way the original analyzer's markers did.
        if (_values[i] >= _peaks[i]) {
            _peaks[i] = _values[i];
            _capHold[i] = (NSInteger)(BT_CAP_HOLD_SECONDS * BT_BAR_FPS);
            _capFall[i] = 0.0f;
        } else if (_capHold[i] > 0) {
            _capHold[i]--;
        } else {
            // Speed gained over one frame, so the distance fallen comes out the
            // same however many frames the second is cut into.
            _capFall[i] += (CGFloat)(BT_CAP_ACCELERATION * BT_BAR_INTERVAL * BT_BAR_INTERVAL);
            _peaks[i] -= _capFall[i];
            if (_peaks[i] < _values[i]) _peaks[i] = _values[i];
            if (_peaks[i] < 0) _peaks[i] = 0;
        }
    }
    [self setNeedsDisplay:YES];
}

- (NSColor *)colorForFraction:(CGFloat)f {
    // Green at the bottom, through yellow, to red at the top.
    if (f < 0.55f) {
        CGFloat t = f / 0.55f;
        return [NSColor colorWithCalibratedRed:(0.15f + 0.75f * t) green:0.90f blue:0.15f alpha:1.0];
    }
    CGFloat t = (f - 0.55f) / 0.45f;
    if (t > 1) t = 1;
    return [NSColor colorWithCalibratedRed:0.95f green:(0.90f - 0.72f * t) blue:0.12f alpha:1.0];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    [[NSColor blackColor] set];
    NSRectFill(bounds);

    CGFloat gap = self.barGap > 0 ? self.barGap : 1.0;
    CGFloat barWidth = self.barWidth > 0 ? self.barWidth : 3.0;
    CGFloat blockHeight = 2.0;
    CGFloat blockGap = 1.0;
    NSInteger blocks = (NSInteger)((NSHeight(bounds) - 2) / (blockHeight + blockGap));
    if (blocks < 1) blocks = 1;

    CGFloat used = (CGFloat)BT_BAR_COUNT * barWidth + (CGFloat)(BT_BAR_COUNT - 1) * gap;
    CGFloat originX = NSMinX(bounds) + (NSWidth(bounds) - used) / 2.0;
    if (originX < 0) originX = 0;

    NSInteger i, b;

    if (self.drawsGrid) {
        // The faint dot grid the original analyzer sat on.
        [[NSColor colorWithCalibratedRed:0.10 green:0.16 blue:0.22 alpha:1.0] set];
        CGFloat gx, gy;
        for (gx = NSMinX(bounds) + 1; gx < NSMaxX(bounds); gx += 2.0) {
            for (gy = NSMinY(bounds) + 1; gy < NSMaxY(bounds); gy += 3.0) {
                NSRectFill(NSMakeRect(gx, gy, 1, 1));
            }
        }
    }

    for (i = 0; i < BT_BAR_COUNT; i++) {
        CGFloat x = originX + (CGFloat)i * (barWidth + gap);
        NSInteger lit = (NSInteger)(_values[i] * (CGFloat)blocks + 0.5f);

        for (b = 0; b < lit; b++) {
            CGFloat fraction = (CGFloat)b / (CGFloat)(blocks - 1 > 0 ? blocks - 1 : 1);
            [[self colorForFraction:fraction] set];
            NSRectFill(NSMakeRect(x, 1 + (CGFloat)b * (blockHeight + blockGap), barWidth, blockHeight));
        }

        // The cap floats clear of the bar and comes down in its own time, which
        // is the whole of what a peak marker is for: the bar answers the music
        // and the cap remembers where it got to.
        //
        // Clear of it in one direction only. Pushed up out of the bar when the
        // two are level, and left alone when it is already above, since above is
        // where it spends its time and dragging it back down to the bar is
        // exactly what a peak marker must not do. Written the other way round it
        // did both: the cap was pinned one block over the bar however far the
        // bar had fallen, and while the bar was rising the cap painted its top
        // block white, which is why the bars wore white tips instead of showing
        // the red they had climbed to.
        if (_peaks[i] > 0.0f) {
            NSInteger peakBlock = (NSInteger)(_peaks[i] * (CGFloat)blocks + 0.5f) - 1;
            if (peakBlock < lit) peakBlock = lit;
            if (peakBlock > blocks - 1) peakBlock = blocks - 1;
            if (peakBlock >= 0) {
                [[NSColor colorWithCalibratedWhite:0.90 alpha:1.0] set];
                NSRectFill(NSMakeRect(x, 1 + (CGFloat)peakBlock * (blockHeight + blockGap),
                                      barWidth, blockHeight));
            }
        }
    }
}

@end
