#import "BTTrackColumns.h"
#import "BTMainWindowViews.h"
#import "BTStyle.h"
#import "BTTrack.h"

static NSString *BTStringOrEmpty(NSString *value) {
    return value ? value : @"";
}

static double BTTimeOrZero(NSDate *date) {
    return date ? [date timeIntervalSince1970] : 0.0;
}

static NSComparisonResult BTCompareNumbers(double a, double b) {
    return (a < b) ? NSOrderedAscending : (a > b) ? NSOrderedDescending : NSOrderedSame;
}

NSString *BTSizeString(long long bytes) {
    double megabytes = (double)bytes / (1024.0 * 1024.0);
    if (megabytes >= 1024.0) return [NSString stringWithFormat:@"%.2f GB", megabytes / 1024.0];
    return [NSString stringWithFormat:@"%.1f MB", megabytes];
}

static NSString *BTShortDateString(NSDate *date) {
    if (date == nil) return @"";
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateStyle:NSDateFormatterShortStyle];
        [formatter setTimeStyle:NSDateFormatterNoStyle];
    });
    return [formatter stringFromDate:date];
}

// Filled stars, the way a rating was shown in 2003.
static NSString *BTStarsString(NSInteger rating) {
    if (rating <= 0) return @"";
    NSMutableString *stars = [NSMutableString string];
    NSInteger i;
    for (i = 0; i < rating && i < 5; i++) [stars appendString:@"★"];
    return stars;
}

// Everything a column is, in one place.
//
// Two numbers here are easy to confuse, so they are two columns. Track is the
// song's place on its album: it belongs to the song and reads the same wherever
// the song appears. Order is the song's place in the playlist, and the same song
// sits at a different number in every playlist that holds it. Both are made and
// one is hidden at a time, since making them once keeps whatever width they have
// been dragged to.
//
// Three separate lists of identifiers used to say what is written here: which
// columns count something, which have no heading, and which may be hidden. A
// column added to the specs and forgotten in one of the three was wrong in a way
// nothing reported.
//
// Two things are still said elsewhere and have to be: what a column sorts by,
// and how its value is read off a song. Neither is a fact about the column that
// a table can hold, so both are chains further down, and a new column needs an
// arm in each.
typedef struct {
    __unsafe_unretained NSString *identifier;
    __unsafe_unretained NSString *heading;
    CGFloat width;
    CGFloat minimum;
    CGFloat maximum;
    BOOL shown;         // before the reader has hidden or shown anything
    BOOL counts;        // a number: set to the right, and kept narrow
    BOOL isPosition;    // may carry the speaker for the row that is playing
    BOOL canBeHidden;   // offered in the menu on the header
} BTColumnSpec;

// Song Name cannot be hidden, since a list of songs with no names is not a view
// anyone wants. Neither can the two the source decides: the mark, and #, which
// is there for a playlist and not for the library.
//
// Track is last on purpose. It can be dragged anywhere and stays where it is
// put; this is only where it starts.
static const BTColumnSpec BTTrackColumns[] = {
//    identifier      heading         width  min  max  shown  counts  position  hideable
    { @"playing",     @"",             18,   18,  18,  YES,   NO,     YES,      NO  },
    { @"order",       @"#",            38,   30,  54,  YES,   YES,    YES,      NO  },
    { @"title",       @"Song Name",   240,   80, 900,  YES,   NO,     NO,       NO  },
    { @"time",        @"Time",         52,   44,  72,  YES,   YES,    NO,       YES },
    { @"artist",      @"Artist",      160,   70, 600,  YES,   NO,     NO,       YES },
    { @"albumArtist", @"Album Artist",160,   70, 600,  NO,    NO,     NO,       YES },
    { @"album",       @"Album",       160,   70, 600,  YES,   NO,     NO,       YES },
    { @"genre",       @"Genre",       110,   60, 400,  YES,   NO,     NO,       YES },
    { @"composer",    @"Composer",    140,   70, 500,  NO,    NO,     NO,       YES },
    { @"year",        @"Year",         54,   46,  80,  NO,    YES,    NO,       YES },
    { @"kind",        @"Kind",        120,   60, 300,  NO,    NO,     NO,       YES },
    { @"disc",        @"Disc",         46,   38,  70,  NO,    YES,    NO,       YES },
    { @"rating",      @"My Rating",    84,   60, 120,  NO,    NO,     NO,       YES },
    { @"playCount",   @"Play Count",   80,   66, 110,  YES,   YES,    NO,       YES },
    { @"lastPlayed",  @"Last Played", 110,   80, 180,  NO,    NO,     NO,       YES },
    { @"dateAdded",   @"Date Added",  110,   80, 180,  NO,    NO,     NO,       YES },
    { @"size",        @"Size",         70,   56, 100,  NO,    YES,    NO,       YES },
    { @"track",       @"Track",        46,   38,  62,  YES,   YES,    YES,      YES },
};

