#import "BTAppDelegate.h"
#import "BTMainWindowController.h"
#import "BTMiniWindowController.h"
#import "BTSplashWindowController.h"
#import "BTPreferencesController.h"
#import "BTEqualizerController.h"
#import "BTLibrary.h"
#import "BTTrack.h"
#import "BTPreferences.h"
#import "BTITunesImport.h"
#import "BTITunesEntry.h"
#import "BTPlayer.h"
#import "BTIPod.h"
#import "BTAudioDisc.h"
#import "BTBlankDisc.h"

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
    [BTAudioDisc startWatching];
    [BTBlankDisc startWatching];

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

// An empty library used to be greeted with an alert offering to add a folder of
// music. It stood in front of the window on every launch until something was
// imported, and it blocked quitting while it was up. Bringing music over from
// iTunes is a button on the window, which says the same thing without a dialog.
- (void)finishLaunching {
    [self checkForMissingFiles];
}

// Songs are played where they already sit, which means anything that moves or
// deletes one of those files does it behind BTunes' back. Told at startup, the
// gap is a day at worst and a backup still has the file; found months later, it
// may not.
//
// Off the main thread, because asking the filesystem about several thousand
// files is most of what a check like this costs and none of it needs the window
// to wait. Nothing is removed either way: a file missing this morning may be a
// volume that is not mounted, and the ratings hanging off the entry cannot be
// got back while the audio usually can.
- (void)checkForMissingFiles {
    BTLibrary *library = [BTLibrary sharedLibrary];
    if ([library.tracks count] == 0) return;

    NSString *xml = [[BTPreferences sharedPreferences] iTunesLibraryPath];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSArray *gone = [library tracksWithMissingFiles];
        if ([gone count] == 0) return;

        // Asked after before being given up on. A song is missing as often
        // because iTunes moved it as because anything was lost, and the
        // persistent id survives a move. Reading the library file is the slow
        // part, so it happens here and only when something is actually missing.
        NSDictionary *places = [library placesForMissingFiles:gone fromITunesLibraryAtPath:xml];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self repair:gone to:places];
        });
    });
}

// On the main thread, because this is where the library is changed and where
// everything else reads it.
- (void)repair:(NSArray *)gone to:(NSDictionary *)places {
    BTLibrary *library = [BTLibrary sharedLibrary];
    NSMutableArray *stillGone = [NSMutableArray array];
    NSUInteger repaired = 0, i;

    for (i = 0; i < [gone count]; i++) {
        BTTrack *track = [gone objectAtIndex:i];
        BTITunesEntry *place = [places objectForKey:track.trackID];
        if (place == nil) {
            [stillGone addObject:track];
            continue;
        }
        [track setPath:place.path root:place.pathRoot];
        repaired++;
    }

    if (repaired > 0) {
        [library noteChanged];
        NSLog(@"BTunes: %lu song%@ had moved and %@ found again",
              (unsigned long)repaired, (repaired == 1 ? @"" : @"s"),
              (repaired == 1 ? @"was" : @"were"));
    }

    // Only what is genuinely lost is worth a dialog. A song that moved and was
    // found again is not news, and a dialog on every launch after a tag edit
    // teaches the reader to dismiss the one that matters.
    if ([stillGone count] == 0) return;

    NSString *log = [library writeMissingFilesLog:stillGone];
    [self reportMissingFiles:stillGone repaired:repaired log:log];
}

// A handful are named outright, since that is usually enough to recognise what
// happened. Past that the names stop being a list and start being a wall, and
// the log is the better place to read them.
#define BT_MISSING_NAMED 10

