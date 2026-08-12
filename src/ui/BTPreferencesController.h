#import <Cocoa/Cocoa.h>

// Two settings: where the music files live, and where the library that
// describes them lives.
@interface BTPreferencesController : NSWindowController
+ (instancetype)sharedController;
@end
