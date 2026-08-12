#import <Foundation/Foundation.h>

@class BTTrack, BTPlaylist;

// Posted whenever tracks or playlists change. The user interface reloads from
// the library rather than tracking incremental edits.
extern NSString *const BTLibraryDidChangeNotification;
// Posted while an import is running. userInfo has "path" and "count".
extern NSString *const BTLibraryImportProgressNotification;

@interface BTLibrary : NSObject

+ (instancetype)sharedLibrary;

@property (nonatomic, readonly) NSMutableArray *tracks;      // BTTrack
@property (nonatomic, readonly) NSMutableArray *playlists;   // top-level BTPlaylist
@property (nonatomic, readonly) BOOL importing;

- (NSString *)libraryFilePath;
- (void)loadFromDisk;
- (void)saveToDisk;

// Recursively imports every supported audio file under the given paths. Files
// already in the library are skipped. The completion block runs on the main
// thread with the number of tracks added.
- (void)importPaths:(NSArray *)paths completion:(void (^)(NSUInteger added))completion;

- (BTTrack *)trackWithID:(NSString *)trackID;
- (void)removeTracks:(NSArray *)tracks;

- (void)addPlaylist:(BTPlaylist *)playlist toFolder:(BTPlaylist *)folder;
- (void)removePlaylist:(BTPlaylist *)playlist;
- (void)movePlaylist:(BTPlaylist *)playlist toFolder:(BTPlaylist *)folder atIndex:(NSInteger)index;
- (BTPlaylist *)playlistWithID:(NSString *)playlistID;

- (void)noteChanged;   // posts the change notification and schedules a save

+ (NSArray *)supportedExtensions;

@end
