#import <Foundation/Foundation.h>

// Posted when a blank disc arrives or goes, and only then. The drive says a
// great deal about itself as a disc is read, and the window only cares about the
// one answer.
extern NSString *const BTBlankDiscDidChangeNotification;

// Whether there is a disc in the drive that could be burned.
//
// Separate from BTBurnPlan, which answers about a playlist and asks the drive
// once when it is about to write. This is the standing question the window needs
// answered all the time, so it watches rather than asks.
@interface BTBlankDisc : NSObject

// A blank CD-R or CD-RW, in a drive that writes them.
+ (BOOL)present;

+ (void)startWatching;

@end
