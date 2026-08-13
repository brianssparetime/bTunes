#import "BTControls.h"
#import "BTStyle.h"

void BTDrawGlyph(BTGlyph glyph, NSRect rect, NSColor *color) {
    switch (glyph) {
        case BTGlyphPlay:        [BTStyle drawPlayGlyphInRect:rect color:color]; break;
        case BTGlyphPause:       [BTStyle drawPauseGlyphInRect:rect color:color]; break;
        case BTGlyphPrevious:    [BTStyle drawPreviousGlyphInRect:rect color:color]; break;
        case BTGlyphNext:        [BTStyle drawNextGlyphInRect:rect color:color]; break;
        case BTGlyphPreviousBar: [BTStyle drawPreviousBarGlyphInRect:rect color:color]; break;
        case BTGlyphNextBar:     [BTStyle drawNextBarGlyphInRect:rect color:color]; break;
        case BTGlyphShuffle:     [BTStyle drawShuffleGlyphInRect:rect color:color]; break;
        case BTGlyphRepeat:      [BTStyle drawRepeatGlyphInRect:rect one:NO color:color]; break;
        case BTGlyphRepeatOne:   [BTStyle drawRepeatGlyphInRect:rect one:YES color:color]; break;
        case BTGlyphShrink:      [BTStyle drawShrinkGlyphInRect:rect color:color]; break;
        case BTGlyphEject:       [BTStyle drawEjectGlyphInRect:rect color:color]; break;
        case BTGlyphSync:        [BTStyle drawSyncGlyphInRect:rect color:color]; break;
        case BTGlyphStop: {
            // Matched to the play triangle beside it, not to the button.
            CGFloat side = NSHeight(rect) * 0.46;
            [color set];
            NSRectFill(NSMakeRect(NSMidX(rect) - side / 2, NSMidY(rect) - side / 2, side, side));
            break;
        }
        case BTGlyphPlus: {
            [color set];
            NSRect r = NSInsetRect(rect, NSWidth(rect) * 0.28, NSHeight(rect) * 0.28);
            NSRectFill(NSMakeRect(NSMidX(r) - 1, NSMinY(r), 2, NSHeight(r)));
            NSRectFill(NSMakeRect(NSMinX(r), NSMidY(r) - 1, NSWidth(r), 2));
            break;
        }
    }
}

NSTextField *BTLabelWithText(NSString *text, NSFont *font) {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [label setStringValue:(text ? text : @"")];
    [label setFont:font];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    return label;
}

BOOL BTHandleTransportKey(NSEvent *event, id sender, BOOL plainArrowsAreVolume) {
    NSString *characters = [event charactersIgnoringModifiers];
    if ([characters length] == 0) return NO;

    unichar key = [characters characterAtIndex:0];
    BOOL option = ([event modifierFlags] & NSAlternateKeyMask) != 0;
    if (([event modifierFlags] & NSCommandKeyMask) != 0) return NO;

    switch (key) {
        case NSLeftArrowFunctionKey:
            [NSApp sendAction:@selector(previousTrack:) to:nil from:sender];
            return YES;
        case NSRightArrowFunctionKey:
            [NSApp sendAction:@selector(nextTrack:) to:nil from:sender];
            return YES;
        case NSUpArrowFunctionKey:
            if (!option && !plainArrowsAreVolume) return NO;
            [NSApp sendAction:@selector(volumeUp:) to:nil from:sender];
            return YES;
        case NSDownArrowFunctionKey:
            if (!option && !plainArrowsAreVolume) return NO;
            [NSApp sendAction:@selector(volumeDown:) to:nil from:sender];
            return YES;
        case ' ':
            [NSApp sendAction:@selector(playPause:) to:nil from:sender];
            return YES;
        case 'm':
        case 'M':
            [NSApp sendAction:@selector(toggleMute:) to:nil from:sender];
            return YES;
        default:
            return NO;
    }
}

#pragma mark - Round transport button

@implementation BTRoundButton

