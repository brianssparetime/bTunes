#import <Foundation/Foundation.h>

// What the two lists put on the pasteboard.
//
// Named here rather than inside either list, because a drag has two ends: songs
// are written by the track list and read by the source list, so neither of them
// owns the name. Written out twice, one end could be renamed and the other
// would simply stop accepting drops, silently.
extern NSString *const BTTrackPasteboardType;
extern NSString *const BTPlaylistPasteboardType;
