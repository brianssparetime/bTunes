#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, BTGlyph) {
    BTGlyphPlay = 0,
    BTGlyphPause,
    BTGlyphPrevious,
    BTGlyphNext,
    // The same skip marks with the stop bar the mini player's original had.
    BTGlyphPreviousBar,
    BTGlyphNextBar,
    BTGlyphShuffle,
    BTGlyphRepeat,
    BTGlyphRepeatOne,
    BTGlyphStop,
    BTGlyphShrink,
    BTGlyphEject,
    BTGlyphSync,
    BTGlyphPlus
};

// Draws a mark inside a rect. Both the round buttons up top and the blocky ones
// in the mini player come through here, so a change to a mark shows up in both.
void BTDrawGlyph(BTGlyph glyph, NSRect rect, NSColor *color);

// A caption: a text field with all of its field-ness turned off. The target
// system has no label class of its own, so every window would otherwise build
// this the same way six setters at a time.
NSTextField *BTLabelWithText(NSString *text, NSFont *font);

// Transport keys, shared by every view and window that can hold focus.
//
// Left and right skip tracks, space plays and pauses, M mutes, and the
// option-modified up and down arrows change volume. Plain up and down change
// volume too, except in a list, where they still move the selection and would
// be missed if taken away. Returns YES when the key was claimed.
BOOL BTHandleTransportKey(NSEvent *event, id sender, BOOL plainArrowsAreVolume);

// Round Aqua transport button. Draws itself; no image files involved.
@interface BTRoundButton : NSButton
@property (nonatomic, assign) BTGlyph glyph;
+ (instancetype)buttonWithFrame:(NSRect)frame glyph:(BTGlyph)glyph target:(id)target action:(SEL)action;
@end

// Small square toggle used for shuffle and repeat at the bottom right.
@interface BTToggleButton : NSButton
@property (nonatomic, assign) BTGlyph glyph;
@property (nonatomic, assign) BOOL on;
+ (instancetype)buttonWithFrame:(NSRect)frame glyph:(BTGlyph)glyph target:(id)target action:(SEL)action;
@end

// Push button in the 2010 manner, drawn rather than left to the system, so it
// matches the rest of the window instead of whichever decade the system is in.
// It sizes itself to its title; callers place it and may widen it.
@interface BTPushButton : NSButton
+ (instancetype)buttonWithTitle:(NSString *)title target:(id)target action:(SEL)action;
@end

// Search field drawn as a capsule with the magnifier placed by hand. The stock
// cell draws its own rounded rectangle and ignores the rounded bezel style, and
// it sits the magnifier low against the text.
@interface BTSearchFieldCell : NSSearchFieldCell
@end

// A list that draws its own selection, so every pane highlights the same blue
// instead of the focused one being blue and the rest gray.
@interface BTListTableView : NSTableView
@end

// Volume slider with the two speaker glyphs on either side.
@interface BTVolumeView : NSView
@property (nonatomic, assign) float volume;
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@end
