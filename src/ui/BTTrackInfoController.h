#import <Cocoa/Cocoa.h>

@class BTTrack;

// What is known about one song, and the few things about it that can be
// changed. Today that is where playback begins and where it ends; the window is
// shaped to take more later without moving what is already here.
@interface BTTrackInfoController : NSWindowController

- (instancetype)initWithTrack:(BTTrack *)track;
- (void)beginSheetForWindow:(NSWindow *)parent completion:(void (^)(BOOL changed))completion;

@end
