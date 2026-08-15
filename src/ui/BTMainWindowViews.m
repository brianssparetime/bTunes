#import "BTMainWindowViews.h"
#import "BTSourceIcon.h"
#import "BTStyle.h"

@implementation BTChromeView
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    [BTStyle drawChromeInRect:[self bounds]];
}
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    if (self.layoutHandler) self.layoutHandler();
}
@end

#pragma mark - Bottom bar

@implementation BTBottomBarView
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    // The same brushed chrome the top of the window is drawn on, so the window
    // is one piece of metal with the lists let into it.
    [BTStyle drawChromeInRect:bounds];

    // The chrome draws no line at its own edges, where the step from the
    // gradient to the content is separation enough. Here it is not: the bar is
    // short, so its top is the light end of the ramp and sits against the list
    // above with nothing between them.
    [[BTStyle chromeEdge] set];
    NSRectFill(NSMakeRect(0, NSMaxY(bounds) - 1, NSWidth(bounds), 1));

    if ([self.statusText length] > 0) {
        NSMutableParagraphStyle *centered = [[NSMutableParagraphStyle alloc] init];
        [centered setAlignment:NSCenterTextAlignment];
        NSDictionary *attrs = @{NSFontAttributeName: [BTStyle uiFont],
                                NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.25 alpha:1.0],
                                NSParagraphStyleAttributeName: centered};
        // Leave the right end clear for the three buttons.
        CGFloat reserved = 84.0;
        CGFloat line = [BTStyle lineHeight] + 1.0;
        [self.statusText drawInRect:NSMakeRect(reserved, NSMidY(bounds) - line / 2.0,
                                               NSWidth(bounds) - reserved * 2, line)
                     withAttributes:attrs];
    }
}
@end

#pragma mark - Source list cell

@implementation BTSourceCell

// Where the eject mark sits inside a row, so the row and the click test agree.
+ (NSRect)ejectRectInFrame:(NSRect)frame {
    return NSMakeRect(NSMaxX(frame) - 18, NSMidY(frame) - 6, 12, 12);
}

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view {
    if (self.showsEject) {
        [BTStyle drawEjectGlyphInRect:[BTSourceCell ejectRectInFrame:frame]
                                color:[NSColor colorWithCalibratedWhite:0.30 alpha:1.0]];
    }

    // A few points of air on the left, so the icon does not sit against the
    // disclosure triangle on rows that have one.
    NSRect content = frame;
    content.origin.x += 4.0;
    content.size.width -= 4.0;

    NSRect textFrame = content;
    if (self.showsEject) textFrame.size.width -= 20;
    if (self.icon) {
        CGFloat side = [BTSourceIcon side];
        NSRect iconFrame = NSMakeRect(NSMinX(content), NSMidY(content) - side / 2.0, side, side);
        [self.icon drawInRect:iconFrame
                     fromRect:NSZeroRect
                    operation:NSCompositeSourceOver
                     fraction:1.0
               respectFlipped:YES
                        hints:nil];
        // The gap between mark and name, which stays what it was as the mark
        // grows: the words are where the eye runs down the list, so they are the
        // thing that should not move.
        CGFloat gap = side + 4.0;
        textFrame.origin.x += gap;
        textFrame.size.width -= gap;
    }
    textFrame.origin.y += 1;
    [super drawInteriorWithFrame:textFrame inView:view];
}

@end

// How far a right-set figure stands off the trailing edge of its column. Enough
// to read as a margin, and not so much that the numbers stop lining up under
// their heading.
#define BT_NUMBER_RIGHT_INSET 5.0

@implementation BTNumberCell

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view {
    frame.size.width -= BT_NUMBER_RIGHT_INSET;
    [super drawInteriorWithFrame:frame inView:view];
}

@end

// Track number cell that shows the speaker instead of the number while its row
// is the one playing, so the indicator needs no column of its own.

@implementation BTTrackNumberCell

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view {
    // The play mark is drawn rather than kept as an image, since it is wanted at
    // whatever colour the row's words are and an image would be one fixed one.
    if (self.showsPlay) {
        CGFloat side = floor(MIN(NSWidth(frame), NSHeight(frame)) - 4.0);
        if (side < 6.0) side = 6.0;
        NSRect box = NSMakeRect(NSMidX(frame) - side / 2.0,
                                NSMidY(frame) - side / 2.0, side, side);
        [BTStyle drawPlayGlyphInRect:box color:[NSColor colorWithCalibratedWhite:0.30 alpha:1.0]];
        return;
    }
    if (self.indicator == nil) {
        [super drawInteriorWithFrame:frame inView:view];
        return;
    }
    NSSize size = [self.indicator size];
    NSRect box = NSMakeRect(NSMidX(frame) - size.width / 2,
                            NSMidY(frame) - size.height / 2,
                            size.width, size.height);
    [self.indicator drawInRect:box
                      fromRect:NSZeroRect
                     operation:NSCompositeSourceOver
                      fraction:1.0
                respectFlipped:YES
                         hints:nil];
}

@end

#pragma mark - Tables that answer the delete key

// The window catches transport keys that no view claimed.

@implementation BTMainWindow
- (void)keyDown:(NSEvent *)event {
    if (BTHandleTransportKey(event, self, YES)) return;
    [super keyDown:event];
}
@end

@implementation BTKeyTableView {
    NSTrackingArea *_hoverArea;
    NSInteger _hoveredRow;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) _hoveredRow = -1;
    return self;
}

- (NSInteger)hoveredRow { return _hoveredRow; }

