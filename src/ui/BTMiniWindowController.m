#import "BTMiniWindowController.h"
#import "BTFireBarView.h"
#import "BTControls.h"
#import "BTStyle.h"
#import "BTPlayer.h"
#import "BTTrack.h"

// The classic small-player proportions, widened: the analyzer wanted more room
// and the extra width buys more bars rather than fatter ones.
#define BT_MINI_WIDTH  310.0
#define BT_MINI_HEIGHT 116.0

// Positions are quoted from the top edge, the way the original skin measured
// them, and flipped once here.
#define BT_TOP(y, h) (BT_MINI_HEIGHT - (y) - (h))

#pragma mark - Palette

static NSColor *BTMiniBody(void)      { return [NSColor colorWithCalibratedWhite:0.196 alpha:1.0]; }
static NSColor *BTMiniBodyLight(void) { return [NSColor colorWithCalibratedWhite:0.290 alpha:1.0]; }
static NSColor *BTMiniBodyDark(void)  { return [NSColor colorWithCalibratedWhite:0.110 alpha:1.0]; }
static NSColor *BTMiniLCD(void)       { return [NSColor colorWithCalibratedRed:0.16 green:0.95 blue:0.32 alpha:1.0]; }

// The chrome the original skin drew in beige is purple here.
// Taken from the one accent definition, so the chrome and the logo agree.
static NSColor *BTMiniPurple(void)      { return [BTStyle accent]; }
static NSColor *BTMiniPurpleLight(void) { return [BTStyle accentLight]; }
static NSColor *BTMiniPurpleDark(void)  { return [BTStyle accentDark]; }

// Elapsed progress keeps the original's amber, against the purple knob.
static NSColor *BTMiniAmber(void)       { return [NSColor colorWithCalibratedRed:0.878 green:0.757 blue:0.290 alpha:1.0]; }

// The lamp on the toggles, taken from the hot end of the analyzer. Amber was
// still too close to the chrome around it to catch the eye.
static NSColor *BTMiniLamp(void)        { return [NSColor colorWithCalibratedRed:1.000 green:0.290 blue:0.075 alpha:1.0]; }

// Layout, measured from the top edge the way the original skin was.
#define BT_MINI_MARGIN       10.0
#define BT_MINI_RIGHT        301.0
#define BT_LCD_X             10.0
#define BT_LCD_W             131.0
#define BT_LCD_Y             24.0
#define BT_LCD_H             49.0     // reaches down level with the volume knob
#define BT_READOUT_X         147.0
#define BT_INFO_Y            42.0
#define BT_INFO_H            14.0
#define BT_VOLUME_Y          60.0
#define BT_VOLUME_H          13.0
#define BT_POSITION_Y        78.0
#define BT_POSITION_H        11.0
#define BT_BUTTON_Y          93.0
#define BT_BUTTON_H          18.0
#define BT_TOGGLE_RIGHT      255.0    // the position bar ends level with this
// Small enough that its top edge clears the volume row above it.
#define BT_LOGO_SIDE         34.0

#pragma mark - Drawing helpers

// A raised block: light along the top and left, dark along the bottom and right.
static void BTDrawRaised(NSRect rect, NSColor *face, NSColor *light, NSColor *dark) {
    [face set];
    NSRectFill(rect);
    [light set];
    NSRectFill(NSMakeRect(NSMinX(rect), NSMaxY(rect) - 1, NSWidth(rect), 1));
    NSRectFill(NSMakeRect(NSMinX(rect), NSMinY(rect), 1, NSHeight(rect)));
    [dark set];
    NSRectFill(NSMakeRect(NSMinX(rect), NSMinY(rect), NSWidth(rect), 1));
    NSRectFill(NSMakeRect(NSMaxX(rect) - 1, NSMinY(rect), 1, NSHeight(rect)));
}

// A recessed block: the same shading, inverted.
static void BTDrawSunken(NSRect rect, NSColor *face, NSColor *light, NSColor *dark) {
    [face set];
    NSRectFill(rect);
    [dark set];
    NSRectFill(NSMakeRect(NSMinX(rect), NSMaxY(rect) - 1, NSWidth(rect), 1));
    NSRectFill(NSMakeRect(NSMinX(rect), NSMinY(rect), 1, NSHeight(rect)));
    [light set];
    NSRectFill(NSMakeRect(NSMinX(rect), NSMinY(rect), NSWidth(rect), 1));
    NSRectFill(NSMakeRect(NSMaxX(rect) - 1, NSMinY(rect), 1, NSHeight(rect)));
}

