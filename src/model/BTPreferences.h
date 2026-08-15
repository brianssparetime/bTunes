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

// Where BTunes puts music it made itself, which today means songs taken off a
// CD. A third root, kept apart from the iTunes music folder because that folder
// belongs to iTunes and nothing here writes to it.
//
// Laid out the way iTunes lays one out, artist then album then the songs, so it
// reads the same as the folder beside it and could be pointed at by anything
// else that expects that shape.
@property (nonatomic, copy) NSString *btunesFolder;

// What a song taken off a CD is encoded as. AAC unless asked otherwise: a disc
// is about six hundred megabytes as it stands, half that as Apple Lossless, and
// a tenth as AAC. Lossless is there for anyone who would rather spend the disk.
@property (nonatomic, assign) BOOL importsLossless;

// Whether a disc that does not name itself is looked up on MusicBrainz. On
// unless turned off, because most commercial CDs carry no CD-Text and a disc
// full of "Track 1" is close to useless in a library this size.
//
// The only thing in BTunes that reaches outside the machine. What goes out is
// the disc's table of contents, boiled down to a number; nothing about the
// library goes with it.
@property (nonatomic, assign) BOOL looksUpDiscs;

// Whether songs are brought to the same loudness as each other while they play.
// Off unless asked for, since it is an alteration to what the recording says,
// and remembered.
//
// A setting rather than a number kept per song: what to do about the difference
// is a choice about this machine, while the difference itself belongs to the
// recording and is kept in the library beside the ratings.
@property (nonatomic, assign) BOOL evensOutVolume;

// Whether the main window is drawn in purple rather than blue. Off unless asked
// for, and remembered. The mini player is purple either way, so this does not
// touch it.
@property (nonatomic, assign) BOOL purpleMode;

// What the setting falls back to when it has never been chosen.
- (NSString *)defaultMusicFolder;
- (NSString *)defaultBTunesFolder;
- (NSString *)defaultDatabaseFolder;
- (NSString *)defaultITunesLibraryPath;

@end
