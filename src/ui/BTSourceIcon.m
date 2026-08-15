#import "BTSourceIcon.h"
#import "BTStyle.h"

// A row's mark is sixteen points square, and every coordinate below is written
// inside that square.
#define BT_SOURCE_ICON_SIDE 16.0

// A colour washed out until it can sit behind ink, and the same colour taken
// down until it can be ink. One mark is built from all three weights, so a
// playlist and a smart playlist differ in hue and in nothing else.
static NSColor *BTPaleTint(NSColor *colour) {
    return [colour blendedColorWithFraction:0.82 ofColor:[NSColor whiteColor]];
}

static NSColor *BTDeepTint(NSColor *colour) {
    return [colour blendedColorWithFraction:0.40 ofColor:[NSColor blackColor]];
}

// A quaver, written in a nine by twelve box and fitted to whatever rect it is
// given: head at the bottom left, stem up the right of it, flag off the top.
//
// Filled as three shapes rather than one. A head, a stem and a flag that
// overlap can cancel one another out inside a single path, since which way
// round each subpath was built decides whether the overlap counts twice or not
// at all.
static void BTDrawNoteInRect(NSRect box) {
    CGFloat scale = MIN(NSWidth(box) / 9.0, NSHeight(box) / 12.0);
    NSAffineTransform *place = [NSAffineTransform transform];
    [place translateXBy:NSMinX(box) + (NSWidth(box) - 9.0 * scale) / 2.0
                    yBy:NSMinY(box) + (NSHeight(box) - 12.0 * scale) / 2.0];
    [place scaleBy:scale];

    // Tilted, the way a notehead is written. Upright it reads as a full stop
    // with a line beside it.
    NSAffineTransform *tilt = [NSAffineTransform transform];
    [tilt translateXBy:2.9 yBy:2.0];
    [tilt rotateByDegrees:-20.0];
    [tilt translateXBy:-2.9 yBy:-2.0];
    NSBezierPath *head = [tilt transformBezierPath:
        [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.0, 0.0, 5.8, 4.0)]];

    NSBezierPath *stem = [NSBezierPath bezierPathWithRect:NSMakeRect(4.4, 2.4, 1.4, 9.6)];

    NSBezierPath *flag = [NSBezierPath bezierPath];
    [flag moveToPoint:NSMakePoint(5.8, 12.0)];
    [flag curveToPoint:NSMakePoint(8.8, 6.4)
         controlPoint1:NSMakePoint(8.6, 11.3)
         controlPoint2:NSMakePoint(9.2, 8.6)];
    [flag curveToPoint:NSMakePoint(5.8, 9.2)
         controlPoint1:NSMakePoint(8.2, 8.8)
         controlPoint2:NSMakePoint(7.2, 9.2)];
    [flag closePath];

    [[place transformBezierPath:head] fill];
    [[place transformBezierPath:stem] fill];
    [[place transformBezierPath:flag] fill];
}

static NSPoint BTPolar(NSPoint centre, CGFloat radius, CGFloat angle) {
    return NSMakePoint(centre.x + radius * cos(angle), centre.y + radius * sin(angle));
}

// A cogwheel: eight square teeth and a hole through the middle. The hole is cut
// by the even-odd rule rather than by drawing the hub the other way round, so it
// is a hole whichever way the oval happens to be built.
static NSBezierPath *BTGearPath(NSPoint centre, CGFloat radius) {
    const NSInteger teeth = 8;
    CGFloat step = 2.0 * M_PI / teeth;
    CGFloat root = radius * 0.68;

    NSBezierPath *gear = [NSBezierPath bezierPath];
    NSInteger i;
    for (i = 0; i < teeth; i++) {
        CGFloat a = i * step;
        NSPoint tipStart  = BTPolar(centre, radius, a - 0.30 * step);
        NSPoint tipEnd    = BTPolar(centre, radius, a + 0.30 * step);
        NSPoint rootStart = BTPolar(centre, root,   a + 0.42 * step);
        NSPoint rootEnd   = BTPolar(centre, root,   a + 0.58 * step);
        if (i == 0) {
            [gear moveToPoint:tipStart];
        } else {
            [gear lineToPoint:tipStart];
        }
        [gear lineToPoint:tipEnd];
        [gear lineToPoint:rootStart];
        [gear lineToPoint:rootEnd];
    }
    [gear closePath];

    CGFloat hub = radius * 0.32;
    [gear appendBezierPathWithOvalInRect:NSMakeRect(centre.x - hub, centre.y - hub, hub * 2, hub * 2)];
    [gear setWindingRule:NSEvenOddWindingRule];
    return gear;
}

