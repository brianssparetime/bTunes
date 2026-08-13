#import <Foundation/Foundation.h>

@class BTLibrary;

// Works out what iTunes has that BTunes does not, without changing either.
//
// Reading only. The XML is opened, compared, and closed. Nothing here writes to
// the iTunes library, and no audio file is moved or copied at any stage: an
// import records where a file already sits.
//
// A song is matched first on its iTunes persistent id and then on its file
// path, because songs added here by scanning a folder carry no iTunes id and
// must not be imported a second time.

// Why something cannot be brought across yet. Blocked things are listed and
// shown, greyed, rather than hidden, so it is clear they exist and are waiting.
typedef NS_ENUM(NSInteger, BTITunesBlock) {
    BTITunesBlockNone = 0,
    BTITunesBlockProtected,        // a locked purchase nothing here can decode
    BTITunesBlockHoldsProtected,   // a playlist holding one
    BTITunesBlockSmart             // rules iTunes does not publish
};

// A song iTunes has that BTunes does not.
@interface BTITunesSyncTrack : NSObject
@property (nonatomic, copy) NSString *persistentID;
@property (nonatomic, copy) NSString *path;          // where it already sits
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, assign) BTITunesBlock blocked;
@property (nonatomic, assign) BOOL excludedBefore;   // left behind in an earlier sync
@property (nonatomic, readonly) BOOL eligible;       // neither blocked nor excluded
@end


typedef NS_ENUM(NSInteger, BTITunesPlaylistChange) {
    BTITunesPlaylistIsNew = 0,
    BTITunesPlaylistGrew        // already here, and iTunes has songs it lacks
};

@interface BTITunesSyncPlaylist : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *persistentID;
// The folders it sits under, outermost first. Empty at the top level.
@property (nonatomic, strong) NSArray *folderNames;
@property (nonatomic, assign) BTITunesPlaylistChange change;
@property (nonatomic, assign) BTITunesBlock blocked;
// iTunes persistent ids of the songs this playlist would add, in iTunes order.
@property (nonatomic, strong) NSArray *incomingTrackIDs;
@property (nonatomic, readonly) BOOL eligible;
@end


@interface BTITunesSync : NSObject

// Reads the file and compares it against the library. Returns a sync whose
// error is set when the file could not be read.
+ (instancetype)syncWithLibraryAtPath:(NSString *)path against:(BTLibrary *)library;

@property (nonatomic, readonly) NSArray *incomingTracks;   // BTITunesSyncTrack
@property (nonatomic, readonly) NSArray *playlists;    // BTITunesSyncPlaylist
@property (nonatomic, readonly) NSString *error;

// "15 new songs to import, 1 new playlist, 2 playlist modifications", counting
// only what could actually come across.
- (NSString *)summary;

@end
