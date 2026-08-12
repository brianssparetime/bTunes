#import "BTFireBarView.h"
#import "BTPlayer.h"

#define BT_BAR_COUNT 19

@implementation BTFireBarView {
    NSTimer *_timer;
    CGFloat _values[BT_BAR_COUNT];
    CGFloat _peaks[BT_BAR_COUNT];
    CGFloat _phases[BT_BAR_COUNT];
    CGFloat _rates[BT_BAR_COUNT];
    double _time;
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
            // Fixed pseudo-random wobble: same every launch, different per bar.
            _phases[i] = (CGFloat)((i * 37) % 100) / 100.0 * 6.2831853;
            _rates[i] = 1.7 + (CGFloat)((i * 53) % 70) / 100.0;
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

// Loudness alone would move every bar together, so each band gets a fixed
// weight (bass louder than treble) and its own slow oscillator.
static CGFloat BTBandShape(NSInteger index) {
    CGFloat t = (CGFloat)index / (CGFloat)(BT_BAR_COUNT - 1);
    return 1.05f - 0.62f * t * t;
}

- (void)step:(NSTimer *)timer {
    BTPlayer *player = [BTPlayer sharedPlayer];
    CGFloat level = [player averageLevel];
    CGFloat peak = [player peakLevel];
    _time += 1.0 / 25.0;

    // Loudness sits high and varies little, so driving the bars from it
    // directly pegs them. Bending the curve pulls the middle down and leaves
    // the top of the range for the loud moments.
    CGFloat shaped = powf(level, 1.8f);

    NSInteger i;
    for (i = 0; i < BT_BAR_COUNT; i++) {
        CGFloat wobble = 0.45f + 0.55f * (CGFloat)((sin(_time * _rates[i] + _phases[i]) + 1.0) / 2.0);
        CGFloat target = shaped * BTBandShape(i) * wobble * 1.70f;
        if (i < 4) target += powf(peak, 2.0f) * 0.22f * wobble;
        if (target > 1.0f) target = 1.0f;

        // Falls faster than before, so the bars move rather than sitting full.
        _values[i] = (target > _values[i]) ? target : (_values[i] * 0.62f + target * 0.38f);
        if (_values[i] > _peaks[i]) {
            _peaks[i] = _values[i];
        } else {
            _peaks[i] -= 0.018f;
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

        NSInteger peakBlock = (NSInteger)(_peaks[i] * (CGFloat)blocks + 0.5f) - 1;
        if (peakBlock > 0 && peakBlock < blocks) {
            [[NSColor colorWithCalibratedWhite:0.85 alpha:1.0] set];
            NSRectFill(NSMakeRect(x, 1 + (CGFloat)peakBlock * (blockHeight + blockGap), barWidth, 1.0));
        }
    }
}

@end
