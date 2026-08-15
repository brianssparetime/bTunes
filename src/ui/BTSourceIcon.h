#import <Cocoa/Cocoa.h>

// Which mark sits beside a row in the left bar.
//
// The drawing is told the kind rather than handed the row, so it needs to know
// nothing about what a source is: not the two strings that stand for the library
// and its by-date view, not the classes an iPod and a disc are. Working out
// which kind a row is stays where the rows are.
typedef NS_ENUM(NSInteger, BTSourceIconKind) {
    BTSourceIconLibrary = 0,
    BTSourceIconRecentlyAdded,
    BTSourceIconPlaylist,
    BTSourceIconSmartPlaylist,
    BTSourceIconFolder,
    BTSourceIconIPod,
    BTSourceIconDisc,
    BTSourceIconITunes
};

// Drawn at the size a row shows it rather than scaled down from something
// larger: at sixteen points every one of these is a handful of pixels, and a
// shape that survives being drawn small is not the same shape as one shrunk.
@interface BTSourceIcon : NSObject

// How wide and tall every one of them comes out, so a row can lay itself out
// without repeating the number.
+ (CGFloat)side;

+ (NSImage *)iconOfKind:(BTSourceIconKind)kind;

@end
