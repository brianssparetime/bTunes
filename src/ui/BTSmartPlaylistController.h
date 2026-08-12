#import <Cocoa/Cocoa.h>

@class BTPlaylist;

// Sheet for building and editing a smart playlist's rules.
@interface BTSmartPlaylistController : NSWindowController

- (instancetype)initWithPlaylist:(BTPlaylist *)playlist;
- (void)beginSheetForWindow:(NSWindow *)parent completion:(void (^)(BOOL accepted))completion;

@end
