#import <Foundation/Foundation.h>

@class BTTrack, BTPlaylist;

// Posted whenever tracks or playlists change. The user interface reloads from
// the library rather than tracking incremental edits.
extern NSString *const BTLibraryDidChangeNotification;

// Posted when a song records something about itself — a play count, a date last
// played — and nothing has joined or left any list.
//
// Separate because the reload above is not cheap: it rebuilds the left bar, the
// three browser columns and the sort, over the whole library. Starting a song
// raises its play count, so on a library this size the reload was the largest
// thing that happened every time a song began, all to move one number.
extern NSString *const BTLibraryTrackDidChangeNotification;

@interface BTLibrary : NSObject

+ (instancetype)sharedLibrary;

@property (nonatomic, readonly) NSMutableArray *tracks;      // BTTrack
@property (nonatomic, readonly) NSMutableArray *playlists;   // top-level BTPlaylist

- (NSString *)libraryFilePath;
// Where the library would sit with no setting chosen: the environment
// override, a folder beside the application, or Application Support.
+ (NSString *)unconfiguredSupportDirectory;
- (void)loadFromDisk;
- (void)saveToDisk;

// Tracks whose file is not where the library says it is.
//
// Reading only, and nothing is ever removed on the strength of it. A file that
// is gone this morning may be a volume that is not mounted, a folder iTunes has
// renamed, or a music root pointed somewhere else for the afternoon. The
// ratings and play counts hanging off the entry cannot be got back, and the
// audio usually can.
- (NSArray *)tracksWithMissingFiles;

// Writes those tracks out and returns where it put them, or nil if it could
// not. Beside the database, since that is BTunes' own folder.
- (NSString *)writeMissingFilesLog:(NSArray *)tracks;
- (NSString *)missingFilesLogPath;

// Puts a song in the library and records where its file is.
//
// Every route in goes through here: a folder scanned, a sync from iTunes, a CD
// taken in, and the database read back at startup. The record of which files
// are already held is what stops a later scan of the same folder offering them
// a second time, and reaching past this to the array leaves that record short
// by however many songs took the shortcut.
- (void)addTrack:(BTTrack *)track;

// The song already recorded against a file, or nil. What anything writing a
// file into the library asks before adding a second entry pointing at it:
// taking a CD in twice replaced the audio and then held the same file twice
// over, once under each import.
- (BTTrack *)trackWithFileAtPath:(NSString *)path;

// Recursively imports every supported audio file under the given paths. Files
// already in the library are skipped. The completion block runs on the main
// thread with the number of tracks added.
- (void)importPaths:(NSArray *)paths completion:(void (^)(NSUInteger added))completion;

- (void)removeTracks:(NSArray *)tracks;

- (void)addPlaylist:(BTPlaylist *)playlist toFolder:(BTPlaylist *)folder;
- (void)removePlaylist:(BTPlaylist *)playlist;
- (void)movePlaylist:(BTPlaylist *)playlist toFolder:(BTPlaylist *)folder atIndex:(NSInteger)index;
- (BTPlaylist *)playlistWithID:(NSString *)playlistID;

// iTunes persistent ids deliberately left behind during a sync, songs and
// playlists alike. Unticked once, it comes up unticked, so something not wanted
// here does not have to be fought off every sync. Kept with the library rather
// than in this machine's settings, so the decision follows the library.
//
// Only ever the tick a row starts with. Whether something *can* come across is
// worked out from the iTunes entry and never from this: a remembered choice
// that decides eligibility makes rows that cannot be ticked and gives no reason,
// which is a fault this has had once already.
- (NSSet *)excludedFromImport;
- (void)setExcluded:(BOOL)excluded forPersistentIDs:(NSArray *)persistentIDs;

- (void)noteChanged;        // posts the change notification and schedules a save
// The same save, the lighter notification. For a play count or a date, never
// for a song or a playlist joining or leaving.
- (void)noteTrackChanged;

+ (NSArray *)supportedExtensions;

@end
