#import "BTSheetController.h"

@class BTTrack;

// What is known about one song, and the few things about it that can be
// changed. Today that is where playback begins and where it ends; the window is
// shaped to take more later without moving what is already here.
//
// What comes back says whether anything was changed, which for this sheet is the
// same question as whether it was accepted.
@interface BTTrackInfoController : BTSheetController

- (instancetype)initWithTrack:(BTTrack *)track;

@end
