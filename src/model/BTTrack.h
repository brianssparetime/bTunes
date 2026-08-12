#import <Foundation/Foundation.h>

// One audio file in the library. Values are cached from the file's tags at
// import time; the file itself is never written to.
@interface BTTrack : NSObject

@property (nonatomic, copy) NSString *trackID;
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

- (NSURL *)fileURL;
- (NSString *)displayTitle;      // falls back to the file name
- (NSString *)displayArtist;
- (NSString *)displayAlbum;
- (NSString *)displayGenre;
- (NSString *)durationString;    // m:ss

// Text used by the search field: title, artist, album, genre, composer.
- (BOOL)matchesSearchString:(NSString *)needle;

@end
