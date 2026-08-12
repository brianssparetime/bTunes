#import <Foundation/Foundation.h>

@class BTIPod, BTPlaylist;

// Posted while a sync runs. userInfo carries "fraction" and "message".
extern NSString *const BTIPodSyncProgressNotification;
// Posted when a sync finishes, with "error" set when it failed.
extern NSString *const BTIPodSyncDidFinishNotification;

// Copies the songs of the chosen playlists onto the device and rewrites its
// database.
//
// The device keeps its own copies of the audio files, so a record of what came
// from where is kept beside the database in BTunesSync.plist: BTunes track id
// to the file on the device. That is what makes a second sync a delta rather
// than a full copy, and it is why nothing has to be matched by guessing at tags.
//
// The existing database is copied to iTunesDB.btunes-backup before anything is
// written.
@interface BTIPodSync : NSObject

+ (instancetype)syncWithIPod:(BTIPod *)iPod;

// Names of the playlists already on the device.
- (NSSet *)playlistNamesOnDevice;

// Playlists here are BTPlaylist objects, already flattened to leaves: the fifth
// generation firmware has no folders, so a folder contributes its contents. The
// songs themselves are resolved against the shared library.
- (void)syncPlaylists:(NSArray *)playlists completion:(void (^)(NSError *error))completion;

@property (nonatomic, readonly) BOOL running;

@end
