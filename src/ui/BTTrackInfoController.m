#import "BTTrackInfoController.h"
#import "BTTrack.h"
#import "BTStyle.h"
#import "BTControls.h"

#define BT_INFO_WIDTH 420.0

// Everything that follows the type. At the size this was drawn for these come to
// the numbers that used to be written out here: 17, 15, 14, 18, 22, and the
// steps 18, 20, 34, 30.
#define BT_HEAD   ([BTStyle lineHeight] + 4.0)    // the song's name
#define BT_SUB    ([BTStyle lineHeight] + 2.0)    // the artist and album under it
#define BT_NOTE   ([BTStyle smallLabelHeight])    // a gray note
#define BT_BOX    ([BTStyle lineHeight] + 5.0)    // a tick box and its words
#define BT_FIELD  ([BTStyle fieldHeight])

// One row down to the next. Each is a row plus the air under it, so the sheet
// opens out with the type rather than closing over it.
#define BT_STEP_TO_SUB   (BT_SUB + 3.0)
#define BT_STEP_TO_NOTE  (BT_NOTE + 6.0)
#define BT_STEP_TO_TIMES (BT_BOX + 16.0)
#define BT_STEP_BETWEEN  (BT_BOX + 12.0)
#define BT_STEP_TO_HINT  24.0

// The stack, top margin to the strip the buttons sit in.
#define BT_INFO_HEIGHT (38.0 + BT_STEP_TO_SUB + BT_STEP_TO_NOTE + BT_STEP_TO_TIMES \
                        + BT_STEP_BETWEEN + BT_STEP_TO_HINT + 50.0)

@implementation BTTrackInfoController {
    BTTrack *_track;
    NSTextField *_startField;
    NSTextField *_endField;
    NSButton *_startBox;
    NSButton *_endBox;
    void (^_completion)(BOOL changed);
}

- (instancetype)initWithTrack:(BTTrack *)track {
    NSRect frame = NSMakeRect(0, 0, BT_INFO_WIDTH, BT_INFO_HEIGHT);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSTitledWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"Song Info"];

    self = [super initWithWindow:window];
    if (self == nil) return nil;

    _track = track;
    [self buildInterface];
    return self;
}

- (void)buildInterface {
    NSView *content = [[self window] contentView];
    CGFloat y = BT_INFO_HEIGHT - 38;

    NSTextField *title = BTLabelWithText([_track displayTitle], [BTStyle boldFont]);
    [title setFrame:NSMakeRect(20, y, BT_INFO_WIDTH - 40, BT_HEAD)];
    [content addSubview:title];

    y -= BT_STEP_TO_SUB;
    NSTextField *by = BTLabelWithText([NSString stringWithFormat:@"%@ — %@",
                                       [_track displayArtist], [_track displayAlbum]],
                                      [BTStyle uiFont]);
    [by setTextColor:[BTStyle secondaryText]];
    [by setFrame:NSMakeRect(20, y, BT_INFO_WIDTH - 40, BT_SUB)];
    [content addSubview:by];

    y -= BT_STEP_TO_NOTE;
    NSTextField *length = BTLabelWithText([NSString stringWithFormat:@"Length %@",
                                           [_track durationString]], [BTStyle smallFont]);
    [length setTextColor:[BTStyle secondaryText]];
    [length setFrame:NSMakeRect(20, y, BT_INFO_WIDTH - 40, BT_NOTE)];
    [content addSubview:length];

    // The two times. Each keeps whatever was typed while its box is off, so
    // turning one off and on again does not mean typing it a second time.
    y -= BT_STEP_TO_TIMES;
    _startBox = [self boxTitled:@"Start playback at" on:_track.usesStartTime atY:y in:content];
    _startField = [self fieldWithTime:_track.startTime
                              enabled:_track.usesStartTime
                                  atY:y
                                   in:content];

    y -= BT_STEP_BETWEEN;
    _endBox = [self boxTitled:@"End playback at" on:_track.usesEndTime atY:y in:content];
    _endField = [self fieldWithTime:(_track.usesEndTime ? _track.endTime : _track.duration)
                            enabled:_track.usesEndTime
                                atY:y
                                 in:content];

    y -= BT_STEP_TO_HINT;
    NSTextField *hint = BTLabelWithText(@"Written as 90, 1:30, or 1m30s.", [BTStyle smallFont]);
    [hint setTextColor:[BTStyle secondaryText]];
    [hint setFrame:NSMakeRect(160, y, BT_INFO_WIDTH - 180, BT_NOTE)];
    [content addSubview:hint];

    BTPushButton *cancel = [BTPushButton buttonWithTitle:@"Cancel" target:self action:@selector(cancel:)];
    [cancel setFrame:NSMakeRect(BT_INFO_WIDTH - 190, 14, 80, NSHeight([cancel frame]))];
    [cancel setKeyEquivalent:@"\033"];
    [content addSubview:cancel];

    BTPushButton *ok = [BTPushButton buttonWithTitle:@"OK" target:self action:@selector(accept:)];
    [ok setFrame:NSMakeRect(BT_INFO_WIDTH - 104, 14, 84, NSHeight([ok frame]))];
    [ok setKeyEquivalent:@"\r"];
    [content addSubview:ok];
}