#define BT_TRACK_COLUMN_COUNT (sizeof(BTTrackColumns) / sizeof(BTTrackColumns[0]))

// The widths above are in points at the size the columns were measured for, so
// they hold their proportion when the type moves. Only the starting widths pass
// through here: once a column has been dragged, that width is the reader's and
// is used as it stands.
#define BT_COLUMN_REFERENCE_SIZE 11.0

static CGFloat BTScaledForType(CGFloat width) {
    return round(width * [BTStyle baseFontSize] / BT_COLUMN_REFERENCE_SIZE);
}

static const BTColumnSpec *BTColumnSpecFor(NSString *identifier) {
    NSUInteger i;
    for (i = 0; i < BT_TRACK_COLUMN_COUNT; i++) {
        if ([BTTrackColumns[i].identifier isEqualToString:identifier]) return &BTTrackColumns[i];
    }
    return NULL;
}

void BTAddTrackColumns(NSTableView *table) {
    NSUInteger i;
    for (i = 0; i < BT_TRACK_COLUMN_COUNT; i++) {
        const BTColumnSpec *spec = &BTTrackColumns[i];

        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec->identifier];
        [[column headerCell] setStringValue:spec->heading];
        [[column headerCell] setFont:[BTStyle uiFont]];
        // The narrowest a column may go is whichever is larger: the number below,
        // or enough room for its own heading. Written out, the numbers were
        // right for one size of type and would have cut the headings short at
        // any other.
        CGFloat headingRoom = 0.0;
        if ([spec->heading length] > 0) {
            NSDictionary *attrs = @{NSFontAttributeName: [BTStyle uiFont]};
            headingRoom = ceil([spec->heading sizeWithAttributes:attrs].width) + 16.0;
        }
        CGFloat minimum = MAX(BTScaledForType(spec->minimum), headingRoom);

        [column setWidth:MAX(BTScaledForType(spec->width), minimum)];
        [column setMinWidth:minimum];
        [column setMaxWidth:MAX(BTScaledForType(spec->maximum), minimum)];
        [column setHidden:!spec->shown];
        [column setEditable:NO];

        // Who may change this column's width, which is two questions rather than
        // one, and they had the same answer when they should not have.
        //
        // Dragging it is somebody deciding. That is allowed on everything except
        // the mark, which has no width worth choosing.
        //
        // The window getting wider is not somebody deciding, and it used to
        // change every column, so a width set by hand was recomputed away by the
        // next resize. Now the words take the slack and the numbers keep what
        // they were given. A column of numbers has a right size: a two-digit
        // count stretched to fill the window reads as a mistake, and stretched
        // far enough it hits the widest it is allowed and sits there, which is
        // how a # column dragged to its narrowest kept coming back at its
        // widest.
        //
        // Capping the numbers was the old way of saying this and it did not
        // work, because a cap only limits how wrong the sharing out can go. Not
        // taking part is the thing that was meant.
        NSUInteger mask = NSTableColumnUserResizingMask;
        if (!spec->counts) mask |= NSTableColumnAutoresizingMask;
        if ([spec->identifier isEqualToString:@"playing"]) mask = 0;
        [column setResizingMask:mask];

        NSTextFieldCell *cell;
        if (spec->isPosition) {
            cell = [[BTTrackNumberCell alloc] init];
        } else if (spec->counts) {
            cell = [[BTNumberCell alloc] init];
        } else {
            cell = [[NSTextFieldCell alloc] init];
        }
        [cell setFont:[BTStyle uiFont]];
        // Truncated with an ellipsis rather than clipped: a clipped cell cuts
        // mid-word and reads as though the tag itself is broken.
        if (!spec->isPosition) [cell setLineBreakMode:NSLineBreakByTruncatingTail];
        if (spec->counts) {
            [cell setAlignment:NSRightTextAlignment];
            [[column headerCell] setAlignment:NSRightTextAlignment];
        }
        [column setDataCell:cell];
        [table addTableColumn:column];
    }
}

