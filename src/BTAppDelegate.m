#import "BTAppDelegate.h"
#import "BTMainWindowController.h"
#import "BTMiniWindowController.h"
#import "BTSplashWindowController.h"
#import "BTPreferencesController.h"
#import "BTLibrary.h"
#import "BTPlayer.h"
#import "BTIPod.h"

@implementation BTAppDelegate {
    BTMainWindowController *_main;
    BTMiniWindowController *_mini;
    BTSplashWindowController *_splash;
    BOOL _miniMode;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildMenus];
    [self applyApplicationIcon];

    // The splash goes up first so the logo is visible while the library loads,
    // which is the slow part on a large library.
    _splash = [BTSplashWindowController splashController];
    [_splash showSplash];

    [BTIPod startWatching];

    BTLibrary *library = [BTLibrary sharedLibrary];
    [library loadFromDisk];
    NSLog(@"BTunes library: %@ (%lu tracks, %lu playlists)",
          [library libraryFilePath],
          (unsigned long)[library.tracks count],
          (unsigned long)[library.playlists count]);

    _main = [[BTMainWindowController alloc] initMainWindow];
    [[_main window] center];

    if (_splash) {
        [_splash dismissAfterMinimumTime:^{
            [self->_main showWindow:nil];
            [self finishLaunching];
        }];
    } else {
        [_main showWindow:nil];
        [self finishLaunching];
    }
}

- (void)finishLaunching {
    if ([[BTLibrary sharedLibrary].tracks count] == 0) {
        [self performSelector:@selector(offerFirstImport) withObject:nil afterDelay:0.3];
    }
}

// Running the executable directly, rather than through the bundle, leaves the
// Dock showing a blank icon unless it is set by hand.
- (void)applyApplicationIcon {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"BTunes" ofType:@"icns"];
    if (path == nil) return;
    NSImage *icon = [[NSImage alloc] initWithContentsOfFile:path];
    if (icon) [NSApp setApplicationIconImage:icon];
}

- (void)offerFirstImport {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"The library is empty."];
    [alert setInformativeText:@"Choose a folder of music to add. BTunes reads the files and never writes to them."];
    [alert addButtonWithTitle:@"Add Music"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [_main addToLibrary:nil];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[BTPlayer sharedPlayer] stop];
    [[BTLibrary sharedLibrary] saveToDisk];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

#pragma mark - Mini mode

- (void)toggleMiniMode:(id)sender {
    _miniMode = !_miniMode;

    if (_miniMode) {
        if (_mini == nil) _mini = [[BTMiniWindowController alloc] initMiniPlayer];
        NSRect mainFrame = [[_main window] frame];
        [[_mini window] setFrameTopLeftPoint:NSMakePoint(NSMinX(mainFrame), NSMaxY(mainFrame))];
        [_mini showWindow:nil];
        [[_mini window] makeKeyAndOrderFront:nil];
        [[_main window] orderOut:nil];
    } else {
        [[_mini window] orderOut:nil];
        [[_main window] makeKeyAndOrderFront:nil];
    }
}

#pragma mark - Transport reaching the main window

// The mini player and the menus both send these up the responder chain. When
// the mini player is the key window the main window controller is not in that
// chain, so the delegate hands them along. Without this, pressing play in mini
// mode does nothing at all until something has already been started elsewhere,
// since only the main window knows which songs are on screen.

- (void)playPause:(id)sender { [_main playPause:sender]; }
- (void)nextTrack:(id)sender { [_main nextTrack:sender]; }
- (void)previousTrack:(id)sender { [_main previousTrack:sender]; }
- (void)toggleShuffle:(id)sender { [_main toggleShuffle:sender]; }
- (void)cycleRepeat:(id)sender { [_main cycleRepeat:sender]; }
- (void)toggleMute:(id)sender { [_main toggleMute:sender]; }
- (void)volumeUp:(id)sender { [_main volumeUp:sender]; }
- (void)volumeDown:(id)sender { [_main volumeDown:sender]; }
- (void)newPlaylist:(id)sender { [_main newPlaylist:sender]; }
- (void)newSmartPlaylist:(id)sender { [_main newSmartPlaylist:sender]; }
- (void)newPlaylistFolder:(id)sender { [_main newPlaylistFolder:sender]; }
- (void)editSmartPlaylist:(id)sender { [_main editSmartPlaylist:sender]; }
- (void)addToLibrary:(id)sender { [_main addToLibrary:sender]; }
- (void)importITunesLibrary:(id)sender { [_main importITunesLibrary:sender]; }
- (void)focusSearch:(id)sender { [_main focusSearch:sender]; }

