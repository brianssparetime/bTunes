#import "BTDisplayView.h"
#import "BTStyle.h"
#import "BTPlayer.h"
#import "BTTrack.h"
#import "BTIPodSync.h"

// The panel is three bands: the title, the artist and album, then the times with
// the scrub bar between them. Keeping them from meeting is the whole of the
// arithmetic here, and all three follow the size of the type, so none of them is
// a number written down.
#define BT_DISPLAY_LINE  ([BTStyle displayLineHeight])   // one band of words
#define BT_DISPLAY_TOP   3.0                             // above the first band
#define BT_DISPLAY_FOOT  15.0                            // the scrub bar and the times


// A line too long for the panel sits still for a while, travels far enough to
// show its tail, rests, and comes back. The wait matters: a line that starts
// moving immediately is unreadable at the moment you most want to read it.
#define BT_MARQUEE_WAIT   5.0
#define BT_MARQUEE_SPEED 26.0   // points per second
#define BT_MARQUEE_REST   2.0

NSString *const BTDisplayProgressNotification = @"BTDisplayProgress";
NSString *const BTDisplayProgressDidEndNotification = @"BTDisplayProgressDidEnd";

// How long a notice stands before the readout goes back to the song. Long
// enough to read a short line twice, short enough not to sit in the way.
#define BT_NOTICE_SECONDS 5.0