// A sheet with its top right corner cut away, which is what says page at a size
// too small for a fold.
static NSBezierPath *BTPagePath(void) {
    NSBezierPath *page = [NSBezierPath bezierPath];
    [page moveToPoint:NSMakePoint(1.5, 0.5)];
    [page lineToPoint:NSMakePoint(14.5, 0.5)];
    [page lineToPoint:NSMakePoint(14.5, 12.0)];
    [page lineToPoint:NSMakePoint(11.0, 15.5)];
    [page lineToPoint:NSMakePoint(1.5, 15.5)];
    [page closePath];
    return page;
}

@implementation BTSourceIcon

+ (CGFloat)side { return BT_SOURCE_ICON_SIDE; }

// A little white slab with a wheel on it.
+ (void)drawIPod {
    // Nine by fifteen rather than eight: the device is about three fifths as
    // wide as it is tall, and a point narrower than that reads as a remote
    // control. The screen and the wheel keep the size they had and stay on the
    // middle, so the extra point becomes margin either side of them.
    NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(3.5, 0.5, 9, 15)
                                                         xRadius:1.7
                                                         yRadius:1.7];
    [[NSColor colorWithCalibratedWhite:0.97 alpha:1.0] set];
    [body fill];
    [[NSColor colorWithCalibratedWhite:0.40 alpha:1.0] set];
    [body stroke];

    [[NSColor colorWithCalibratedWhite:0.65 alpha:1.0] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.7, 2.2, 4.6, 4.6)] fill];
    [[NSColor colorWithCalibratedRed:0.62 green:0.76 blue:0.93 alpha:1.0] set];
    NSRectFill(NSMakeRect(5.7, 8.6, 4.6, 4.6));
}

// A disc seen face on: the silver ring, the clear centre, and the hole.
+ (void)drawDisc {
    NSBezierPath *edge = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 15, 15)];
    [[NSColor colorWithCalibratedWhite:0.86 alpha:1.0] set];
    [edge fill];
    [[NSColor colorWithCalibratedWhite:0.45 alpha:1.0] set];
    [edge stroke];

    // A sheen across it, which is what says silver rather than white.
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.9] set];
    NSBezierPath *sheen = [NSBezierPath bezierPath];
    [sheen moveToPoint:NSMakePoint(3.4, 13.3)];
    [sheen lineToPoint:NSMakePoint(7.3, 14.8)];
    [sheen lineToPoint:NSMakePoint(11.9, 6.9)];
    [sheen lineToPoint:NSMakePoint(9.2, 4.9)];
    [sheen closePath];
    [sheen fill];

    [[BTStyle sourceIcon] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.7, 5.7, 4.6, 4.6)] fill];
    [[NSColor whiteColor] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(7.1, 7.1, 1.8, 1.8)] fill];
}

