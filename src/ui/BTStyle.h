#import <Cocoa/Cocoa.h>

// Colors, fonts, and drawing helpers for the 2003 look. Everything the
// interface draws goes through here so the palette stays in one place.
@interface BTStyle : NSObject

+ (NSFont *)uiFont;
+ (NSFont *)boldFont;
+ (NSFont *)smallFont;
+ (NSFont *)displayFont;
+ (NSFont *)displayBoldFont;

// The accent, shared with the logo: body, lit edge, and shadow.
+ (NSColor *)accent;
+ (NSColor *)accentLight;
+ (NSColor *)accentDark;

+ (NSColor *)windowBackground;
+ (NSColor *)chromeTop;
+ (NSColor *)chromeBottom;
+ (NSColor *)chromeEdge;
+ (NSColor *)listBackground;
+ (NSColor *)selection;
+ (NSColor *)inactiveSelection;
+ (NSColor *)displayBackground;
+ (NSColor *)displayEdge;
+ (NSColor *)displayText;

+ (void)drawVerticalGradientInRect:(NSRect)rect from:(NSColor *)top to:(NSColor *)bottom;
+ (void)drawChromeInRect:(NSRect)rect;
+ (void)drawSunkenBezelInRect:(NSRect)rect radius:(CGFloat)radius fill:(NSColor *)fill;
// The recessed channel the volume knob rides in. Left unfilled on purpose: the
// 2003 control had no colored bar, and one reads as pasted in from a different
// toolkit.
+ (void)drawGrooveInRect:(NSRect)rect;

// The glossy round transport buttons and the small square toggles.
+ (void)drawAquaCircleInRect:(NSRect)rect pressed:(BOOL)pressed enabled:(BOOL)enabled;
+ (void)drawToggleBackgroundInRect:(NSRect)rect on:(BOOL)on pressed:(BOOL)pressed;

// Glyphs, drawn as paths so they stay crisp at any size and need no image files.
+ (void)drawPlayGlyphInRect:(NSRect)rect color:(NSColor *)color;
+ (void)drawPauseGlyphInRect:(NSRect)rect color:(NSColor *)color;
+ (void)drawPreviousGlyphInRect:(NSRect)rect color:(NSColor *)color;
+ (void)drawNextGlyphInRect:(NSRect)rect color:(NSColor *)color;
// The same marks with the stop bar the mini player's original had.
+ (void)drawPreviousBarGlyphInRect:(NSRect)rect color:(NSColor *)color;
+ (void)drawNextBarGlyphInRect:(NSRect)rect color:(NSColor *)color;
+ (void)drawSpeakerGlyphInRect:(NSRect)rect waves:(NSInteger)waves color:(NSColor *)color;
+ (void)drawMagnifierGlyphInRect:(NSRect)rect color:(NSColor *)color;
+ (void)drawShrinkGlyphInRect:(NSRect)rect color:(NSColor *)color;
+ (void)drawEjectGlyphInRect:(NSRect)rect color:(NSColor *)color;
+ (void)drawShuffleGlyphInRect:(NSRect)rect color:(NSColor *)color;
+ (void)drawRepeatGlyphInRect:(NSRect)rect one:(BOOL)one color:(NSColor *)color;

+ (NSString *)timeStringFromInterval:(NSTimeInterval)interval;
+ (NSString *)longTimeStringFromInterval:(NSTimeInterval)interval;

@end
