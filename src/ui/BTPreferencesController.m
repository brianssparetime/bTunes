#import "BTPreferencesController.h"
#import "BTPreferences.h"
#import "BTLibrary.h"
#import "BTStyle.h"
#import "BTControls.h"

#define BT_PREFS_WIDTH  520.0

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
#define BT_NOTE_WIDTH (BT_PREFS_WIDTH - 104.0)

// How tall a note is: asked of its own words rather than counted in lines. The
// measuring belongs to the palette, since the burn dialog wants the same answer
// about its own wrapping lines; a note is always in the small face, which is the
// whole of what this adds.
static CGFloat BTNoteHeight(NSString *text, CGFloat width) {
    return [BTStyle heightForText:text font:[BTStyle smallFont] width:width];
}

@implementation BTPreferencesController {
    NSTextField *_musicField;
    NSTextField *_databaseField;
    NSTextField *_iTunesField;
    NSTextField *_detuneField;
    NSTextField *_btunesField;
    NSButton *_losslessBox;
    NSButton *_lookupBox;
    NSButton *_purpleBox;
}

+ (instancetype)sharedController {
    static BTPreferencesController *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[BTPreferencesController alloc] initPreferences]; });
    return shared;
}

// The four paths, in the order they are shown. Held together so the window can
// be measured before it is built: how tall it has to be is the sum of what goes
// in it, and what goes in it includes four notes of different lengths.
+ (NSArray *)settingRows {
    return @[
        @[@"Music:", @"The folder the music sits in. Songs are recorded as their place below it, so pointing this at the same music on another machine opens the same library there."],
        @[@"Library:", @"Where BTunes keeps its own database: ratings, play counts, and playlists. Songs are not moved."],
        @[@"iTunes:", @"The iTunes library file a sync reads. It is only ever read, never written. Point it at a copy while trying something out."],
        @[@"Detune:", @"The folder of free recordings standing in for locked purchases. Leave it empty until there is one: locked songs then simply stay locked. Choose the folder holding detune-mapping.json."],
        @[@"BTunes:", @"Where BTunes puts music it makes itself, which today means songs taken off a CD. Laid out the way iTunes lays one out, artist then album, and kept apart from the iTunes folder because that folder belongs to iTunes."],
    ];
}

+ (NSString *)losslessNote {
    return @"A CD is about six hundred megabytes as it stands, half that as Apple Lossless, "
           @"and a tenth as AAC. Lossless is exact; AAC is what iTunes used and what fits.";
}

+ (NSString *)lookupNote {
    return @"Most CDs do not say what their songs are called. This asks MusicBrainz, "
           @"which is the only thing BTunes sends anywhere: the disc's table of contents "
           @"boiled down to a number, and nothing about your library.";
}

+ (NSString *)purpleNote {
    return @"Draws the main window in purple instead of blue. The mini player is purple either way.";
}

// One setting down to the next: the field, the air under it, its note however
// many lines that turns out to be, and the air under that.
+ (CGFloat)stepForNote:(NSString *)note {
    return BT_FIELD + BT_TO_NOTE + BTNoteHeight(note, BT_NOTE_WIDTH) + BT_AFTER_NOTE;
}

// The window is the sum of what goes in it. Four settings whose notes run to
// different lengths, then purple mode with its own, over a top and bottom
// margin.
+ (CGFloat)windowHeight {
    CGFloat total = 52.0;
    NSArray *rows = [self settingRows];
    NSUInteger i;
    for (i = 0; i < [rows count]; i++) {
        total += [self stepForNote:[[rows objectAtIndex:i] objectAtIndex:1]];
    }
    total += BT_BOX_TO_NOTE + BTNoteHeight([self lookupNote], BT_PREFS_WIDTH - 58.0)
           + BT_AFTER_NOTE + BT_BOX;
    total += BT_BOX_TO_NOTE + BTNoteHeight([self losslessNote], BT_PREFS_WIDTH - 58.0)
           + BT_AFTER_NOTE + BT_BOX;
    return total + BT_BOX_TO_NOTE + BTNoteHeight([self purpleNote], BT_PREFS_WIDTH - 58.0) + 38.0;
}

