#import "BTDisplayView.h"
#import "BTStyle.h"
#import "BTPlayer.h"
#import "BTTrack.h"
#import "BTIPodSync.h"

@implementation BTDisplayView {
    BOOL _showRemaining;
    BOOL _scrubbing;
    BOOL _syncing;
    double _syncFraction;
    NSString *_syncMessage;
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _showRemaining = YES;
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(refresh) name:BTPlayerDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(refresh) name:BTPlayerTimeDidChangeNotification object:nil];
        [nc addObserver:self selector:@selector(syncProgress:) name:BTIPodSyncProgressNotification object:nil];
        [nc addObserver:self selector:@selector(syncFinished:) name:BTIPodSyncDidFinishNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)refresh {
    [self setNeedsDisplay:YES];
}

#pragma mark - Sync progress

// While a sync runs the readout shows it instead of the song, since the whole
// window is about the iPod at that point.
- (void)syncProgress:(NSNotification *)note {
    _syncing = YES;
    _syncFraction = [[[note userInfo] objectForKey:@"fraction"] doubleValue];
    _syncMessage = [[note userInfo] objectForKey:@"message"];
    [self setNeedsDisplay:YES];
}

- (void)syncFinished:(NSNotification *)note {
    _syncing = NO;
    _syncMessage = nil;
    [self setNeedsDisplay:YES];
}

- (void)drawSyncInRect:(NSRect)bounds {
    NSMutableParagraphStyle *centered = [[NSMutableParagraphStyle alloc] init];
    [centered setAlignment:NSCenterTextAlignment];
    [centered setLineBreakMode:NSLineBreakByTruncatingMiddle];

    NSDictionary *attrs = @{NSFontAttributeName: [BTStyle displayBoldFont],
                            NSForegroundColorAttributeName: [BTStyle displayText],
                            NSParagraphStyleAttributeName: centered};
    [@"Syncing iPod" drawInRect:NSMakeRect(NSMinX(bounds) + 6, NSMaxY(bounds) - 15, NSWidth(bounds) - 12, 12)
                 withAttributes:attrs];

    if ([_syncMessage length] > 0) {
        NSDictionary *lineAttrs = @{NSFontAttributeName: [BTStyle displayFont],
                                    NSForegroundColorAttributeName: [BTStyle displayText],
                                    NSParagraphStyleAttributeName: centered};
        [_syncMessage drawInRect:NSMakeRect(NSMinX(bounds) + 6, NSMaxY(bounds) - 27, NSWidth(bounds) - 12, 12)
                  withAttributes:lineAttrs];
    }

    NSRect groove = [self progressRect];
    NSBezierPath *groovePath = [NSBezierPath bezierPathWithRoundedRect:groove xRadius:3 yRadius:3];
    [[NSColor colorWithCalibratedWhite:0.78 alpha:1.0] set];
    [groovePath fill];
    [[NSColor colorWithCalibratedWhite:0.52 alpha:1.0] set];
    [groovePath stroke];

    NSRect filled = groove;
    filled.size.width = NSWidth(groove) * MAX(0.0, MIN(1.0, _syncFraction));
    [[NSColor colorWithCalibratedRed:0.36 green:0.55 blue:0.86 alpha:1.0] set];
    [[NSBezierPath bezierPathWithRoundedRect:filled xRadius:3 yRadius:3] fill];
}

// The panel is three bands: title, artist and album, then the times with the
// scrub bar between them. Keep them from meeting.
#define BT_DISPLAY_TITLE_HEIGHT  12.0
#define BT_DISPLAY_FOOT_HEIGHT   14.0