// Followed rather than asked for, because the mark has to appear as the pointer
// arrives and go as it leaves, and nothing else in the window is watching.
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_hoverArea) [self removeTrackingArea:_hoverArea];
    _hoverArea = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                      NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
               owner:self
            userInfo:nil];
    [self addTrackingArea:_hoverArea];
}

- (void)setHoveredRow:(NSInteger)row {
    if (row == _hoveredRow) return;
    NSInteger was = _hoveredRow;
    _hoveredRow = row;
    // Only the two rows that changed, so moving down a list of five thousand
    // songs does not redraw the list five thousand times.
    if (was >= 0 && was < [self numberOfRows]) [self setNeedsDisplayInRect:[self rectOfRow:was]];
    if (row >= 0 && row < [self numberOfRows]) [self setNeedsDisplayInRect:[self rectOfRow:row]];
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    [self setHoveredRow:[self rowAtPoint:point]];
    [super mouseMoved:event];
}

- (void)mouseEntered:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    [self setHoveredRow:[self rowAtPoint:point]];
}

- (void)mouseExited:(NSEvent *)event {
    [self setHoveredRow:-1];
}

// A list that scrolls under a still pointer is showing a different row there,
// and no mouse moved to say so. Without this the mark stays on the row it was
// on, which is now somewhere else entirely.
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    NSClipView *clip = [[self enclosingScrollView] contentView];
    if (clip == nil) return;
    [clip setPostsBoundsChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(listScrolled:)
                                                name:NSViewBoundsDidChangeNotification
                                              object:clip];
}

- (void)listScrolled:(NSNotification *)note {
    [self followPointer];
}

- (void)viewDidEndLiveResize {
    [super viewDidEndLiveResize];
    [self followPointer];
}

// Where the pointer is now, asked of the window rather than waited for. Outside
// the list, or over a window that is not the one being used, nothing is offered.
- (void)followPointer {
    NSWindow *window = [self window];
    if (window == nil || ![window isKeyWindow]) { [self setHoveredRow:-1]; return; }
    NSPoint point = [self convertPoint:[window mouseLocationOutsideOfEventStream] fromView:nil];
    if (!NSPointInRect(point, [self visibleRect])) { [self setHoveredRow:-1]; return; }
    [self setHoveredRow:[self rowAtPoint:point]];
}

- (void)keyDown:(NSEvent *)event {
    if (BTHandleDeleteKey(event, self)) return;
    if (BTHandleTransportKey(event, self, NO)) return;
    [super keyDown:event];
}
@end

@implementation BTKeyOutlineView

// A smaller triangle beside a folder than the system draws, painted over the
// one the system drew.
//
// Its size is not a question an outline view answers. Handing a smaller rect to
// frameOfOutlineCellAtRow: moves the mark and does not size it: the list was
// rendered with that rect inset and the pixels compared against the same list
// without, and not one of them differed. Painting over is what is left.
//
// The click still lands on the rect the system chose, which is larger than the
// mark now drawn in it. A folder that opens from slightly outside its triangle
// is the forgiving way round.
- (void)drawRow:(NSInteger)row clipRect:(NSRect)clipRect {
    [super drawRow:row clipRect:clipRect];

    NSRect knob = [self frameOfOutlineCellAtRow:row];
    if (NSIsEmptyRect(knob)) return;

    BOOL selected = [self isRowSelected:row];
    BOOL strong = selected && BTListHasFocus(self);
    NSColor *behind = selected ? (strong ? [BTStyle selection] : [BTStyle inactiveSelection])
                               : [BTStyle listBackground];
    [behind set];
    NSRectFill(NSInsetRect(knob, -1.0, -1.0));

    // Squat rather than square, which is the shape the system's own mark has;
    // a point or so smaller than it in each direction is the whole change.
    CGFloat width = 8.0, height = 6.0;
    NSRect mark = NSMakeRect(round(NSMidX(knob) - width / 2.0),
                             round(NSMidY(knob) - height / 2.0), width, height);
    [BTStyle drawDisclosureInRect:mark
                             open:[self isItemExpanded:[self itemAtRow:row]]
                            color:(strong ? [NSColor whiteColor]
                                          : [NSColor colorWithCalibratedWhite:0.35 alpha:1.0])];
}

// A click on the eject mark ejects rather than selecting the row.
- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSInteger row = [self rowAtPoint:point];
    if (row >= 0) {
        NSCell *cell = [self preparedCellAtColumn:0 row:row];
        if ([cell isKindOfClass:[BTSourceCell class]] && [(BTSourceCell *)cell showsEject]) {
            NSRect frame = [self frameOfCellAtColumn:0 row:row];
            if (NSPointInRect(point, [BTSourceCell ejectRectInFrame:frame])) {
                [NSApp sendAction:@selector(ejectSource:) to:nil from:self];
                return;
            }
        }
    }
    [super mouseDown:event];
}

- (void)keyDown:(NSEvent *)event {
    if (BTHandleDeleteKey(event, self)) return;

    unichar key = [[event charactersIgnoringModifiers] length] > 0
        ? [[event charactersIgnoringModifiers] characterAtIndex:0] : 0;

    // On a folder, the arrows open and close it. Everywhere else in this list
    // they skip tracks, which is what they do in the rest of the window.
    if (key == NSLeftArrowFunctionKey || key == NSRightArrowFunctionKey) {
        NSInteger row = [self selectedRow];
        id item = (row >= 0) ? [self itemAtRow:row] : nil;
        if (item && [self isExpandable:item]) {
            if (key == NSRightArrowFunctionKey) {
                [self expandItem:item];
            } else {
                [self collapseItem:item];
            }
            return;
        }
    }

    if (BTHandleTransportKey(event, self, NO)) return;
    [super keyDown:event];
}
@end
