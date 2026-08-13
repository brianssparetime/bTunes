#import <Foundation/Foundation.h>

// Which folder a track's path is measured from. Both are per-machine settings,
// which is what lets one library be opened on another machine: point the setting
// at wherever the files are there and every track resolves again.
typedef NS_ENUM(NSInteger, BTPathRoot) {
    BTPathRootMusic = 0,    // the music folder, where nearly everything lives
    BTPathRootDetune        // the free recordings standing in for locked purchases
};

// One audio file in the library. Values are cached from the file's tags at
// import time; the file itself is never written to.
@interface BTTrack : NSObject

@property (nonatomic, copy) NSString *trackID;

// Where the file is, as the library records it: the part below its root when the
// file sits under one, and a full path beginning with a slash when it does not.
// Which of the two it is can be told from the leading slash.
//
// Storing it below the root is what lets one library be opened on another
// machine. A library written where the music is at ~/Music can be read where the
// same music is mounted at /Volumes/Music, and every track still resolves.
//
// Assigning a full path converts it, so nothing has to remember to. Assigning a
// path that is already relative leaves it alone. Assignment measures against
// whichever root is set at the time, so use setPath:root: when the file is not
// ordinary music and the two cannot get out of step.
@property (nonatomic, copy) NSString *path;

// Which root the path above is measured from. Music unless the track came from
// detune, and written to the library only when it did, so a library holding no
// substituted songs looks exactly as it did before they were possible.
@property (nonatomic, assign) BTPathRoot pathRoot;

// Sets both at once, in the order that makes them agree. Setting the path alone
// measures it against whatever root happens to be set, which is right for
// ordinary music and a trap for anything else.
- (void)setPath:(NSString *)path root:(BTPathRoot)root;
// The iTunes persistent id, kept when a track arrives from an iTunes library so
// a later pass can match it back to its source.
@property (nonatomic, copy) NSString *persistentID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *albumArtist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, copy) NSString *genre;
@property (nonatomic, copy) NSString *composer;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, assign) NSInteger trackNumber;
@property (nonatomic, assign) NSInteger discNumber;
@property (nonatomic, assign) NSInteger year;
@property (nonatomic, assign) NSInteger rating;      // 0 to 5 stars
@property (nonatomic, assign) NSInteger playCount;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) long long fileSize;
@property (nonatomic, strong) NSDate *dateAdded;
@property (nonatomic, strong) NSDate *lastPlayed;
// A DRM-locked purchase. It stays in the library so playlist membership
// survives, but nothing on this system can decode it.
@property (nonatomic, assign) BOOL isProtected;

// Where playback begins and ends within the file, for a song with a long silent
// tail, a run-in that is not wanted, or two songs sharing one file. Each is only
// obeyed while its flag is set, so a time can be turned off and kept rather than
// having to be typed again.
@property (nonatomic, assign) BOOL usesStartTime;
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) BOOL usesEndTime;
@property (nonatomic, assign) NSTimeInterval endTime;

// Where playback should begin, and where it should stop, taking the flags into
// account. The end is the track's own length when nothing was set.
- (NSTimeInterval)playbackStart;
- (NSTimeInterval)playbackEnd;

// Whole seconds as a clock reads them: m:ss, and h:mm:ss once there is an hour.
//
// Takes seconds already worked out rather than an interval, because how a
// fraction of a second is dealt with is the caller's business and the callers
// disagree on purpose: a song's length rounds to the nearest second, and the
// elapsed time truncates, since a readout that reaches 3:29 before the song
// does is wrong.
//
// The burn does not use this. A disc holds eighty minutes and says so, where
// this would say 1:20:00.
+ (NSString *)clockStringFromSeconds:(NSInteger)seconds;

// How long a list of songs runs, said the way a person would say it: the
// largest unit that gives a number worth saying, and the same time in minutes
// after it.
//
// The units run minutes, hours, days, months, years, decades, centuries, and
// the one used is the largest whose whole number reaches two. Forty-seven hours
// stays in hours and forty-eight becomes two days, because "1 day" tells a
// reader less than "25 hours" does.
//
// Minutes come second always, since that is the figure worth comparing one list
// against another. Past a million of them the exact count stops meaning
// anything and it is said in millions, then in billions.
+ (NSString *)runningTimeStringFromInterval:(NSTimeInterval)interval;

+ (instancetype)trackWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

// Where the file is on this machine, with the music root put back in front of
// it. Everything that opens, copies, or compares the file itself wants this
// rather than path.
- (NSString *)resolvedPath;
- (NSURL *)fileURL;
- (NSString *)displayTitle;      // falls back to the file name
- (NSString *)displayArtist;
- (NSString *)displayAlbum;
- (NSString *)displayGenre;
- (NSString *)durationString;    // m:ss

// Text used by the search field: title, artist, album, genre, composer.
- (BOOL)matchesSearchString:(NSString *)needle;

// Reads 90, 1:30, 1m30s, and 1:02:30 as times. Returns a negative number when
// the text cannot be read as one at all, so nothing is silently taken as zero.
+ (NSTimeInterval)timeFromText:(NSString *)text;
// The form the info window shows back, which timeFromText: reads again.
+ (NSString *)textFromTime:(NSTimeInterval)time;

@end
