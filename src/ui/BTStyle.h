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

// A row that cannot be imported yet, or a song that cannot play. Every reason
// draws the same gray today. The reason is passed in rather than decided
// beforehand, so giving one its own color later is a change to this method and
// to nowhere else. Takes the reason as a plain integer to keep the palette from
// having to know what the reasons are.
+ (NSColor *)ineligibleTextForReason:(NSInteger)reason;
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
// The dent under a toggle while the mouse is down. A toggle that is on shows it
// by the color of its mark instead.
+ (void)drawTogglePressedInRect:(NSRect)rect;

// A push button in the manner of 2010 and 2011: ends rounded all the way, a
// gradient shallow enough to read as a lit surface rather than as a bubble, and
// a thin border. The blue one is the default button.
+ (void)drawPushButtonInRect:(NSRect)rect
                     pressed:(BOOL)pressed
                     enabled:(BOOL)enabled
                   isDefault:(BOOL)isDefault;

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
// Two arrows chasing each other round a circle, for bringing music over.
+ (void)drawSyncGlyphInRect:(NSRect)rect color:(NSColor *)color;
+ (void)drawShuffleGlyphInRect:(NSRect)rect color:(NSColor *)color;
+ (void)drawRepeatGlyphInRect:(NSRect)rect one:(BOOL)one color:(NSColor *)color;

+ (NSString *)timeStringFromInterval:(NSTimeInterval)interval;
+ (NSString *)longTimeStringFromInterval:(NSTimeInterval)interval;

@end
