#import "BTLibrary.h"
#import "BTITunesEntry.h"

@class BTTrack;

// Reading an iTunes library: turning one of its entries into a track, and
// finding a song again once the file has moved.
//
// The XML is read and never written. Ratings, play counts, and date-added
// values are carried across, since those cannot be re-derived.
//
// Bringing music over is the sync's job and only the sync's. There used to be a
// second way in from the File menu that took the whole file at once, with no
// comparison and nothing to choose, and it disagreed with the sync about what
// may come across: it imported locked purchases the sync blocks, and remembered
// nothing about what had been turned down. Two importers with different rules
// is the shape of a bug rather than a convenience.
@interface BTLibrary (ITunesImport)

// One iTunes entry turned into a track. Takes an entry that has already been
// read, rather than the raw dictionary, so that the file a track points at is
// the one eligibility was decided about. Working the path out again here is how
// a song comes to be judged importable and then imported as its locked original.
- (BTTrack *)trackFromEntry:(BTITunesEntry *)source;

// What iTunes knows about a song already in the library, put onto it.
//
// For a song that got here by scanning a folder: the file is right and the
// listening history is missing, because a scan reads tags and tags carry none
// of it. The track takes the iTunes id so it is recognised by id from now on.
//
// Nothing already recorded is thrown away. The play counts are added, since
// both are real listening; the earlier date added wins, since that is when the
// song was first had; the later date played wins for the same reason. Returns
// whether anything was taken.
- (BOOL)fillInTrack:(BTTrack *)track fromEntry:(BTITunesEntry *)source;

// Where iTunes now says each of these songs lives, for the ones it still knows
// about and whose file is actually there. Keyed by BTunes track id, so the
// answer can be worked out away from the main thread and applied on it.
//
// A song does not go missing only by being deleted. Consolidating the media
// folder moves it, and editing a tag with "Keep Media folder organized" on
// renames it and its folders; in both cases the audio is untouched and only the
// path BTunes wrote down has gone stale. The persistent id survives all of that,
// which is what makes the repair possible at all.
//
// Reads the file and nothing else. Nothing is written here, to iTunes or to the
// library.
- (NSDictionary *)placesForMissingFiles:(NSArray *)missing
                fromITunesLibraryAtPath:(NSString *)xmlPath;

@end