BOOL BTColumnCanBeHidden(NSString *identifier) {
    const BTColumnSpec *spec = BTColumnSpecFor(identifier);
    return spec ? spec->canBeHidden : NO;
}

NSArray *BTSortTracks(NSArray *tracks, NSString *column, BOOL ascending,
                      NSDictionary *order) {
    NSString *key = column;
    if (key == nil) return tracks;   // the source's own order

    return [tracks sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        BTTrack *left = a, *right = b;
        NSComparisonResult result = NSOrderedSame;

        if ([key isEqualToString:@"order"]) {
            // The playlist's own order, which is the order it was built in.
            result = BTCompareNumbers([[order objectForKey:left.trackID] doubleValue],
                                      [[order objectForKey:right.trackID] doubleValue]);
        } else if ([key isEqualToString:@"track"]) {
            // A track number only means something within an album, so albums
            // stay together and disc and track order the songs inside them.
            result = [[left displayAlbum] caseInsensitiveCompare:[right displayAlbum]];
            if (result == NSOrderedSame) result = BTCompareNumbers([left orderingDiscNumber],
                                                                  [right orderingDiscNumber]);
            if (result == NSOrderedSame) result = BTCompareNumbers(left.trackNumber, right.trackNumber);
        } else if ([key isEqualToString:@"title"]) {
            result = [[left displayTitle] caseInsensitiveCompare:[right displayTitle]];
        } else if ([key isEqualToString:@"album"]) {
            result = [[left displayAlbum] caseInsensitiveCompare:[right displayAlbum]];
            if (result == NSOrderedSame) result = BTCompareNumbers([left orderingDiscNumber],
                                                                  [right orderingDiscNumber]);
            if (result == NSOrderedSame) result = BTCompareNumbers(left.trackNumber, right.trackNumber);
        } else if ([key isEqualToString:@"genre"]) {
            result = [[left displayGenre] caseInsensitiveCompare:[right displayGenre]];
        } else if ([key isEqualToString:@"albumArtist"]) {
            result = [BTStringOrEmpty(left.albumArtist) caseInsensitiveCompare:BTStringOrEmpty(right.albumArtist)];
        } else if ([key isEqualToString:@"composer"]) {
            result = [BTStringOrEmpty(left.composer) caseInsensitiveCompare:BTStringOrEmpty(right.composer)];
        } else if ([key isEqualToString:@"kind"]) {
            result = [BTStringOrEmpty(left.kind) caseInsensitiveCompare:BTStringOrEmpty(right.kind)];
        } else if ([key isEqualToString:@"time"]) {
            result = BTCompareNumbers(left.duration, right.duration);
        } else if ([key isEqualToString:@"playCount"]) {
            result = BTCompareNumbers(left.playCount, right.playCount);
        } else if ([key isEqualToString:@"year"]) {
            result = BTCompareNumbers(left.year, right.year);
        } else if ([key isEqualToString:@"disc"]) {
            result = BTCompareNumbers(left.discNumber, right.discNumber);
        } else if ([key isEqualToString:@"rating"]) {
            result = BTCompareNumbers(left.rating, right.rating);
        } else if ([key isEqualToString:@"size"]) {
            result = BTCompareNumbers((double)left.fileSize, (double)right.fileSize);
        } else if ([key isEqualToString:@"dateAdded"]) {
            // Never played and never added sort together at the bottom rather
            // than landing in 1970.
            result = BTCompareNumbers(BTTimeOrZero(left.dateAdded), BTTimeOrZero(right.dateAdded));
        } else if ([key isEqualToString:@"lastPlayed"]) {
            result = BTCompareNumbers(BTTimeOrZero(left.lastPlayed), BTTimeOrZero(right.lastPlayed));
        } else {
            // Artist, then album, then track number: the order iTunes falls back to.
            result = [[left displayArtist] caseInsensitiveCompare:[right displayArtist]];
            if (result == NSOrderedSame) result = [[left displayAlbum] caseInsensitiveCompare:[right displayAlbum]];
            if (result == NSOrderedSame) result = BTCompareNumbers(left.trackNumber, right.trackNumber);
        }

        if (result == NSOrderedSame) result = [[left displayTitle] caseInsensitiveCompare:[right displayTitle]];
        return ascending ? result : -result;
    }];
}

