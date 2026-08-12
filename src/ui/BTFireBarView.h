#import <Cocoa/Cocoa.h>

// The mini-mode analyzer: green-through-red bars with falling peak caps.
//
// The bars are driven by the playback level meter rather than a Fourier
// transform, with a fixed per-band shape and a slow wobble so neighboring bars
// do not move as one. It reads like a spectrum without decoding a second copy
// of the audio.
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
