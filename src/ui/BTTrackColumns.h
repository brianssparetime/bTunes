#import <Cocoa/Cocoa.h>

@class BTTrack;

// The columns of the song list: what each one is, how it sorts, and what it
// shows for a song.
//
// Everything here answers from a song and a column name, and touches no window,
// which is what lets the three questions sit together. They belong together
// because a column that is added has to be answered in all three, and having
// them in one file is the nearest thing to being told when one is missed.
//
// The playlist order is passed in rather than looked up, because it belongs to
// the list being shown rather than to the song: the same song sits at a
// different number in every playlist that holds it.

// Builds the columns onto a table, in the order they start in. Which are shown,
// how wide they are, and where they sit are the reader's business from then on.
void BTAddTrackColumns(NSTableView *table);

// Whether a column is offered in the menu on the header. Song Name is not, since
// a list of songs with no names is not a view anyone wants, and neither are the
// two the source decides rather than the reader.
BOOL BTColumnCanBeHidden(NSString *identifier);

// What a column shows for a song, or nil for a column that shows nothing.
id BTTrackColumnValue(NSString *identifier, BTTrack *track, NSDictionary *playlistOrder);

// The songs in the order a column sorts them. A column nobody sorted by leaves
// the list in the order it arrived.
NSArray *BTSortTracks(NSArray *tracks, NSString *column, BOOL ascending,
                      NSDictionary *playlistOrder);

// Bytes, said the way a file size is said. Also used by the count along the
// bottom of the window.
NSString *BTSizeString(long long bytes);
