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

// The blocks a bar is built from, and the gap between them.
#define BT_BLOCK_HEIGHT 2.0
#define BT_BLOCK_GAP    1.0

@implementation BTFireBarView {
    NSTimer *_timer;
    CGFloat _values[BT_BAR_COUNT];
    CGFloat _peaks[BT_BAR_COUNT];
    CGFloat _capFall[BT_BAR_COUNT];
    NSInteger _capHold[BT_BAR_COUNT];
    CGFloat _ceiling;
    BOOL _settled;

    // Where every block and every dot goes, worked out once for a given size.
    // None of it changes between one frame and the next, and at fifty frames a
    // second the arithmetic and the several hundred colour objects it allocated
    // cost more than the drawing did.
    NSSize _laidOutFor;
    CGFloat _laidOutWidth, _laidOutGap;
    NSRect *_gridDots;
    NSInteger _gridDotCount;
    NSInteger _blocks;
    CGFloat _originX;
    NSArray *_blockColors;
    // Scratch for one call to NSRectFillList: a whole row of blocks, or every
    // cap, goes down in one operation under one colour.
    NSRect _fillList[BT_BAR_COUNT];
}

// The whole of the bounds is filled, starting with black. Saying so is what
// keeps the panel behind from being redrawn under the bars fifty times a
// second, which is most of what mini mode used to cost.
- (BOOL)isOpaque { return YES; }

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
    free(_gridDots);
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
// rate is set to. The answer is the same every frame, so it is worked out once.
static const CGFloat *BTBandDecay(void) {
    static CGFloat table[BT_BAR_COUNT];
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSInteger i;
        for (i = 0; i < BT_BAR_COUNT; i++) {
            CGFloat t = (CGFloat)i / (CGFloat)(BT_BAR_COUNT - 1);
            double perSecond = BT_BAR_LEFT_AFTER_A_SECOND_LOW
                + (BT_BAR_LEFT_AFTER_A_SECOND_HIGH - BT_BAR_LEFT_AFTER_A_SECOND_LOW) * (double)t;
            table[i] = (CGFloat)pow(perSecond, BT_BAR_INTERVAL);
        }
    });
    return table;
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
    const CGFloat *decay = BTBandDecay();

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
            _values[i] *= decay[i];
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

static NSColor *BTBlockColor(CGFloat f) {
    // Green at the bottom, through yellow, to red at the top.
    if (f < 0.55f) {
        CGFloat t = f / 0.55f;
        return [NSColor colorWithCalibratedRed:(0.15f + 0.75f * t) green:0.90f blue:0.15f alpha:1.0];
    }
    CGFloat t = (f - 0.55f) / 0.45f;
    if (t > 1) t = 1;
    return [NSColor colorWithCalibratedRed:0.95f green:(0.90f - 0.72f * t) blue:0.12f alpha:1.0];
}

// Everything about the display that follows from its size rather than from the
// music: how many blocks tall a bar can be, what colour each row of blocks is,
// where the leftmost bar starts, and where the dots of the grid go.
- (void)layOutForSize {
    NSRect bounds = [self bounds];
    CGFloat gap = self.barGap > 0 ? self.barGap : 1.0;
    CGFloat barWidth = self.barWidth > 0 ? self.barWidth : 3.0;

    if (NSEqualSizes(bounds.size, _laidOutFor)
        && barWidth == _laidOutWidth && gap == _laidOutGap) return;
    _laidOutFor = bounds.size;
    _laidOutWidth = barWidth;
    _laidOutGap = gap;

    _blocks = (NSInteger)((NSHeight(bounds) - 2) / (BT_BLOCK_HEIGHT + BT_BLOCK_GAP));
    if (_blocks < 1) _blocks = 1;

    CGFloat used = (CGFloat)BT_BAR_COUNT * barWidth + (CGFloat)(BT_BAR_COUNT - 1) * gap;
    _originX = NSMinX(bounds) + (NSWidth(bounds) - used) / 2.0;
    if (_originX < 0) _originX = 0;

    NSMutableArray *colors = [NSMutableArray arrayWithCapacity:(NSUInteger)_blocks];
    NSInteger b;
    for (b = 0; b < _blocks; b++) {
        [colors addObject:BTBlockColor((CGFloat)b / (CGFloat)(_blocks - 1 > 0 ? _blocks - 1 : 1))];
    }
    _blockColors = colors;

    // The grid is several hundred single points, and laying them out again
    // every frame cost more than filling them does.
    free(_gridDots);
    _gridDots = NULL;
    _gridDotCount = 0;
    NSInteger columns = (NSInteger)ceil((NSWidth(bounds) - 1) / 2.0);
    NSInteger rows = (NSInteger)ceil((NSHeight(bounds) - 1) / 3.0);
    if (columns > 0 && rows > 0) {
        _gridDots = malloc(sizeof(NSRect) * (size_t)(columns * rows));
        CGFloat gx, gy;
        for (gx = NSMinX(bounds) + 1; gx < NSMaxX(bounds); gx += 2.0) {
            for (gy = NSMinY(bounds) + 1; gy < NSMaxY(bounds); gy += 3.0) {
                _gridDots[_gridDotCount++] = NSMakeRect(gx, gy, 1, 1);
            }
        }
    }
}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [self layOutForSize];
}

