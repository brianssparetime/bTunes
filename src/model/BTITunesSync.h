#import <Foundation/Foundation.h>
#import "BTITunesEntry.h"

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

// A song iTunes has that BTunes does not.
@interface BTITunesSyncTrack : NSObject
@property (nonatomic, copy) NSString *persistentID;
// Where the file already sits. Nil when iTunes holds only a cloud copy, which
// is a thing BTunes has nothing to point at.
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, assign) BTITunesBlock blocked;
// Left behind in an earlier sync. This decides nothing about what may be
// imported; it only says the box should start unticked, so a song turned down
// once does not have to be turned down again. Ticking it imports it.
@property (nonatomic, assign) BOOL excludedBefore;
@property (nonatomic, assign) BOOL alreadyHere;      // imported by an earlier sync
// A free recording is standing in for a locked purchase, so this song comes
// from detune rather than from where iTunes keeps it.
@property (nonatomic, assign) BOOL fromDetune;
// The entry as it was read, kept so the import points at the file eligibility
// was decided about rather than working the question out a second time and
// possibly differently.
@property (nonatomic, strong) BTITunesEntry *source;
// Something this sync could actually bring across.
@property (nonatomic, readonly) BOOL eligible;
@end


typedef NS_ENUM(NSInteger, BTITunesPlaylistChange) {
    BTITunesPlaylistIsNew = 0,
    BTITunesPlaylistGrew,       // already here, and iTunes has songs it lacks
    BTITunesPlaylistUnchanged   // already here with nothing to add
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
@property (nonatomic, readonly) BOOL alreadyHere;
@property (nonatomic, readonly) BOOL eligible;
@end


@interface BTITunesSync : NSObject

// Reads the file and compares it against the library. Returns a sync whose
// error is set when the file could not be read.
//
// This takes a few seconds on the target machine, nearly all of it spent asking
// the filesystem about six thousand files, so a window should use the form
// below instead and say what it is doing meanwhile.
+ (instancetype)syncWithLibraryAtPath:(NSString *)path against:(BTLibrary *)library;

// The same comparison, off the main thread. Both blocks are called on the main
// thread: progress several times as it goes, completion once at the end.
+ (void)syncWithLibraryAtPath:(NSString *)path
                      against:(BTLibrary *)library
                     progress:(void (^)(double fraction, NSString *stage))progress
                   completion:(void (^)(BTITunesSync *sync))completion;

@property (nonatomic, readonly) NSArray *incomingTracks;   // BTITunesSyncTrack
@property (nonatomic, readonly) NSArray *playlists;    // BTITunesSyncPlaylist
@property (nonatomic, readonly) NSString *error;

// "15 new songs to import, 1 new playlist, 2 playlist modifications", counting
// only what could actually come across.
- (NSString *)summary;

// Brings the chosen songs and playlists into the library. Both sets hold iTunes
// persistent ids. Songs are referenced where they already sit; nothing is moved
// or copied, and nothing is written back to iTunes.
//
// A playlist already here grows rather than being replaced, and its new songs
// join at the end so an arrangement made by hand is never disturbed.
- (NSDictionary *)importInto:(BTLibrary *)library
                 chosenSongs:(NSSet *)songIDs
             chosenPlaylists:(NSSet *)playlistIDs;

@end