- (NSRect)progressRect {
    // Inset past the rounded ends so the groove does not run into them.
    NSRect b = [self bounds];
    return NSMakeRect(NSMinX(b) + 56, NSMinY(b) + 6, NSWidth(b) - 112, 6);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    // Deeply rounded ends, the way the readout was drawn in 2003.
    [BTStyle drawSunkenBezelInRect:bounds
                            radius:(NSHeight(bounds) * 0.40)
                              fill:[BTStyle displayBackground]];

    if (_syncing) {
        [self drawSyncInRect:bounds];
        return;
    }

    BTPlayer *player = [BTPlayer sharedPlayer];
    BTTrack *track = [player currentTrack];

    NSMutableParagraphStyle *centered = [[NSMutableParagraphStyle alloc] init];
    [centered setAlignment:NSCenterTextAlignment];
    [centered setLineBreakMode:NSLineBreakByTruncatingTail];

    NSDictionary *titleAttrs = @{NSFontAttributeName: [BTStyle displayBoldFont],
                                 NSForegroundColorAttributeName: [BTStyle displayText],
                                 NSParagraphStyleAttributeName: centered};
    NSDictionary *lineAttrs = @{NSFontAttributeName: [BTStyle displayFont],
                                NSForegroundColorAttributeName: [BTStyle displayText],
                                NSParagraphStyleAttributeName: centered};

    if (track == nil) {
        NSRect r = NSMakeRect(NSMinX(bounds), NSMidY(bounds) - 7, NSWidth(bounds), 14);
        [@"BTunes" drawInRect:r withAttributes:titleAttrs];
        return;
    }

    NSRect titleRect = NSMakeRect(NSMinX(bounds) + 6,
                                  NSMaxY(bounds) - BT_DISPLAY_TITLE_HEIGHT - 3,
                                  NSWidth(bounds) - 12,
                                  BT_DISPLAY_TITLE_HEIGHT);
    [[track displayTitle] drawInRect:titleRect withAttributes:titleAttrs];

    NSString *second = [NSString stringWithFormat:@"%@ - %@", [track displayArtist], [track displayAlbum]];
    NSRect secondRect = NSMakeRect(NSMinX(bounds) + 6,
                                   NSMinY(titleRect) - BT_DISPLAY_TITLE_HEIGHT,
                                   NSWidth(bounds) - 12,
                                   BT_DISPLAY_TITLE_HEIGHT);
    [second drawInRect:secondRect withAttributes:lineAttrs];

    NSTimeInterval elapsed = [player currentTime];
    NSTimeInterval duration = [player duration];

    NSMutableParagraphStyle *left = [[NSMutableParagraphStyle alloc] init];
    [left setAlignment:NSLeftTextAlignment];
    NSMutableParagraphStyle *right = [[NSMutableParagraphStyle alloc] init];
    [right setAlignment:NSRightTextAlignment];

    NSDictionary *timeLeftAttrs = @{NSFontAttributeName: [BTStyle smallFont],
                                    NSForegroundColorAttributeName: [BTStyle displayText],
                                    NSParagraphStyleAttributeName: left};
    NSDictionary *timeRightAttrs = @{NSFontAttributeName: [BTStyle smallFont],
                                     NSForegroundColorAttributeName: [BTStyle displayText],
                                     NSParagraphStyleAttributeName: right};

    // Both readouts center on the scrub bar rather than sitting on the floor of
    // the panel. Measuring the drawn text is the only way to line them up: a
    // fixed rect leaves the glyphs wherever the font's metrics put them.
    NSRect groove = [self progressRect];
    NSString *leading = [BTStyle timeStringFromInterval:elapsed];
    NSString *trailing = _showRemaining
        ? [NSString stringWithFormat:@"-%@", [BTStyle timeStringFromInterval:(duration - elapsed)]]
        : [BTStyle timeStringFromInterval:duration];

    CGFloat textHeight = [leading sizeWithAttributes:timeLeftAttrs].height;
    CGFloat textY = NSMidY(groove) - textHeight / 2.0;

    // Held in against the scrub bar rather than out against the rounded ends.
    [leading drawInRect:NSMakeRect(NSMinX(bounds) + 14, textY, 36, textHeight)
         withAttributes:timeLeftAttrs];
    [trailing drawInRect:NSMakeRect(NSMaxX(bounds) - 50, textY, 36, textHeight)
          withAttributes:timeRightAttrs];

    // Progress groove and knob.
    NSBezierPath *groovePath = [NSBezierPath bezierPathWithRoundedRect:groove xRadius:3 yRadius:3];
    [[NSColor colorWithCalibratedWhite:0.78 alpha:1.0] set];
    [groovePath fill];
    [[NSColor colorWithCalibratedWhite:0.52 alpha:1.0] set];
    [groovePath setLineWidth:1.0];
    [groovePath stroke];

    if (duration > 0) {
        CGFloat fraction = (CGFloat)(elapsed / duration);
        if (fraction < 0) fraction = 0;
        if (fraction > 1) fraction = 1;
        NSRect filled = groove;
        filled.size.width = NSWidth(groove) * fraction;
        NSBezierPath *filledPath = [NSBezierPath bezierPathWithRoundedRect:filled xRadius:3 yRadius:3];
        [[NSColor colorWithCalibratedRed:0.36 green:0.55 blue:0.86 alpha:1.0] set];
        [filledPath fill];

        // A round knob centred on the groove, rather than a tall oval whose
        // weight sits above the line it runs along.
        CGFloat side = 11.0;
        NSRect knob = NSMakeRect(NSMinX(groove) + NSWidth(groove) * fraction - side / 2.0,
                                 NSMidY(groove) - side / 2.0,
                                 side, side);
        [BTStyle drawAquaCircleInRect:knob pressed:NO enabled:YES];
    }
}

#pragma mark - Scrubbing

- (void)seekToPoint:(NSPoint)point {
    BTPlayer *player = [BTPlayer sharedPlayer];
    if ([player duration] <= 0) return;
    NSRect groove = [self progressRect];
    CGFloat fraction = (point.x - NSMinX(groove)) / NSWidth(groove);
    if (fraction < 0) fraction = 0;
    if (fraction > 1) fraction = 1;
    [player seekToTime:[player duration] * fraction];
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSRect groove = NSInsetRect([self progressRect], -4, -6);

    if (NSPointInRect(point, groove)) {
        _scrubbing = YES;
        [self seekToPoint:point];
        return;
    }
    if (point.x > NSMaxX([self bounds]) - 52 && point.y < NSMinY([self bounds]) + 16) {
        _showRemaining = !_showRemaining;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_scrubbing) return;
    [self seekToPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
}

- (void)mouseUp:(NSEvent *)event {
    _scrubbing = NO;
}

@end