- (instancetype)initPreferences {
    NSRect frame = NSMakeRect(0, 0, BT_PREFS_WIDTH, [BTPreferencesController windowHeight]);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"Preferences"];
    [window center];

    self = [super initWithWindow:window];
    if (self == nil) return nil;

    NSView *content = [window contentView];
    CGFloat y = [BTPreferencesController windowHeight] - 52.0;

    NSArray *rows = [BTPreferencesController settingRows];
    SEL actions[] = { @selector(chooseMusicFolder:), @selector(chooseDatabaseFolder:),
                      @selector(chooseITunesLibrary:), @selector(chooseDetuneFolder:),
                      @selector(chooseBTunesFolder:) };
    NSTextField *__strong *fields[] = { &_musicField, &_databaseField, &_iTunesField,
                                        &_detuneField, &_btunesField };
    NSUInteger row;
    for (row = 0; row < [rows count]; row++) {
        *fields[row] = [self addRowAtY:&y
                                 label:[[rows objectAtIndex:row] objectAtIndex:0]
                                  note:[[rows objectAtIndex:row] objectAtIndex:1]
                                action:actions[row]
                                inView:content];
    }

    _lookupBox = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 400, BT_BOX)];
    [_lookupBox setButtonType:NSSwitchButton];
    [_lookupBox setFont:[BTStyle uiFont]];
    [_lookupBox setTitle:@"Look up CDs that do not name themselves"];
    [_lookupBox setTarget:self];
    [_lookupBox setAction:@selector(lookupChanged:)];
    [content addSubview:_lookupBox];

    NSString *lookupNote = [BTPreferencesController lookupNote];
    CGFloat lookupHeight = BTNoteHeight(lookupNote, BT_PREFS_WIDTH - 58.0);
    [content addSubview:[self labelWithText:lookupNote
                                      frame:NSMakeRect(38, y - BT_BOX_TO_NOTE - lookupHeight,
                                                       BT_PREFS_WIDTH - 58, lookupHeight)
                                      small:YES]];
    y -= BT_BOX_TO_NOTE + lookupHeight + BT_AFTER_NOTE + BT_BOX;

    _losslessBox = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 400, BT_BOX)];
    [_losslessBox setButtonType:NSSwitchButton];
    [_losslessBox setFont:[BTStyle uiFont]];
    [_losslessBox setTitle:@"Take CDs in as Apple Lossless"];
    [_losslessBox setTarget:self];
    [_losslessBox setAction:@selector(losslessChanged:)];
    [content addSubview:_losslessBox];

    NSString *losslessNote = [BTPreferencesController losslessNote];
    CGFloat losslessHeight = BTNoteHeight(losslessNote, BT_PREFS_WIDTH - 58.0);
    [content addSubview:[self labelWithText:losslessNote
                                      frame:NSMakeRect(38, y - BT_BOX_TO_NOTE - losslessHeight,
                                                       BT_PREFS_WIDTH - 58, losslessHeight)
                                      small:YES]];
    // The box below sits at its origin and extends upward, so its own height
    // comes off too. Without it the note above runs straight into it.
    y -= BT_BOX_TO_NOTE + losslessHeight + BT_AFTER_NOTE + BT_BOX;

    // Its own row rather than a sixth path to choose: this is a choice about
    // how the window looks, not about where something lives. The note sits
    // under it at the same left edge as the words beside the box, the way the
    // notes under the three paths do.
    _purpleBox = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 300, BT_BOX)];
    [_purpleBox setButtonType:NSSwitchButton];
    [_purpleBox setFont:[BTStyle uiFont]];
    // Named in the colour it turns things, which says more than the words do.
    [_purpleBox setAttributedTitle:
        [[NSAttributedString alloc] initWithString:@"Purple mode"
                                       attributes:@{NSFontAttributeName: [BTStyle uiFont],
                                                    NSForegroundColorAttributeName: [BTStyle accent]}]];
    [_purpleBox setTarget:self];
    [_purpleBox setAction:@selector(purpleModeChanged:)];
    [content addSubview:_purpleBox];

    NSString *purpleNote = [BTPreferencesController purpleNote];
    CGFloat purpleHeight = BTNoteHeight(purpleNote, BT_PREFS_WIDTH - 58.0);
    [content addSubview:[self labelWithText:purpleNote
                                      frame:NSMakeRect(38, y - BT_BOX_TO_NOTE - purpleHeight,
                                                       BT_PREFS_WIDTH - 58, purpleHeight)
                                      small:YES]];

    [self refresh];
    return self;
}

- (void)lookupChanged:(id)sender {
    [[BTPreferences sharedPreferences] setLooksUpDiscs:([_lookupBox state] == NSOnState)];
}

- (void)losslessChanged:(id)sender {
    [[BTPreferences sharedPreferences] setImportsLossless:([_losslessBox state] == NSOnState)];
}

- (void)purpleModeChanged:(id)sender {
    [[BTPreferences sharedPreferences] setPurpleMode:([_purpleBox state] == NSOnState)];
}

// The note under each row is the small gray one; the row's own name is not.
- (NSTextField *)labelWithText:(NSString *)text frame:(NSRect)frame small:(BOOL)small {
    NSTextField *label = BTLabelWithText(text, (small ? [BTStyle smallFont] : [BTStyle uiFont]));
    [label setFrame:frame];
    if (small) [label setTextColor:[BTStyle secondaryText]];
    [[label cell] setLineBreakMode:NSLineBreakByWordWrapping];
    return label;
}

- (NSTextField *)addRowAtY:(CGFloat *)y
                     label:(NSString *)labelText
                      note:(NSString *)noteText
                    action:(SEL)action
                    inView:(NSView *)content {
    [content addSubview:[self labelWithText:labelText
                                      frame:NSMakeRect(20, *y, 60, BT_NAME)
                                      small:NO]];

    NSTextField *path = [[NSTextField alloc] initWithFrame:NSMakeRect(84, *y - 3, BT_PREFS_WIDTH - 84 - 120, BT_FIELD)];
    [path setEditable:NO];
    [path setSelectable:YES];
    [path setFont:[BTStyle uiFont]];
    [[path cell] setLineBreakMode:NSLineBreakByTruncatingHead];
    [content addSubview:path];

    BTPushButton *choose = [BTPushButton buttonWithTitle:@"Choose..." target:self action:action];
    [choose setFrame:NSMakeRect(BT_PREFS_WIDTH - 112, *y - 3, 92, NSHeight([choose frame]))];
    [content addSubview:choose];

    CGFloat noteHeight = BTNoteHeight(noteText, BT_NOTE_WIDTH);
    [content addSubview:[self labelWithText:noteText
                                      frame:NSMakeRect(84, *y - BT_TO_NOTE - noteHeight,
                                                       BT_NOTE_WIDTH, noteHeight)
                                      small:YES]];
    *y -= BT_TO_NOTE + noteHeight + BT_AFTER_NOTE + BT_FIELD;
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
