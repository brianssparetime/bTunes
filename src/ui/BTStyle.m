#import "BTStyle.h"

static NSFont *BTFontNamed(NSString *name, CGFloat size, BOOL bold) {
    NSFont *font = [NSFont fontWithName:name size:size];
    if (font) return font;
    return bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
}

@implementation BTStyle

+ (NSFont *)uiFont        { return BTFontNamed(@"Lucida Grande", 11.0, NO); }
+ (NSFont *)boldFont      { return BTFontNamed(@"Lucida Grande Bold", 11.0, YES); }
+ (NSFont *)smallFont     { return BTFontNamed(@"Lucida Grande", 9.0, NO); }
+ (NSFont *)displayFont   { return BTFontNamed(@"Lucida Grande", 10.0, NO); }
+ (NSFont *)displayBoldFont { return BTFontNamed(@"Lucida Grande Bold", 10.0, YES); }

// #8400FF, with the same lit edge and shadow the logo is drawn from. Change
// these alongside the palette at the top of tools/make_logo.py.
+ (NSColor *)accent      { return [NSColor colorWithCalibratedRed:0.518 green:0.000 blue:1.000 alpha:1.0]; }
+ (NSColor *)accentLight { return [NSColor colorWithCalibratedRed:0.729 green:0.478 blue:1.000 alpha:1.0]; }
+ (NSColor *)accentDark  { return [NSColor colorWithCalibratedRed:0.196 green:0.000 blue:0.549 alpha:1.0]; }

// Weighted toward the older gray chrome rather than the near-white the current
// system draws, so the window reads as something from a few releases back.
+ (NSColor *)windowBackground { return [NSColor colorWithCalibratedWhite:0.671 alpha:1.0]; }
+ (NSColor *)chromeTop       { return [NSColor colorWithCalibratedWhite:0.741 alpha:1.0]; }
+ (NSColor *)chromeBottom    { return [NSColor colorWithCalibratedWhite:0.549 alpha:1.0]; }
// The line under the chrome. Kept mid gray: at near black it reads as a slot
// cut through the window rather than as the edge of the bar.
+ (NSColor *)chromeEdge      { return [NSColor colorWithCalibratedWhite:0.588 alpha:1.0]; }
+ (NSColor *)listBackground  { return [NSColor whiteColor]; }

// Locked, not downloaded, holding one of those, or smart: one gray for all of
// them for now. The same gray the track list already uses for a song that
// cannot play, so the two agree about what gray means.
+ (NSColor *)ineligibleTextForReason:(NSInteger)reason {
    (void)reason;
    return [NSColor colorWithCalibratedWhite:0.55 alpha:1.0];
}
+ (NSColor *)selection       { return [NSColor colorWithCalibratedRed:0.220 green:0.459 blue:0.843 alpha:1.0]; }
+ (NSColor *)inactiveSelection { return [NSColor colorWithCalibratedWhite:0.702 alpha:1.0]; }
// The readout carries a faint green cast so it reads as a small screen rather
// than another gray panel.
+ (NSColor *)displayBackground { return [NSColor colorWithCalibratedRed:0.855 green:0.886 blue:0.855 alpha:1.0]; }
+ (NSColor *)displayEdge     { return [NSColor colorWithCalibratedWhite:0.427 alpha:1.0]; }
+ (NSColor *)displayText     { return [NSColor colorWithCalibratedRed:0.055 green:0.106 blue:0.067 alpha:1.0]; }

+ (void)drawVerticalGradientInRect:(NSRect)rect from:(NSColor *)top to:(NSColor *)bottom {
    NSGradient *g = [[NSGradient alloc] initWithStartingColor:bottom endingColor:top];
    [g drawInRect:rect angle:90.0];
}

// A faint brushed grain, built once and tiled. Horizontal runs of the same
// value rather than loose noise, so it reads as metal that has been polished
// along its length instead of as dirt on the window.
static NSImage *BTSteelGrain(void) {
    static NSImage *grain = nil;
    if (grain) return grain;

    NSSize size = NSMakeSize(96.0, 32.0);
    grain = [[NSImage alloc] initWithSize:size];
    [grain lockFocus];

    unsigned int seed = 20030428;   // fixed, so the grain never shuffles
    NSInteger y, x;
    for (y = 0; y < (NSInteger)size.height; y++) {
        x = 0;
        while (x < (NSInteger)size.width) {
            seed = seed * 1103515245 + 12345;
            CGFloat value = (CGFloat)((seed >> 16) & 0x7FFF) / 32767.0 - 0.5;
            NSInteger run = 2 + (NSInteger)(((seed >> 8) & 0x7) );

            if (value >= 0) {
                [[NSColor colorWithCalibratedWhite:1.0 alpha:(value * 0.14)] set];
            } else {
                [[NSColor colorWithCalibratedWhite:0.0 alpha:(-value * 0.10)] set];
            }
            NSRectFillUsingOperation(NSMakeRect(x, y, run, 1), NSCompositeSourceOver);
            x += run;
        }
    }
    [grain unlockFocus];
    return grain;
}