// The ribbed bars that flank the title, drawn as stacked lines.
static void BTDrawRibbon(NSRect rect) {
    CGFloat y;
    NSInteger line = 0;
    for (y = NSMinY(rect); y < NSMaxY(rect); y += 2.0, line++) {
        [(line % 2 == 0) ? BTMiniPurpleLight() : BTMiniPurpleDark() set];
        NSRectFill(NSMakeRect(NSMinX(rect), y, NSWidth(rect), 1));
    }
}

static NSFont *BTMiniFixedFont(CGFloat size) {
    NSFont *font = [NSFont fontWithName:@"Monaco" size:size];
    return font ? font : [NSFont userFixedPitchFontOfSize:size];
}

#pragma mark - Blocky button

@interface BTMiniButton : NSButton
@property (nonatomic, assign) BTGlyph glyph;
@property (nonatomic, assign) BOOL showsLamp;  // the shuffle and repeat toggles
@property (nonatomic, assign) BOOL on;
@end

@implementation BTMiniButton

- (void)setOn:(BOOL)on { _on = on; [self setNeedsDisplay:YES]; }
- (void)setGlyph:(BTGlyph)glyph { _glyph = glyph; [self setNeedsDisplay:YES]; }

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    BOOL pressed = [self isHighlighted];

    NSColor *face = [NSColor colorWithCalibratedWhite:(pressed ? 0.55 : 0.72) alpha:1.0];
    if (pressed) {
        BTDrawSunken(bounds, face, [NSColor colorWithCalibratedWhite:0.88 alpha:1.0],
                     [NSColor colorWithCalibratedWhite:0.32 alpha:1.0]);
    } else {
        BTDrawRaised(bounds, face, [NSColor colorWithCalibratedWhite:0.93 alpha:1.0],
                     [NSColor colorWithCalibratedWhite:0.30 alpha:1.0]);
    }

    NSColor *ink = [NSColor colorWithCalibratedWhite:0.13 alpha:1.0];
    NSRect inner = NSInsetRect(bounds, 3, 3);

    if (self.showsLamp) {
        // A small lamp in the top left corner, lit in purple when the setting
        // is on. The original marked its toggles the same way.
        // Amber when on. The purple lamp disappeared against the purple chrome;
        // this one is unmistakable at a glance.
        NSRect lamp = NSMakeRect(NSMinX(bounds) + 3, NSMaxY(bounds) - 8, 6, 5);
        [self.on ? BTMiniLamp() : [NSColor colorWithCalibratedWhite:0.42 alpha:1.0] set];
        NSRectFill(lamp);
        inner = NSInsetRect(bounds, 4, 4);
        inner.origin.x += 2;
        inner.size.width -= 2;
    }

    switch (self.glyph) {
        case BTGlyphPlay:     [BTStyle drawPlayGlyphInRect:inner color:ink]; break;
        case BTGlyphPause:    [BTStyle drawPauseGlyphInRect:inner color:ink]; break;
        case BTGlyphPrevious: [BTStyle drawPreviousBarGlyphInRect:inner color:ink]; break;
        case BTGlyphNext:     [BTStyle drawNextBarGlyphInRect:inner color:ink]; break;
        case BTGlyphShuffle:  [BTStyle drawShuffleGlyphInRect:inner color:ink]; break;
        case BTGlyphRepeat:   [BTStyle drawRepeatGlyphInRect:inner one:NO color:ink]; break;
        case BTGlyphRepeatOne:[BTStyle drawRepeatGlyphInRect:inner one:YES color:ink]; break;
        case BTGlyphStop: {
            // Matched to the play triangle beside it, not to the button.
            CGFloat side = NSHeight(inner) * 0.46;
            [ink set];
            NSRectFill(NSMakeRect(NSMidX(inner) - side / 2, NSMidY(inner) - side / 2, side, side));
            break;
        }
        case BTGlyphShrink: [BTStyle drawShrinkGlyphInRect:inner color:ink]; break;
        case BTGlyphEject:  [BTStyle drawEjectGlyphInRect:inner color:ink]; break;
        case BTGlyphPlus: break;
    }
}

