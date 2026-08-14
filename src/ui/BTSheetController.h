#import <Cocoa/Cocoa.h>

@class BTPushButton;

// What every dialog here has in common: it goes up as a sheet on the window it
// is about, it ends in Cancel and one accepting button along the bottom right,
// and it tells whoever opened it which of the two was pressed.
//
// Three dialogs wrote all of that out separately, including the same four
// numbers placing the buttons, so any one of them could drift from the others
// and nothing would say so.
@interface BTSheetController : NSWindowController

// The window the sheet hangs from. Held rather than asked for, because a sheet
// sometimes has something to say to it after coming down: the burn puts the
// system's progress panel on this same window a moment later.
@property (nonatomic, strong, readonly) NSWindow *parentWindow;

@property (nonatomic, readonly) BTPushButton *cancelButton;
@property (nonatomic, readonly) BTPushButton *acceptButton;

// The two buttons, in the order the system puts them: the accepting one
// furthest right and answering Return, Cancel beside it answering Escape. The
// width is the sheet's, since both are placed in from its right edge.
- (void)addButtonsAccepting:(NSString *)title
                     action:(SEL)accept
                     cancel:(SEL)cancel
                    inWidth:(CGFloat)width;

- (void)beginSheetForWindow:(NSWindow *)parent completion:(void (^)(BOOL accepted))completion;

// Takes the sheet down and hands the answer back. The answer is given once
// however often this is called, since a dialog that reports twice is worse than
// one that reports late.
- (void)finishAccepted:(BOOL)accepted;

@end