id BTTrackColumnValue(NSString *identifier, BTTrack *track, NSDictionary *playlistOrder) {

    if ([identifier isEqualToString:@"playing"]) return @"";
    if ([identifier isEqualToString:@"order"]) {
        NSNumber *place = [playlistOrder objectForKey:track.trackID];
        return place ? [NSString stringWithFormat:@"%ld", (long)[place integerValue]] : @"";
    }
    if ([identifier isEqualToString:@"track"]) {
        return track.trackNumber > 0 ? [NSString stringWithFormat:@"%ld", (long)track.trackNumber] : @"";
    }
    if ([identifier isEqualToString:@"title"]) return [track displayTitle];
    if ([identifier isEqualToString:@"time"]) return [track durationString];
    if ([identifier isEqualToString:@"artist"]) return [track displayArtist];
    if ([identifier isEqualToString:@"album"]) return [track displayAlbum];
    if ([identifier isEqualToString:@"genre"]) return (track.genre ? track.genre : @"");
    if ([identifier isEqualToString:@"albumArtist"]) return (track.albumArtist ? track.albumArtist : @"");
    if ([identifier isEqualToString:@"composer"]) return (track.composer ? track.composer : @"");
    if ([identifier isEqualToString:@"kind"]) return (track.kind ? track.kind : @"");
    if ([identifier isEqualToString:@"rating"]) return BTStarsString(track.rating);
    if ([identifier isEqualToString:@"lastPlayed"]) return BTShortDateString(track.lastPlayed);
    if ([identifier isEqualToString:@"dateAdded"]) return BTShortDateString(track.dateAdded);
    if ([identifier isEqualToString:@"size"]) {
        return track.fileSize > 0 ? BTSizeString(track.fileSize) : @"";
    }
    if ([identifier isEqualToString:@"year"]) {
        return track.year > 0 ? [NSString stringWithFormat:@"%ld", (long)track.year] : @"";
    }
    if ([identifier isEqualToString:@"disc"]) {
        return track.discNumber > 0 ? [NSString stringWithFormat:@"%ld", (long)track.discNumber] : @"";
    }
    if ([identifier isEqualToString:@"playCount"]) {
        return track.playCount > 0 ? [NSString stringWithFormat:@"%ld", (long)track.playCount] : @"";
    }
    return nil;
}
