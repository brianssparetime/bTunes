#import <Foundation/Foundation.h>

// One audio file in the library. Values are cached from the file's tags at
// import time; the file itself is never written to.
@interface BTTrack : NSObject

@property (nonatomic, copy) NSString *trackID;

// Where the file is, as the library records it: the part below the music root
// when the file sits under it, and a full path beginning with a slash when it
// does not. Which of the two it is can be told from the leading slash, so no
// second field is needed.
//
// Storing it below the root is what lets one library be opened on another
// machine. The root is a per-machine setting, so a library written where the
// music is at ~/Music can be read where the same music is mounted at
// /Volumes/Music, and every track still resolves.
//
// Assigning a full path converts it, so nothing has to remember to. Assigning a
// path that is already relative leaves it alone.
@property (nonatomic, copy) NSString *path;
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

@end