+ (instancetype)buttonWithFrame:(NSRect)frame glyph:(BTGlyph)glyph target:(id)target action:(SEL)action {
    BTRoundButton *b = [[BTRoundButton alloc] initWithFrame:frame];
    b.glyph = glyph;
    [b setTarget:target];
    [b setAction:action];
    [b setBordered:NO];
    [b setTitle:@""];
    [b setButtonType:NSMomentaryChangeButton];
    return b;
}

- (void)drawRect:(NSRect)dirtyRect {
    BOOL pressed = [self isHighlighted];
    BOOL enabled = [self isEnabled];
    NSRect bounds = [self bounds];
    [BTStyle drawAquaCircleInRect:bounds pressed:pressed enabled:enabled];

    // Dark gray rather than black: the glyphs on these buttons were never pure
    // black, and at this size black reads as a smudge.
    NSColor *ink = enabled ? [NSColor colorWithCalibratedWhite:0.24 alpha:1.0]
                           : [NSColor colorWithCalibratedWhite:0.62 alpha:1.0];
    BTDrawGlyph(self.glyph, bounds, ink);
}

- (void)setGlyph:(BTGlyph)glyph {
    _glyph = glyph;
    [self setNeedsDisplay:YES];
}

@end

#pragma mark - Square toggle

@implementation BTToggleButton

+ (instancetype)buttonWithFrame:(NSRect)frame glyph:(BTGlyph)glyph target:(id)target action:(SEL)action {
    BTToggleButton *b = [[BTToggleButton alloc] initWithFrame:frame];
    b.glyph = glyph;
    [b setTarget:target];
    [b setAction:action];
    [b setBordered:NO];
    [b setTitle:@""];
    [b setButtonType:NSMomentaryChangeButton];
    return b;
}

- (void)setOn:(BOOL)on {
    _on = on;
    [self setNeedsDisplay:YES];
}

- (void)setGlyph:(BTGlyph)glyph {
    _glyph = glyph;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    if ([self isHighlighted]) [BTStyle drawTogglePressedInRect:bounds];

    // On is carried by the mark itself, in the blue the window already uses for
    // a selected row, so the two agree about what blue means here.
    NSColor *ink = self.on ? [BTStyle selection] : [NSColor colorWithCalibratedWhite:0.25 alpha:1.0];
    BTDrawGlyph(self.glyph, bounds, ink);
}

@end

#pragma mark - Push button

@implementation BTPushButton

+ (instancetype)buttonWithTitle:(NSString *)title target:(id)target action:(SEL)action {
    BTPushButton *b = [[BTPushButton alloc] initWithFrame:NSMakeRect(0, 0, 90, 22)];
    [b setTitle:title];
    [b setBezelStyle:NSRoundedBezelStyle];
    [b setFont:[BTStyle uiFont]];
    [b setTarget:target];
    [b setAction:action];
    [b sizeToFit];
    // Room around the words, since the drawn capsule has more curve at its ends
    // than the system bezel this measured against.
    NSRect frame = [b frame];
    [b setFrame:NSMakeRect(0, 0, NSWidth(frame) + 12.0, 22.0)];
    return b;
}

- (BOOL)isDefaultButton {
    return [[self keyEquivalent] isEqualToString:@"\r"];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    BOOL enabled = [self isEnabled];
    [BTStyle drawPushButtonInRect:bounds
                          pressed:[self isHighlighted]
                          enabled:enabled
                        isDefault:[self isDefaultButton]];

    NSColor *ink = [NSColor colorWithCalibratedWhite:0.16 alpha:1.0];
    if ([self isDefaultButton]) ink = [NSColor whiteColor];
    if (!enabled) ink = [NSColor colorWithCalibratedWhite:0.62 alpha:1.0];

    NSMutableParagraphStyle *centred = [[NSMutableParagraphStyle alloc] init];
    [centred setAlignment:NSCenterTextAlignment];
    [centred setLineBreakMode:NSLineBreakByClipping];
    NSDictionary *attrs = @{NSFontAttributeName: [self font],
                            NSForegroundColorAttributeName: ink,
                            NSParagraphStyleAttributeName: centred};

    // Placed off the measured height of the line rather than off the em box, the
    // same reason the word in the search field needed lifting.
    NSSize size = [[self title] sizeWithAttributes:attrs];
    [[self title] drawInRect:NSMakeRect(NSMinX(bounds), NSMidY(bounds) - size.height / 2.0,
                                        NSWidth(bounds), size.height)
              withAttributes:attrs];
}

