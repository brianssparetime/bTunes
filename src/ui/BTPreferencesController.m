#import "BTPreferencesController.h"
#import "BTPreferences.h"
#import "BTLibrary.h"
#import "BTStyle.h"

#define BT_PREFS_WIDTH  520.0
#define BT_PREFS_HEIGHT 210.0

@implementation BTPreferencesController {
    NSTextField *_musicField;
    NSTextField *_databaseField;
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
                             note:@"Where the audio files live. Adding songs starts here, and this is what changes when the library moves to converted files."
                           action:@selector(chooseMusicFolder:)
                          inView:content];

    _databaseField = [self addRowAtY:&y
                               label:@"Library:"
                                note:@"Where BTunes keeps its own database: ratings, play counts, and playlists. Songs are not moved."
                              action:@selector(chooseDatabaseFolder:)
                             inView:content];

    [self refresh];
    return self;
}

- (NSTextField *)labelWithText:(NSString *)text frame:(NSRect)frame small:(BOOL)small {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setStringValue:text];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setFont:(small ? [BTStyle smallFont] : [BTStyle uiFont])];
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

    NSButton *choose = [[NSButton alloc] initWithFrame:NSMakeRect(BT_PREFS_WIDTH - 112, *y - 5, 92, 26)];
    [choose setTitle:@"Choose..."];
    [choose setBezelStyle:NSRoundedBezelStyle];
    [choose setFont:[BTStyle uiFont]];
    [choose setTarget:self];
    [choose setAction:action];
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