// The green quaver pair from the iTunes 4 icon, standing on the disc it was
// drawn over. Two heads joined by a beam rather than the one flagged note the
// library and the playlists wear, because that pair is the shape being quoted
// and it is what tells this row from those at a glance.
//
// The disc is a plain circle rather than the tilted, rainbowed one in the
// original. An ellipse seen at an angle loses its roundness at sixteen points
// and reads as a smudge under the note; a circle still reads as a disc.
+ (void)drawITunes {
    NSColor *green = [NSColor colorWithCalibratedRed:0.408 green:0.690 blue:0.314 alpha:1.0];
    NSColor *deep  = [NSColor colorWithCalibratedRed:0.180 green:0.360 blue:0.140 alpha:1.0];
    NSColor *lit   = [NSColor colorWithCalibratedRed:0.549 green:0.831 blue:0.416 alpha:1.0];

    NSBezierPath *disc = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.8, 12.0, 12.0)];
    [[NSColor colorWithCalibratedWhite:0.86 alpha:1.0] set];
    [disc fill];
    [[NSColor colorWithCalibratedWhite:0.45 alpha:1.0] set];
    [disc stroke];

    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.9] set];
    NSBezierPath *sheen = [NSBezierPath bezierPath];
    [sheen moveToPoint:NSMakePoint(2.6, 10.4)];
    [sheen lineToPoint:NSMakePoint(5.6, 11.7)];
    [sheen lineToPoint:NSMakePoint(8.0, 5.2)];
    [sheen lineToPoint:NSMakePoint(5.6, 3.9)];
    [sheen closePath];
    [sheen fill];

    [[NSColor colorWithCalibratedWhite:0.62 alpha:1.0] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(4.6, 4.9, 3.8, 3.8)] fill];
    [[NSColor whiteColor] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.9, 6.2, 1.2, 1.2)] fill];

    // Each head is tilted about its own middle, the way a notehead is written.
    NSRect headRects[2] = { NSMakeRect(3.6, 2.4, 4.7, 3.5), NSMakeRect(8.4, 3.8, 4.7, 3.5) };
    NSBezierPath *heads[2];
    NSUInteger i;
    for (i = 0; i < 2; i++) {
        NSRect r = headRects[i];
        NSAffineTransform *tilt = [NSAffineTransform transform];
        [tilt translateXBy:NSMidX(r) yBy:NSMidY(r)];
        [tilt rotateByDegrees:-20.0];
        [tilt translateXBy:-NSMidX(r) yBy:-NSMidY(r)];
        heads[i] = [tilt transformBezierPath:[NSBezierPath bezierPathWithOvalInRect:r]];
    }

    NSBezierPath *stemA = [NSBezierPath bezierPathWithRect:NSMakeRect(7.0, 4.1, 1.3, 7.2)];
    NSBezierPath *stemB = [NSBezierPath bezierPathWithRect:NSMakeRect(11.8, 5.5, 1.3, 7.2)];

    NSBezierPath *beam = [NSBezierPath bezierPath];
    [beam moveToPoint:NSMakePoint(7.0, 10.4)];
    [beam lineToPoint:NSMakePoint(13.1, 12.2)];
    [beam lineToPoint:NSMakePoint(13.1, 14.2)];
    [beam lineToPoint:NSMakePoint(7.0, 12.4)];
    [beam closePath];

    // Filled one at a time. Overlapping subpaths inside a single path cancel
    // where they cross, depending on which way round each was built.
    NSBezierPath *parts[5] = { heads[0], heads[1], stemA, stemB, beam };
    for (i = 0; i < 5; i++) {
        [green set];
        [parts[i] fill];
        [deep set];
        [parts[i] setLineWidth:0.6];
        [parts[i] stroke];
    }

    // A lit edge along the top of the beam, which is where the light falls in
    // the icon this quotes.
    [lit set];
    NSBezierPath *shine = [NSBezierPath bezierPath];
    [shine moveToPoint:NSMakePoint(7.4, 12.5)];
    [shine lineToPoint:NSMakePoint(12.8, 14.1)];
    [shine setLineWidth:0.7];
    [shine stroke];
}

// A clock face, since the list is about when rather than what.
+ (void)drawRecentlyAdded {
    NSBezierPath *face = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 15, 15)];
    [[BTStyle sourceIcon] set];
    [face fill];
    [[NSColor whiteColor] set];
    NSBezierPath *hands = [NSBezierPath bezierPath];
    [hands setLineWidth:1.6];
    [hands moveToPoint:NSMakePoint(8, 8)];
    [hands lineToPoint:NSMakePoint(8, 12.0)];      // to the hour
    [hands moveToPoint:NSMakePoint(8, 8)];
    [hands lineToPoint:NSMakePoint(11.2, 8)];      // and past it
    [hands stroke];
}

