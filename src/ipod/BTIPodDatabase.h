#import <Foundation/Foundation.h>

// The iPod's own database, iPod_Control/iTunes/iTunesDB.
//
// The format is a tree of chunks, each tagged with a four letter type, a header
// length and a total length. Everything is little endian and strings are
// UTF-16. A fifth generation iPod is the last one that reads this file without
// a signed checksum, so an honest writer works.
//
// Reading is used to show what is already on the device. Writing replaces the
// database, and the caller is expected to back up the old one first.

@interface BTIPodTrackRef : NSObject
@property (nonatomic, assign) uint32_t trackID;
@property (nonatomic, copy) NSString *location;      // ":iPod_Control:Music:F04:ABCD.mp3"
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, copy) NSString *genre;
@property (nonatomic, copy) NSString *fileType;      // "MPEG audio file"
@property (nonatomic, assign) uint32_t sizeInBytes;
@property (nonatomic, assign) uint32_t durationMilliseconds;
@property (nonatomic, assign) uint32_t trackNumber;
@property (nonatomic, assign) uint32_t year;
@property (nonatomic, assign) uint32_t bitRate;
@property (nonatomic, assign) uint64_t persistentID;

- (NSString *)filesystemPathUnderMount:(NSString *)mountPath;
@end


@interface BTIPodPlaylistRef : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) BOOL isMaster;
@property (nonatomic, strong) NSMutableArray *trackIDs;   // NSNumber of uint32_t
@end


@interface BTIPodDatabase : NSObject

@property (nonatomic, readonly) NSMutableArray *tracks;      // BTIPodTrackRef
@property (nonatomic, readonly) NSMutableArray *playlists;   // BTIPodPlaylistRef

// Parses an existing database. Returns nil when the file is missing or is not
// in a shape this code recognizes.
+ (instancetype)databaseWithContentsOfFile:(NSString *)path;

+ (instancetype)emptyDatabase;

// Names of the playlists on the device, excluding the master list.
- (NSSet *)playlistNames;

// Serializes the whole database. deviceName becomes the master playlist name.
- (NSData *)serializedDataWithDeviceName:(NSString *)deviceName;

@end
