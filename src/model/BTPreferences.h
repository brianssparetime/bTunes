#import <Foundation/Foundation.h>

// Posted when a setting changes. The database location change is applied by
// whoever posts it, so observers only have to reload.
extern NSString *const BTPreferencesDidChangeNotification;

// The two locations BTunes cares about, kept apart on purpose.
//
// The music folder is where the audio files live. It is a starting point for
// adding songs today, and the thing to change when the library moves to
// converted files.
//
// The database folder holds library.json, the ratings, play counts and
// playlists. Those are the irreplaceable part, so they are allowed to live
// somewhere other than the audio.
@interface BTPreferences : NSObject

+ (instancetype)sharedPreferences;

@property (nonatomic, copy) NSString *musicFolder;
@property (nonatomic, copy) NSString *databaseFolder;

// What the setting falls back to when it has never been chosen.
- (NSString *)defaultMusicFolder;
- (NSString *)defaultDatabaseFolder;

@end