@end

#pragma mark - Purple slider

@interface BTMiniSlider : NSView
@property (nonatomic, assign) double value;         // 0 to 1
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@property (nonatomic, assign) BOOL wideThumb;
@property (nonatomic, strong) NSColor *fillColor;   // purple for volume, amber for progress
@end

@implementation BTMiniSlider

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    NSRect groove = NSMakeRect(NSMinX(bounds), NSMidY(bounds) - 3, NSWidth(bounds), 6);
    BTDrawSunken(groove, BTMiniBodyDark(), BTMiniBodyLight(), [NSColor blackColor]);

    CGFloat thumbWidth = self.wideThumb ? 29.0 : 14.0;
    CGFloat travel = NSWidth(bounds) - thumbWidth;
    CGFloat filled = travel * (CGFloat)self.value;

    NSRect fill = NSMakeRect(NSMinX(groove) + 1, NSMinY(groove) + 1, filled + thumbWidth / 2, NSHeight(groove) - 2);
    [(self.fillColor ? self.fillColor : BTMiniPurple()) set];
    NSRectFill(fill);

    NSRect thumb = NSMakeRect(NSMinX(bounds) + filled, NSMinY(bounds), thumbWidth, NSHeight(bounds));
    BTDrawRaised(thumb, BTMiniPurple(), BTMiniPurpleLight(), BTMiniPurpleDark());

    // Grip lines on the thumb.
    [BTMiniPurpleDark() set];
    CGFloat x;
    for (x = NSMidX(thumb) - 2; x <= NSMidX(thumb) + 2; x += 2.0) {
        NSRectFill(NSMakeRect(x, NSMinY(thumb) + 3, 1, NSHeight(thumb) - 6));
    }
}

- (void)setValueFromPoint:(NSPoint)point {
    CGFloat thumbWidth = self.wideThumb ? 29.0 : 14.0;
    CGFloat travel = NSWidth([self bounds]) - thumbWidth;
    if (travel <= 0) return;

    double v = (point.x - thumbWidth / 2) / travel;
    if (v < 0) v = 0;
    if (v > 1) v = 1;
    self.value = v;
    [self setNeedsDisplay:YES];

    if (self.target && self.action && [self.target respondsToSelector:self.action]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.target performSelector:self.action withObject:self];
        #pragma clang diagnostic pop
    }
}