@implementation BTDisplayView {
    BOOL _showRemaining;
    BOOL _scrubbing;
    BOOL _syncing;
    // Something the player could not do, shown in place of the song for a
    // moment. Nothing else in the window is anywhere for the player to say
    // this, and an alert for a locked song would be worse than the silence it
    // replaces.
    NSString *_notice;
    double _syncFraction;
    NSString *_syncMessage;
    NSString *_syncTitle;
    NSDate *_lineShownAt;
    NSString *_lineTrackID;

    // What the readout last put on screen. Everything on it is a song, a clock
    // counting in whole seconds, or a knob that moves a point at a time, so
    // comparing against these answers whether the tick has brought anything
    // worth drawing.
    NSString *_drawnTrackID;
    NSString *_drawnLeading;
    NSString *_drawnTrailing;
    CGFloat _drawnKnob;

    // Whether either line is too long for the panel, measured when the words or
    // the panel change rather than twenty times a second.
    NSString *_measuredTitle;
    NSString *_measuredSecond;
    CGFloat _measuredWidth;
    BOOL _linesTravel;
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
        [nc addObserver:self selector:@selector(progress:) name:BTDisplayProgressNotification object:nil];
        [nc addObserver:self selector:@selector(syncFinished:) name:BTDisplayProgressDidEndNotification object:nil];
        [nc addObserver:self selector:@selector(couldNotPlay:) name:BTPlayerCouldNotPlayNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// The player's tick calls this twenty times a second and the readout has
// something new about once, so it asks before repainting. Redrawing regardless
// meant laying out four lines of type, two rounded paths and a gradient knob
// twenty times over to put the same picture back.
- (void)refresh {
    if ([self hasSomethingNewToDraw]) [self setNeedsDisplay:YES];
}

// A line too long for the panel travels on every tick, and that is the one case
// where each frame really is a new picture.
- (BOOL)linesTravel {
    BTTrack *track = [[BTPlayer sharedPlayer] currentTrack];
    if (track == nil) return NO;

    NSString *title = [track displayTitle];
    NSString *second = [NSString stringWithFormat:@"%@ - %@",
                        [track displayArtist], [track displayAlbum]];
    CGFloat room = NSWidth([self bounds]) - 12;
    if (room == _measuredWidth && BTSameString(title, _measuredTitle)
        && BTSameString(second, _measuredSecond)) {
        return _linesTravel;
    }

    _measuredTitle = title;
    _measuredSecond = second;
    _measuredWidth = room;
    _linesTravel =
        [title sizeWithAttributes:@{NSFontAttributeName: [BTStyle displayBoldFont]}].width > room
        || [second sizeWithAttributes:@{NSFontAttributeName: [BTStyle displayFont]}].width > room;
    return _linesTravel;
}

// Where the elapsed part of the groove ends, to the point. The knob rides on
// the same number, so one comparison covers both.
//
// The clock is asked for once and handed down. Asking the player the time is
// not free, and a check meant to save work should not cost four of them.
- (CGFloat)knobFor:(NSTimeInterval)elapsed of:(NSTimeInterval)duration {
    if (duration <= 0) return 0.0;
    CGFloat fraction = (CGFloat)(elapsed / duration);
    if (fraction < 0) fraction = 0;
    if (fraction > 1) fraction = 1;
    return floor(NSWidth([self progressRect]) * fraction);
}

- (NSString *)trailingFor:(NSTimeInterval)elapsed of:(NSTimeInterval)duration {
    if (!_showRemaining) return [BTStyle timeStringFromInterval:duration];
    return [NSString stringWithFormat:@"-%@",
            [BTStyle timeStringFromInterval:(duration - elapsed)]];
}

- (BOOL)hasSomethingNewToDraw {
    // The sync bar and a notice are put up and taken down by their own
    // handlers, which mark the view themselves. The tick has nothing to add.
    if (_syncing || [_notice length] > 0) return NO;

    BTPlayer *player = [BTPlayer sharedPlayer];
    BTTrack *track = [player currentTrack];
    if (track == nil) return _drawnTrackID != nil;
    if (!BTSameString(track.trackID, _drawnTrackID)) return YES;
    if ([self linesTravel]) return YES;

    NSTimeInterval elapsed = [player currentTime];
    NSTimeInterval duration = [player duration];
    return !BTSameString([BTStyle timeStringFromInterval:elapsed], _drawnLeading)
        || !BTSameString([self trailingFor:elapsed of:duration], _drawnTrailing)
        || [self knobFor:elapsed of:duration] != _drawnKnob;
}

- (void)couldNotPlay:(NSNotification *)note {
    _notice = [[note userInfo] objectForKey:@"reason"];
    [self setNeedsDisplay:YES];

    // Cleared on a timer of its own, because with nothing playing there is no
    // tick to come round and take it away.
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(clearNotice)
                                               object:nil];
    [self performSelector:@selector(clearNotice) withObject:nil afterDelay:BT_NOTICE_SECONDS];
}

- (void)clearNotice {
    _notice = nil;
    [self setNeedsDisplay:YES];
}

// Two lines, centred, in place of the song. The same shape the readout uses
// while something slow is running, so it reads as the panel speaking rather
// than as a song with a strange name.
- (void)drawNoticeInRect:(NSRect)bounds {
    NSMutableParagraphStyle *centred = [[NSMutableParagraphStyle alloc] init];
    [centred setAlignment:NSCenterTextAlignment];
    [centred setLineBreakMode:NSLineBreakByTruncatingTail];

    NSDictionary *headAttrs = @{NSFontAttributeName: [BTStyle displayBoldFont],
                                NSForegroundColorAttributeName: [BTStyle displayText],
                                NSParagraphStyleAttributeName: centred};
    NSDictionary *lineAttrs = @{NSFontAttributeName: [BTStyle displayFont],
                                NSForegroundColorAttributeName: [BTStyle displayText],
                                NSParagraphStyleAttributeName: centred};

    CGFloat top = NSMaxY(bounds) - BT_DISPLAY_LINE - BT_DISPLAY_TOP;
    [@"Nothing played" drawInRect:NSMakeRect(NSMinX(bounds) + 6, top,
                                             NSWidth(bounds) - 12, BT_DISPLAY_LINE)
                   withAttributes:headAttrs];
    [_notice drawInRect:NSMakeRect(NSMinX(bounds) + 6, top - BT_DISPLAY_LINE,
                                   NSWidth(bounds) - 12, BT_DISPLAY_LINE)
         withAttributes:lineAttrs];
}

#pragma mark - Sync progress

// While a sync runs the readout shows it instead of the song, since the whole
// window is about the iPod at that point.
// Anything else with something slow to report, naming itself as it goes.
- (void)progress:(NSNotification *)note {
    _syncing = YES;
    _syncTitle = [[note userInfo] objectForKey:@"title"];
    _syncFraction = [[[note userInfo] objectForKey:@"fraction"] doubleValue];
    _syncMessage = [[note userInfo] objectForKey:@"message"];
    [self setNeedsDisplay:YES];
}

- (void)syncProgress:(NSNotification *)note {
    _syncing = YES;
    _syncTitle = @"Syncing iPod";
    _syncFraction = [[[note userInfo] objectForKey:@"fraction"] doubleValue];
    _syncMessage = [[note userInfo] objectForKey:@"message"];
    [self setNeedsDisplay:YES];
}

- (void)syncFinished:(NSNotification *)note {
    _syncing = NO;
    _syncMessage = nil;
    _syncTitle = nil;
    [self setNeedsDisplay:YES];
}

- (void)drawSyncInRect:(NSRect)bounds {
    NSMutableParagraphStyle *centered = [[NSMutableParagraphStyle alloc] init];
    [centered setAlignment:NSCenterTextAlignment];
    [centered setLineBreakMode:NSLineBreakByTruncatingMiddle];

    NSDictionary *attrs = @{NSFontAttributeName: [BTStyle displayBoldFont],
                            NSForegroundColorAttributeName: [BTStyle displayText],
                            NSParagraphStyleAttributeName: centered};
    NSString *title = [_syncTitle length] > 0 ? _syncTitle : @"Working";
    [title drawInRect:NSMakeRect(NSMinX(bounds) + 6,
                                 NSMaxY(bounds) - BT_DISPLAY_LINE - BT_DISPLAY_TOP,
                                 NSWidth(bounds) - 12, BT_DISPLAY_LINE)
       withAttributes:attrs];

    if ([_syncMessage length] > 0) {
        NSDictionary *lineAttrs = @{NSFontAttributeName: [BTStyle displayFont],
                                    NSForegroundColorAttributeName: [BTStyle displayText],
                                    NSParagraphStyleAttributeName: centered};
        [_syncMessage drawInRect:NSMakeRect(NSMinX(bounds) + 6,
                                            NSMaxY(bounds) - 2.0 * BT_DISPLAY_LINE - BT_DISPLAY_TOP,
                                            NSWidth(bounds) - 12, BT_DISPLAY_LINE)
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
    [[BTStyle progressFill] set];
    [[NSBezierPath bezierPathWithRoundedRect:filled xRadius:3 yRadius:3] fill];
}

// Centred while it fits; once it does not, it scrolls on the cycle above.
- (void)drawLine:(NSString *)line
          inRect:(NSRect)rect
      attributes:(NSDictionary *)attributes
         elapsed:(NSTimeInterval)elapsed {
    NSSize size = [line sizeWithAttributes:attributes];
    if (size.width <= NSWidth(rect)) {
        [line drawInRect:rect withAttributes:attributes];
        return;
    }

    CGFloat span = size.width - NSWidth(rect) + 6.0;
    CGFloat travel = span / BT_MARQUEE_SPEED;
    CGFloat offset = 0.0;

    if (elapsed > BT_MARQUEE_WAIT) {
        CGFloat t = elapsed - BT_MARQUEE_WAIT;
        CGFloat cycle = travel * 2.0 + BT_MARQUEE_REST + BT_MARQUEE_WAIT;
        CGFloat phase = fmod(t, cycle);

        if (phase < travel) {
            offset = span * (phase / travel);
        } else if (phase < travel + BT_MARQUEE_REST) {
            offset = span;
        } else if (phase < travel * 2.0 + BT_MARQUEE_REST) {
            offset = span * (1.0 - (phase - travel - BT_MARQUEE_REST) / travel);
        }
    }

    // Left aligned while scrolling, so the text starts where it can be read
    // rather than sliding in from the middle.
    NSMutableParagraphStyle *left = [[NSMutableParagraphStyle alloc] init];
    [left setAlignment:NSLeftTextAlignment];
    [left setLineBreakMode:NSLineBreakByClipping];
    NSMutableDictionary *scrolling = [NSMutableDictionary dictionaryWithDictionary:attributes];
    [scrolling setObject:left forKey:NSParagraphStyleAttributeName];

    [NSGraphicsContext saveGraphicsState];
    NSRectClip(rect);
    [line drawInRect:NSMakeRect(NSMinX(rect) - offset, NSMinY(rect), size.width + 8.0, NSHeight(rect))
      withAttributes:scrolling];
    [NSGraphicsContext restoreGraphicsState];
}

+ (CGFloat)naturalHeight {
    return BT_DISPLAY_TOP + 2.0 * BT_DISPLAY_LINE + BT_DISPLAY_FOOT;
}

- (NSRect)progressRect {
    // Inset past the rounded ends so the groove does not run into them.
    NSRect b = [self bounds];
    return NSMakeRect(NSMinX(b) + 56, NSMinY(b) + 6, NSWidth(b) - 112, 6);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    // Fully rounded ends, the way the readout was drawn in 2003.
    //
    // Round the whole way rather than nearly so. At four tenths of the height
    // the arcs stopped short and left nearly nine points of dead straight edge
    // in the middle of each end.
    //
    // A hairline that runs straight lands on one row of pixels and reaches its
    // full colour. The same line around a curve is spread across two and never
    // does: that short segment held 0.427 exactly while the arcs above and
    // below it wandered between 0.43 and 0.54. Curvature that runs out at half
    // the height leaves no crisp segment beside the soft ones, and the end
    // reads as a smooth curve rather than a frayed one.
    [BTStyle drawSunkenBezelInRect:bounds
                            radius:(NSHeight(bounds) / 2.0)
                              fill:[BTStyle displayBackground]];

    if (_syncing) {
        [self drawSyncInRect:bounds];
        return;
    }
    // After the progress, before the song: something slow running is the more
    // urgent thing to show, and a notice arrives when nothing is playing anyway.
    if ([_notice length] > 0) {
        [self drawNoticeInRect:bounds];
        return;
    }

    BTPlayer *player = [BTPlayer sharedPlayer];
    BTTrack *track = [player currentTrack];

    NSMutableParagraphStyle *centered = [[NSMutableParagraphStyle alloc] init];
    [centered setAlignment:NSCenterTextAlignment];
    [centered setLineBreakMode:NSLineBreakByTruncatingTail];
    // Without this, a line that does not fit is squeezed until the spaces
    // disappear before anything is truncated, which is unreadable.
    [centered setTighteningFactorForTruncation:0.0];

    NSDictionary *titleAttrs = @{NSFontAttributeName: [BTStyle displayBoldFont],
                                 NSForegroundColorAttributeName: [BTStyle displayText],
                                 NSParagraphStyleAttributeName: centered};
    NSDictionary *lineAttrs = @{NSFontAttributeName: [BTStyle displayFont],
                                NSForegroundColorAttributeName: [BTStyle displayText],
                                NSParagraphStyleAttributeName: centered};

    // Kept so refresh can tell a new picture from the one already up.
    _drawnTrackID = track.trackID;

    if (track == nil) {
        CGFloat h = BT_DISPLAY_LINE + 2.0;
        NSRect r = NSMakeRect(NSMinX(bounds), NSMidY(bounds) - h / 2.0, NSWidth(bounds), h);
        [@"BTunes" drawInRect:r withAttributes:titleAttrs];
        return;
    }

    // The clock restarts with each song, so every one gets its still moment
    // before anything moves.
    if (![_lineTrackID isEqualToString:track.trackID]) {
        _lineTrackID = track.trackID;
        _lineShownAt = [NSDate date];
    }
    NSTimeInterval shown = _lineShownAt ? -[_lineShownAt timeIntervalSinceNow] : 0.0;

    NSRect titleRect = NSMakeRect(NSMinX(bounds) + 6,
                                  NSMaxY(bounds) - BT_DISPLAY_LINE - BT_DISPLAY_TOP,
                                  NSWidth(bounds) - 12,
                                  BT_DISPLAY_LINE);
    [self drawLine:[track displayTitle] inRect:titleRect attributes:titleAttrs elapsed:shown];

    // The whole line is kept even when it does not fit: it scrolls rather than
    // being cut down.
    NSString *second = [NSString stringWithFormat:@"%@ - %@",
                        [track displayArtist], [track displayAlbum]];
    NSRect secondRect = NSMakeRect(NSMinX(bounds) + 6,
                                   NSMinY(titleRect) - BT_DISPLAY_LINE,
                                   NSWidth(bounds) - 12,
                                   BT_DISPLAY_LINE);
    [self drawLine:second inRect:secondRect attributes:lineAttrs elapsed:shown];

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
    NSString *trailing = [self trailingFor:elapsed of:duration];
    _drawnLeading = leading;
    _drawnTrailing = trailing;
    _drawnKnob = [self knobFor:elapsed of:duration];

    CGFloat textHeight = [leading sizeWithAttributes:timeLeftAttrs].height;
    CGFloat textY = NSMidY(groove) - textHeight / 2.0;

    // Wide enough for the longest time there is rather than a width written
    // down, since a song over an hour with the remaining time showing is eight
    // characters and grows with the type.
    CGFloat textWidth = ceil([@"-0:00:00" sizeWithAttributes:timeLeftAttrs].width) + 2.0;

    // Held in against the scrub bar rather than out against the rounded ends.
    [leading drawInRect:NSMakeRect(NSMinX(bounds) + 14, textY, textWidth, textHeight)
         withAttributes:timeLeftAttrs];
    [trailing drawInRect:NSMakeRect(NSMaxX(bounds) - 14 - textWidth, textY, textWidth, textHeight)
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
        [[BTStyle progressFill] set];
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
