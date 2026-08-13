#import "BTLibrary.h"
#import "BTITunesEntry.h"

@class BTTrack;

// Reads an iTunes library XML file and reproduces its tracks, playlists, and
// folder structure inside BTunes.
//
// The XML is read and never written. Ratings, play counts, and date-added
// values are carried across, since those cannot be re-derived.
//
// Two limits are worth knowing about. Smart playlist criteria live in an
// undocumented binary blob that iTunes does not publish in readable form, so a
// smart playlist arrives as an ordinary playlist holding the songs it resolved
// to at export time. Protected purchases arrive as entries that cannot play
// until they are converted to an open format; keeping them preserves playlist
// membership so a later conversion has somewhere to land.
@interface BTLibrary (ITunesImport)

// Paths worth trying, in order, inside a given home directory.
+ (NSArray *)iTunesLibraryPathsForHome:(NSString *)home;

// Adds everything found in the file to the current library. A track limit
// above zero stops after that many new tracks, for trying the import out on a
// sample; zero imports everything. Returns a summary with the keys
// "tracksAdded", "tracksSkipped", "protectedTracks", "playlistsAdded",
// "foldersAdded", "smartAsStatic", and "error".
- (NSDictionary *)importITunesLibraryAtPath:(NSString *)path trackLimit:(NSInteger)trackLimit;

// One iTunes entry turned into a track. Takes an entry that has already been
// read, rather than the raw dictionary, so that the file a track points at is
// the one eligibility was decided about. Working the path out again here is how
// a song comes to be judged importable and then imported as its locked original.
- (BTTrack *)trackFromEntry:(BTITunesEntry *)source;

@end