- (void)showPreferences:(id)sender {
    [[BTPreferencesController sharedController] showWindow:nil];
    [[[BTPreferencesController sharedController] window] makeKeyAndOrderFront:nil];
}

#pragma mark - Menus

- (NSMenuItem *)itemWithTitle:(NSString *)title
                       action:(SEL)action
                          key:(NSString *)key
                    modifiers:(NSUInteger)modifiers
                       target:(id)target {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    if (modifiers != 0) [item setKeyEquivalentModifierMask:modifiers];
    if (target) [item setTarget:target];
    return item;
}

- (void)buildMenus {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

    // Application menu.
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"BTunes" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"BTunes"];
    [appMenu addItem:[self itemWithTitle:@"About BTunes"
                                  action:@selector(orderFrontStandardAboutPanel:)
                                     key:@"" modifiers:0 target:NSApp]];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItem:[self itemWithTitle:@"Preferences..."
                                  action:@selector(showPreferences:)
                                     key:@","
                               modifiers:NSCommandKeyMask
                                  target:self]];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItem:[self itemWithTitle:@"Hide BTunes" action:@selector(hide:) key:@"h" modifiers:0 target:NSApp]];
    [appMenu addItem:[self itemWithTitle:@"Quit BTunes" action:@selector(terminate:) key:@"q" modifiers:0 target:NSApp]];
    [appItem setSubmenu:appMenu];
    [mainMenu addItem:appItem];

    // File.
    NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"File" action:NULL keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItem:[self itemWithTitle:@"New Playlist" action:@selector(newPlaylist:) key:@"n" modifiers:NSCommandKeyMask target:nil]];
    [fileMenu addItem:[self itemWithTitle:@"New Smart Playlist..."
                                   action:@selector(newSmartPlaylist:)
                                      key:@"n"
                                modifiers:(NSCommandKeyMask | NSAlternateKeyMask)
                                   target:nil]];
    [fileMenu addItem:[self itemWithTitle:@"New Playlist Folder"
                                   action:@selector(newPlaylistFolder:)
                                      key:@"n"
                                modifiers:(NSCommandKeyMask | NSShiftKeyMask)
                                   target:nil]];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItem:[self itemWithTitle:@"Add to Library..." action:@selector(addToLibrary:) key:@"o" modifiers:NSCommandKeyMask target:nil]];
    [fileMenu addItem:[self itemWithTitle:@"Import iTunes Library..." action:@selector(importITunesLibrary:) key:@"" modifiers:0 target:nil]];
    [fileMenu addItem:[self itemWithTitle:@"Edit Smart Playlist..." action:@selector(editSmartPlaylist:) key:@"i" modifiers:NSCommandKeyMask target:nil]];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItem:[self itemWithTitle:@"Delete" action:@selector(deleteSelection:) key:@"" modifiers:0 target:nil]];
    [fileItem setSubmenu:fileMenu];
    [mainMenu addItem:fileItem];

    // Edit, with the standard text editing keys the search field expects.
    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    // Titled by the undo manager as it validates, so the menu names the thing
    // it will take back.
    [editMenu addItem:[self itemWithTitle:@"Undo" action:@selector(undo:) key:@"z" modifiers:NSCommandKeyMask target:nil]];
    [editMenu addItem:[self itemWithTitle:@"Redo" action:@selector(redo:) key:@"Z" modifiers:NSCommandKeyMask target:nil]];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItem:[self itemWithTitle:@"Cut" action:@selector(cut:) key:@"x" modifiers:NSCommandKeyMask target:nil]];
    [editMenu addItem:[self itemWithTitle:@"Copy" action:@selector(copy:) key:@"c" modifiers:NSCommandKeyMask target:nil]];
    [editMenu addItem:[self itemWithTitle:@"Paste" action:@selector(paste:) key:@"v" modifiers:NSCommandKeyMask target:nil]];
    [editMenu addItem:[self itemWithTitle:@"Select All" action:@selector(selectAll:) key:@"a" modifiers:NSCommandKeyMask target:nil]];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItem:[self itemWithTitle:@"Search" action:@selector(focusSearch:) key:@"f" modifiers:NSCommandKeyMask target:nil]];
    [editItem setSubmenu:editMenu];
    [mainMenu addItem:editItem];

    // Controls.
    NSMenuItem *controlsItem = [[NSMenuItem alloc] initWithTitle:@"Controls" action:NULL keyEquivalent:@""];
    NSMenu *controlsMenu = [[NSMenu alloc] initWithTitle:@"Controls"];
    [controlsMenu addItem:[self itemWithTitle:@"Play or Pause" action:@selector(playPause:) key:@" " modifiers:0 target:nil]];
    [controlsMenu addItem:[self itemWithTitle:@"Next Song" action:@selector(nextTrack:) key:@"" modifiers:NSCommandKeyMask target:nil]];
    [controlsMenu addItem:[self itemWithTitle:@"Previous Song" action:@selector(previousTrack:) key:@"" modifiers:NSCommandKeyMask target:nil]];
    [controlsMenu addItem:[NSMenuItem separatorItem]];
    [controlsMenu addItem:[self itemWithTitle:@"Shuffle" action:@selector(toggleShuffle:) key:@"s" modifiers:NSCommandKeyMask target:nil]];
    [controlsMenu addItem:[self itemWithTitle:@"Repeat" action:@selector(cycleRepeat:) key:@"r" modifiers:NSCommandKeyMask target:nil]];
    [controlsMenu addItem:[NSMenuItem separatorItem]];
    // Deliberately not forwarded from the mini player: renumbering a playlist
    // nobody can see is not something to offer.
    [controlsMenu addItem:[self itemWithTitle:@"Sync Playlist Order to Album/Track Order"
                                       action:@selector(syncPlaylistOrder:)
                                          key:@""
                                    modifiers:0
                                       target:nil]];
    [controlsMenu addItem:[NSMenuItem separatorItem]];
    // Plain M is handled by the windows, since a menu key equivalent would fire
    // while typing in the search field.
    [controlsMenu addItem:[self itemWithTitle:@"Mute" action:@selector(toggleMute:) key:@"" modifiers:0 target:nil]];
    [controlsMenu addItem:[self itemWithTitle:@"Volume Up" action:@selector(volumeUp:) key:@"" modifiers:NSCommandKeyMask target:nil]];
    [controlsMenu addItem:[self itemWithTitle:@"Volume Down" action:@selector(volumeDown:) key:@"" modifiers:NSCommandKeyMask target:nil]];
    [controlsItem setSubmenu:controlsMenu];
    [mainMenu addItem:controlsItem];

    // Window.
    NSMenuItem *windowItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:NULL keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItem:[self itemWithTitle:@"Mini Player"
                                     action:@selector(toggleMiniMode:)
                                        key:@"m"
                                  modifiers:(NSCommandKeyMask | NSShiftKeyMask)
                                     target:self]];
    [windowMenu addItem:[self itemWithTitle:@"Minimize" action:@selector(performMiniaturize:) key:@"m" modifiers:NSCommandKeyMask target:nil]];
    [windowMenu addItem:[self itemWithTitle:@"Zoom" action:@selector(performZoom:) key:@"" modifiers:0 target:nil]];
    [windowItem setSubmenu:windowMenu];
    [mainMenu addItem:windowItem];
    [NSApp setWindowsMenu:windowMenu];

    [NSApp setMainMenu:mainMenu];
}

@end