- (void)drawRect:(NSRect)dirtyRect {
    [self layOutForSize];

    [[NSColor blackColor] set];
    NSRectFill([self bounds]);

    if (self.drawsGrid && _gridDotCount > 0) {
        // The faint dot grid the original analyzer sat on.
        [[NSColor colorWithCalibratedRed:0.10 green:0.16 blue:0.22 alpha:1.0] set];
        NSRectFillList(_gridDots, _gridDotCount);
    }

    CGFloat step = _laidOutWidth + _laidOutGap;
    NSInteger lit[BT_BAR_COUNT];
    NSInteger i, b, n;
    for (i = 0; i < BT_BAR_COUNT; i++) {
        lit[i] = (NSInteger)(_values[i] * (CGFloat)_blocks + 0.5f);
    }

    // A row at a time rather than a bar at a time. Every block in a row is the
    // same colour, so the row goes down in one operation; taken bar by bar the
    // display changed colour two hundred times a frame and allocated a colour
    // for each of them.
    for (b = 0; b < _blocks; b++) {
        CGFloat y = 1 + (CGFloat)b * (BT_BLOCK_HEIGHT + BT_BLOCK_GAP);
        n = 0;
        for (i = 0; i < BT_BAR_COUNT; i++) {
            if (lit[i] > b) {
                _fillList[n++] = NSMakeRect(_originX + (CGFloat)i * step, y,
                                            _laidOutWidth, BT_BLOCK_HEIGHT);
            }
        }
        if (n > 0) {
            [(NSColor *)[_blockColors objectAtIndex:(NSUInteger)b] set];
            NSRectFillList(_fillList, n);
        }
    }

    // The cap floats clear of the bar and comes down in its own time, which is
    // the whole of what a peak marker is for: the bar answers the music and the
    // cap remembers where it got to.
    //
    // Clear of it in one direction only. Pushed up out of the bar when the two
    // are level, and left alone when it is already above, since above is where
    // it spends its time and dragging it back down to the bar is exactly what a
    // peak marker must not do. Written the other way round it did both: the cap
    // was pinned one block over the bar however far the bar had fallen, and
    // while the bar was rising the cap painted its top block white, which is why
    // the bars wore white tips instead of showing the red they had climbed to.
    n = 0;
    for (i = 0; i < BT_BAR_COUNT; i++) {
        if (_peaks[i] <= 0.0f) continue;
        NSInteger peakBlock = (NSInteger)(_peaks[i] * (CGFloat)_blocks + 0.5f) - 1;
        if (peakBlock < lit[i]) peakBlock = lit[i];
        if (peakBlock > _blocks - 1) peakBlock = _blocks - 1;
        if (peakBlock < 0) continue;
        _fillList[n++] = NSMakeRect(_originX + (CGFloat)i * step,
                                    1 + (CGFloat)peakBlock * (BT_BLOCK_HEIGHT + BT_BLOCK_GAP),
                                    _laidOutWidth, BT_BLOCK_HEIGHT);
    }
    if (n > 0) {
        [[NSColor colorWithCalibratedWhite:0.90 alpha:1.0] set];
        NSRectFillList(_fillList, n);
    }
}

@end