+ (void)drawChromeInRect:(NSRect)rect {
    [self drawVerticalGradientInRect:rect from:[self chromeTop] to:[self chromeBottom]];

    [NSGraphicsContext saveGraphicsState];
    [[NSGraphicsContext currentContext] setPatternPhase:NSMakePoint(0, 0)];
    [[NSColor colorWithPatternImage:BTSteelGrain()] set];
    NSRectFillUsingOperation(rect, NSCompositeSourceOver);
    [NSGraphicsContext restoreGraphicsState];

    // No drawn line at either edge. The step from the gradient's dark end to
    // the content below is separation enough, and any line across a boundary
    // this wide reads as a seam however light it is made.
}

+ (void)drawSunkenBezelInRect:(NSRect)rect radius:(CGFloat)radius fill:(NSColor *)fill {
    NSRect inner = NSInsetRect(rect, 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:inner xRadius:radius yRadius:radius];
    [fill set];
    [path fill];

    // No shading under the top edge: on a panel this size it reads as something
    // above casting a shadow into it rather than as a recess. The border and the
    // bounce along the floor carry the depth on their own.
    [NSGraphicsContext saveGraphicsState];
    [path addClip];

    // A faint catch along the bottom inside, the light bouncing back up.
    NSGradient *bounce = [[NSGradient alloc]
        initWithStartingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.55]
                  endingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.0]];
    [bounce drawInRect:NSMakeRect(NSMinX(inner), NSMinY(inner), NSWidth(inner), 5.0)
                 angle:90.0];
    [NSGraphicsContext restoreGraphicsState];

    [[self displayEdge] set];
    [path setLineWidth:1.0];
    [path stroke];
}

+ (void)drawGrooveInRect:(NSRect)rect {
    CGFloat radius = NSHeight(rect) / 2.0;
    NSRect inner = NSInsetRect(rect, 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:inner xRadius:radius yRadius:radius];

    [[NSColor colorWithCalibratedWhite:0.72 alpha:1.0] set];
    [path fill];

    [NSGraphicsContext saveGraphicsState];
    [path addClip];
    // Darkest right under the top edge, easing off downward, then a bright line
    // along the floor: the shading that makes a channel look cut in.
    NSGradient *shade = [[NSGradient alloc]
        initWithStartingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.55]
                  endingColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.30]];
    [shade drawInRect:inner angle:90.0];
    [NSGraphicsContext restoreGraphicsState];

    [[NSColor colorWithCalibratedWhite:0.48 alpha:1.0] set];
    [path setLineWidth:1.0];
    [path stroke];
}

