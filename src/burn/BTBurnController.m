#import "BTBurnController.h"
#import "BTBurnPlan.h"
#import "BTPlaylist.h"
#import "BTLibrary.h"
#import "BTStyle.h"
#import "BTControls.h"
#import <DiscRecording/DiscRecording.h>
#import <DiscRecordingUI/DiscRecordingUI.h>

#define BT_BURN_SHEET_WIDTH 460.0

// The gap between songs, in the order the popup offers it. Two is the default,
// which is what a commercial disc uses and what iTunes wrote.
static const NSUInteger BTBurnGapChoices[] = { 2, 1, 0 };
#define BT_BURN_GAP_COUNT 3

// The dialog and the burn it starts both have to outlive the method that made
// them: the sheet returns immediately, and so does the burn. One drive means
// one burn, so one place to keep it is enough, and a second attempt while one
// is running finds this already taken.
static BTBurnController *sRunning = nil;

@interface BTBurnController () <NSWindowDelegate>
+ (void)releaseRunning;
- (void)reserveDevices:(NSArray *)devices;
- (void)refresh;
@end

@implementation BTBurnController {
    BTBurnPlan *_plan;
    NSWindow *_parent;
    NSArray *_devices;              // DRDevice, the ones that write CD-R
    NSArray *_reserved;             // the ones whose blank media is spoken for
    DRNotificationCenter *_center;

    NSTextField *_heading;
    NSTextField *_summary;
    NSTextField *_note;
    NSTextField *_driveLabel;
    NSPopUpButton *_drivePopUp;
    NSTextField *_gapLabel;
    NSPopUpButton *_gapPopUp;
    NSButton *_verifyCheck;
    NSTextField *_status;
    BTPushButton *_burnButton;
    // A refusal that no longer follows from what the dialog can see. A file
    // that has gone since the plan was made does not come back because a tray
    // was opened, so the reason has to stick rather than being recomputed away.
    NSString *_blocked;
}

+ (BOOL)isBusy {
    return sRunning != nil;
}

+ (void)burnPlaylist:(BTPlaylist *)playlist modalForWindow:(NSWindow *)parent {
    if (sRunning != nil) {
        NSBeep();
        return;
    }
    BTBurnPlan *plan = [BTBurnPlan planForPlaylist:playlist
                                            tracks:[BTLibrary sharedLibrary].tracks];
    sRunning = [[BTBurnController alloc] initWithPlan:plan parent:parent];
    [sRunning present];
}

- (instancetype)initWithPlan:(BTBurnPlan *)plan parent:(NSWindow *)parent {
    NSRect frame = NSMakeRect(0, 0, BT_BURN_SHEET_WIDTH, 260);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSTitledWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"Burn Disc"];

    self = [super initWithWindow:window];
    if (self == nil) return nil;

    _plan = plan;
    _parent = parent;
    [self buildInterface];
    return self;
}

#pragma mark - Building the dialog

- (NSTextField *)wrappingLabelWithFont:(NSFont *)font {
    NSTextField *field = BTLabelWithText(@"", font);
    [[field cell] setWraps:YES];
    return field;
}

