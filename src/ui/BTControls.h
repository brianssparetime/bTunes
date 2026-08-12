#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, BTGlyph) {
    BTGlyphPlay = 0,
    BTGlyphPause,
    BTGlyphPrevious,
    BTGlyphNext,
    BTGlyphShuffle,
    BTGlyphRepeat,
    BTGlyphRepeatOne,
    BTGlyphStop,
    BTGlyphShrink,
    BTGlyphEject,
    BTGlyphPlus
};

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
