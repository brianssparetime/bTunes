#import "BTPreferencesController.h"
#import "BTPreferences.h"
#import "BTLibrary.h"
#import "BTStyle.h"
#import "BTControls.h"

#define BT_PREFS_WIDTH  520.0
#define BT_PREFS_HEIGHT 416.0

@implementation BTPreferencesController {
    NSTextField *_musicField;
    NSTextField *_databaseField;
    NSTextField *_iTunesField;
    NSTextField *_detuneField;
    NSButton *_purpleBox;
}

+ (instancetype)sharedController {
    static BTPreferencesController *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[BTPreferencesController alloc] initPreferences]; });
    return shared;
}

- (instancetype)initPreferences {
    NSRect frame = NSMakeRect(0, 0, BT_PREFS_WIDTH, BT_PREFS_HEIGHT);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"Preferences"];
    [window center];

    self = [super initWithWindow:window];
    if (self == nil) return nil;

    NSView *content = [window contentView];
    CGFloat y = BT_PREFS_HEIGHT - 52.0;

    _musicField = [self addRowAtY:&y
                            label:@"Music:"
                             note:@"The folder the music sits in. Songs are recorded as their place below it, so pointing this at the same music on another machine opens the same library there."
                           action:@selector(chooseMusicFolder:)
                          inView:content];

    _databaseField = [self addRowAtY:&y
                               label:@"Library:"
                                note:@"Where BTunes keeps its own database: ratings, play counts, and playlists. Songs are not moved."
                              action:@selector(chooseDatabaseFolder:)
                             inView:content];

    _iTunesField = [self addRowAtY:&y
                             label:@"iTunes:"
                              note:@"The iTunes library file a sync reads. It is only ever read, never written. Point it at a copy while trying something out."
                            action:@selector(chooseITunesLibrary:)
                            inView:content];

    _detuneField = [self addRowAtY:&y
                             label:@"Detune:"
                              note:@"The folder of free recordings standing in for locked purchases. Leave it empty until there is one: locked songs then simply stay locked. Choose the folder holding detune-mapping.json."
                            action:@selector(chooseDetuneFolder:)
                            inView:content];

    // Its own row rather than a fifth path to choose: this is a choice about
    // how the window looks, not about where something lives. The note sits
    // under it at the same left edge as the words beside the box, the way the
    // notes under the three paths do.
    _purpleBox = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 300, 18)];
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

    [content addSubview:[self labelWithText:@"Draws the main window in purple instead of blue. The mini player is purple either way."
                                      frame:NSMakeRect(38, y - 26, BT_PREFS_WIDTH - 58, 28)
                                      small:YES]];

    [self refresh];
    return self;
}

- (void)purpleModeChanged:(id)sender {
    [[BTPreferences sharedPreferences] setPurpleMode:([_purpleBox state] == NSOnState)];
}

// The note under each row is the small gray one; the row's own name is not.
- (NSTextField *)labelWithText:(NSString *)text frame:(NSRect)frame small:(BOOL)small {
    NSTextField *label = BTLabelWithText(text, (small ? [BTStyle smallFont] : [BTStyle uiFont]));
    [label setFrame:frame];
    if (small) [label setTextColor:[NSColor colorWithCalibratedWhite:0.35 alpha:1.0]];
    [[label cell] setLineBreakMode:NSLineBreakByWordWrapping];
    return label;
}

- (NSTextField *)addRowAtY:(CGFloat *)y
                     label:(NSString *)labelText
                      note:(NSString *)noteText
                    action:(SEL)action
                    inView:(NSView *)content {
    [content addSubview:[self labelWithText:labelText
                                      frame:NSMakeRect(20, *y, 60, 17)
                                      small:NO]];

    NSTextField *path = [[NSTextField alloc] initWithFrame:NSMakeRect(84, *y - 3, BT_PREFS_WIDTH - 84 - 120, 22)];
    [path setEditable:NO];
    [path setSelectable:YES];
    [path setFont:[BTStyle uiFont]];
    [[path cell] setLineBreakMode:NSLineBreakByTruncatingHead];
    [content addSubview:path];

    BTPushButton *choose = [BTPushButton buttonWithTitle:@"Choose..." target:self action:action];
    [choose setFrame:NSMakeRect(BT_PREFS_WIDTH - 112, *y - 3, 92, NSHeight([choose frame]))];
    [content addSubview:choose];

    *y -= 24.0;
    [content addSubview:[self labelWithText:noteText
                                      frame:NSMakeRect(84, *y - 18, BT_PREFS_WIDTH - 104, 32)
                                      small:YES]];
    *y -= 56.0;
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
