#import "BTPreferencesController.h"
#import "BTPreferences.h"
#import "BTLibrary.h"
#import "BTStyle.h"
#import "BTControls.h"

#define BT_PREFS_WIDTH  520.0
// Narrower than this and the path field is shorter than the button beside it.
#define BT_PREFS_MIN_WIDTH 420.0
#define BT_PREFS_MIN_HEIGHT 240.0

// The parts that follow the type. At the size this was drawn for they come to
// the numbers that used to be written out: 17, 22, 18, 28, 32, and the steps 24
// and 56 that carry one setting to the next.
#define BT_NAME     ([BTStyle lineHeight] + 4.0)     // "Music:" beside the path
#define BT_FIELD    ([BTStyle fieldHeight])          // the path itself
// A tick box and the words beside it. Asked of the palette, which is where the
// same question is answered for the burn dialog and the smart playlist sheet.
// Two of the four windows worked it out for themselves and came to two points
// less, which is drift rather than a decision.
#define BT_BOX      ([BTStyle checkboxHeight])
// The air around a note. Ten points under the box or field it explains, and
// sixteen under the note before the next setting starts, which is what the
// numbers written here used to come to.
#define BT_TO_NOTE   10.0
#define BT_AFTER_NOTE 16.0
// A tick box does not fill its frame the way a field does, so its note sits
// closer to it or the two read as unrelated.
#define BT_BOX_TO_NOTE 4.0
// The column the names sit in, and where the path beside them starts. Wide
// enough for "BTunes Home:", which is what the setting is called now that the
// folders inside it are the layout rather than five separate questions.
#define BT_NAME_WIDTH  92.0
#define BT_PATH_LEFT  116.0
// A note under a path starts out beside the field and stops twenty points short
// of the right edge. One under a tick box starts at the box's own words, so it
// runs wider.
#define BT_NOTE_WIDTH(w) ((w) - BT_PATH_LEFT - 20.0)
#define BT_BOX_NOTE_WIDTH(w) ((w) - 58.0)

// How tall a note is: asked of the field that draws it rather than of the words
// it holds. A field wraps a few points narrower than the frame it is given, so
// the same sentence measured as a string comes out a line short, and comes out
// a line short only at the widths where it matters. Verified against the words
// under Music at 400 points: the string says two lines and the field takes
// three.
static CGFloat BTNoteHeight(NSTextField *note, CGFloat width) {
    if ([[note stringValue] length] == 0) return 0.0;
    return ceil([[note cell] cellSizeForBounds:NSMakeRect(0, 0, width, 10000.0)].height);
}

// The air above a note, which a setting that carries no note does not want
// either.
static CGFloat BTGapAbove(CGFloat noteHeight, CGFloat gap) {
    return (noteHeight > 0.0) ? gap : 0.0;
}

// A clip view holds what it is given by the bottom, so a pane taller than the
// window opens showing its last setting, and shrinking the window walks the
// first ones out of sight. Flipped, it holds the pane by the top instead, which
// is where the settings start and where they stay through a resize.
@interface BTTopClipView : NSClipView
@end

@implementation BTTopClipView
- (BOOL)isFlipped { return YES; }
@end

// One setting in the pane: a path with a button to choose it, or a tick box.
// Either way a note may sit under it.
//
// One list of these rather than a list of paths and a list of boxes, because
// the box that turns on the alternative iTunes library sits between the paths
// and the path it reveals sits under the box. Two lists can only put every path
// before every box, and a row that comes and goes needs the pane's height and
// its layout to walk the same order.
@interface BTPrefsRow : NSObject
@property (nonatomic, assign) BOOL isBox;
@property (nonatomic, strong) NSTextField *name;      // a path's own name
@property (nonatomic, strong) NSTextField *field;     // and the path itself
@property (nonatomic, strong) NSButton *chooser;
// The height the button chose for itself, kept rather than read back from its
// frame: a rounded bezel draws at a height of its own choosing, and a row that
// has been away has no frame left to ask.
@property (nonatomic, assign) CGFloat chooserHeight;
@property (nonatomic, strong) NSButton *box;
@property (nonatomic, strong) NSTextField *note;
@property (nonatomic, assign) BOOL shown;
@end