@end

#pragma mark - Search field

#define BT_SEARCH_GLYPH 11.0
#define BT_SEARCH_LEFT  7.0


@implementation BTSearchFieldCell

- (NSRect)searchButtonRectForBounds:(NSRect)rect {
    // The magnifier is drawn here rather than by the cell, so this rect only
    // has to keep the cell from putting anything in the same place.
    return NSZeroRect;
}

- (NSRect)searchTextRectForBounds:(NSRect)rect {
    CGFloat left = BT_SEARCH_LEFT + BT_SEARCH_GLYPH + 5.0;
    CGFloat right = 20.0;

    // The whole height of the capsule, less a hair top and bottom. The cell
    // centres its line within whatever rect it is handed, which is why every
    // attempt to place the line by hand came out low: a rect one line tall,
    // positioned by eye, only moved the word half as far as it was moved.
    // Handing over the full height lets the centring that is already there do
    // the work, and the word lands on the same line as the magnifier.
    // The capsule's own height, unshifted. The cell centres its line inside
    // whatever rect it is handed, so handing it the whole capsule puts the word
    // on the middle without any arithmetic here.
    //
    // Every correction tried before this was measured by drawing the field
    // offscreen, which places the line differently from a field inside a window.
    // The offscreen answer and the running one differed by five points, so the
    // measurements were confidently wrong twice. This is measured from the app.
    return NSMakeRect(NSMinX(rect) + left, NSMinY(rect),
                      NSWidth(rect) - left - right, NSHeight(rect));
}

// The field editor has to be given the same rect the text is drawn in, or the
// typed text lands somewhere else and the two overlap.
- (void)editWithFrame:(NSRect)frame
               inView:(NSView *)view
               editor:(NSText *)editor
             delegate:(id)delegate
                event:(NSEvent *)event {
    [super editWithFrame:[self searchTextRectForBounds:frame]
                  inView:view
                  editor:editor
                delegate:delegate
                   event:event];
}

- (void)selectWithFrame:(NSRect)frame
                 inView:(NSView *)view
                 editor:(NSText *)editor
               delegate:(id)delegate
                  start:(NSInteger)start
                 length:(NSInteger)length {
    [super selectWithFrame:[self searchTextRectForBounds:frame]
                    inView:view
                    editor:editor
                  delegate:delegate
                     start:start
                    length:length];
}

- (NSRect)cancelButtonRectForBounds:(NSRect)rect {
    CGFloat side = 13.0;
    return NSMakeRect(NSMaxX(rect) - side - 5.0, NSMidY(rect) - side / 2, side, side);
}

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view {
    NSRect box = NSInsetRect(frame, 0.5, 0.5);
    CGFloat radius = NSHeight(box) / 2.0;

    NSBezierPath *capsule = [NSBezierPath bezierPathWithRoundedRect:box
                                                            xRadius:radius
                                                            yRadius:radius];
    [[NSColor whiteColor] set];
    [capsule fill];
    [[NSColor colorWithCalibratedWhite:0.51 alpha:1.0] set];
    [capsule setLineWidth:1.0];
    [capsule stroke];

    // Centered on the same line as the text, not sitting under it.
    NSRect glyph = NSMakeRect(NSMinX(frame) + BT_SEARCH_LEFT,
                              NSMidY(frame) - BT_SEARCH_GLYPH / 2,
                              BT_SEARCH_GLYPH, BT_SEARCH_GLYPH);
    [BTStyle drawMagnifierGlyphInRect:glyph
                                color:[NSColor colorWithCalibratedWhite:0.35 alpha:1.0]];

    // The interior gets the whole frame. The cell places the text and the clear
    // button inside it using the rects above, and its hit testing uses those
    // same rects: hand it a smaller frame and the clear button is drawn
    // somewhere other than where clicks are looked for.
    [self drawInteriorWithFrame:frame inView:view];
}

@end