- (NSButton *)boxTitled:(NSString *)title on:(BOOL)on atY:(CGFloat)y in:(NSView *)content {
    NSButton *box = [[NSButton alloc] initWithFrame:NSMakeRect(20, y, 150, BT_BOX)];
    [box setButtonType:NSSwitchButton];
    [box setTitle:title];
    [box setFont:[BTStyle uiFont]];
    [box setState:(on ? NSOnState : NSOffState)];
    [box setTarget:self];
    [box setAction:@selector(boxChanged:)];
    [content addSubview:box];
    return box;
}

- (NSTextField *)fieldWithTime:(NSTimeInterval)time
                       enabled:(BOOL)enabled
                           atY:(CGFloat)y
                            in:(NSView *)content {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(178, y - 2, 90, BT_FIELD)];
    [field setFont:[BTStyle uiFont]];
    [field setStringValue:[BTTrack textFromTime:time]];
    [field setEnabled:enabled];
    [content addSubview:field];
    return field;
}

// A field with nothing to say while its box is off, so it is plain which of the
// two times is actually being obeyed.
- (void)boxChanged:(id)sender {
    [_startField setEnabled:([_startBox state] == NSOnState)];
    [_endField setEnabled:([_endBox state] == NSOnState)];
    if (sender == _startBox && [_startBox state] == NSOnState) {
        [[self window] makeFirstResponder:_startField];
    } else if (sender == _endBox && [_endBox state] == NSOnState) {
        [[self window] makeFirstResponder:_endField];
    }
}

#pragma mark - Sheet

- (void)beginSheetForWindow:(NSWindow *)parent completion:(void (^)(BOOL changed))completion {
    _completion = [completion copy];
    [parent beginSheet:[self window] completionHandler:nil];
}

- (void)finishChanged:(BOOL)changed {
    NSWindow *sheet = [self window];
    [[sheet sheetParent] endSheet:sheet];
    [sheet orderOut:nil];
    if (_completion) _completion(changed);
    _completion = nil;
}

- (void)complain:(NSString *)what {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:what];
    [alert setInformativeText:@"A time is written as 90, 1:30, or 1m30s."];
    [alert runModal];
}

- (void)accept:(id)sender {
    BOOL wantsStart = ([_startBox state] == NSOnState);
    BOOL wantsEnd = ([_endBox state] == NSOnState);

    // Refused rather than taken as zero, so a slip does not quietly set a song
    // to start at the beginning or stop at once.
    NSTimeInterval start = wantsStart ? [BTTrack timeFromText:[_startField stringValue]] : 0.0;
    if (wantsStart && start < 0) {
        [self complain:@"That start time cannot be read."];
        return;
    }
    NSTimeInterval end = wantsEnd ? [BTTrack timeFromText:[_endField stringValue]] : 0.0;
    if (wantsEnd && end < 0) {
        [self complain:@"That end time cannot be read."];
        return;
    }
    if (wantsStart && wantsEnd && end <= start) {
        [self complain:@"The end comes before the start."];
        return;
    }

    _track.usesStartTime = wantsStart;
    if (wantsStart) _track.startTime = start;
    _track.usesEndTime = wantsEnd;
    if (wantsEnd) _track.endTime = end;

    [self finishChanged:YES];
}

- (void)cancel:(id)sender {
    [self finishChanged:NO];
}

@end