- (void)reportMissingFiles:(NSArray *)gone repaired:(NSUInteger)repaired log:(NSString *)log {
    NSUInteger count = [gone count];

    NSMutableString *detail = [NSMutableString string];
    if (count <= BT_MISSING_NAMED) {
        NSUInteger i;
        for (i = 0; i < count; i++) {
            BTTrack *track = [gone objectAtIndex:i];
            [detail appendFormat:@"%@ - %@\n", [track displayArtist], [track displayTitle]];
        }
        [detail appendString:@"\n"];
    }

    [detail appendString:@"Nothing has been removed. The ratings, play counts and playlist "
                         @"membership are all still here, waiting for the files to come back."];
    if (repaired > 0) {
        [detail appendFormat:@"\n\nAnother %lu had only moved, and %@ been pointed at the new place.",
                             (unsigned long)repaired, (repaired == 1 ? @"has" : @"have")];
    }
    if ([log length] > 0) {
        [detail appendFormat:@"\n\nThe full list is in:\n%@", log];
    }

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:[NSString stringWithFormat:@"%lu song%@ %@ missing.",
                           (unsigned long)count,
                           (count == 1 ? @"" : @"s"),
                           (count == 1 ? @"is" : @"are")]];
    [alert setInformativeText:detail];
    [alert addButtonWithTitle:@"OK"];
    if ([log length] > 0) [alert addButtonWithTitle:@"Show Log"];

    if ([alert runModal] == NSAlertSecondButtonReturn && [log length] > 0) {
        [[NSWorkspace sharedWorkspace] selectFile:log inFileViewerRootedAtPath:@""];
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
        // Closed rather than ordered out: the analyzer and the marquee are
        // driven by timers the controller starts when the window opens and
        // stops when it closes. Ordering the window away left both running, so
        // leaving mini mode did not give the processor back.
        [_mini close];
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
- (void)showITunesSync:(id)sender { [_main showITunesSync:sender]; }
- (void)focusSearch:(id)sender { [_main focusSearch:sender]; }
- (void)getInfo:(id)sender { [_main getInfo:sender]; }

- (void)showPreferences:(id)sender {
    [[BTPreferencesController sharedController] showWindow:nil];
    [[[BTPreferencesController sharedController] window] makeKeyAndOrderFront:nil];
}

- (void)showEqualizer:(id)sender {
    [[BTEqualizerController sharedController] showWindow:nil];
    [[[BTEqualizerController sharedController] window] makeKeyAndOrderFront:nil];
}

#pragma mark - Menus

- (NSMenuItem *)itemWithTitle:(NSString *)title
                       action:(SEL)action
                          key:(NSString *)key
                    modifiers:(NSUInteger)modifiers
                       target:(id)target {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    // Always set, even to nothing at all.
    //
    // A menu item's modifier mask is Command until it is told otherwise, so
    // leaving it alone quietly turned every asked-for "no modifiers" into a
    // Command shortcut. Mute became the ⌘M that the comment beside it says to
    // avoid, and Play or Pause became ⌘Space, which the system takes for
    // Spotlight and the application therefore never sees. Both were meant to be
    // the bare key the windows already answer.
    [item setKeyEquivalentModifierMask:modifiers];
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
    [appMenu addItem:[self itemWithTitle:@"Hide BTunes" action:@selector(hide:) key:@"h" modifiers:NSCommandKeyMask target:NSApp]];
    [appMenu addItem:[self itemWithTitle:@"Quit BTunes" action:@selector(terminate:) key:@"q" modifiers:NSCommandKeyMask target:NSApp]];
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
    [fileMenu addItem:[self itemWithTitle:@"iTunes Sync" action:@selector(showITunesSync:) key:@"" modifiers:0 target:nil]];
    [fileMenu addItem:[self itemWithTitle:@"Burn Playlist to Disc..."
                                   action:@selector(burnPlaylist:)
                                      key:@"b"
                                modifiers:NSCommandKeyMask
                                   target:nil]];
    [fileMenu addItem:[self itemWithTitle:@"Get Info" action:@selector(getInfo:) key:@"i" modifiers:NSCommandKeyMask target:nil]];
    [fileMenu addItem:[self itemWithTitle:@"Edit Smart Playlist..." action:@selector(editSmartPlaylist:) key:@"" modifiers:0 target:nil]];
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
    // A bare letter, the way the bare space plays and pauses. Command-M is already
    // Minimize. Both are held back while something is being typed.
    [controlsMenu addItem:[self itemWithTitle:@"Mute" action:@selector(toggleMute:) key:@"m" modifiers:0 target:nil]];
    [controlsMenu addItem:[self itemWithTitle:@"Volume Up" action:@selector(volumeUp:) key:@"" modifiers:NSCommandKeyMask target:nil]];
    [controlsMenu addItem:[self itemWithTitle:@"Volume Down" action:@selector(volumeDown:) key:@"" modifiers:NSCommandKeyMask target:nil]];
    [controlsMenu addItem:[NSMenuItem separatorItem]];
    // No key of its own. iTunes gave the equalizer Command-2 because Command-1
    // was its main window, and one half of that pair on its own is a shortcut
    // nobody would guess.
    [controlsMenu addItem:[self itemWithTitle:@"Equalizer"
                                       action:@selector(showEqualizer:)
                                          key:@""
                                    modifiers:0
                                       target:self]];
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