- (void)mouseDown:(NSEvent *)event {
    [self setValueFromPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
}

- (void)mouseDragged:(NSEvent *)event {
    [self setValueFromPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
}

@end

#pragma mark - Panel

@interface BTMiniPanelView : NSView
@property (nonatomic, assign) CGFloat scrollOffset;
@property (nonatomic, strong) NSImage *logo;
@end

@implementation BTMiniPanelView {
    NSPoint _dragStart;
    NSPoint _windowStart;
}

- (BOOL)isOpaque { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];

    // Body and its outer bevel.
    BTDrawRaised(bounds, BTMiniBody(), BTMiniBodyLight(), [NSColor blackColor]);

    // Title bar with a ribbon either side of the name.
    NSRect title = NSMakeRect(1, BT_TOP(1, 14), NSWidth(bounds) - 2, 14);
    [BTMiniBodyDark() set];
    NSRectFill(title);

    NSDictionary *titleAttrs = @{NSFontAttributeName: [BTStyle boldFont],
                                 NSForegroundColorAttributeName: BTMiniPurpleLight()};
    NSString *name = @"BTUNES";
    NSSize nameSize = [name sizeWithAttributes:titleAttrs];
    CGFloat nameX = NSMidX(bounds) - nameSize.width / 2;
    [name drawAtPoint:NSMakePoint(nameX, NSMidY(title) - nameSize.height / 2) withAttributes:titleAttrs];

    BTDrawRibbon(NSMakeRect(24, NSMidY(title) - 3, nameX - 30, 6));
    BTDrawRibbon(NSMakeRect(nameX + nameSize.width + 6, NSMidY(title) - 3,
                            NSWidth(bounds) - (nameX + nameSize.width) - 44, 6));

    // Readout panel on the left: elapsed time above, analyzer below.
    NSRect lcd = NSMakeRect(BT_LCD_X, BT_TOP(BT_LCD_Y, BT_LCD_H), BT_LCD_W, BT_LCD_H);
    BTDrawSunken(lcd, [NSColor blackColor], BTMiniBodyLight(), [NSColor blackColor]);

    BTPlayer *player = [BTPlayer sharedPlayer];
    BTTrack *track = [player currentTrack];

    NSString *time = track ? [BTStyle timeStringFromInterval:[player currentTime]] : @"--:--";
    NSDictionary *digitAttrs = @{NSFontAttributeName: BTMiniFixedFont(15.0),
                                 NSForegroundColorAttributeName: BTMiniLCD()};
    NSSize timeSize = [time sizeWithAttributes:digitAttrs];
    [time drawAtPoint:NSMakePoint(NSMaxX(lcd) - timeSize.width - 4, NSMaxY(lcd) - timeSize.height - 1)
       withAttributes:digitAttrs];

    // Play or pause marker to the left of the digits, drawn at the height of
    // the digits themselves rather than as a small mark beside them.
    CGFloat markerSide = timeSize.height * 0.66;
    NSRect marker = NSMakeRect(NSMinX(lcd) + 5,
                               NSMaxY(lcd) - 1 - timeSize.height / 2.0 - markerSide / 2.0,
                               markerSide, markerSide);
    if (track) {
        if ([player isPlaying]) {
            [BTStyle drawPlayGlyphInRect:NSInsetRect(marker, -1, -1) color:BTMiniLCD()];
        } else {
            [BTStyle drawPauseGlyphInRect:NSInsetRect(marker, -1, -1) color:BTMiniLCD()];
        }
    }

    // Track readout on the right.
    NSRect readout = NSMakeRect(BT_READOUT_X, BT_TOP(24, 14), BT_MINI_RIGHT - BT_READOUT_X, 14);
    BTDrawSunken(readout, [NSColor blackColor], BTMiniBodyLight(), [NSColor blackColor]);

    NSFont *textFont = BTMiniFixedFont(10.0);
    NSString *headline = track
        ? [NSString stringWithFormat:@"%@ - %@", [track displayArtist], [track displayTitle]]
        : @"BTunes";
    NSDictionary *headlineAttrs = @{NSFontAttributeName: textFont,
                                    NSForegroundColorAttributeName: BTMiniLCD()};
    NSSize headlineSize = [headline sizeWithAttributes:headlineAttrs];
    NSRect clip = NSInsetRect(readout, 3, 2);

    [NSGraphicsContext saveGraphicsState];
    NSRectClip(clip);
    // Too long a title travels to the end, rests there, comes back, and rests
    // again before setting off. Sliding back and forth without pausing gives
    // the eye nowhere to read from.
    CGFloat offset = 0;
    if (headlineSize.width > NSWidth(clip)) {
        CGFloat span = headlineSize.width - NSWidth(clip) + 12;
        CGFloat rest = 26.0;
        CGFloat cycle = (span + rest) * 2.0;
        CGFloat phase = fmod(self.scrollOffset, cycle);

        if (phase < span) {
            offset = phase;                                   // travelling out
        } else if (phase < span + rest) {
            offset = span;                                    // holding at the end
        } else if (phase < span * 2.0 + rest) {
            offset = span - (phase - span - rest);             // coming back
        } else {
            offset = 0;                                       // holding at the start
        }
    }
    [headline drawAtPoint:NSMakePoint(NSMinX(clip) - offset, NSMidY(readout) - headlineSize.height / 2)
           withAttributes:headlineAttrs];
    [NSGraphicsContext restoreGraphicsState];

    // Three readouts under it, filling the row out to the right edge: length,
    // format, and track number. Each value is centered in its box.
    if (track) {
        NSDictionary *smallAttrs = @{NSFontAttributeName: [BTStyle smallFont],
                                     NSForegroundColorAttributeName: BTMiniLCD()};
        CGFloat span = BT_MINI_RIGHT - BT_READOUT_X;
        CGFloat gap = 4.0;
        CGFloat boxWidth = (span - gap * 2) / 3.0;
        NSString *kind = track.kind ? [[track.kind componentsSeparatedByString:@" "] objectAtIndex:0] : @"";
        NSString *number = track.trackNumber > 0
            ? [NSString stringWithFormat:@"%ld", (long)track.trackNumber] : @"";
        NSArray *values = @[[track durationString], kind, number];

        NSUInteger i;
        for (i = 0; i < 3; i++) {
            NSRect box = NSMakeRect(BT_READOUT_X + (boxWidth + gap) * i,
                                    BT_TOP(BT_INFO_Y, BT_INFO_H), boxWidth, BT_INFO_H);
            BTDrawSunken(box, [NSColor blackColor], BTMiniBodyLight(), [NSColor blackColor]);

            NSString *value = [values objectAtIndex:i];
            NSSize valueSize = [value sizeWithAttributes:smallAttrs];
            [value drawAtPoint:NSMakePoint(NSMidX(box) - valueSize.width / 2,
                                           NSMidY(box) - valueSize.height / 2)
                withAttributes:smallAttrs];
        }
    }

    // The logo fills the corner the position bar and the toggles leave open.
    if (self.logo) {
        [self.logo drawInRect:[BTMiniPanelView logoRect]
                     fromRect:NSZeroRect
                    operation:NSCompositeSourceOver
                     fraction:1.0
               respectFlipped:YES
                        hints:nil];
    }
}

+ (NSRect)logoRect {
    return NSMakeRect(BT_MINI_RIGHT - BT_LOGO_SIDE,
                      BT_TOP(BT_BUTTON_Y + BT_BUTTON_H - BT_LOGO_SIDE, BT_LOGO_SIDE),
                      BT_LOGO_SIDE, BT_LOGO_SIDE);
}

#pragma mark - Dragging the borderless window

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];

    // The logo is the way back to the full window.
    if (NSPointInRect(point, [BTMiniPanelView logoRect])) {
        [NSApp sendAction:@selector(toggleMiniMode:) to:nil from:self];
        return;
    }

    _dragStart = [NSEvent mouseLocation];
    _windowStart = [[self window] frame].origin;
    if ([event clickCount] == 2) {
        [NSApp sendAction:@selector(toggleMiniMode:) to:nil from:self];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint now = [NSEvent mouseLocation];
    [[self window] setFrameOrigin:NSMakePoint(_windowStart.x + (now.x - _dragStart.x),
                                              _windowStart.y + (now.y - _dragStart.y))];
}

