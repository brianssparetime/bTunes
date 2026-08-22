#import "BTWindowFrames.h"

NSString * const BTMainWindowFrameName = @"BTunesMainWindow";
NSString * const BTMiniWindowFrameName = @"BTunesMiniPlayer";

// A saved position may name a display that is no longer attached, and a
// borderless window is not pulled back onto a screen the way a titled one is,
// since there is no title bar for the system to keep reachable. Move the frame
// until it lies inside the working area of whichever screen holds most of it,
// without changing its size. The far edges are answered first so that a window
// larger than the screen keeps its top left corner rather than its bottom
// right.
static NSRect BTFrameOnAScreen(NSRect frame) {
    NSScreen *best = nil;
    CGFloat bestArea = 0.0;
    for (NSScreen *screen in [NSScreen screens]) {
        NSRect shared = NSIntersectionRect(frame, [screen visibleFrame]);
        CGFloat area = NSWidth(shared) * NSHeight(shared);
        if (area > bestArea) {
            bestArea = area;
            best = screen;
        }
    }
    if (best == nil) best = [NSScreen mainScreen];
    if (best == nil) return frame;

    NSRect limit = [best visibleFrame];
    if (NSMaxX(frame) > NSMaxX(limit)) frame.origin.x = NSMaxX(limit) - NSWidth(frame);
    if (NSMinX(frame) < NSMinX(limit)) frame.origin.x = NSMinX(limit);
    if (NSMaxY(frame) > NSMaxY(limit)) frame.origin.y = NSMaxY(limit) - NSHeight(frame);
    if (NSMinY(frame) < NSMinY(limit)) frame.origin.y = NSMinY(limit);
    return frame;
}

BOOL BTRestoreWindowFrame(NSWindow *window, NSString *name) {
    if (window == nil || ![window setFrameUsingName:name]) return NO;

    // A frame written down before the smallest allowed size grew would come
    // back too small, and setting a frame by hand is not held to that limit the
    // way dragging an edge is. Grown from the top left, the corner the window
    // was left by.
    NSRect frame = [window frame];
    NSSize least = [window minSize];
    if (NSWidth(frame) < least.width || NSHeight(frame) < least.height) {
        CGFloat top = NSMaxY(frame);
        frame.size.width = MAX(NSWidth(frame), least.width);
        frame.size.height = MAX(NSHeight(frame), least.height);
        frame.origin.y = top - NSHeight(frame);
    }

    [window setFrame:BTFrameOnAScreen(frame) display:NO];
    return YES;
}

BOOL BTRestoreWindowPosition(NSWindow *window, NSString *name) {
    if (window == nil) return NO;

    NSSize size = [window frame].size;
    if (![window setFrameUsingName:name]) return NO;

    NSRect frame = [window frame];
    frame.origin.y += NSHeight(frame) - size.height;
    frame.size = size;
    [window setFrame:BTFrameOnAScreen(frame) display:NO];
    return YES;
}

void BTSaveWindowFrame(NSWindow *window, NSString *name) {
    if (window == nil) return;
    [window saveFrameUsingName:name];
}
