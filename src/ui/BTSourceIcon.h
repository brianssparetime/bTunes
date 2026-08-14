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
    BTSourceIconDisc
};

// Drawn at the size a row shows it rather than scaled down from something
// larger: at fourteen points every one of these is a handful of pixels, and a
// shape that survives being drawn small is not the same shape as one shrunk.
@interface BTSourceIcon : NSObject

+ (NSImage *)iconOfKind:(BTSourceIconKind)kind;

@end
