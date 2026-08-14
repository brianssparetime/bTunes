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
        case BTGlyphBurn:        [BTStyle drawBurnGlyphInRect:rect color:color]; break;
        case BTGlyphImport:      [BTStyle drawImportGlyphInRect:rect color:color]; break;
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

// The band one line of text sits in, centred in whatever it is given.
//
// Both the placeholder and the field editor are placed through this, because
// they have to agree. A line is laid along the top of the rect it is handed, not
// centred in it, so a rect the height of the capsule leaves the words riding
// high by the slack between the two. The placeholder was already being handed a
// band this size and looked right; the field editor was handed the whole capsule
// and the typed word sat above the magnifier, which is a difference nobody
// reading the field would call anything but a fault.
//
// Handing it a rect already one line tall changes nothing, so the placeholder
// path passing through here a second time is harmless.
- (NSRect)lineBandInRect:(NSRect)rect {
    NSFont *font = [self font];
    CGFloat line = ceil([font ascender] - [font descender]);
    CGFloat slack = (NSHeight(rect) - line) / 2.0;
    if (slack <= 0) return rect;
    return NSMakeRect(NSMinX(rect), NSMinY(rect) + slack, NSWidth(rect), line);
}

- (NSRect)searchTextRectForBounds:(NSRect)rect {
    CGFloat left = BT_SEARCH_LEFT + BT_SEARCH_GLYPH + 5.0;
    CGFloat right = 20.0;

    // Room for the magnifier on the left and the clear mark on the right, and
    // the line put on the middle by the band above.
    //
    // Every correction tried before this was measured by drawing the field
    // offscreen, which places a line differently from a field inside a window.
    // The offscreen answer and the running one differed by five points, so the
    // measurements were confidently wrong twice. This one is measured from a
    // field with the keyboard in it.
    NSRect band = [self lineBandInRect:rect];
    return NSMakeRect(NSMinX(band) + left, NSMinY(band),
                      NSWidth(band) - left - right, NSHeight(band));
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

    // The placeholder, on the same band the typed word is given. This is what
    // places the words when nothing is being typed; searchTextRectForBounds:
    // places them when something is. Changing one and expecting the other to
    // move is how three attempts at this missed.
    [self drawInteriorWithFrame:[self lineBandInRect:frame] inView:view];
}

@end

#pragma mark - List

NSString *const BTListFocusDidChangeNotification = @"BTListFocusDidChange";

// One list at a time draws the strong colour: the one the keyboard is talking
// to, in the window being used. Two lists filling rows in the same colour at
// once read as one list, and where their rows nearly line up across a divider
// the two fills merge into a single band with tabs on it, which is what gave
// this away. The grids cannot be made to line up either, since the two lists
// have different row heights and one of them sits below a column header.
BOOL BTListHasFocus(NSTableView *list) {
    NSWindow *window = [list window];
    if (![window isKeyWindow]) return NO;

    id responder = [window firstResponder];
    if (responder == list) return YES;

    // While a name is being edited the field editor holds focus, and it belongs
    // to the list being edited rather than to nothing.
    return [responder isKindOfClass:[NSView class]] &&
           [(NSView *)responder isDescendantOf:list];
}

void BTDrawListSelection(NSTableView *list, NSRect clipRect) {
    NSIndexSet *selected = [list selectedRowIndexes];
    if ([selected count] == 0) return;

    NSColor *color = BTListHasFocus(list) ? [BTStyle selection]
                                          : [BTStyle inactiveSelection];
    [color set];

    NSRange rows = [list rowsInRect:clipRect];
    NSUInteger row;
    for (row = rows.location; row < NSMaxRange(rows); row++) {
        if ([selected containsIndex:row]) {
            NSRectFill([list rectOfRow:(NSInteger)row]);
        }
    }
}

// A notification handler of its own rather than setNeedsDisplay: directly. That
// takes a BOOL, and handing it a notification passes a pointer where a single
// byte is read, which is a coin toss rather than a redraw.
@implementation NSView (BTListFocus)
- (void)btListFocusChanged:(NSNotification *)note {
    [self setNeedsDisplay:YES];
}
@end

