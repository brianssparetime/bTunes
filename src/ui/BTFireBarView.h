#import <Cocoa/Cocoa.h>

// The mini-mode analyzer: green-through-red bars with falling peak caps.
//
// One bar per band of a Fourier transform of the audio as it is rendered, low
// frequencies on the left. The bars rise the moment their band does and fall in
// their own time, the bass hanging and the treble snapping back, so the display
// shows what is being played rather than only how loud it is.
@interface BTFireBarView : NSView

// Bar geometry. The classic look is narrow bars: three points wide with a
// single point between them.
@property (nonatomic, assign) CGFloat barWidth;
@property (nonatomic, assign) CGFloat barGap;
// Faint dot grid behind the bars, the way the original analyzer window looked.
@property (nonatomic, assign) BOOL drawsGrid;

- (void)startAnimating;
- (void)stopAnimating;
@end
