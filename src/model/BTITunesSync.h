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
// must not be imported a second time. Matching one that way is not the end of
// it: see fillsInTrackID below.
//
// A playlist is matched on its persistent id alone. Matching on name as well
// meant a playlist made here by hand was silently grown by an iTunes one that
// happened to share its name.

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
// The BTunes track this song already is, when that track got here by scanning a
// folder and so carries no iTunes identity at all. Nil for everything else.
//
// Such a song is in the library and its file is the right file, but nothing
// iTunes knows about it has ever reached it: no rating, no play count, no date
// added. Nor would it ever, since every sync saw the matching file and stopped
// there. Ticking one of these attaches the iTunes id and fills those in; it
// adds no second copy of the song.
@property (nonatomic, copy) NSString *fillsInTrackID;
@property (nonatomic, readonly) BOOL fillsInDetails;
// A free recording is standing in for a locked purchase, so this song comes
// from detune rather than from where iTunes keeps it.
@property (nonatomic, assign) BOOL fromDetune;
// A free copy of the same recording, already in the iTunes library, is standing
// in for a locked purchase. The song comes from where iTunes keeps it, but from
// a different file than the one this entry names.
@property (nonatomic, assign) BOOL fromTwin;
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
// Turned down the last time a sync ran, so it starts unticked. Only the tick
// it starts with: every one of these can still be ticked and brought across.
@property (nonatomic, assign) BOOL excludedBefore;
// iTunes persistent ids of the songs this playlist would add, in iTunes order.
@property (nonatomic, strong) NSArray *incomingTrackIDs;
@property (nonatomic, readonly) BOOL alreadyHere;
@property (nonatomic, readonly) BOOL eligible;
@end


// A song iTunes has put into a playlist that is already here.
//
// Neither list can name one of these on its own. The song is usually in the
// library already, so it is not among the incoming songs, and the playlist can
// say only how many it gained. The change is the joining of the two, so the
// joining is what is offered.
@interface BTITunesSyncModification : NSObject
@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, copy) NSString *playlistName;
@property (nonatomic, copy) NSString *songID;
@property (nonatomic, copy) NSString *songTitle;
@property (nonatomic, copy) NSString *songArtist;
// Turned down the last time a sync ran, so it starts unticked. Only the tick it
// starts with: every one of these can still be ticked and brought across.
@property (nonatomic, assign) BOOL excludedBefore;
// How the pair is remembered between syncs, and the only name it has. A
// persistent id names one song or one playlist and can never name the joining
// of the two. iTunes writes its ids as hex, so a slash appears in neither half
// and a key can never be mistaken for either.
@property (nonatomic, readonly) NSString *key;
+ (NSString *)keyForPlaylist:(NSString *)playlistID song:(NSString *)songID;
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
// Every song joining a playlist that is already here, for the playlists that
// could actually grow. Built here rather than worked out from the two lists
// above, which between them hold neither end of it.
@property (nonatomic, readonly) NSArray *modifications;   // BTITunesSyncModification
@property (nonatomic, readonly) NSString *error;

// "15 new songs to import, 1 new playlist, 9 songs added to 2 playlists",
// counting only what could actually come across.
- (NSString *)summary;

// Brings the chosen songs and playlists into the library. Both sets hold iTunes
// persistent ids. Songs are referenced where they already sit; nothing is moved
// or copied, and nothing is written back to iTunes.
//
// A playlist already here grows rather than being replaced, and its new songs
// join at the end so an arrangement made by hand is never disturbed. It grows by
// everything it gained except the keys named in skippedAdditions, so a playlist
// can come across holding some of what iTunes put in it and not the rest.
- (NSDictionary *)importInto:(BTLibrary *)library
                 chosenSongs:(NSSet *)songIDs
             chosenPlaylists:(NSSet *)playlistIDs
           skippedAdditions:(NSSet *)skippedKeys;

@end