- (void)buildInterface {
    NSView *content = [[self window] contentView];

    _heading = BTLabelWithText([NSString stringWithFormat:@"Burn \"%@\" to an audio CD",
                                                          [_plan name]],
                               [BTStyle boldFont]);
    [content addSubview:_heading];

    _summary = BTLabelWithText(@"", [BTStyle uiFont]);
    [content addSubview:_summary];

    // Only there when it has something to say, since the whole file reaching
    // the disc is what a reader would assume anyway.
    _note = [self wrappingLabelWithFont:[BTStyle smallFont]];
    [content addSubview:_note];

    _driveLabel = BTLabelWithText(@"Disc Burner:", [BTStyle uiFont]);
    [content addSubview:_driveLabel];

    _drivePopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
    [[_drivePopUp cell] setControlSize:NSSmallControlSize];
    [_drivePopUp setFont:[BTStyle uiFont]];
    [_drivePopUp setTarget:self];
    [_drivePopUp setAction:@selector(driveChanged:)];
    [content addSubview:_drivePopUp];

    _gapLabel = BTLabelWithText(@"Gap Between Songs:", [BTStyle uiFont]);
    [content addSubview:_gapLabel];

    _gapPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
    [_gapPopUp addItemsWithTitles:@[@"2 seconds", @"1 second", @"none"]];
    [[_gapPopUp cell] setControlSize:NSSmallControlSize];
    [_gapPopUp setFont:[BTStyle uiFont]];
    [_gapPopUp setTarget:self];
    [_gapPopUp setAction:@selector(gapChanged:)];
    [content addSubview:_gapPopUp];

    // Off by default. It reads the whole disc back and so doubles the time,
    // which is a trade worth making deliberately rather than every time.
    _verifyCheck = [[NSButton alloc] initWithFrame:NSZeroRect];
    [_verifyCheck setButtonType:NSSwitchButton];
    [_verifyCheck setTitle:@"Verify the disc after burning"];
    [_verifyCheck setFont:[BTStyle uiFont]];
    [_verifyCheck setState:NSOffState];
    [content addSubview:_verifyCheck];

    _status = [self wrappingLabelWithFont:[BTStyle uiFont]];
    [content addSubview:_status];

    BTPushButton *cancel = [BTPushButton buttonWithTitle:@"Cancel"
                                                  target:self
                                                  action:@selector(cancel:)];
    [cancel setFrame:NSMakeRect(BT_BURN_SHEET_WIDTH - 190, 14, 80, NSHeight([cancel frame]))];
    [cancel setKeyEquivalent:@"\033"];
    [content addSubview:cancel];

    _burnButton = [BTPushButton buttonWithTitle:@"Burn" target:self action:@selector(burn:)];
    [_burnButton setFrame:NSMakeRect(BT_BURN_SHEET_WIDTH - 104, 14, 84, NSHeight([_burnButton frame]))];
    [_burnButton setKeyEquivalent:@"\r"];
    [content addSubview:_burnButton];

    [self layoutWindow];
    [self reloadDevices];
}

// Placed from the top down, since only the two wrapping lines change height.
// The buttons stay pinned to the bottom.
- (void)layoutWindow {
    CGFloat noteHeight = ([[_note stringValue] length] > 0) ? 28 : 0;
    CGFloat height = 34 + 24 + noteHeight + 12 + 30 + 30 + 28 + 40 + 46;

    NSWindow *window = [self window];
    NSRect frame = [window frame];
    NSRect contentRect = NSMakeRect(NSMinX(frame), NSMinY(frame), BT_BURN_SHEET_WIDTH, height);
    NSRect wanted = [window frameRectForContentRect:contentRect];
    // A sheet already on screen is placed by the window it hangs from, so it is
    // only resized when the height genuinely changed.
    if (fabs(NSHeight(wanted) - NSHeight(frame)) > 0.5) [window setFrame:wanted display:YES];

    CGFloat right = BT_BURN_SHEET_WIDTH - 20;
    CGFloat y = height - 34;
    [_heading setFrame:NSMakeRect(20, y, right - 20, 18)];

    y -= 24;
    [_summary setFrame:NSMakeRect(20, y, right - 20, 18)];

    if (noteHeight > 0) {
        y -= noteHeight;
        [_note setFrame:NSMakeRect(20, y, right - 20, noteHeight - 4)];
    }
    [_note setHidden:(noteHeight == 0)];

    y -= 42;
    [_driveLabel setFrame:NSMakeRect(20, y + 4, 130, 18)];
    [_drivePopUp setFrame:NSMakeRect(150, y, right - 150, 22)];

    y -= 30;
    [_gapLabel setFrame:NSMakeRect(20, y + 4, 130, 18)];
    [_gapPopUp setFrame:NSMakeRect(150, y, 130, 22)];

    y -= 28;
    [_verifyCheck setFrame:NSMakeRect(150, y, right - 150, 20)];

    y -= 40;
    [_status setFrame:NSMakeRect(20, y, right - 20, 36)];
}

#pragma mark - Drives, and what they hold

// The list is rebuilt rather than patched, since a drive can be unplugged while
// the dialog is up and the selection has to survive one that was not.
- (void)reloadDevices {
    DRDevice *wasSelected = [self selectedDevice];
    _devices = [BTBurnPlan writableDevices];

    [_drivePopUp removeAllItems];
    NSUInteger i;
    for (i = 0; i < [_devices count]; i++) {
        NSString *title = [[_devices objectAtIndex:i] displayName];
        [_drivePopUp addItemWithTitle:([title length] > 0 ? title : @"Disc Burner")];
    }

    // A drive plugged in while the dialog is up gets the reservation too, and
    // one unplugged gives its back, so the two lists cannot drift apart.
    if (_center != nil) [self reserveDevices:_devices];

    if ([_devices count] == 0) {
        [_drivePopUp addItemWithTitle:@"No disc burner"];
        [_drivePopUp setEnabled:NO];
    } else {
        [_drivePopUp setEnabled:YES];
        for (i = 0; i < [_devices count]; i++) {
            if (wasSelected && [[_devices objectAtIndex:i] isEqualToDevice:wasSelected]) {
                [_drivePopUp selectItemAtIndex:(NSInteger)i];
                break;
            }
        }
    }
    [self refresh];
}