@implementation BTPrefsRow

- (id)init {
    self = [super init];
    if (self) _shown = YES;
    return self;
}

- (CGFloat)controlHeight {
    return self.isBox ? BT_BOX : BT_FIELD;
}

// Every view of the row at once, so a row that is not shown neither draws nor
// takes a click at the place it would have been.
- (void)setShown:(BOOL)shown {
    _shown = shown;
    NSArray *views = @[self.name ?: [NSNull null], self.field ?: [NSNull null],
                       self.chooser ?: [NSNull null], self.box ?: [NSNull null],
                       self.note ?: [NSNull null]];
    NSUInteger i;
    for (i = 0; i < [views count]; i++) {
        id view = [views objectAtIndex:i];
        if (view != [NSNull null]) [view setHidden:!shown];
    }
}

@end

@implementation BTPreferencesController {
    // What the window shows through, and the pane it shows. The pane is as tall
    // as the settings need, which at any narrow width is taller than a small
    // screen, so the window is a window onto it rather than the whole of it.
    NSScrollView *_scroll;
    NSView *_pane;

    // Every setting the layout has to place, in the order it places them. Held
    // because the layout is redone whenever the window changes width: a note
    // wraps to a different number of lines and everything under it moves.
    NSMutableArray *_rows;

    NSTextField *_btunesHomeField;
    NSTextField *_iTunesHomeField;
    NSTextField *_iTunesXMLField;
    BTPrefsRow *_iTunesXMLRow;
    NSButton *_alternateXMLBox;
    NSButton *_losslessBox;
    NSButton *_lookupBox;
    NSButton *_evenVolumeBox;
    NSButton *_purpleBox;
}

+ (instancetype)sharedController {
    static BTPreferencesController *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[BTPreferencesController alloc] initPreferences]; });
    return shared;
}

// The rows the pane is shown to hold, whether or not each is showing at the
// moment. A note is a line, and a second line only where there is a second thing
// to know; a setting its own name explains carries none.
- (NSArray *)shownRows {
    NSMutableArray *shown = [NSMutableArray array];
    NSUInteger i;
    for (i = 0; i < [_rows count]; i++) {
        BTPrefsRow *row = [_rows objectAtIndex:i];
        if ([row shown]) [shown addObject:row];
    }
    return shown;
}

- (CGFloat)noteWidthForRow:(BTPrefsRow *)row inWidth:(CGFloat)width {
    // A note under a path starts beside the field; one under a tick box starts
    // at the box's own words, so it runs wider.
    return row.isBox ? BT_BOX_NOTE_WIDTH(width) : BT_NOTE_WIDTH(width);
}

- (CGFloat)gapAboveNoteForRow:(BTPrefsRow *)row height:(CGFloat)noteHeight {
    return BTGapAbove(noteHeight, row.isBox ? BT_BOX_TO_NOTE : BT_TO_NOTE);
}

// The pane is the sum of what goes in it: each control, the air under it, its
// note however many lines that turns out to be, and the air under that. It
// shortens as the window widens, since a wider note takes fewer lines to say
// the same thing, and shortens again when the alternative library is not asked
// for and its row is not there at all.
//
// The last row carries no step after it, because a step is the room made for
// whatever comes next and nothing does. The bottom margin is that room.
- (CGFloat)heightForWidth:(CGFloat)width {
    NSArray *rows = [self shownRows];
    if ([rows count] == 0) return 90.0;

    CGFloat total = 52.0 + [[rows objectAtIndex:0] controlHeight];
    NSUInteger i;
    for (i = 0; i < [rows count]; i++) {
        BTPrefsRow *row = [rows objectAtIndex:i];
        CGFloat note = BTNoteHeight(row.note, [self noteWidthForRow:row inWidth:width]);
        total += [self gapAboveNoteForRow:row height:note] + note;
        if (i + 1 < [rows count]) {
            total += BT_AFTER_NOTE + [[rows objectAtIndex:i + 1] controlHeight];
        }
    }
    return total + 38.0;
}

