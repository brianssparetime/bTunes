#import <Foundation/Foundation.h>

// Posted when a setting changes. The database location change is applied by
// whoever posts it, so observers only have to reload.
extern NSString *const BTPreferencesDidChangeNotification;

// The two locations BTunes cares about, kept apart on purpose.
//
// The music folder is the root every track's path is stored against. A track
// records the part of its path below this folder, so moving the setting points
// the whole library at the same music somewhere else: another disk, a mounted
// share, or the converted files when detune finishes with them. It is also
// where the panel that adds songs starts.
//
// The database folder holds library.json, the ratings, play counts and
// playlists. Those are the irreplaceable part, so they are allowed to live
// somewhere other than the audio.
@interface BTPreferences : NSObject

+ (instancetype)sharedPreferences;

@property (nonatomic, copy) NSString *musicFolder;
@property (nonatomic, copy) NSString *databaseFolder;

// The iTunes library file a sync compares against. Read and never written, so
// pointing it at the real one is safe; pointing it at a copy is safer still
// while trying something out.
@property (nonatomic, copy) NSString *iTunesLibraryPath;

// Whether the main window is drawn in purple rather than blue. Off unless asked
// for, and remembered. The mini player is purple either way, so this does not
// touch it.
@property (nonatomic, assign) BOOL purpleMode;

// What the setting falls back to when it has never been chosen.
- (NSString *)defaultMusicFolder;
- (NSString *)defaultDatabaseFolder;
- (NSString *)defaultITunesLibraryPath;

@end