@end

#pragma mark - Window

// A borderless window refuses key status by default, which left every keyboard
// shortcut dead in mini mode.
@interface BTMiniWindow : NSWindow
@end

@implementation BTMiniWindow

- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }

- (void)keyDown:(NSEvent *)event {
    NSString *characters = [event charactersIgnoringModifiers];
    if ([characters length] == 0) {
        [super keyDown:event];
        return;
    }

    unichar key = [characters characterAtIndex:0];
    switch (key) {
        case ' ':
            [NSApp sendAction:@selector(playPause:) to:nil from:self];
            return;
        case NSLeftArrowFunctionKey:
            [NSApp sendAction:@selector(previousTrack:) to:nil from:self];
            return;
        case NSRightArrowFunctionKey:
            [NSApp sendAction:@selector(nextTrack:) to:nil from:self];
            return;
        case NSUpArrowFunctionKey:
            [NSApp sendAction:@selector(volumeUp:) to:nil from:self];
            return;
        case NSDownArrowFunctionKey:
            [NSApp sendAction:@selector(volumeDown:) to:nil from:self];
            return;
        case 'm':
        case 'M':
            [NSApp sendAction:@selector(toggleMute:) to:nil from:self];
            return;
        default:
            break;
    }
    [super keyDown:event];
}

@end

#pragma mark - Controller

@implementation BTMiniWindowController {
    BTMiniPanelView *_panel;
    BTFireBarView *_bars;
    BTMiniButton *_playButton;
    BTMiniButton *_shuffleButton;
    BTMiniButton *_repeatButton;
    BTMiniSlider *_volume;
    BTMiniSlider *_position;
    NSTimer *_scrollTimer;
    BOOL _draggingPosition;
}

