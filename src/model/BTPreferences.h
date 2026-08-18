#import <Foundation/Foundation.h>

// Posted when a setting changes. The database location change is applied by
// whoever posts it, so observers only have to reload.
extern NSString *const BTPreferencesDidChangeNotification;

// Two folders are chosen and everything else is worked out from them.
//
// The BTunes home holds everything BTunes owns: its database, the free
// recordings from detune, songs taken off a CD, and the folders podcasts and
// hand-added music will use. Each of those is a path root, so a track records
// which one its path is measured from and the whole home moves to another disk
// by pointing this one setting at it.
//
// The iTunes home is read and never written. The music root every ordinary
// track is measured from sits inside it, at whichever of the layouts iTunes has
// used over the years is actually there.
//
// The folders inside the two homes are named by the layout rather than chosen,
// which is what keeps the next kind of file from becoming a seventh setting.
// Any of them can still be pointed elsewhere from the file at
// +configFilePath, for a test run or a machine laid out differently.
@interface BTPreferences : NSObject

+ (instancetype)sharedPreferences;

@property (nonatomic, copy) NSString *btunesHome;
@property (nonatomic, copy) NSString *iTunesHome;

// The iTunes library file a sync compares against. Read and never written, so
// pointing it at the real one is safe; pointing it at a copy is safer still
// while trying something out. Empty means the usual names inside the iTunes
// home, in the order iTunes has used them.
@property (nonatomic, copy) NSString *iTunesLibraryPath;

// Where the ratings, play counts and playlists live. The irreplaceable part.
@property (nonatomic, copy) NSString *databaseFolder;

// The root nearly every song is measured from, inside the iTunes home.
@property (nonatomic, copy) NSString *musicFolder;

// The folder holding detune-mapping.json and the free recordings it describes,
// which stand in for the locked purchases iTunes will not let anything decode.
// A folder that is not there means the substitution simply does not happen:
// locked songs stay locked and nothing else changes.
//
// The folder is self-contained and names no absolute path inside itself, so
// moving it into the home carries every substituted song with it.
@property (nonatomic, copy) NSString *detuneFolder;

// Where BTunes puts music it made itself, which today means songs taken off a
// CD. Kept apart from the iTunes music folder because that folder belongs to
// iTunes and nothing here writes to it.
//
// Laid out the way iTunes lays one out, artist then album then the songs, so it
// reads the same as the folder beside it and could be pointed at by anything
// else that expects that shape.
@property (nonatomic, copy) NSString *importedCDsFolder;

// Not yet used. Named here so the layout is settled and the roots that will
// hold them are already in the library's vocabulary.
@property (nonatomic, readonly) NSString *podcastsFolder;
@property (nonatomic, readonly) NSString *addedMusicFolder;

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

// What each setting falls back to when it has never been chosen.
- (NSString *)defaultBTunesHome;
- (NSString *)defaultITunesHome;
- (NSString *)defaultMusicFolder;
- (NSString *)defaultDatabaseFolder;
- (NSString *)defaultDetuneFolder;
- (NSString *)defaultImportedCDsFolder;
- (NSString *)defaultITunesLibraryPath;

// The file BTunes is tried against on the machine it is developed for, offered
// when the alternative library is asked for and nothing has been chosen yet.
- (NSString *)suggestedAlternateITunesLibraryPath;

// Drops a folder chosen before the homes existed when what it names is no
// longer there and the layout's own place for it is. Moving "detune files" into
// the home by hand would otherwise leave the old choice pointing at nothing, and
// a detune folder that is not there means every locked song quietly stays
// locked with no reason given.
- (void)forgetSavedFoldersThatHaveMoved;

// Drops the database folder chosen before the home existed. Said by whoever
// moved the database, and only once it is demonstrably at its new place.
- (void)forgetSavedDatabaseFolder;

// Where the folders inside the two homes can be pointed somewhere else. It
// cannot live inside the BTunes home, since it is the thing that says where the
// BTunes home is, so it sits in Application Support: the pointer there, the
// data in the music folder. Read once, and nothing in the interface writes it.
+ (NSString *)configFilePath;

@end
