#import <Cocoa/Cocoa.h>

// Two lines of type that read the same, either of which may be missing. The
// readouts hold on to the words they last drew so the player's tick does not
// repaint what is already on screen, and a song without an album gives a nil
// where the comparison expects a string.
static inline BOOL BTSameString(NSString *a, NSString *b) {
    return (a == b) || (a != nil && [a isEqualToString:b]);
}

// Colors, fonts, and drawing helpers for the 2003 look. Everything the
// interface draws goes through here so the palette stays in one place.
@interface BTStyle : NSObject

// The one size every other size here comes from. Change this and the fonts, the
// row heights, the captions and the fields all move together.
//
// The face is Lucida Grande because that is what iTunes 4 was set in. The rest
// of this section exists because changing the size used to mean finding the
// same decision written out in fifteen places and getting all fifteen right.
+ (CGFloat)baseFontSize;

// The same face at a size of the caller's choosing. For the one place that has
// to hold still while the rest of the window grows: the mini player is a fixed
// panel measured from its top edge, so its type does not follow the base any
// more than its palette follows purple mode.
+ (NSFont *)fontOfSize:(CGFloat)size bold:(BOOL)bold;

+ (NSFont *)uiFont;             // the base size: lists, captions, buttons
+ (NSFont *)boldFont;           // the same, for a heading
+ (NSFont *)smallFont;          // two under: a note beneath a field
+ (NSFont *)displayFont;        // one under: the readout at the top
+ (NSFont *)displayBoldFont;

// How tall one line of the base font is, asked of the font rather than assumed.
// It is not a straight multiple of the size: Lucida Grande goes 13 points at
// size 11 and 15 at size 12, so anything that adds one to a row height for one
// extra point of type is already wrong.
+ (CGFloat)lineHeight;
+ (CGFloat)smallLineHeight;
+ (CGFloat)displayLineHeight;

// A row in a list, in the three weights the window uses. The differences are
// deliberate: the browser columns are tight, the songs are ordinary, and a
// source row carries an icon and wants the air.
+ (CGFloat)browserRowHeight;
+ (CGFloat)listRowHeight;
+ (CGFloat)sourceRowHeight;

// The heading strip over a list. Both panes take this rather than the system's
// own header height, because in iTunes 4 the source pane's heading and the track
// list's were one band running across the window.
+ (CGFloat)listHeaderHeight;

// The frame a caption needs, and the frame a control needs. A control is taller
// than its words because it draws a border and a background around them.
+ (CGFloat)labelHeight;
+ (CGFloat)smallLabelHeight;
+ (CGFloat)fieldHeight;         // text field, popup button
+ (CGFloat)checkboxHeight;

// How tall a run of words needs to be at a given width, measured rather than
// counted in lines. How many lines a sentence takes depends on the words and on
// the size of the type, so a number written down is right for one wording at one
// size and loses the end of the sentence the first time either changes. Two
// windows had worked this out separately under two names.
+ (CGFloat)heightForText:(NSString *)text font:(NSFont *)font width:(CGFloat)width;

// The one purple everything purple is made from: the logo, the mini player, and
// the whole of the main window while purple mode is on. Change this and the
// rest follows.
+ (NSColor *)accent;
// The lit edge and the shadow, worked out from the accent rather than picked
// beside it, so they move when it does.
+ (NSColor *)accentLight;
+ (NSColor *)accentDark;

// A blue turned purple while purple mode is on, and left alone otherwise. The
// blue keeps its own lightness and strength and only changes hue, so whatever
// told two blues apart still tells the two purples apart.
+ (NSColor *)tinted:(NSColor *)blue;

// Every blue the main window draws comes from one of these, so purple mode has
// one place to turn them all.
+ (NSColor *)progressFill;        // how far into a song, and sync progress
+ (NSColor *)sourceIcon;          // the mark beside a source in the left pane
+ (NSColor *)smartPlaylistIcon;   // the same, for one built from rules
+ (NSColor *)defaultButtonTop;
+ (NSColor *)defaultButtonBottom;
+ (NSColor *)defaultButtonEdge;

+ (NSColor *)windowBackground;
+ (NSColor *)chromeTop;
+ (NSColor *)chromeBottom;
+ (NSColor *)chromeEdge;
+ (NSColor *)listBackground;
+ (NSColor *)selection;

// The hairline between one column heading and the next, the darker rule closing
// a heading off from its rows, and the dimmed word over the source pane.
+ (NSColor *)headerDivider;
+ (NSColor *)headerRule;
+ (NSColor *)paneHeaderText;

// The small gray note: what a field means, what a length is, what is checked.
// Secondary to whatever it sits under, and the same gray wherever it appears,
// which it was not: three files wrote it out and one of them had drifted.
+ (NSColor *)secondaryText;

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

// The heading strip over any list: a near-white band dished across the middle,
// bright along both edges, closed by a rule along its lower edge, whichever edge
// that is in the context it is handed. The source pane takes the same one, so
// the band runs unbroken across the window.
+ (void)drawListHeaderInRect:(NSRect)rect;

+ (void)drawChromeInRect:(NSRect)rect;
+ (void)drawSunkenBezelInRect:(NSRect)rect radius:(CGFloat)radius fill:(NSColor *)fill;
// The recessed channel the volume knob rides in. Left unfilled on purpose: the
// 2003 control had no colored bar, and one reads as pasted in from a different
// toolkit.
+ (void)drawGrooveInRect:(NSRect)rect;

// The same channel standing on end, for the equalizer's sliders. Not the
// horizontal one turned on its side: the shading that makes a channel look cut
// into a surface runs across the channel rather than along it, so a groove
// rotated ninety degrees comes out looking lit from the wrong direction.
+ (void)drawVerticalGrooveInRect:(NSRect)rect;

// The thumb that rides one. A capsule rather than the round knob the volume uses,
// because eleven circles in a row read as a row of buttons.
+ (void)drawSliderThumbInRect:(NSRect)rect pressed:(BOOL)pressed;

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

// The triangle beside a folder: pointing right while it is shut, down while it
// is open.
+ (void)drawDisclosureInRect:(NSRect)rect open:(BOOL)open color:(NSColor *)color;

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
// A disc with a flame over it, for burning one, and an arrow coming down into a
// disc, for taking one in. Both have to read at fifteen points, so the disc is a
// ring and a hole and nothing else.
+ (void)drawBurnGlyphInRect:(NSRect)rect color:(NSColor *)color;
+ (void)drawImportGlyphInRect:(NSRect)rect color:(NSColor *)color;
// Two arrows chasing each other round a circle, for bringing music over.
// A tick box, drawn rather than left to the system, which paints its own blue
// and pays no attention to which colour the window has been asked to use.
// State is NSOffState, NSOnState, or NSMixedState.
+ (void)drawCheckboxInRect:(NSRect)rect state:(NSInteger)state enabled:(BOOL)enabled;

+ (void)drawSyncGlyphInRect:(NSRect)rect color:(NSColor *)color;
+ (void)drawShuffleGlyphInRect:(NSRect)rect color:(NSColor *)color;
+ (void)drawRepeatGlyphInRect:(NSRect)rect one:(BOOL)one color:(NSColor *)color;

+ (NSString *)timeStringFromInterval:(NSTimeInterval)interval;

@end