- (NSImage *)logoImage {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"btunes-mini" ofType:@"png"];
    if (path == nil) path = [[NSBundle mainBundle] pathForResource:@"btunes-splash" ofType:@"png"];
    if (path == nil) path = [[NSBundle mainBundle] pathForResource:@"BTunes" ofType:@"icns"];
    if (path == nil) return nil;
    return [[NSImage alloc] initWithContentsOfFile:path];
}

- (BTMiniButton *)buttonWithFrame:(NSRect)frame glyph:(BTGlyph)glyph action:(SEL)action {
    BTMiniButton *button = [[BTMiniButton alloc] initWithFrame:frame];
    button.glyph = glyph;
    [button setBordered:NO];
    [button setTitle:@""];
    [button setButtonType:NSMomentaryChangeButton];
    [button setTarget:self];
    [button setAction:action];
    [_panel addSubview:button];
    return button;
}

- (instancetype)initMiniPlayer {
    NSRect frame = NSMakeRect(0, 0, BT_MINI_WIDTH, BT_MINI_HEIGHT);
    NSWindow *window = [[BTMiniWindow alloc] initWithContentRect:frame
                                                       styleMask:NSBorderlessWindowMask
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
    // The mini player stays on top of everything, including whatever is running
    // full screen on another space. The full window is an ordinary window and
    // is deliberately left alone.
    [window setLevel:NSFloatingWindowLevel];
    [window setCollectionBehavior:(NSWindowCollectionBehaviorCanJoinAllSpaces |
                                   NSWindowCollectionBehaviorFullScreenAuxiliary |
                                   NSWindowCollectionBehaviorStationary)];
    [window setHidesOnDeactivate:NO];
    [window setHasShadow:YES];
    [window setTitle:@"BTunes"];

    self = [super initWithWindow:window];
    if (self == nil) return nil;

    _panel = [[BTMiniPanelView alloc] initWithFrame:frame];
    _panel.logo = [self logoImage];
    [window setContentView:_panel];

    // Analyzer, filling the readout panel under the time.
    _bars = [[BTFireBarView alloc] initWithFrame:NSMakeRect(BT_LCD_X + 4, BT_TOP(46, 25),
                                                            BT_LCD_W - 8, 25)];
    _bars.barWidth = 3.0;
    _bars.barGap = 1.0;
    _bars.drawsGrid = YES;
    [_panel addSubview:_bars];

    // Volume, filling its row out to the right edge.
    _volume = [[BTMiniSlider alloc] initWithFrame:NSMakeRect(BT_READOUT_X, BT_TOP(BT_VOLUME_Y, BT_VOLUME_H),
                                                             BT_MINI_RIGHT - BT_READOUT_X, BT_VOLUME_H)];
    _volume.value = [[BTPlayer sharedPlayer] volume];
    _volume.target = self;
    _volume.action = @selector(volumeChanged:);
    [_panel addSubview:_volume];

    // Position, stopping level with the right edge of the loop button so the
    // logo has a square corner to sit in.
    _position = [[BTMiniSlider alloc] initWithFrame:NSMakeRect(BT_MINI_MARGIN,
                                                               BT_TOP(BT_POSITION_Y, BT_POSITION_H),
                                                               BT_TOGGLE_RIGHT - BT_MINI_MARGIN,
                                                               BT_POSITION_H)];
    _position.wideThumb = YES;
    _position.fillColor = BTMiniAmber();
    _position.target = self;
    _position.action = @selector(positionChanged:);
    [_panel addSubview:_position];

    // Transport row: one play and pause button rather than two, then stop,
    // then the two toggles.
    // The buttons are a tenth smaller than the row they sit in, which is where
    // the space between them comes from.
    CGFloat height = BT_BUTTON_H - 2.0;
    CGFloat buttonY = BT_TOP(BT_BUTTON_Y, BT_BUTTON_H) + 1.0;
    CGFloat width = 22.0;
    CGFloat step = width + 3.0;

    [self buttonWithFrame:NSMakeRect(BT_MINI_MARGIN, buttonY, width, height)
                    glyph:BTGlyphPrevious action:@selector(previous:)];
    _playButton = [self buttonWithFrame:NSMakeRect(BT_MINI_MARGIN + step, buttonY, width, height)
                                  glyph:BTGlyphPlay action:@selector(miniPlayPause:)];
    [self buttonWithFrame:NSMakeRect(BT_MINI_MARGIN + step * 2, buttonY, width, height)
                    glyph:BTGlyphStop action:@selector(stop:)];
    [self buttonWithFrame:NSMakeRect(BT_MINI_MARGIN + step * 3, buttonY, width, height)
                    glyph:BTGlyphNext action:@selector(next:)];

    CGFloat toggleWidth = 31.0;
    _shuffleButton = [self buttonWithFrame:NSMakeRect(BT_TOGGLE_RIGHT - toggleWidth * 2 - 4, buttonY,
                                                      toggleWidth, height)
                                     glyph:BTGlyphShuffle
                                    action:@selector(shuffle:)];
    _shuffleButton.showsLamp = YES;

    _repeatButton = [self buttonWithFrame:NSMakeRect(BT_TOGGLE_RIGHT - toggleWidth, buttonY,
                                                     toggleWidth, height)
                                    glyph:BTGlyphRepeat
                                   action:@selector(repeatPressed:)];
    _repeatButton.showsLamp = YES;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(playerChanged:) name:BTPlayerDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(playerChanged:) name:BTPlayerTimeDidChangeNotification object:nil];

    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_scrollTimer invalidate];
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [_bars startAnimating];
    if (_scrollTimer == nil) {
        _scrollTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / 12.0)
                                                        target:self
                                                      selector:@selector(scrollTick:)
                                                      userInfo:nil
                                                       repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:_scrollTimer forMode:NSRunLoopCommonModes];
    }
    [self playerChanged:nil];
}

