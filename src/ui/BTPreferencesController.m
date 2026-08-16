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
// A note under a path starts out beside the field and stops twenty points short
// of the right edge. One under a tick box starts at the box's own words, so it
// runs wider.
#define BT_NOTE_WIDTH(w) ((w) - 104.0)
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

// Escape closes the window. Every setting here takes effect as it is made, so
// there is nothing to cancel and nothing to confirm, and the key is simply the
// way out that a window with no buttons along its foot still ought to have.
//
// Answered twice, because Escape arrives by two roads. A field being typed in
// turns it into cancelOperation:, which the field editor sends up the chain
// after using the first press to put back what was in the field. A tick box
// holding the keyboard, or nothing holding it at all, leaves it a plain key
// press that reaches the window unanswered.
@interface BTPreferencesWindow : NSWindow
@end

@implementation BTPreferencesWindow

- (void)cancelOperation:(id)sender {
    [self performClose:sender];
}

- (void)keyDown:(NSEvent *)event {
    if ([[event charactersIgnoringModifiers] isEqualToString:@"\033"]) {
        [self performClose:self];
        return;
    }
    [super keyDown:event];
}

@end

@implementation BTPreferencesController {
    // What the window shows through, and the pane it shows. The pane is as tall
    // as the settings need, which at any narrow width is taller than a small
    // screen, so the window is a window onto it rather than the whole of it.
    NSScrollView *_scroll;
    NSView *_pane;

    // Every view the layout has to place, in the order it places them. Held
    // because the layout is redone whenever the window changes width: a note
    // wraps to a different number of lines and everything under it moves.
    NSMutableArray *_names;
    NSMutableArray *_paths;
    NSMutableArray *_choosers;
    NSMutableArray *_pathNotes;
    NSMutableArray *_boxes;
    NSMutableArray *_boxNotes;

    NSTextField *_musicField;
    NSTextField *_databaseField;
    NSTextField *_iTunesField;
    NSTextField *_detuneField;
    NSTextField *_btunesField;
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

// The five paths, in the order they are shown: what each is called, and the
// note under it. A note is a line, and a second line only where there is a
// second thing to know; a setting its own name explains carries none.
+ (NSArray *)settingRows {
    return @[
        @[@"Music:", @"Folder of music files (e.g. iTunes library)\nNothing there modified"],
        @[@"Library:", @"Where BTunes stores its data"],
        @[@"iTunes:", (@"iTunes XML library from which to import playlists and songs\n"
                       @"Make sure \"Share iTunes library XML\" is checked in iTunes")],
        @[@"Detune:", @"Free recordings of iTunes protected music"],
        @[@"BTunes:", @"Music BTunes records or imports (other than via iTunes)"],
    ];
}

// The tick boxes, in the order they are shown: what each says, and the note
// under it. Three of the four say the whole of it themselves.
+ (NSArray *)boxRows {
    return @[
        @[@"Look up CDs that do not provide track names", @""],
        @[@"Import CDs as Apple Lossless (ALAC) instead of AAC", @""],
        @[@"Soundcheck", @"Plays songs at the same loudness as each other"],
        @[@"Purple mode", @""],
    ];
}

// The pane is the sum of what goes in it: the paths, each a field, the air
// under it, its note however many lines that turns out to be, and the air under
// that; then the tick boxes, whose notes run to different lengths too. It
// shortens as the window widens, since a wider note takes fewer lines to say
// the same thing.
//
// The last box carries no step after it, because a step is the room made for
// whatever comes next and nothing does. The bottom margin is that room.
- (CGFloat)heightForWidth:(CGFloat)width {
    CGFloat total = 52.0;
    NSUInteger i;
    for (i = 0; i < [_pathNotes count]; i++) {
        CGFloat note = BTNoteHeight([_pathNotes objectAtIndex:i], BT_NOTE_WIDTH(width));
        total += BT_FIELD + BTGapAbove(note, BT_TO_NOTE) + note + BT_AFTER_NOTE;
    }

    for (i = 0; i < [_boxNotes count]; i++) {
        CGFloat note = BTNoteHeight([_boxNotes objectAtIndex:i], BT_BOX_NOTE_WIDTH(width));
        total += BTGapAbove(note, BT_BOX_TO_NOTE) + note;
        if (i + 1 < [_boxNotes count]) total += BT_AFTER_NOTE + BT_BOX;
    }
    return total + 38.0;
}

- (instancetype)initPreferences {
    // Opened at the width it was drawn for and at whatever height that width
    // turns out to need, which cannot be known until the notes exist to be
    // asked. The window is made at a nominal height and sized once they do.
    NSRect frame = NSMakeRect(0, 0, BT_PREFS_WIDTH, 400.0);
    NSWindow *window = [[BTPreferencesWindow alloc]
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
    [self refresh];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// The settings are made once and placed again on every resize, so nothing here
// decides where anything goes. Sizes that never change, such as the height a
// push button chooses for itself, are settled here and read back at layout.
- (void)buildSettings {
    _names = [NSMutableArray array];
    _paths = [NSMutableArray array];
    _choosers = [NSMutableArray array];
    _pathNotes = [NSMutableArray array];
    _boxes = [NSMutableArray array];
    _boxNotes = [NSMutableArray array];

    NSArray *rows = [BTPreferencesController settingRows];
    SEL actions[] = { @selector(chooseMusicFolder:), @selector(chooseDatabaseFolder:),
                      @selector(chooseITunesLibrary:), @selector(chooseDetuneFolder:),
                      @selector(chooseBTunesFolder:) };
    NSTextField *__strong *fields[] = { &_musicField, &_databaseField, &_iTunesField,
                                        &_detuneField, &_btunesField };
    NSUInteger row;
    for (row = 0; row < [rows count]; row++) {
        *fields[row] = [self addRowWithLabel:[[rows objectAtIndex:row] objectAtIndex:0]
                                        note:[[rows objectAtIndex:row] objectAtIndex:1]
                                      action:actions[row]];
    }

    // The boxes, in the order boxRows names them. Each is a choice about how
    // BTunes behaves rather than about where something lives, which is why none
    // of them is a sixth path to choose.
    NSArray *boxes = [BTPreferencesController boxRows];
    SEL boxActions[] = { @selector(lookupChanged:), @selector(losslessChanged:),
                         @selector(evenVolumeChanged:), @selector(purpleModeChanged:) };
    NSButton *__strong *boxFields[] = { &_lookupBox, &_losslessBox,
                                        &_evenVolumeBox, &_purpleBox };
    NSUInteger box;
    for (box = 0; box < [boxes count]; box++) {
        NSString *title = [[boxes objectAtIndex:box] objectAtIndex:0];
        NSString *note = [[boxes objectAtIndex:box] objectAtIndex:1];

        NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
        [button setButtonType:NSSwitchButton];
        [button setFont:[BTStyle uiFont]];
        [button setTitle:title];
        [button setTarget:self];
        [button setAction:boxActions[box]];
        [_pane addSubview:button];
        [_boxes addObject:button];
        *boxFields[box] = button;

        // The note sits under the box at the same left edge as the words beside
        // it, the way the notes under the paths do.
        NSTextField *label = [self labelWithText:note small:YES];
        [_pane addSubview:label];
        [_boxNotes addObject:label];
    }

    // Named in the colour it turns things, which says more than the words do.
    [_purpleBox setAttributedTitle:
        [[NSAttributedString alloc] initWithString:[[boxes lastObject] objectAtIndex:0]
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

- (void)placeSettingsInWidth:(CGFloat)width fromTop:(CGFloat)top {
    CGFloat noteWidth = BT_NOTE_WIDTH(width);
    CGFloat boxNoteWidth = BT_BOX_NOTE_WIDTH(width);
    CGFloat y = top - 52.0;
    NSUInteger i;

    for (i = 0; i < [_paths count]; i++) {
        [[_names objectAtIndex:i] setFrame:NSMakeRect(20, y, 60, BT_NAME)];
        [[_paths objectAtIndex:i] setFrame:NSMakeRect(84, y - 3, width - 84 - 120, BT_FIELD)];

        NSButton *choose = [_choosers objectAtIndex:i];
        [choose setFrame:NSMakeRect(width - 112, y - 3, 92, NSHeight([choose frame]))];

        NSTextField *note = [_pathNotes objectAtIndex:i];
        CGFloat noteHeight = BTNoteHeight(note, noteWidth);
        CGFloat gap = BTGapAbove(noteHeight, BT_TO_NOTE);
        [note setFrame:NSMakeRect(84, y - gap - noteHeight, noteWidth, noteHeight)];

        y -= gap + noteHeight + BT_AFTER_NOTE + BT_FIELD;
    }

    for (i = 0; i < [_boxes count]; i++) {
        [[_boxes objectAtIndex:i] setFrame:NSMakeRect(20, y, width - 40, BT_BOX)];

        NSTextField *note = [_boxNotes objectAtIndex:i];
        CGFloat noteHeight = BTNoteHeight(note, boxNoteWidth);
        CGFloat gap = BTGapAbove(noteHeight, BT_BOX_TO_NOTE);
        [note setFrame:NSMakeRect(38, y - gap - noteHeight, boxNoteWidth, noteHeight)];

        // The next box sits at its own origin and extends upward, so its height
        // comes off here too. Without it the note above runs straight into it.
        y -= gap + noteHeight + BT_AFTER_NOTE + BT_BOX;
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

- (NSTextField *)addRowWithLabel:(NSString *)labelText
                            note:(NSString *)noteText
                          action:(SEL)action {
    NSTextField *name = [self labelWithText:labelText small:NO];
    [_pane addSubview:name];
    [_names addObject:name];

    NSTextField *path = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [path setEditable:NO];
    [path setSelectable:YES];
    [path setFont:[BTStyle uiFont]];
    [[path cell] setLineBreakMode:NSLineBreakByTruncatingHead];
    [_pane addSubview:path];
    [_paths addObject:path];

    // Made at the height it asks for, which the layout then leaves alone: a
    // rounded bezel draws at a height of its own choosing.
    BTPushButton *choose = [BTPushButton buttonWithTitle:@"Choose..." target:self action:action];
    [_pane addSubview:choose];
    [_choosers addObject:choose];

    NSTextField *note = [self labelWithText:noteText small:YES];
    [_pane addSubview:note];
    [_pathNotes addObject:note];

    return path;
}

- (void)refresh {
    BTPreferences *prefs = [BTPreferences sharedPreferences];
    [_musicField setStringValue:[prefs musicFolder]];
    [_databaseField setStringValue:[prefs databaseFolder]];
    [_iTunesField setStringValue:[prefs iTunesLibraryPath]];
    // Said outright rather than left blank, because an empty box beside a name
    // reads as a setting that failed to load rather than one not yet made.
    NSString *detune = [prefs detuneFolder];
    [_detuneField setStringValue:([detune length] > 0 ? detune : @"None chosen")];
    [_btunesField setStringValue:[prefs btunesFolder]];
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

// Choosing the folder that holds the map, not the map itself, since the folder
// is the thing that moves and the audio is found relative to it.
// Made if it is not there yet, since this is a folder BTunes owns rather than
// one it is being pointed at.
- (void)chooseBTunesFolder:(id)sender {
    NSString *chosen = [self chooseFolderStartingAt:[[BTPreferences sharedPreferences] btunesFolder]];
    if (chosen == nil) return;
    [[BTPreferences sharedPreferences] setBtunesFolder:chosen];
    [self refresh];
}

- (void)chooseDetuneFolder:(id)sender {
    NSString *chosen = [self chooseFolderStartingAt:[[BTPreferences sharedPreferences] detuneFolder]];
    if (chosen == nil) return;

    // Said now rather than discovered at the next sync, when the reason nothing
    // came unlocked would be a great deal harder to work out.
    NSString *map = [chosen stringByAppendingPathComponent:@"detune-mapping.json"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:map]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"That folder holds no detune-mapping.json."];
        [alert setInformativeText:@"Choose the folder the map sits in. Without it nothing can be matched, and locked songs stay locked."];
        [alert runModal];
        return;
    }

    [[BTPreferences sharedPreferences] setDetuneFolder:chosen];
    [self refresh];
}

- (void)chooseMusicFolder:(id)sender {
    NSString *chosen = [self chooseFolderStartingAt:[[BTPreferences sharedPreferences] musicFolder]];
    if (chosen == nil) return;
    [[BTPreferences sharedPreferences] setMusicFolder:chosen];
    [self refresh];
}

- (void)chooseDatabaseFolder:(id)sender {
    BTLibrary *library = [BTLibrary sharedLibrary];
    NSString *chosen = [self chooseFolderStartingAt:[[BTPreferences sharedPreferences] databaseFolder]];
    if (chosen == nil) return;

    // The library in hand is written out to where it came from before the
    // setting moves, so nothing in progress is lost. Whatever is at the new
    // location is then read; an empty folder starts an empty library.
    [library saveToDisk];
    [[BTPreferences sharedPreferences] setDatabaseFolder:chosen];
    [library loadFromDisk];
    [library noteChanged];
    [self refresh];

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"The library location changed."];
    [alert setInformativeText:[NSString stringWithFormat:
        @"BTunes now reads and writes its database in %@. Songs stay where they are.", chosen]];
    [alert runModal];
}

@end