+ (void)drawAquaCircleInRect:(NSRect)rect pressed:(BOOL)pressed enabled:(BOOL)enabled {
    NSRect box = NSInsetRect(rect, 0.5, 0.5);

    NSColor *top = pressed ? [NSColor colorWithCalibratedWhite:0.72 alpha:1.0]
                           : [NSColor colorWithCalibratedWhite:0.99 alpha:1.0];
    NSColor *bottom = pressed ? [NSColor colorWithCalibratedWhite:0.55 alpha:1.0]
                              : [NSColor colorWithCalibratedWhite:0.78 alpha:1.0];
    if (!enabled) {
        top = [NSColor colorWithCalibratedWhite:0.93 alpha:1.0];
        bottom = [NSColor colorWithCalibratedWhite:0.87 alpha:1.0];
    }

    // A soft gray rim rather than an outline: the 2003 buttons had no black
    // edge, they had a lighter ring that darkened toward the bottom.
    NSBezierPath *rim = [NSBezierPath bezierPathWithOvalInRect:box];
    [NSGraphicsContext saveGraphicsState];
    [rim addClip];
    // Almost as light as the face at the top, so the edge disappears where the
    // button is brightest and only shows along the sides and underneath. A rim
    // darker than the face reads as a ring drawn across the top.
    [self drawVerticalGradientInRect:box
                                from:[NSColor colorWithCalibratedWhite:0.93 alpha:1.0]
                                  to:[NSColor colorWithCalibratedWhite:0.42 alpha:1.0]];
    [NSGraphicsContext restoreGraphicsState];

    box = NSInsetRect(box, 1.0, 1.0);
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:box];

    [NSGraphicsContext saveGraphicsState];
    [circle addClip];
    [self drawVerticalGradientInRect:box from:top to:bottom];

    // The cap: light gathering near the top of the dome and falling away from
    // there. This is what made those buttons read as polished rather than as
    // flat discs.
    //
    // Drawn as a radial fade, which reaches nothing in every direction at the
    // ellipse's edge. A vertical gradient clipped to the same ellipse fades at
    // the top and the bottom but stops dead at the sides, and peaking it
    // partway down leaves the surface dimmest between the top edge and the
    // highlight. Brightness that falls and then rises again reads as a crease
    // across something that should be smooth.
    NSRect cap = NSInsetRect(box, NSWidth(box) * 0.10, 0);
    cap.origin.y = NSMinY(box) + NSHeight(box) * 0.34;
    cap.size.height = NSHeight(box) * 0.66;

    NSGradient *capGradient = [[NSGradient alloc]
        initWithStartingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:(pressed ? 0.24 : 0.78)]
                  endingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.0]];
    // Off centre toward the top, so the brightest point sits high on the dome
    // rather than in the middle of it.
    [capGradient drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:cap]
           relativeCenterPosition:NSMakePoint(0.0, 0.45)];

    // Light bouncing back up off the surface the button sits on.
    NSGradient *bounce = [[NSGradient alloc]
        initWithStartingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.55]
                  endingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.0]];
    [bounce drawInRect:NSMakeRect(NSMinX(box), NSMinY(box), NSWidth(box), NSHeight(box) * 0.30)
                 angle:90.0];

    [NSGraphicsContext restoreGraphicsState];
}

// Only while the mouse is down. A toggle that is on says so by the color of its
// mark, not by a filled tile behind it: a solid block of blue in the gray at the
// bottom of the window pulls the eye away from the song list for a setting that
// is not the point of the window.
+ (void)drawTogglePressedInRect:(NSRect)rect {
    NSRect box = NSInsetRect(rect, 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:box xRadius:3.0 yRadius:3.0];
    [[NSColor colorWithCalibratedWhite:0.72 alpha:1.0] set];
    [path fill];
    [[NSColor colorWithCalibratedWhite:0.42 alpha:1.0] set];
    [path stroke];
}

#pragma mark - Glyphs

+ (void)drawTriangleInRect:(NSRect)rect pointingRight:(BOOL)right color:(NSColor *)color {
    NSBezierPath *p = [NSBezierPath bezierPath];
    if (right) {
        [p moveToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))];
        [p lineToPoint:NSMakePoint(NSMaxX(rect), NSMidY(rect))];
        [p lineToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];
    } else {
        [p moveToPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect))];
        [p lineToPoint:NSMakePoint(NSMinX(rect), NSMidY(rect))];
        [p lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
    }
    [p closePath];
    [color set];
    [p fill];
}

+ (void)drawPlayGlyphInRect:(NSRect)rect color:(NSColor *)color {
    NSRect r = NSInsetRect(rect, NSWidth(rect) * 0.30, NSHeight(rect) * 0.26);
    // A triangle centered by its bounding box reads as sitting left of center,
    // because its weight is all at the base. Nudge it toward the point.
    r.origin.x += NSWidth(rect) * 0.045;
    [self drawTriangleInRect:r pointingRight:YES color:color];
}

+ (void)drawPauseGlyphInRect:(NSRect)rect color:(NSColor *)color {
    CGFloat w = NSWidth(rect) * 0.11;
    CGFloat h = NSHeight(rect) * 0.44;
    CGFloat gap = w * 1.2;
    [color set];
    NSRectFill(NSMakeRect(NSMidX(rect) - gap / 2 - w, NSMidY(rect) - h / 2, w, h));
    NSRectFill(NSMakeRect(NSMidX(rect) + gap / 2, NSMidY(rect) - h / 2, w, h));
}

