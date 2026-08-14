#import "BTSourceIcon.h"
#import "BTStyle.h"

// A row's mark is fourteen points square, and every coordinate below is written
// inside that square.
#define BT_SOURCE_ICON_SIDE 14.0

@implementation BTSourceIcon

// A little white slab with a wheel on it.
+ (void)drawIPod {
    NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(3.5, 0.5, 7, 13)
                                                         xRadius:1.5
                                                         yRadius:1.5];
    [[NSColor colorWithCalibratedWhite:0.97 alpha:1.0] set];
    [body fill];
    [[NSColor colorWithCalibratedWhite:0.40 alpha:1.0] set];
    [body stroke];

    [[NSColor colorWithCalibratedWhite:0.65 alpha:1.0] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5, 2, 4, 4)] fill];
    [[NSColor colorWithCalibratedRed:0.62 green:0.76 blue:0.93 alpha:1.0] set];
    NSRectFill(NSMakeRect(5, 7.5, 4, 4));
}

// A disc seen face on: the silver ring, the clear centre, and the hole.
+ (void)drawDisc {
    NSBezierPath *edge = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 13, 13)];
    [[NSColor colorWithCalibratedWhite:0.86 alpha:1.0] set];
    [edge fill];
    [[NSColor colorWithCalibratedWhite:0.45 alpha:1.0] set];
    [edge stroke];

    // A sheen across it, which is what says silver rather than white.
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.9] set];
    NSBezierPath *sheen = [NSBezierPath bezierPath];
    [sheen moveToPoint:NSMakePoint(3.0, 11.6)];
    [sheen lineToPoint:NSMakePoint(6.4, 12.9)];
    [sheen lineToPoint:NSMakePoint(10.4, 6.0)];
    [sheen lineToPoint:NSMakePoint(8.0, 4.4)];
    [sheen closePath];
    [sheen fill];

    [[BTStyle sourceIcon] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.0, 5.0, 4, 4)] fill];
    [[NSColor whiteColor] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(6.2, 6.2, 1.6, 1.6)] fill];
}

// A clock face, since the list is about when rather than what.
+ (void)drawRecentlyAdded {
    NSBezierPath *face = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 13, 13)];
    [[BTStyle sourceIcon] set];
    [face fill];
    [[NSColor whiteColor] set];
    NSBezierPath *hands = [NSBezierPath bezierPath];
    [hands setLineWidth:1.4];
    [hands moveToPoint:NSMakePoint(7, 7)];
    [hands lineToPoint:NSMakePoint(7, 10.5)];      // to the hour
    [hands moveToPoint:NSMakePoint(7, 7)];
    [hands lineToPoint:NSMakePoint(9.8, 7)];       // and past it
    [hands stroke];
}

// A note on a filled circle: the whole library.
+ (void)drawLibrary {
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 13, 13)];
    [[BTStyle sourceIcon] set];
    [circle fill];
    [[NSColor whiteColor] set];
    NSRectFill(NSMakeRect(8, 5, 1.6, 6));
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.4, 3.4, 4, 3.2)] fill];
}

+ (void)drawFolder {
    NSBezierPath *folder = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0.5, 2.5, 13, 9)
                                                           xRadius:1.5
                                                           yRadius:1.5];
    [[NSColor colorWithCalibratedRed:0.63 green:0.70 blue:0.80 alpha:1.0] set];
    [folder fill];
    [[NSColor colorWithCalibratedWhite:0.35 alpha:1.0] set];
    [folder stroke];
    NSRectFill(NSMakeRect(1.5, 11, 5, 1.5));
}

// A note on a page. One built from rules carries a mark in its corner and is
// drawn in its own colour, so the two are told apart twice over.
+ (void)drawPlaylistSmart:(BOOL)smart {
    NSBezierPath *page = [NSBezierPath bezierPathWithRect:NSMakeRect(1.5, 1.5, 11, 11)];
    [[NSColor whiteColor] set];
    [page fill];
    [[NSColor colorWithCalibratedWhite:0.45 alpha:1.0] set];
    [page stroke];

    [(smart ? [BTStyle smartPlaylistIcon] : [BTStyle sourceIcon]) set];
    NSRectFill(NSMakeRect(8, 5, 1.4, 5));
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.6, 3.6, 3.6, 2.8)] fill];
    if (smart) NSRectFill(NSMakeRect(3, 10, 2, 2));
}

+ (NSImage *)iconOfKind:(BTSourceIconKind)kind {
    NSImage *image = [[NSImage alloc]
        initWithSize:NSMakeSize(BT_SOURCE_ICON_SIDE, BT_SOURCE_ICON_SIDE)];
    [image lockFocus];
    switch (kind) {
        case BTSourceIconIPod:           [self drawIPod];             break;
        case BTSourceIconDisc:           [self drawDisc];             break;
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
