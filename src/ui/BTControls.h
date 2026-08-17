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
    BTGlyphPlus,
    BTGlyphBurn,
    BTGlyphImport
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

// How every list in the window fills a selected row. Shared as a function
// because the source list is an outline view and cannot inherit it, and a list
// drawing the system's own blue is exactly what purple mode cannot reach.
void BTDrawListSelection(NSTableView *list, NSRect clipRect);

// Whether this list draws the strong selection: its window is the one being
// used and this is the list the keyboard is talking to. Everything else draws
// the gray one.
//
// The fill and the text have to agree about this, so both ask here. White words
// on the gray fill are barely words at all.
BOOL BTListHasFocus(NSTableView *list);

// Redraws the list when the window gains or loses focus, and when the keyboard
// moves between lists, since the selection is a different colour either side of
// both.
void BTWatchListFocus(NSView *list);

// Posted after the keyboard moves from one list to another.
extern NSString *const BTListFocusDidChangeNotification;
// Says the keyboard has moved. Called by a list as it takes or gives up focus.
void BTNoteListFocusChanged(void);

@interface NSView (BTListFocus)
- (void)btListFocusChanged:(NSNotification *)note;
@end

// The delete key, shared the same way and for the same reason as the transport
// keys. A list that wants it tells its delegate through tableViewDeletePressed:,
// which is how both lists in the main window ask to have a row removed. Returns
// YES when the key was claimed.
BOOL BTHandleDeleteKey(NSEvent *event, NSTableView *list);

// One column's heading. The system draws a flat strip; this one is dished the
// way iTunes 4's was, with a hairline standing between it and the next column.
@interface BTHeaderCell : NSTableHeaderCell
@end

// The strip the headings sit on, so the space past the last column is shaded
// with them rather than left to the system. Without it the heading stops
// wherever the columns happen to end and flat gray runs on to the window edge.
@interface BTHeaderView : NSTableHeaderView
@end

// The source pane's heading, which names the pane instead of heading columns:
// the same strip, carrying one dimmed word centred on the pane, and nothing to
// click. Taller than the strip by the air it holds under it, so ask it for its
// height rather than working one out.
@interface BTPaneHeaderView : NSTableHeaderView
@property (nonatomic, copy) NSString *title;
+ (CGFloat)height;
@end

// The square where a heading meets a scroller, shaded with the heading so the
// strip runs the full width of the pane.
@interface BTHeaderCornerView : NSView
@end


// A list that draws its own selection, so every pane highlights the same colour
// instead of the focused one being blue and the rest gray.
//
// Every column added to one of these gets the heading above, and the list gets
// the strip to put them on. Done here rather than at each of the four places a
// column is made, so a column added later cannot come out in the system's
// shading beside the others.
@interface BTListTableView : NSTableView
@end

// The same, for an outline view, which cannot inherit the table subclass. Every
// list in the application is one of these two, so a list that is neither draws
// the system's own blue and is the one pane that does not match.
@interface BTListOutlineView : NSOutlineView
@end

// A tick box drawn in the window's own colour. The system draws its checkboxes
// blue whatever else has been asked for, which leaves a purple window full of
// blue ticks. Handles the three states and an optional title beside the box.
@interface BTCheckboxCell : NSButtonCell
@end

// Volume slider with the two speaker glyphs on either side.
@interface BTVolumeView : NSView
@property (nonatomic, assign) float volume;
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@end

// The windows that are dismissed rather than worked in: the equalizer and the
// preferences. Both hold settings that take effect as they are made, so there
// is nothing to cancel and nothing to confirm, and both want the two ways out
// of a window that carries no buttons along its foot.
@interface BTPanelWindow : NSWindow
@end