#pragma mark - List

@implementation BTListTableView

- (void)highlightSelectionInClipRect:(NSRect)clipRect {
    NSIndexSet *selected = [self selectedRowIndexes];
    if ([selected count] == 0) return;

    // The whole window agrees on one selection color: blue while the window is
    // active, gray when it is not. Which pane holds focus does not change it.
    NSColor *color = [[self window] isKeyWindow] ? [BTStyle selection] : [BTStyle inactiveSelection];
    [color set];

    NSRange rows = [self rowsInRect:clipRect];
    NSUInteger row;
    for (row = rows.location; row < NSMaxRange(rows); row++) {
        if ([selected containsIndex:row]) {
            NSRectFill([self rectOfRow:(NSInteger)row]);
        }
    }
}

// Redraw when the window activates so the selection color follows it.
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if ([self window] == nil) return;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(windowChangedKey:)
               name:NSWindowDidBecomeKeyNotification object:[self window]];
    [nc addObserver:self selector:@selector(windowChangedKey:)
               name:NSWindowDidResignKeyNotification object:[self window]];
}

- (void)windowChangedKey:(NSNotification *)note {
    [self setNeedsDisplay:YES];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

#pragma mark - Volume

// Drawn rather than assembled from a stock slider. The system control brings
// its own metrics and its own idea of a knob, and next to hand-drawn speakers
// the pair never sat together.
#define BT_VOLUME_KNOB   13.0
#define BT_VOLUME_LEFT   15.0
#define BT_VOLUME_RIGHT  20.0

@implementation BTVolumeView {
    float _volume;
    BOOL _dragging;
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) _volume = 0.75f;
    return self;
}

- (NSRect)trackRect {
    NSRect bounds = [self bounds];
    return NSMakeRect(NSMinX(bounds) + BT_VOLUME_LEFT,
                      NSMidY(bounds) - 2.5,
                      NSWidth(bounds) - BT_VOLUME_LEFT - BT_VOLUME_RIGHT,
                      5.0);
}

- (float)volume { return _volume; }

- (void)setVolume:(float)volume {
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    _volume = volume;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    NSColor *ink = [NSColor colorWithCalibratedWhite:0.28 alpha:1.0];
    NSRect track = [self trackRect];

    // The same speaker at both ends, the same size, on the track's centre line.
    // Only the arcs differ.
    [BTStyle drawSpeakerGlyphInRect:NSMakeRect(NSMinX(bounds) + 1, NSMidY(bounds) - 5.5, 13, 11)
                              waves:0
                              color:ink];
    [BTStyle drawSpeakerGlyphInRect:NSMakeRect(NSMaxX(bounds) - 16, NSMidY(bounds) - 5.5, 13, 11)
                              waves:2
                              color:ink];

    CGFloat travel = NSWidth(track) - BT_VOLUME_KNOB;
    CGFloat knobX = NSMinX(track) + travel * (CGFloat)_volume;

    [BTStyle drawGrooveInRect:track];

    NSRect knob = NSMakeRect(knobX, NSMidY(bounds) - BT_VOLUME_KNOB / 2,
                             BT_VOLUME_KNOB, BT_VOLUME_KNOB);
    [BTStyle drawAquaCircleInRect:knob pressed:_dragging enabled:YES];
}

- (void)setVolumeFromPoint:(NSPoint)point {
    NSRect track = [self trackRect];
    CGFloat travel = NSWidth(track) - BT_VOLUME_KNOB;
    if (travel <= 0) return;

    [self setVolume:(float)((point.x - NSMinX(track) - BT_VOLUME_KNOB / 2) / travel)];

    if (self.target && self.action && [self.target respondsToSelector:self.action]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.target performSelector:self.action withObject:self];
        #pragma clang diagnostic pop
    }
}

- (void)mouseDown:(NSEvent *)event {
    _dragging = YES;
    [self setVolumeFromPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
}

- (void)mouseDragged:(NSEvent *)event {
    [self setVolumeFromPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
}

- (void)mouseUp:(NSEvent *)event {
    _dragging = NO;
    [self setNeedsDisplay:YES];
}

@end
