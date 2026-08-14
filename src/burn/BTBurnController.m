#import "BTBurnController.h"
#import "BTBurnPlan.h"
#import "BTPlaylist.h"
#import "BTLibrary.h"
#import "BTStyle.h"
#import "BTControls.h"
#import <DiscRecording/DiscRecording.h>
#import <DiscRecordingUI/DiscRecordingUI.h>

#define BT_BURN_SHEET_WIDTH 460.0

// The parts that follow the type. At the size this was drawn for they come to
// the numbers that used to be written out: 18, 22, 20, 28, 36, and the steps.
#define BT_LABEL  ([BTStyle labelHeight])          // a caption on its own line
#define BT_FIELD  ([BTStyle fieldHeight])          // the drive and the gap
#define BT_BOX    ([BTStyle checkboxHeight])       // verify after burning
// The two lines that wrap ask their own words how tall they need to be. Written
// as a number of lines it was right for one size of type and one wording, and
// the first time either changed the last line went missing without a sign.
#define BT_STATUS_MIN ([BTStyle lineHeight] * 2.0 + 10.0)   // never less than two lines
// A caption sits above the bottom edge of the control beside it.
#define BT_RISE   4.0

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
- (void)setPreparing:(BOOL)preparing count:(NSUInteger)count;
- (void)startBurnOf:(NSArray *)tracks with:(DRDevice *)device;
- (void)refuse:(NSString *)text;
@end

@implementation BTBurnController {
    BTBurnPlan *_plan;
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
    // Set while the trimmed songs are being written out. Nothing can be
    // touched then, including Cancel: a half-decoded song has no clean place
    // to stop and the wait is seconds rather than minutes.
    BOOL _preparing;
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
    sRunning = [[BTBurnController alloc] initWithPlan:plan];
    [sRunning beginSheetForWindow:parent completion:nil];
}

- (instancetype)initWithPlan:(BTBurnPlan *)plan {
    NSRect frame = NSMakeRect(0, 0, BT_BURN_SHEET_WIDTH, 260);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSTitledWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"Burn Disc"];

    self = [super initWithWindow:window];
    if (self == nil) return nil;

    _plan = plan;
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

    [self addButtonsAccepting:@"Burn"
                       action:@selector(burn:)
                       cancel:@selector(cancel:)
                      inWidth:BT_BURN_SHEET_WIDTH];

    [self layoutWindow];
    [self reloadDevices];
}

// Placed from the top down, since only the two wrapping lines change height.
// The buttons stay pinned to the bottom.
- (void)layoutWindow {
    CGFloat textWidth = BT_BURN_SHEET_WIDTH - 40;
    CGFloat noteHeight = [BTStyle heightForText:[_note stringValue]
                                           font:[BTStyle smallFont]
                                          width:textWidth];
    if (noteHeight > 0) noteHeight += 6.0;      // air under it
    CGFloat statusHeight = MAX(BT_STATUS_MIN, [BTStyle heightForText:[_status stringValue]
                                                                font:[BTStyle uiFont]
                                                               width:textWidth] + 4.0);

    // Heading, summary, the note when there is one, then the drive, the gap, the
    // tick box, the reason, and the strip the buttons sit in.
    CGFloat height = (BT_LABEL + 16) + (BT_LABEL + 6) + noteHeight + 12
                   + (BT_FIELD + 8) + (BT_FIELD + 8) + (BT_BOX + 8)
                   + (statusHeight + 4) + 46;

    NSWindow *window = [self window];
    NSRect frame = [window frame];
    NSRect contentRect = NSMakeRect(NSMinX(frame), NSMinY(frame), BT_BURN_SHEET_WIDTH, height);
    NSRect wanted = [window frameRectForContentRect:contentRect];
    // A sheet already on screen is placed by the window it hangs from, so it is
    // only resized when the height genuinely changed.
    if (fabs(NSHeight(wanted) - NSHeight(frame)) > 0.5) [window setFrame:wanted display:YES];

    CGFloat right = BT_BURN_SHEET_WIDTH - 20;
    CGFloat y = height - (BT_LABEL + 16);
    [_heading setFrame:NSMakeRect(20, y, right - 20, BT_LABEL)];

    y -= BT_LABEL + 6;
    [_summary setFrame:NSMakeRect(20, y, right - 20, BT_LABEL)];

    if (noteHeight > 0) {
        y -= noteHeight;
        [_note setFrame:NSMakeRect(20, y, right - 20, noteHeight - 6.0)];
    }
    [_note setHidden:(noteHeight == 0)];

    y -= BT_FIELD + 20;
    [_driveLabel setFrame:NSMakeRect(20, y + BT_RISE, 130, BT_LABEL)];
    [_drivePopUp setFrame:NSMakeRect(150, y, right - 150, BT_FIELD)];

    y -= BT_FIELD + 8;
    [_gapLabel setFrame:NSMakeRect(20, y + BT_RISE, 130, BT_LABEL)];
    [_gapPopUp setFrame:NSMakeRect(150, y, 130, BT_FIELD)];

    y -= BT_BOX + 8;
    [_verifyCheck setFrame:NSMakeRect(150, y, right - 150, BT_BOX)];

    y -= statusHeight + 4;
    [_status setFrame:NSMakeRect(20, y, right - 20, statusHeight)];
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
        [_drivePopUp setEnabled:!_preparing];
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
            @"%lu song%@ here %@ a start or end time. The disc gets the part that plays, "
            @"so %@ converted first and Burn takes a moment to begin.",
            (unsigned long)trimmed, (trimmed == 1 ? @"" : @"s"),
            (trimmed == 1 ? @"has" : @"have"),
            (trimmed == 1 ? @"it is" : @"they are")]];
    } else {
        [_note setStringValue:@""];
    }

    if (_preparing) {
        [self layoutWindow];
        return;
    }

    NSString *problem = _blocked;
    if (problem == nil) problem = [_plan refusalText];
    if (problem == nil) problem = [_plan problemWithScratchSpace];
    if (problem == nil) problem = [_plan problemWithDisc:[self selectedDevice]];

    [_status setStringValue:(problem ? problem
                                     : @"Ready. Nothing is written until Burn is pressed.")];
    [self.acceptButton setEnabled:(problem == nil)];

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