- (void)close {
    [_bars stopAnimating];
    [_scrollTimer invalidate];
    _scrollTimer = nil;
    [super close];
}

- (void)scrollTick:(NSTimer *)timer {
    _panel.scrollOffset = _panel.scrollOffset + 1.5;
    [_panel setNeedsDisplay:YES];
}

- (void)playerChanged:(NSNotification *)note {
    BTPlayer *player = [BTPlayer sharedPlayer];
    _playButton.glyph = [player isPlaying] ? BTGlyphPause : BTGlyphPlay;
    _shuffleButton.on = player.shuffle;
    _repeatButton.on = (player.repeatMode != BTRepeatModeOff);
    _volume.value = [player volume];

    NSTimeInterval duration = [player duration];
    if (!_draggingPosition) {
        _position.value = (duration > 0) ? ([player currentTime] / duration) : 0.0;
    }
    [_volume setNeedsDisplay:YES];
    [_position setNeedsDisplay:YES];
    [_panel setNeedsDisplay:YES];
}

#pragma mark - Actions

// Routed rather than called directly: with nothing loaded yet, only the main
// window knows which song to start.
//
// The name must differ from the selector being sent. This controller sits in
// the responder chain, so a method named playPause: that sends playPause: finds
// itself and recurses until the stack runs out.
- (void)miniPlayPause:(id)sender {
    [NSApp sendAction:@selector(playPause:) to:nil from:self];
}
- (void)pause:(id)sender { [[BTPlayer sharedPlayer] pause]; }
- (void)stop:(id)sender { [[BTPlayer sharedPlayer] stop]; }
- (void)next:(id)sender { [[BTPlayer sharedPlayer] next]; }
- (void)previous:(id)sender { [[BTPlayer sharedPlayer] previous]; }

- (void)shuffle:(id)sender {
    BTPlayer *player = [BTPlayer sharedPlayer];
    player.shuffle = !player.shuffle;
}

- (void)repeatPressed:(id)sender {
    BTPlayer *player = [BTPlayer sharedPlayer];
    player.repeatMode = (BTRepeatMode)((player.repeatMode + 1) % 3);
}

- (void)volumeChanged:(id)sender {
    [[BTPlayer sharedPlayer] setVolume:(float)_volume.value];
}

- (void)positionChanged:(id)sender {
    BTPlayer *player = [BTPlayer sharedPlayer];
    NSTimeInterval duration = [player duration];
    if (duration <= 0) return;
    [player seekToTime:duration * _position.value];
}

@end