// Sent on the next turn of the run loop rather than at once. A list is told it
// is becoming first responder before the window has finished believing it, so a
// redraw taken at that moment asks who has focus and is given the old answer.
void BTNoteListFocusChanged(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:BTListFocusDidChangeNotification object:nil];
    });
}

void BTWatchListFocus(NSView *list) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    // Any list moving the keyboard repaints every list, since the one losing
    // focus has to turn gray at the same moment the other turns.
    [nc addObserver:list selector:@selector(btListFocusChanged:)
               name:BTListFocusDidChangeNotification object:nil];

    if ([list window] == nil) return;
    [nc addObserver:list selector:@selector(btListFocusChanged:)
               name:NSWindowDidBecomeKeyNotification object:[list window]];
    [nc addObserver:list selector:@selector(btListFocusChanged:)
               name:NSWindowDidResignKeyNotification object:[list window]];
}

BOOL BTHandleDeleteKey(NSEvent *event, NSTableView *list) {
    NSString *characters = [event charactersIgnoringModifiers];
    if ([characters length] == 0) return NO;

    unichar key = [characters characterAtIndex:0];
    if (key != NSDeleteCharacter && key != NSBackspaceCharacter &&
        key != NSDeleteFunctionKey) {
        return NO;
    }

    id delegate = [list delegate];
    if (![delegate respondsToSelector:@selector(tableViewDeletePressed:)]) return NO;
    [delegate performSelector:@selector(tableViewDeletePressed:) withObject:list];
    return YES;
}

// A table and an outline view have no common ancestor of ours, so these two are
// siblings and each hooks up the shared behaviour itself. Every method here is
// one line calling a function above, which is where the behaviour actually
// lives; what cannot be shared is the hooking up. The two must stay in step,
// and they are kept side by side so that is easy to see.

@implementation BTListTableView

- (void)highlightSelectionInClipRect:(NSRect)clipRect {
    BTDrawListSelection(self, clipRect);
}

- (BOOL)becomeFirstResponder {
    BOOL became = [super becomeFirstResponder];
    if (became) BTNoteListFocusChanged();
    return became;
}

- (BOOL)resignFirstResponder {
    BOOL resigned = [super resignFirstResponder];
    if (resigned) BTNoteListFocusChanged();
    return resigned;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    BTWatchListFocus(self);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

@implementation BTListOutlineView

- (void)highlightSelectionInClipRect:(NSRect)clipRect {
    BTDrawListSelection(self, clipRect);
}

- (BOOL)becomeFirstResponder {
    BOOL became = [super becomeFirstResponder];
    if (became) BTNoteListFocusChanged();
    return became;
}

- (BOOL)resignFirstResponder {
    BOOL resigned = [super resignFirstResponder];
    if (resigned) BTNoteListFocusChanged();
    return resigned;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    BTWatchListFocus(self);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

@implementation BTCheckboxCell

- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view {
    CGFloat side = MIN(13.0, NSHeight(frame));
    NSRect box = NSMakeRect(NSMinX(frame), NSMinY(frame) + (NSHeight(frame) - side) / 2.0,
                            side, side);
    [BTStyle drawCheckboxInRect:box state:[self state] enabled:[self isEnabled]];

    NSString *title = [self title];
    if ([title length] == 0) return;

    // The words sit beside the box on the same line, which is where a checkbox
    // has always put them.
    NSColor *ink = [self isEnabled] ? [NSColor blackColor]
                                    : [NSColor colorWithCalibratedWhite:0.55 alpha:1.0];
    NSDictionary *attributes = @{NSFontAttributeName: ([self font] ?: [BTStyle uiFont]),
                                 NSForegroundColorAttributeName: ink};
    NSSize size = [title sizeWithAttributes:attributes];
    NSRect where = NSMakeRect(NSMaxX(box) + 4.0,
                              NSMinY(frame) + (NSHeight(frame) - size.height) / 2.0,
                              NSWidth(frame) - side - 4.0, size.height);
    [title drawInRect:where withAttributes:attributes];
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
