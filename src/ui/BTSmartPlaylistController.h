#import "BTSheetController.h"

@class BTPlaylist;

// Sheet for building and editing a smart playlist's rules. Going up, coming
// down, and the two buttons at the foot are the base class's business.
@interface BTSmartPlaylistController : BTSheetController

- (instancetype)initWithPlaylist:(BTPlaylist *)playlist;

@end