+ (void)drawSkipGlyphInRect:(NSRect)rect forward:(BOOL)forward bar:(BOOL)bar color:(NSColor *)color {
    NSRect r = NSInsetRect(rect, NSWidth(rect) * 0.26, NSHeight(rect) * 0.28);
    CGFloat barWidth = bar ? NSWidth(r) * 0.16 : 0.0;

    NSRect triangles = r;
    triangles.size.width -= barWidth;
    if (bar && !forward) triangles.origin.x += barWidth;

    NSRect first = triangles;
    first.size.width /= 2.0;
    NSRect second = first;
    second.origin.x += first.size.width;
    [self drawTriangleInRect:first pointingRight:forward color:color];
    [self drawTriangleInRect:second pointingRight:forward color:color];

    if (!bar) return;
    [color set];
    CGFloat barX = forward ? NSMaxX(r) - barWidth : NSMinX(r);
    NSRectFill(NSMakeRect(barX, NSMinY(r), barWidth, NSHeight(r)));
}

// The 2003 transport buttons are bare double triangles. The bar belongs to the
// mini player, whose buttons follow a different original.
+ (void)drawPreviousGlyphInRect:(NSRect)rect color:(NSColor *)color {
    [self drawSkipGlyphInRect:rect forward:NO bar:NO color:color];
}

+ (void)drawNextGlyphInRect:(NSRect)rect color:(NSColor *)color {
    [self drawSkipGlyphInRect:rect forward:YES bar:NO color:color];
}

+ (void)drawPreviousBarGlyphInRect:(NSRect)rect color:(NSColor *)color {
    [self drawSkipGlyphInRect:rect forward:NO bar:YES color:color];
}

+ (void)drawNextBarGlyphInRect:(NSRect)rect color:(NSColor *)color {
    [self drawSkipGlyphInRect:rect forward:YES bar:YES color:color];
}

+ (void)drawSpeakerGlyphInRect:(NSRect)rect waves:(NSInteger)waves color:(NSColor *)color {
    // Built from one closed path so the box and the cone do not show a seam
    // where they meet, and sized off the rect so both ends of the volume
    // control are drawn by the same code at different scales.
    CGFloat h = NSHeight(rect);
    CGFloat centre = NSMidY(rect);
    CGFloat boxWidth = h * 0.24;
    CGFloat coneWidth = h * 0.28;

    NSBezierPath *speaker = [NSBezierPath bezierPath];
    [speaker moveToPoint:NSMakePoint(NSMinX(rect), centre - h * 0.15)];
    [speaker lineToPoint:NSMakePoint(NSMinX(rect) + boxWidth, centre - h * 0.15)];
    [speaker lineToPoint:NSMakePoint(NSMinX(rect) + boxWidth + coneWidth, centre - h * 0.40)];
    [speaker lineToPoint:NSMakePoint(NSMinX(rect) + boxWidth + coneWidth, centre + h * 0.40)];
    [speaker lineToPoint:NSMakePoint(NSMinX(rect) + boxWidth, centre + h * 0.15)];
    [speaker lineToPoint:NSMakePoint(NSMinX(rect), centre + h * 0.15)];
    [speaker closePath];
    [color set];
    [speaker fill];

    CGFloat waveOrigin = NSMinX(rect) + boxWidth + coneWidth;
    NSInteger i;
    for (i = 0; i < waves; i++) {
        CGFloat radius = h * (0.20 + 0.19 * (CGFloat)i);
        NSBezierPath *arc = [NSBezierPath bezierPath];
        [arc appendBezierPathWithArcWithCenter:NSMakePoint(waveOrigin, centre)
                                        radius:radius
                                    startAngle:-45.0
                                      endAngle:45.0];
        [arc setLineWidth:1.2];
        [arc setLineCapStyle:NSRoundLineCapStyle];
        [arc stroke];
    }
}

// A filled arrowhead whose tip sits at the given point, pointing right.
static void BTDrawArrowhead(NSPoint tip, CGFloat length, CGFloat halfHeight, NSColor *color) {
    NSBezierPath *head = [NSBezierPath bezierPath];
    [head moveToPoint:NSMakePoint(tip.x - length, tip.y + halfHeight)];
    [head lineToPoint:tip];
    [head lineToPoint:NSMakePoint(tip.x - length, tip.y - halfHeight)];
    [head closePath];
    [color set];
    [head fill];
}

