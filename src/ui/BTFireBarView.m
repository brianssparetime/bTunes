#import "BTFireBarView.h"
#import "BTPlayer.h"

#define BT_BAR_COUNT 31

@implementation BTFireBarView {
    NSTimer *_timer;
    CGFloat _values[BT_BAR_COUNT];
    CGFloat _peaks[BT_BAR_COUNT];
    CGFloat _capFall[BT_BAR_COUNT];
    NSInteger _capHold[BT_BAR_COUNT];
    CGFloat _ceiling;
    CGFloat _average;
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
    _timer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 25.0)
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

// How loud a band gets when it fires. Bass carries most of the energy in most
// recordings, so the left of the display sits higher than the right.
static CGFloat BTBandGain(NSInteger index) {
    CGFloat t = (CGFloat)index / (CGFloat)(BT_BAR_COUNT - 1);
    return 1.02f - 0.55f * t * t;
}

// How often a band fires. Treble is busy and constant, bass is occasional and
// tied to the beat, which is what gives an analyzer its texture.
static CGFloat BTBandActivity(NSInteger index) {
    CGFloat t = (CGFloat)index / (CGFloat)(BT_BAR_COUNT - 1);
    return 0.16f + 0.62f * t;
}

// And how fast it falls away afterwards. Bass hangs, treble snaps back.
static CGFloat BTBandDecay(NSInteger index) {
    CGFloat t = (CGFloat)index / (CGFloat)(BT_BAR_COUNT - 1);
    return 0.86f - 0.16f * t;
}

static CGFloat BTRandomFraction(void) {
    return (CGFloat)arc4random_uniform(10000) / 10000.0f;
}

- (void)step:(NSTimer *)timer {
    BTPlayer *player = [BTPlayer sharedPlayer];
    CGFloat level = [player averageLevel];

    // A recording's loudness barely moves, so a fixed scale either pegs on a
    // loud track or barely lifts on a quiet one. The bars are measured against
    // a ceiling that follows the loudest recent moment and sags back down,
    // which is what keeps the display using its whole range on any material.
    if (level > _ceiling) {
        _ceiling = level;
    } else {
        _ceiling = _ceiling * 0.995f + level * 0.005f;
    }
    if (_ceiling < 0.12f) _ceiling = 0.12f;

    CGFloat relative = level / _ceiling;
    if (relative > 1.0f) relative = 1.0f;

    // A transient is loudness above where it has been sitting, and that is what
    // an analyzer is really showing. Tracked separately from the ceiling, which
    // moves too slowly to notice a beat.
    _average = _average * 0.90f + relative * 0.10f;
    CGFloat transient = relative - _average;
    if (transient < 0) transient = 0;

    NSInteger i;
    for (i = 0; i < BT_BAR_COUNT; i++) {
        // Each band fires on its own, with its own chance and its own height.
        // Driving every bar from one number is what made the display move as a
        // block and sit full: with nothing falling, the caps rest on the bars
        // and are never seen.
        CGFloat chance = relative * BTBandActivity(i) + transient * 1.6f * (1.0f - BTBandActivity(i));
        if (BTRandomFraction() < chance) {
            CGFloat height = relative * BTBandGain(i) * (0.45f + 0.75f * BTRandomFraction());
            if (transient > 0.02f && i < BT_BAR_COUNT / 3) height += transient * 1.4f;
            if (height > _values[i]) _values[i] = height;
        }

        _values[i] *= BTBandDecay(i);
        if (_values[i] > 1.0f) _values[i] = 1.0f;
        if (_values[i] < 0.0f) _values[i] = 0.0f;

        // The cap holds where the bar last reached, waits, then falls away
        // picking up speed, the way the original analyzer's markers did.
        if (_values[i] >= _peaks[i]) {
            _peaks[i] = _values[i];
            _capHold[i] = 12;
            _capFall[i] = 0.0f;
        } else if (_capHold[i] > 0) {
            _capHold[i]--;
        } else {
            _capFall[i] += 0.0011f;
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

        // The cap floats a block clear of the bar so it reads as a marker
        // rather than as the top of the bar itself.
        NSInteger peakBlock = (NSInteger)(_peaks[i] * (CGFloat)blocks + 0.5f) - 1;
        if (peakBlock > lit - 1) peakBlock = lit;
        if (peakBlock > 0 && peakBlock < blocks) {
            [[NSColor colorWithCalibratedWhite:0.90 alpha:1.0] set];
            NSRectFill(NSMakeRect(x, 1 + (CGFloat)peakBlock * (blockHeight + blockGap),
                                  barWidth, blockHeight));
        }
    }
}

@end