- (instancetype)initPreferences {
    // Opened at the width it was drawn for and at whatever height that width
    // turns out to need, which cannot be known until the notes exist to be
    // asked. The window is made at a nominal height and sized once they do.
    NSRect frame = NSMakeRect(0, 0, BT_PREFS_WIDTH, 400.0);
    NSWindow *window = [[BTPanelWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:@"Preferences"];
    [window setContentMinSize:NSMakeSize(BT_PREFS_MIN_WIDTH, BT_PREFS_MIN_HEIGHT)];

    self = [super initWithWindow:window];
    if (self == nil) return nil;

    _pane = [[NSView alloc] initWithFrame:frame];
    [self buildSettings];
    // Before the height is worked out, since it is what decides whether the
    // alternative library's row is one of the rows to make room for.
    [self refresh];

    _scroll = [[NSScrollView alloc] initWithFrame:[[window contentView] bounds]];
    [_scroll setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
    [_scroll setBorderType:NSNoBorder];
    [_scroll setHasVerticalScroller:YES];
    [_scroll setHasHorizontalScroller:NO];
    [_scroll setAutohidesScrollers:YES];
    [_scroll setDrawsBackground:YES];
    [_scroll setBackgroundColor:[NSColor windowBackgroundColor]];
    [_scroll setContentView:[[BTTopClipView alloc] initWithFrame:[[_scroll contentView] frame]]];
    [_scroll setDocumentView:_pane];
    [[window contentView] addSubview:_scroll];

    // The room to lay out in is what the clip view has, not what the window
    // has: a scroller showing takes fifteen points off it, and the notes wrap
    // to that width rather than to the window's.
    NSClipView *clip = [_scroll contentView];
    [clip setPostsFrameChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(roomChanged:)
                                                 name:NSViewFrameDidChangeNotification
                                               object:clip];

    [window setContentSize:NSMakeSize(BT_PREFS_WIDTH, [self heightForWidth:BT_PREFS_WIDTH])];
    [self openNoTallerThanTheScreen];
    [window center];
    [self layoutPane];
    [self showTopOfPane];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// The settings are made once and placed again on every resize, so nothing here
// decides where anything goes. Sizes that never change, such as the height a
// push button chooses for itself, are settled here and read back at layout.
- (void)buildSettings {
    _rows = [NSMutableArray array];

    // Two folders are chosen and everything else is worked out from them. What
    // sits inside each is the layout rather than a question put to the reader,
    // which is what keeps the next kind of file from becoming a third path.
    _btunesHomeField = [self addPathRowWithLabel:@"BTunes Home:"
                                            note:@"BTunes data files and imported music files (other than iTunes)"
                                          action:@selector(chooseBTunesHome:)];
    _iTunesHomeField = [self addPathRowWithLabel:@"iTunes Home:"
                                            note:@"BTunes never writes to this folder"
                                          action:@selector(chooseITunesHome:)];

    _alternateXMLBox = [self addBoxWithTitle:@"Use alternative iTunes XML"
                                        note:(@"Otherwise the library file inside the iTunes home is read\n"
                                              @"Make sure \"Share iTunes library XML\" is checked in iTunes")
                                      action:@selector(alternateXMLChanged:)];

    // Under the box that asks for it, and gone when it is not asked for. A field
    // naming a file that is not being read would be answering a question nobody
    // put.
    _iTunesXMLField = [self addPathRowWithLabel:@"XML file:"
                                           note:@""
                                         action:@selector(chooseITunesLibrary:)];
    _iTunesXMLRow = [_rows lastObject];

    _lookupBox = [self addBoxWithTitle:@"Look up CDs that do not provide track names"
                                  note:@"" action:@selector(lookupChanged:)];
    _losslessBox = [self addBoxWithTitle:@"Import CDs as Apple Lossless (ALAC) instead of AAC"
                                    note:@"" action:@selector(losslessChanged:)];
    _evenVolumeBox = [self addBoxWithTitle:@"Soundcheck"
                                      note:@"Plays songs at the same loudness as each other"
                                    action:@selector(evenVolumeChanged:)];
    _purpleBox = [self addBoxWithTitle:@"Purple mode" note:@"" action:@selector(purpleModeChanged:)];

    // Named in the colour it turns things, which says more than the words do.
    [_purpleBox setAttributedTitle:
        [[NSAttributedString alloc] initWithString:@"Purple mode"
                                       attributes:@{NSFontAttributeName: [BTStyle uiFont],
                                                    NSForegroundColorAttributeName: [BTStyle accent]}]];
}

// A window is pulled back onto the display as it is ordered front, so one built
// taller than the screen opens with its lower settings cut off and no way to
// reach them. Open no taller than there is room for; the rest is scrolled to.
- (void)openNoTallerThanTheScreen {
    NSWindow *window = [self window];
    NSScreen *screen = [window screen];
    if (screen == nil) screen = [NSScreen mainScreen];
    if (screen == nil) return;

    NSRect content = [window contentRectForFrameRect:[window frame]];
    CGFloat chrome = NSHeight([window frame]) - NSHeight(content);
    CGFloat most = NSHeight([screen visibleFrame]) - chrome;
    if (NSHeight(content) > most) {
        [window setContentSize:NSMakeSize(NSWidth(content), MAX(most, BT_PREFS_MIN_HEIGHT))];
    }
}

- (void)roomChanged:(NSNotification *)note {
    [self layoutPane];
}

- (void)layoutPane {
    NSSize room = [[_scroll contentView] bounds].size;
    if (room.width <= 0.0) return;

    // The pane is at least as tall as the window, so settings that take less
    // than a windowful fill it rather than leaving the scroller a stub of
    // travel to nowhere.
    CGFloat height = MAX([self heightForWidth:room.width], room.height);
    NSSize size = NSMakeSize(room.width, height);
    if (!NSEqualSizes(size, [_pane frame].size)) [_pane setFrameSize:size];
    [self placeSettingsInWidth:room.width fromTop:height];
}

// Said once at the start, since the clip view is flipped and holds its position
// from the top of the pane thereafter.
- (void)showTopOfPane {
    NSClipView *clip = [_scroll contentView];
    [clip scrollToPoint:NSZeroPoint];
    [_scroll reflectScrolledClipView:clip];
}

// Each row is placed at its own origin and extends upward from it, so the step
// down to the next one carries that next row's height. A path and a tick box are
// not the same height, and the two now alternate.
- (void)placeSettingsInWidth:(CGFloat)width fromTop:(CGFloat)top {
    NSArray *rows = [self shownRows];
    CGFloat y = top - 52.0;
    NSUInteger i;

    // A row that is not showing is left holding no ground at all, rather than
    // the frame it had when it last showed. Hidden is enough for the eye and not
    // enough for anything that reads the pane back.
    for (i = 0; i < [_rows count]; i++) {
        BTPrefsRow *row = [_rows objectAtIndex:i];
        if ([row shown]) continue;
        [row.name setFrame:NSZeroRect];
        [row.field setFrame:NSZeroRect];
        [row.chooser setFrame:NSZeroRect];
        [row.box setFrame:NSZeroRect];
        [row.note setFrame:NSZeroRect];
    }

    for (i = 0; i < [rows count]; i++) {
        BTPrefsRow *row = [rows objectAtIndex:i];
        CGFloat noteWidth = [self noteWidthForRow:row inWidth:width];
        CGFloat noteHeight = BTNoteHeight(row.note, noteWidth);
        CGFloat gap = [self gapAboveNoteForRow:row height:noteHeight];
        CGFloat noteLeft;

        if (row.isBox) {
            [row.box setFrame:NSMakeRect(20, y, width - 40, BT_BOX)];
            noteLeft = 38;
        } else {
            [row.name setFrame:NSMakeRect(20, y, BT_NAME_WIDTH, BT_NAME)];
            [row.field setFrame:NSMakeRect(BT_PATH_LEFT, y - 3,
                                           width - BT_PATH_LEFT - 120, BT_FIELD)];
            [row.chooser setFrame:NSMakeRect(width - 112, y - 3, 92, row.chooserHeight)];
            noteLeft = BT_PATH_LEFT;
        }

        [row.note setFrame:NSMakeRect(noteLeft, y - gap - noteHeight, noteWidth, noteHeight)];

        y -= gap + noteHeight + BT_AFTER_NOTE;
        if (i + 1 < [rows count]) y -= [[rows objectAtIndex:i + 1] controlHeight];
    }
}

- (void)lookupChanged:(id)sender {
    [[BTPreferences sharedPreferences] setLooksUpDiscs:([_lookupBox state] == NSOnState)];
}

- (void)losslessChanged:(id)sender {
    [[BTPreferences sharedPreferences] setImportsLossless:([_losslessBox state] == NSOnState)];
}

- (void)evenVolumeChanged:(id)sender {
    [[BTPreferences sharedPreferences] setEvensOutVolume:([_evenVolumeBox state] == NSOnState)];
}

- (void)purpleModeChanged:(id)sender {
    [[BTPreferences sharedPreferences] setPurpleMode:([_purpleBox state] == NSOnState)];
}

// The note under each row is the small gray one; the row's own name is not.
- (NSTextField *)labelWithText:(NSString *)text small:(BOOL)small {
    NSTextField *label = BTLabelWithText(text, (small ? [BTStyle smallFont] : [BTStyle uiFont]));
    if (small) [label setTextColor:[BTStyle secondaryText]];
    [[label cell] setLineBreakMode:NSLineBreakByWordWrapping];
    return label;
}

- (NSTextField *)addPathRowWithLabel:(NSString *)labelText
                                note:(NSString *)noteText
                              action:(SEL)action {
    BTPrefsRow *row = [[BTPrefsRow alloc] init];

    row.name = [self labelWithText:labelText small:NO];
    [_pane addSubview:row.name];

    row.field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [row.field setEditable:NO];
    [row.field setSelectable:YES];
    [row.field setFont:[BTStyle uiFont]];
    [[row.field cell] setLineBreakMode:NSLineBreakByTruncatingHead];
    [_pane addSubview:row.field];

    // Made at the height it asks for, which the layout then leaves alone: a
    // rounded bezel draws at a height of its own choosing.
    row.chooser = [BTPushButton buttonWithTitle:@"Choose..." target:self action:action];
    row.chooserHeight = NSHeight([row.chooser frame]);
    [_pane addSubview:row.chooser];

    row.note = [self labelWithText:noteText small:YES];
    [_pane addSubview:row.note];

    [_rows addObject:row];
    return row.field;
}

// A choice about how BTunes behaves rather than about where something lives,
// which is why none of these is a path to choose. The note sits under the box at
// the same left edge as the words beside it, the way a path's note does.
- (NSButton *)addBoxWithTitle:(NSString *)title note:(NSString *)noteText action:(SEL)action {
    BTPrefsRow *row = [[BTPrefsRow alloc] init];
    row.isBox = YES;

    row.box = [[NSButton alloc] initWithFrame:NSZeroRect];
    [row.box setButtonType:NSSwitchButton];
    [row.box setFont:[BTStyle uiFont]];
    [row.box setTitle:title];
    [row.box setTarget:self];
    [row.box setAction:action];
    [_pane addSubview:row.box];

    row.note = [self labelWithText:noteText small:YES];
    [_pane addSubview:row.note];

    [_rows addObject:row];
    return row.box;
}

- (void)refresh {
    BTPreferences *prefs = [BTPreferences sharedPreferences];
    [_btunesHomeField setStringValue:[prefs btunesHome]];
    [_iTunesHomeField setStringValue:[prefs iTunesHome]];

    BOOL alternate = [prefs usesAlternateITunesLibrary];
    [_alternateXMLBox setState:(alternate ? NSOnState : NSOffState)];
    [_iTunesXMLRow setShown:alternate];
    [_iTunesXMLField setStringValue:[prefs iTunesLibraryPath]];

    [_losslessBox setState:([prefs importsLossless] ? NSOnState : NSOffState)];
    [_lookupBox setState:([prefs looksUpDiscs] ? NSOnState : NSOffState)];
    [_evenVolumeBox setState:([prefs evensOutVolume] ? NSOnState : NSOffState)];
    [_purpleBox setState:([prefs purpleMode] ? NSOnState : NSOffState)];
}

- (NSString *)chooseFolderStartingAt:(NSString *)current {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setCanCreateDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setPrompt:@"Choose"];
    if ([current length] > 0) {
        [panel setDirectoryURL:[NSURL fileURLWithPath:current]];
    }
    if ([panel runModal] != NSFileHandlingPanelOKButton) return nil;
    return [[[panel URLs] objectAtIndex:0] path];
}

// A file rather than a folder, and only an XML one.
- (void)chooseITunesLibrary:(id)sender {
    BTPreferences *prefs = [BTPreferences sharedPreferences];
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setAllowedFileTypes:@[@"xml"]];
    [panel setPrompt:@"Choose"];
    [panel setMessage:@"Choose an iTunes library XML file. It is read, never written."];

    NSString *current = [prefs iTunesLibraryPath];
    if ([current length] > 0) {
        [panel setDirectoryURL:[NSURL fileURLWithPath:[current stringByDeletingLastPathComponent]]];
    }
    if ([panel runModal] != NSFileHandlingPanelOKButton) return;

    [prefs setITunesLibraryPath:[[[panel URLs] objectAtIndex:0] path]];
    [self refresh];
}

- (void)chooseITunesHome:(id)sender {
    NSString *chosen = [self chooseFolderStartingAt:[[BTPreferences sharedPreferences] iTunesHome]];
    if (chosen == nil) return;
    [[BTPreferences sharedPreferences] setITunesHome:chosen];
    [self refresh];
}

// The database sits inside this folder, so choosing another one is choosing
// another library as well as another place for the songs BTunes made.
- (void)chooseBTunesHome:(id)sender {
    BTLibrary *library = [BTLibrary sharedLibrary];
    NSString *chosen = [self chooseFolderStartingAt:[[BTPreferences sharedPreferences] btunesHome]];
    if (chosen == nil) return;

    // The library in hand is written out to where it came from before the
    // setting moves, so nothing in progress is lost. Whatever is at the new
    // location is then read; an empty folder starts an empty library.
    [library saveToDisk];
    [[BTPreferences sharedPreferences] setBtunesHome:chosen];
    [library loadFromDisk];
    [library noteChanged];
    [self refresh];

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"The BTunes folder changed."];
    [alert setInformativeText:[NSString stringWithFormat:
        @"BTunes now keeps its database and the music it imports in %@. "
        @"Songs already in the library stay where they are.", chosen]];
    [alert runModal];
}

// Ticked means a file has been named; unticked means the library inside the
// iTunes home is read. There is no third state to keep, so the tick is the
// presence of the setting rather than a setting of its own.
- (void)alternateXMLChanged:(id)sender {
    BTPreferences *prefs = [BTPreferences sharedPreferences];
    if ([_alternateXMLBox state] == NSOnState) {
        [prefs setITunesLibraryPath:[prefs suggestedAlternateITunesLibraryPath]];
    } else {
        [prefs setITunesLibraryPath:nil];
    }
    [self refresh];
    [self sizeWindowToSettings];
}

// The window follows the settings when a row comes or goes, rather than leaving
// blank space under them or a scroller with one row's worth of travel. Still no
// taller than the screen, which is the rule a window built from its contents has
// to keep either way.
- (void)sizeWindowToSettings {
    NSWindow *window = [self window];
    NSRect content = [window contentRectForFrameRect:[window frame]];
    [window setContentSize:NSMakeSize(NSWidth(content), [self heightForWidth:NSWidth(content)])];
    [self openNoTallerThanTheScreen];
    [self layoutPane];
    [self showTopOfPane];
}

@end