- (DRDevice *)selectedDevice {
    NSInteger index = [_drivePopUp indexOfSelectedItem];
    if (index < 0 || index >= (NSInteger)[_devices count]) return nil;
    return [_devices objectAtIndex:(NSUInteger)index];
}

// Everything the reader is told about the burn comes from here, so the running
// time, the reason it is refused, and whether the button is alive can never
// disagree with each other.
- (void)refresh {
    // Every song in the playlist, not only the ones that would reach the disc.
    // Saying "5 songs" beside a reason that names a sixth reads as an offer to
    // burn the five, which is exactly what is being refused.
    NSUInteger readable = [[_plan songs] count];
    NSUInteger missing = [[_plan unreadable] count];
    NSUInteger songs = readable + missing;

    if (missing > 0) {
        [_summary setStringValue:[NSString stringWithFormat:
            @"%lu song%@, %lu of which cannot be read.",
            (unsigned long)songs, (songs == 1 ? @"" : @"s"), (unsigned long)missing]];
    } else {
        [_summary setStringValue:[NSString stringWithFormat:@"%lu song%@, %@ on the disc.",
                                  (unsigned long)songs, (songs == 1 ? @"" : @"s"),
                                  [BTBurnPlan stringFromSectors:[_plan sectors]]]];
    }

    NSUInteger trimmed = [[_plan trimmed] count];
    if (trimmed > 0) {
        [_note setStringValue:[NSString stringWithFormat:
            @"%lu song%@ here %@ a start or end time. The disc gets the whole file, since "
            @"the times are BTunes' own and the disc has nowhere to keep them.",
            (unsigned long)trimmed, (trimmed == 1 ? @"" : @"s"),
            (trimmed == 1 ? @"has" : @"have")]];
    } else {
        [_note setStringValue:@""];
    }

    NSString *problem = _blocked;
    if (problem == nil) problem = [_plan refusalText];
    if (problem == nil) problem = [_plan problemWithDisc:[self selectedDevice]];

    [_status setStringValue:(problem ? problem
                                     : @"Ready. Nothing is written until Burn is pressed.")];
    [_burnButton setEnabled:(problem == nil)];

    [self layoutWindow];
}

- (void)driveChanged:(id)sender {
    [self refresh];
}

// The gap is part of what has to fit, so changing it recomputes rather than
// being discovered at the end of the disc.
- (void)gapChanged:(id)sender {
    NSInteger index = [_gapPopUp indexOfSelectedItem];
    if (index < 0 || index >= BT_BURN_GAP_COUNT) index = 0;
    _plan.gapSeconds = BTBurnGapChoices[index];
    [self refresh];
}

#pragma mark - Watching the drive

- (void)startWatching {
    _center = [DRNotificationCenter currentRunLoopCenter];
    [_center addObserver:self selector:@selector(deviceChanged:)
                    name:DRDeviceStatusChangedNotification object:nil];
    [_center addObserver:self selector:@selector(deviceListChanged:)
                    name:DRDeviceAppearedNotification object:nil];
    [_center addObserver:self selector:@selector(deviceListChanged:)
                    name:DRDeviceDisappearedNotification object:nil];
    [self reserveDevices:_devices];
}

// Says to the rest of the system that a blank disc put in now is meant for us,
// which keeps the Finder's own "you inserted a blank disc" panel from landing on
// top of this one. Every acquire owes a release, so the list held here is the
// one released rather than whichever drives are attached by then.
- (void)reserveDevices:(NSArray *)devices {
    NSUInteger i;
    for (i = 0; i < [_reserved count]; i++) {
        [[_reserved objectAtIndex:i] releaseMediaReservation];
    }
    _reserved = devices;
    for (i = 0; i < [_reserved count]; i++) {
        [[_reserved objectAtIndex:i] acquireMediaReservation];
    }
}

