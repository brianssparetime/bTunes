#import "BTMainWindowViews.h"
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
    [BTStyle drawVerticalGradientInRect:bounds from:[BTStyle chromeTop] to:[BTStyle chromeBottom]];
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
        [self.statusText drawInRect:NSMakeRect(reserved, NSMidY(bounds) - 7, NSWidth(bounds) - reserved * 2, 14)
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
    content.origin.x += 5.0;
    content.size.width -= 5.0;

    NSRect textFrame = content;
    if (self.showsEject) textFrame.size.width -= 20;
    if (self.icon) {
        NSRect iconFrame = NSMakeRect(NSMinX(content), NSMidY(content) - 7, 14, 14);
        [self.icon drawInRect:iconFrame
                     fromRect:NSZeroRect
                    operation:NSCompositeSourceOver
                     fraction:1.0
               respectFlipped:YES
                        hints:nil];
        textFrame.origin.x += 18;
        textFrame.size.width -= 18;
    }
    textFrame.origin.y += 1;
    [super drawInteriorWithFrame:textFrame inView:view];
}

@end

// Track number cell that shows the speaker instead of the number while its row
// is the one playing, so the indicator needs no column of its own.

@implementation BTTrackNumberCell

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view {
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

@implementation BTKeyTableView
- (void)keyDown:(NSEvent *)event {
    if (BTHandleDeleteKey(event, self)) return;
    if (BTHandleTransportKey(event, self, NO)) return;
    [super keyDown:event];
}
@end

@implementation BTKeyOutlineView

// A click on the eject mark ejects rather than selecting the row.
- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    NSInteger row = [self rowAtPoint:point];
    if (row >= 0) {
        NSCell *cell = [self preparedCellAtColumn:0 row:row];
        if ([cell isKindOfClass:[BTSourceCell class]] && [(BTSourceCell *)cell showsEject]) {
            NSRect frame = [self frameOfCellAtColumn:0 row:row];
            if (NSPointInRect(point, [BTSourceCell ejectRectInFrame:frame])) {
                [NSApp sendAction:@selector(ejectIPod:) to:nil from:self];
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