// The drive is watched only while the dialog is up, so the two are tied to the
// sheet going up and coming down rather than tracked by hand.
- (void)beginSheetForWindow:(NSWindow *)parent completion:(void (^)(BOOL accepted))completion {
    [super beginSheetForWindow:parent completion:completion];
    [self startWatching];
}

- (void)finishAccepted:(BOOL)accepted {
    [self stopWatching];
    [super finishAccepted:accepted];
}

- (void)cancel:(id)sender {
    [self finishAccepted:NO];
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

    NSString *tight = [_plan problemWithScratchSpace];
    if (tight != nil) {
        [self refuse:tight];
        return;
    }

    // Decoding the trimmed songs is the slow part and none of it needs the
    // window to wait, so it happens off the main thread with the dialog saying
    // what it is doing. Everything after it is back on the main thread, which
    // is where the drive is spoken to.
    NSUInteger trimmed = [[_plan trimmed] count];
    [self setPreparing:(trimmed > 0) count:trimmed];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *reason = nil;
        NSArray *tracks = [self->_plan buildTracks:&reason];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setPreparing:NO count:0];
            if (tracks == nil) {
                [self refuse:(reason ? reason : @"This playlist cannot be burned.")];
                return;
            }
            [self startBurnOf:tracks with:device];
        });
    });
}

// Nothing can be pressed while a song is being decoded, and the reason it
// cannot is on screen rather than left to be guessed at.
- (void)setPreparing:(BOOL)preparing count:(NSUInteger)count {
    _preparing = preparing;
    [self.acceptButton setEnabled:!preparing];
    [self.cancelButton setEnabled:!preparing];
    [_drivePopUp setEnabled:(!preparing && [_devices count] > 0)];
    [_gapPopUp setEnabled:!preparing];
    [_verifyCheck setEnabled:!preparing];

    if (preparing) {
        [_status setStringValue:[NSString stringWithFormat:
            @"Converting %lu song%@ to the part that plays...",
            (unsigned long)count, (count == 1 ? @"" : @"s")]];
        [self layoutWindow];
    }
}

- (void)startBurnOf:(NSArray *)tracks with:(DRDevice *)device {
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
    NSWindow *parent = [self parentWindow];
    [self finishAccepted:YES];

    // The progress panel is a sheet on the same window this one was, so it goes
    // up once ours is actually gone rather than fighting it for the position.
    dispatch_async(dispatch_get_main_queue(), ^{
        DRBurnProgressPanel *panel = [DRBurnProgressPanel progressPanel];
        [panel setDelegate:self];
        [panel setDescription:[NSString stringWithFormat:@"Burning \"%@\" to disc.", name]];
        [panel beginProgressSheetForBurn:burn layout:tracks modalForWindow:parent];
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
    // The framework read these for the whole burn, so this is the first moment
    // they can go.
    [_plan removeScratch];
    [BTBurnController releaseRunning];
}

@end
