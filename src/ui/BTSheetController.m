#import "BTSheetController.h"
#import "BTControls.h"

// Where the two buttons sit, in from the right edge of the sheet and up from its
// floor. The accepting one is wider because it carries the longer word: OK,
// Burn, and whatever a later dialog wants.
#define BT_SHEET_BUTTON_FOOT    14.0
#define BT_SHEET_CANCEL_RIGHT  190.0
#define BT_SHEET_CANCEL_WIDTH   80.0
#define BT_SHEET_ACCEPT_RIGHT  104.0
#define BT_SHEET_ACCEPT_WIDTH   84.0

@implementation BTSheetController {
    void (^_completion)(BOOL accepted);
}

- (void)addButtonsAccepting:(NSString *)title
                     action:(SEL)accept
                     cancel:(SEL)cancel
                    inWidth:(CGFloat)width {
    NSView *content = [[self window] contentView];

    _cancelButton = [BTPushButton buttonWithTitle:@"Cancel" target:self action:cancel];
    [_cancelButton setKeyEquivalent:@"\033"];
    [_cancelButton setFrame:NSMakeRect(width - BT_SHEET_CANCEL_RIGHT, BT_SHEET_BUTTON_FOOT,
                                       BT_SHEET_CANCEL_WIDTH, NSHeight([_cancelButton frame]))];
    [content addSubview:_cancelButton];

    _acceptButton = [BTPushButton buttonWithTitle:title target:self action:accept];
    [_acceptButton setKeyEquivalent:@"\r"];
    [_acceptButton setFrame:NSMakeRect(width - BT_SHEET_ACCEPT_RIGHT, BT_SHEET_BUTTON_FOOT,
                                       BT_SHEET_ACCEPT_WIDTH, NSHeight([_acceptButton frame]))];
    [content addSubview:_acceptButton];
}

- (void)beginSheetForWindow:(NSWindow *)parent completion:(void (^)(BOOL accepted))completion {
    _parentWindow = parent;
    _completion = [completion copy];
    [parent beginSheet:[self window] completionHandler:nil];
}

- (void)finishAccepted:(BOOL)accepted {
    NSWindow *sheet = [self window];
    [[sheet sheetParent] endSheet:sheet];
    [sheet orderOut:nil];

    // Let go of before it is run, so a completion that opens another sheet on
    // this one cannot reach round and be run a second time.
    void (^completion)(BOOL) = _completion;
    _completion = nil;
    if (completion) completion(accepted);
}

@end