- (void)stopWatching {
    [self reserveDevices:nil];
    [_center removeObserver:self name:DRDeviceStatusChangedNotification object:nil];
    [_center removeObserver:self name:DRDeviceAppearedNotification object:nil];
    [_center removeObserver:self name:DRDeviceDisappearedNotification object:nil];
    _center = nil;
}

- (void)deviceChanged:(NSNotification *)note {
    [self refresh];
}

- (void)deviceListChanged:(NSNotification *)note {
    [self reloadDevices];
}

#pragma mark - The sheet

- (void)present {
    [_parent beginSheet:[self window] completionHandler:nil];
    [self startWatching];
}

- (void)dismiss {
    [self stopWatching];
    NSWindow *sheet = [self window];
    [[sheet sheetParent] endSheet:sheet];
    [sheet orderOut:nil];
}

- (void)cancel:(id)sender {
    [self dismiss];
    [BTBurnController releaseRunning];
}

// The last reference to this controller is the one held for the burn, so it is
// let go on the next pass rather than while a method of its own is running.
+ (void)releaseRunning {
    dispatch_async(dispatch_get_main_queue(), ^{ sRunning = nil; });
}

#pragma mark - Burning

- (void)burn:(id)sender {
    // Asked again rather than trusted from when the dialog opened. A tray can
    // be opened and a file can be moved while a dialog sits there, and a burn
    // that starts and cannot finish costs a disc.
    DRDevice *device = [self selectedDevice];
    if ([_plan problemWithDisc:device] != nil) {
        // Not made sticky. Putting a disc in fixes this one, and refresh is
        // already saying what is wrong with the drive.
        NSBeep();
        [self refresh];
        return;
    }

    NSString *reason = nil;
    NSArray *tracks = [_plan buildTracks:&reason];
    if (tracks == nil) {
        [self refuse:(reason ? reason : @"This playlist cannot be burned.")];
        return;
    }

    DRBurn *burn = [DRBurn burnForDevice:device];
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    NSDictionary *existing = [burn properties];
    if (existing) [properties addEntriesFromDictionary:existing];

    // One playlist, one disc, closed when it is done, so it plays in anything
    // that plays CDs rather than waiting for a session that never comes.
    [properties setObject:@NO forKey:DRBurnAppendableKey];
    [properties setObject:@([_verifyCheck state] == NSOnState) forKey:DRBurnVerifyDiscKey];
    [properties setObject:DRBurnCompletionActionEject forKey:DRBurnCompletionActionKey];

    // Names on the disc need the whole session written in one pass, and only
    // some drives do it. Asked rather than assumed, and asked without insisting,
    // so a drive that cannot manage it still burns the music.
    NSDictionary *writes = [[device info] objectForKey:DRDeviceWriteCapabilitiesKey];
    if ([[writes objectForKey:DRDeviceCanWriteCDTextKey] boolValue]) {
        DRCDTextBlock *text = [_plan cdText];
        if (text != nil) {
            [properties setObject:DRBurnStrategyCDSAO forKey:DRBurnStrategyKey];
            [properties setObject:@NO forKey:DRBurnStrategyIsRequiredKey];
            [properties setObject:text forKey:DRCDTextKey];
        }
    }
    [burn setProperties:properties];

    NSString *name = [_plan name];
    [self dismiss];

    // The progress panel is a sheet on the same window this one was, so it goes
    // up once ours is actually gone rather than fighting it for the position.
    dispatch_async(dispatch_get_main_queue(), ^{
        DRBurnProgressPanel *panel = [DRBurnProgressPanel progressPanel];
        [panel setDelegate:self];
        [panel setDescription:[NSString stringWithFormat:@"Burning \"%@\" to disc.", name]];
        [panel beginProgressSheetForBurn:burn layout:tracks modalForWindow:self->_parent];
    });
}

// Said in the dialog rather than in an alert on top of it, and it stays said:
// a file that has gone does not come back because a tray was opened.
- (void)refuse:(NSString *)text {
    NSBeep();
    _blocked = [text copy];
    [self refresh];
}

#pragma mark - Progress panel

// The panel shows its own errors and plays its own sound when it is done, which
// is the behaviour anyone who has burned a disc on this system expects.
- (BOOL)burnProgressPanel:(DRBurnProgressPanel *)panel burnDidFinish:(DRBurn *)burn {
    return NO;
}

- (void)burnProgressPanelDidFinish:(NSNotification *)note {
    DRBurnProgressPanel *panel = [note object];
    [panel setDelegate:nil];
    [BTBurnController releaseRunning];
}

@end