+ (void)drawMagnifierGlyphInRect:(NSRect)rect color:(NSColor *)color {
    // Cells draw in a flipped context while views do not, so the lens has to be
    // placed against whichever edge is currently the top. Drawn the same way in
    // both, the handle ends up pointing the wrong way in one of them.
    BOOL flipped = [[NSGraphicsContext currentContext] isFlipped];
    CGFloat diameter = MIN(NSWidth(rect), NSHeight(rect)) * 0.62;
    NSRect lens = flipped ? NSMakeRect(NSMinX(rect), NSMinY(rect), diameter, diameter)
                          : NSMakeRect(NSMinX(rect), NSMaxY(rect) - diameter, diameter, diameter);

    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(lens, 0.75, 0.75)];
    [path setLineWidth:1.5];
    [color set];
    [path stroke];

    // The handle runs away from the lens, down and to the right on screen.
    CGFloat down = flipped ? 1.0 : -1.0;
    NSPoint start = NSMakePoint(NSMaxX(lens) - diameter * 0.16,
                                flipped ? NSMaxY(lens) - diameter * 0.16 : NSMinY(lens) + diameter * 0.16);
    NSBezierPath *handle = [NSBezierPath bezierPath];
    [handle setLineWidth:1.5];
    [handle setLineCapStyle:NSRoundLineCapStyle];
    [handle moveToPoint:start];
    [handle lineToPoint:NSMakePoint(start.x + diameter * 0.5, start.y + down * diameter * 0.5)];
    [handle stroke];
}

+ (void)drawEjectGlyphInRect:(NSRect)rect color:(NSColor *)color {
    // The old eject mark: a triangle standing on a bar.
    NSRect r = NSInsetRect(rect, NSWidth(rect) * 0.26, NSHeight(rect) * 0.26);
    CGFloat barHeight = MAX(1.5, NSHeight(r) * 0.20);
    CGFloat gap = MAX(1.0, NSHeight(r) * 0.14);

    [color set];
    NSRectFill(NSMakeRect(NSMinX(r), NSMinY(r), NSWidth(r), barHeight));

    NSBezierPath *triangle = [NSBezierPath bezierPath];
    [triangle moveToPoint:NSMakePoint(NSMinX(r), NSMinY(r) + barHeight + gap)];
    [triangle lineToPoint:NSMakePoint(NSMaxX(r), NSMinY(r) + barHeight + gap)];
    [triangle lineToPoint:NSMakePoint(NSMidX(r), NSMaxY(r))];
    [triangle closePath];
    [triangle fill];
}

+ (void)drawShrinkGlyphInRect:(NSRect)rect color:(NSColor *)color {
    // Two arrows meeting in the middle, each with a solid head. Four thin
    // barbed arrows read as an X at this size, and the barbs vanish.
    //
    // The arrows run corner to corner of a square inside the button, and the
    // button is round: at an inset much under a sixth, those corners fall
    // outside the circle.
    NSRect r = NSInsetRect(rect, NSWidth(rect) * 0.25, NSHeight(rect) * 0.25);
    NSPoint centre = NSMakePoint(NSMidX(r), NSMidY(r));
    // Converging from the lower left and the upper right, the way collapse
    // marks are normally drawn.
    NSPoint corners[2] = { NSMakePoint(NSMinX(r), NSMaxY(r)),
                           NSMakePoint(NSMaxX(r), NSMinY(r)) };

    [color set];

    NSInteger i;
    for (i = 0; i < 2; i++) {
        NSPoint corner = corners[i];
        CGFloat dx = centre.x - corner.x;
        CGFloat dy = centre.y - corner.y;
        CGFloat length = hypot(dx, dy);
        if (length < 2.0) continue;
        dx /= length;
        dy /= length;

        // A thin shaft with a broad head, the two tips nearly meeting in the
        // middle. The head carries the meaning at this size, so it stays large
        // while the shaft stays quiet.
        CGFloat headLength = length * 0.52;
        CGFloat headHalf = length * 0.42;
        NSPoint tip = NSMakePoint(corner.x + dx * length * 0.88,
                                  corner.y + dy * length * 0.88);
        NSPoint base = NSMakePoint(tip.x - dx * headLength, tip.y - dy * headLength);
        NSPoint perpendicular = NSMakePoint(-dy, dx);

        NSBezierPath *shaft = [NSBezierPath bezierPath];
        [shaft setLineWidth:length * 0.16];
        [shaft setLineCapStyle:NSRoundLineCapStyle];
        [shaft moveToPoint:corner];
        [shaft lineToPoint:base];
        [shaft stroke];

        NSBezierPath *head = [NSBezierPath bezierPath];
        [head moveToPoint:tip];
        [head lineToPoint:NSMakePoint(base.x + perpendicular.x * headHalf,
                                      base.y + perpendicular.y * headHalf)];
        [head lineToPoint:NSMakePoint(base.x - perpendicular.x * headHalf,
                                      base.y - perpendicular.y * headHalf)];
        [head closePath];
        [head fill];
    }
}

