#import <Cocoa/Cocoa.h>

@class BTBrowserView;

@protocol BTBrowserViewDelegate <NSObject>
- (void)browserViewSelectionDidChange:(BTBrowserView *)browser;
@end

// The three lists across the top of the window: Genre, Artist, Album. Each
// column narrows the one to its right, and all three narrow the track list.
@interface BTBrowserView : NSView

@property (nonatomic, weak) id<BTBrowserViewDelegate> browserDelegate;

- (void)setSourceTracks:(NSArray *)tracks;
- (NSArray *)filteredTracks;
- (void)resetSelection;

// Ends of the internal tab order, so the window can put the three columns in
// its own key view loop.
- (NSView *)firstColumnView;
- (NSView *)lastColumnView;

@end