// A stack of ruled cards with a note on the front one: every song there is,
// rather than a page of them. Gold whatever else the window is doing, because
// this is the row the list is read down from and it should look like itself in
// either palette.
+ (void)drawLibrary {
    NSColor *edge = [NSColor colorWithCalibratedRed:0.42 green:0.31 blue:0.08 alpha:1.0];
    NSColor *behind = [NSColor colorWithCalibratedRed:0.72 green:0.60 blue:0.24 alpha:1.0];

    NSRect back = NSMakeRect(0.5, 4.5, 11, 11);
    NSRect middle = NSMakeRect(2.5, 2.5, 11, 11);
    NSRect front = NSMakeRect(4.5, 0.5, 11, 11);

    NSUInteger i;
    NSRect behindRects[2] = { back, middle };
    for (i = 0; i < 2; i++) {
        NSBezierPath *card = [NSBezierPath bezierPathWithRect:behindRects[i]];
        [behind set];
        [card fill];
        [edge set];
        [card stroke];
    }

    NSBezierPath *card = [NSBezierPath bezierPathWithRect:front];
    [[NSColor colorWithCalibratedRed:0.94 green:0.86 blue:0.59 alpha:1.0] set];
    [card fill];

    // Ruled the way a sheet of music is ruled. Clipped to the card, so the lines
    // stop at its edge rather than being cut to length by hand.
    [NSGraphicsContext saveGraphicsState];
    [card addClip];
    [[NSColor colorWithCalibratedRed:0.78 green:0.65 blue:0.30 alpha:1.0] set];
    CGFloat y;
    for (y = NSMinY(front) + 1.5; y < NSMaxY(front); y += 2.0) {
        NSRectFill(NSMakeRect(NSMinX(front), y, NSWidth(front), 1.0));
    }
    [NSGraphicsContext restoreGraphicsState];

    [edge set];
    [card stroke];

    [[NSColor colorWithCalibratedRed:0.16 green:0.10 blue:0.02 alpha:1.0] set];
    BTDrawNoteInRect(NSMakeRect(5.6, 1.3, 9.4, 9.4));
}

+ (void)drawFolder {
    NSBezierPath *folder = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0.5, 2.0, 15, 11)
                                                           xRadius:1.7
                                                           yRadius:1.7];
    [[NSColor colorWithCalibratedRed:0.63 green:0.70 blue:0.80 alpha:1.0] set];
    [folder fill];
    [[NSColor colorWithCalibratedWhite:0.35 alpha:1.0] set];
    [folder stroke];
    NSRectFill(NSMakeRect(1.5, 12.5, 6, 1.5));
}

// A page with a mark on it. A list built by hand carries a note, one built from
// rules carries a cogwheel, and the two are drawn in different hues as well, so
// which is which survives being read at a glance and being read in either
// palette.
+ (void)drawPlaylistSmart:(BOOL)smart {
    NSColor *colour = smart ? [BTStyle smartPlaylistIcon] : [BTStyle sourceIcon];
    NSBezierPath *page = BTPagePath();
    [BTPaleTint(colour) set];
    [page fill];
    [colour set];
    [page stroke];

    [BTDeepTint(colour) set];
    if (smart) {
        [BTGearPath(NSMakePoint(8.0, 7.6), 4.9) fill];
    } else {
        BTDrawNoteInRect(NSMakeRect(3.0, 2.0, 10.0, 11.5));
    }
}

+ (NSImage *)iconOfKind:(BTSourceIconKind)kind {
    NSImage *image = [[NSImage alloc]
        initWithSize:NSMakeSize(BT_SOURCE_ICON_SIDE, BT_SOURCE_ICON_SIDE)];
    [image lockFocus];
    switch (kind) {
        case BTSourceIconIPod:           [self drawIPod];             break;
        case BTSourceIconDisc:           [self drawDisc];             break;
        case BTSourceIconITunes:         [self drawITunes];           break;
        case BTSourceIconRecentlyAdded:  [self drawRecentlyAdded];    break;
        case BTSourceIconLibrary:        [self drawLibrary];          break;
        case BTSourceIconFolder:         [self drawFolder];           break;
        case BTSourceIconSmartPlaylist:  [self drawPlaylistSmart:YES]; break;
        case BTSourceIconPlaylist:       [self drawPlaylistSmart:NO];  break;
    }
    [image unlockFocus];
    return image;
}

@end