+ (void)drawShuffleGlyphInRect:(NSRect)rect color:(NSColor *)color {
    // Two paths that cross, each ending in an arrowhead on the right. The
    // crossing is kept shallow: at full button height the curves read as a
    // tall X rather than a shuffle mark.
    NSRect r = NSInsetRect(rect, 3.0, 0.0);
    CGFloat height = 7.0;
    r = NSMakeRect(NSMinX(r), NSMidY(rect) - height / 2.0, NSWidth(r), height);
    if (NSWidth(r) < 6 || NSHeight(r) < 4) return;

    CGFloat headLength = 4.0;
    CGFloat yLow = NSMinY(r);
    CGFloat yHigh = NSMaxY(r);
    CGFloat xLeft = NSMinX(r);
    CGFloat xRight = NSMaxX(r) - headLength;
    CGFloat span = xRight - xLeft;

    NSBezierPath *strokes = [NSBezierPath bezierPath];
    [strokes setLineWidth:1.5];
    [strokes setLineCapStyle:NSRoundLineCapStyle];

    [strokes moveToPoint:NSMakePoint(xLeft, yLow)];
    [strokes curveToPoint:NSMakePoint(xRight, yHigh)
            controlPoint1:NSMakePoint(xLeft + span * 0.45, yLow)
            controlPoint2:NSMakePoint(xLeft + span * 0.55, yHigh)];

    [strokes moveToPoint:NSMakePoint(xLeft, yHigh)];
    [strokes curveToPoint:NSMakePoint(xRight, yLow)
            controlPoint1:NSMakePoint(xLeft + span * 0.45, yHigh)
            controlPoint2:NSMakePoint(xLeft + span * 0.55, yLow)];

    [color set];
    [strokes stroke];

    BTDrawArrowhead(NSMakePoint(NSMaxX(r), yHigh), headLength, 2.6, color);
    BTDrawArrowhead(NSMakePoint(NSMaxX(r), yLow), headLength, 2.6, color);
}

+ (void)drawRepeatGlyphInRect:(NSRect)rect one:(BOOL)one color:(NSColor *)color {
    // A stadium-shaped loop with an arrowhead riding the top edge. Kept low so
    // it sits at the same visual weight as the shuffle mark beside it.
    NSRect r = NSInsetRect(rect, 2.5, 0.0);
    CGFloat height = 7.0;
    r = NSMakeRect(NSMinX(r), NSMidY(rect) - height / 2.0 - 1.0, NSWidth(r), height);
    if (NSWidth(r) < 8 || NSHeight(r) < 4) return;

    CGFloat radius = NSHeight(r) / 2.0;
    NSBezierPath *loop = [NSBezierPath bezierPathWithRoundedRect:r xRadius:radius yRadius:radius];
    [loop setLineWidth:1.5];
    [color set];
    [loop stroke];

    BTDrawArrowhead(NSMakePoint(NSMaxX(r) - radius + 1.5, NSMaxY(r)), 4.5, 3.0, color);

    if (one) {
        NSDictionary *attrs = @{NSFontAttributeName: BTFontNamed(@"Lucida Grande Bold", 9.0, YES),
                                NSForegroundColorAttributeName: color};
        NSSize size = [@"1" sizeWithAttributes:attrs];
        [@"1" drawAtPoint:NSMakePoint(NSMidX(rect) - size.width / 2, NSMidY(rect) - size.height / 2)
           withAttributes:attrs];
    }
}

#pragma mark - Time

+ (NSString *)timeStringFromInterval:(NSTimeInterval)interval {
    if (interval < 0) interval = 0;
    NSInteger total = (NSInteger)interval;
    NSInteger hours = total / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger seconds = total % 60;
    if (hours > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];
}

+ (NSString *)longTimeStringFromInterval:(NSTimeInterval)interval {
    NSInteger total = (NSInteger)interval;
    NSInteger days = total / 86400;
    NSInteger hours = (total % 86400) / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger seconds = total % 60;

    if (days > 0) {
        return [NSString stringWithFormat:@"%ld days %ld hours", (long)days, (long)hours];
    }
    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];
}

@end
