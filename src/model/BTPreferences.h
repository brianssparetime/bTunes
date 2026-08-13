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
// The database folder holds btunes_library.json, the ratings, play counts and
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

// The folder holding detune-mapping.json and the free recordings it describes,
// which stand in for the locked purchases iTunes will not let anything decode.
// Empty until one exists, and empty means the substitution simply does not
// happen: locked songs stay locked and nothing else changes.
//
// A second root, and the reason a track records which root its path belongs to.
// The folder is self-contained and names no absolute path inside itself, so
// moving it and repointing this setting carries every substituted song with it.
@property (nonatomic, copy) NSString *detuneFolder;

// Whether the main window is drawn in purple rather than blue. Off unless asked
// for, and remembered. The mini player is purple either way, so this does not
// touch it.
@property (nonatomic, assign) BOOL purpleMode;

// What the setting falls back to when it has never been chosen.
- (NSString *)defaultMusicFolder;
- (NSString *)defaultDatabaseFolder;
- (NSString *)defaultITunesLibraryPath;

@end
