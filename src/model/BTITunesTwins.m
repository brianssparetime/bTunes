#import "BTITunesTwins.h"
#import "BTITunesEntry.h"

// Two recordings of one song run to the same length, near enough. Three seconds
// covers a fade cut differently and the gap iTunes leaves at the end.
static const NSTimeInterval BTTwinTolerance = 3.0;
// Wider where the record agrees as well, which is what a remaster trimming the
// silence at either end looks like. Only the album name earns this: without it
// the same twelve seconds would pair a single edit with the album version.
static const NSTimeInterval BTTwinAlbumTolerance = 12.0;

// Case, accents, punctuation, and the two spellings of "and" all say nothing
// about which recording this is. What survives is the words.
static NSString *BTFolded(NSString *text) {
    if ([text length] == 0) return @"";

    NSString *folded = [text stringByFoldingWithOptions:(NSCaseInsensitiveSearch |
                                                         NSDiacriticInsensitiveSearch |
                                                         NSWidthInsensitiveSearch)
                                                 locale:nil];
    folded = [folded stringByReplacingOccurrencesOfString:@"&" withString:@" and "];

    NSUInteger length = [folded length];
    unichar *source = malloc(sizeof(unichar) * length);
    unichar *kept = malloc(sizeof(unichar) * (length + 1));
    if (source == NULL || kept == NULL) { free(source); free(kept); return @""; }
    [folded getCharacters:source range:NSMakeRange(0, length)];

    NSCharacterSet *words = [NSCharacterSet alphanumericCharacterSet];
    NSUInteger i, out = 0;
    BOOL pending = NO;
    for (i = 0; i < length; i++) {
        if ([words characterIsMember:source[i]]) {
            if (pending && out > 0) kept[out++] = ' ';
            kept[out++] = source[i];
            pending = NO;
        } else {
            pending = YES;
        }
    }

    NSString *result = [[NSString alloc] initWithCharacters:kept length:out];
    free(source);
    free(kept);
    return result;
}

// A featured performer is on the recording rather than a different take of it,
// so this one bracket is noise and every other one is not.
static BOOL BTNamesAPerformer(NSString *foldedQualifier) {
    NSArray *credits = @[@"feat ", @"featuring ", @"ft ", @"with "];
    NSUInteger i;
    for (i = 0; i < [credits count]; i++) {
        if ([foldedQualifier hasPrefix:[credits objectAtIndex:i]]) return YES;
    }
    return [foldedQualifier isEqualToString:@"feat"] || [foldedQualifier isEqualToString:@"ft"];
}

// The title split in two: the words outside any bracket, and the bracketed
// asides that say which recording this is. Round and square brackets both, and
// nesting is counted so an inner pair does not end the outer one early.
static void BTSplitTitle(NSString *title, NSString **bare, NSArray **qualifiers) {
    NSMutableString *outside = [NSMutableString string];
    NSMutableString *inside = [NSMutableString string];
    NSMutableArray *found = [NSMutableArray array];
    NSUInteger i, length = [title length], depth = 0;

    for (i = 0; i < length; i++) {
        unichar c = [title characterAtIndex:i];
        if (c == '(' || c == '[') {
            depth++;
            if (depth == 1) continue;
        } else if ((c == ')' || c == ']') && depth > 0) {
            depth--;
            if (depth == 0) {
                NSString *folded = BTFolded(inside);
                if ([folded length] > 0 && !BTNamesAPerformer(folded)) [found addObject:folded];
                [inside setString:@""];
                continue;
            }
        }
        [(depth > 0 ? inside : outside) appendFormat:@"%C", c];
    }
    // An opening bracket that never closes leaves its words unaccounted for,
    // and dropping them would let "Song (Live" match "Song".
    if ([inside length] > 0) {
        NSString *folded = BTFolded(inside);
        if ([folded length] > 0 && !BTNamesAPerformer(folded)) [found addObject:folded];
    }

    if (bare) *bare = BTFolded(outside);
    if (qualifiers) *qualifiers = [found sortedArrayUsingSelector:@selector(compare:)];
}

static BOOL BTSaysLive(NSString *folded) {
    if ([folded length] == 0) return NO;
    NSArray *words = [folded componentsSeparatedByString:@" "];
    return [words containsObject:@"live"];
}

// The performers as a set rather than a sentence, because one library spells the
// same seven-name chamber ensemble in two orders.
static NSString *BTPerformersKey(NSDictionary *entry) {
    NSString *artist = BTITunesString(entry, @"Artist");
    if ([artist length] == 0) artist = BTITunesString(entry, @"Album Artist");

    NSString *folded = BTFolded(artist);
    if ([folded length] == 0) return @"";
    NSArray *words = [[folded componentsSeparatedByString:@" "]
                      sortedArrayUsingSelector:@selector(compare:)];
    return [words componentsJoinedByString:@" "];
}

// What a recording is, as far as anything here can tell: who plays it, what it
// is called, which take it is, and whether an audience is present.
static NSString *BTRecordingKey(NSDictionary *entry) {
    NSString *bare = nil;
    NSArray *qualifiers = nil;
    BTSplitTitle(BTITunesString(entry, @"Name") ?: @"", &bare, &qualifiers);
    if ([bare length] == 0) return nil;

    BOOL live = BTSaysLive(bare) ||
                [qualifiers containsObject:@"live"] ||
                BTSaysLive(BTFolded(BTITunesString(entry, @"Album")));

    return [NSString stringWithFormat:@"%@\n%@\n%@\n%d",
            BTPerformersKey(entry), bare,
            [qualifiers componentsJoinedByString:@","], live ? 1 : 0];
}

static NSTimeInterval BTSeconds(NSDictionary *entry) {
    id value = [entry objectForKey:@"Total Time"];
    if (![value respondsToSelector:@selector(doubleValue)]) return 0.0;
    return [value doubleValue] / 1000.0;
}

static long long BTBytes(NSDictionary *entry) {
    id value = [entry objectForKey:@"Size"];
    return [value respondsToSelector:@selector(longLongValue)] ? [value longLongValue] : 0;
}

// Anything with pictures. A television episode is not a recording of a song
// however closely its name matches one.
static BOOL BTIsVideo(NSDictionary *entry) {
    if ([[entry objectForKey:@"Has Video"] boolValue]) return YES;
    NSArray *flags = @[@"Movie", @"TV Show", @"Music Video", @"Podcast"];
    NSUInteger i;
    for (i = 0; i < [flags count]; i++) {
        if ([[entry objectForKey:[flags objectAtIndex:i]] boolValue]) return YES;
    }
    return NO;
}


@interface BTITunesTwin ()
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) long long fileSize;
// Held for choosing between candidates, which is nobody else's business.
@property (nonatomic, copy) NSString *albumKey;
@property (nonatomic, copy) NSString *persistentID;
@end

@implementation BTITunesTwin
@end


@implementation BTITunesTwins {
    NSDictionary *_byRecording;
}

+ (instancetype)twinsInEntries:(NSDictionary *)entries {
    if (![entries isKindOfClass:[NSDictionary class]] || [entries count] == 0) return nil;

    NSMutableDictionary *index = [NSMutableDictionary dictionary];
    NSArray *keys = [entries allKeys];
    NSUInteger i;

    for (i = 0; i < [keys count]; i++) {
        NSDictionary *entry = [entries objectForKey:[keys objectAtIndex:i]];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        if (BTIsVideo(entry)) continue;

        NSString *path = BTITunesPathFromLocation(BTITunesString(entry, @"Location"));
        if (path == nil) continue;                       // a cloud copy stands in for nothing
        if (BTITunesEntryIsProtected(entry, path)) continue;
        if (BTSeconds(entry) <= 0.0) continue;           // nothing to compare a length against

        NSString *recording = BTRecordingKey(entry);
        if (recording == nil) continue;

        BTITunesTwin *twin = [[BTITunesTwin alloc] init];
        twin.path = path;
        twin.kind = BTITunesString(entry, @"Kind");
        twin.duration = BTSeconds(entry);
        twin.fileSize = BTBytes(entry);
        twin.albumKey = BTFolded(BTITunesString(entry, @"Album"));
        twin.persistentID = BTITunesString(entry, @"Persistent ID") ?: @"";

        NSMutableArray *sharing = [index objectForKey:recording];
        if (sharing == nil) {
            sharing = [NSMutableArray arrayWithCapacity:1];
            [index setObject:sharing forKey:recording];
        }
        [sharing addObject:twin];
    }

    if ([index count] == 0) return nil;

    BTITunesTwins *twins = [[BTITunesTwins alloc] init];
    twins->_byRecording = index;
    return twins;
}

- (NSUInteger)count {
    NSUInteger total = 0;
    NSArray *lists = [_byRecording allValues];
    NSUInteger i;
    for (i = 0; i < [lists count]; i++) total += [[lists objectAtIndex:i] count];
    return total;
}

- (BTITunesTwin *)twinForEntry:(NSDictionary *)entry files:(NSFileManager *)files {
    NSTimeInterval wanted = BTSeconds(entry);
    if (wanted <= 0.0) return nil;

    NSString *recording = BTRecordingKey(entry);
    NSArray *sharing = recording ? [_byRecording objectForKey:recording] : nil;
    if ([sharing count] == 0) return nil;

    NSString *album = BTFolded(BTITunesString(entry, @"Album"));
    NSMutableArray *close = [NSMutableArray array];
    NSUInteger i;
    for (i = 0; i < [sharing count]; i++) {
        BTITunesTwin *twin = [sharing objectAtIndex:i];
        NSTimeInterval apart = fabs(twin.duration - wanted);
        BOOL sameAlbum = ([album length] > 0 && [twin.albumKey isEqualToString:album]);
        if (apart > (sameAlbum ? BTTwinAlbumTolerance : BTTwinTolerance)) continue;
        [close addObject:twin];
    }
    if ([close count] == 0) return nil;

    // The nearest match on the same record first, then the nearest anywhere,
    // and the id to break a tie. Ordered rather than picked, because the
    // dictionary hands these back in no fixed order and a sync that answers
    // differently on two runs is worse than one that answers plainly.
    NSArray *ordered = [close sortedArrayUsingComparator:^NSComparisonResult(BTITunesTwin *a, BTITunesTwin *b) {
        BOOL albumA = ([album length] > 0 && [a.albumKey isEqualToString:album]);
        BOOL albumB = ([album length] > 0 && [b.albumKey isEqualToString:album]);
        if (albumA != albumB) return albumA ? NSOrderedAscending : NSOrderedDescending;

        NSTimeInterval apartA = fabs(a.duration - wanted), apartB = fabs(b.duration - wanted);
        if (apartA < apartB) return NSOrderedAscending;
        if (apartA > apartB) return NSOrderedDescending;
        return [a.persistentID compare:b.persistentID];
    }];

    for (i = 0; i < [ordered count]; i++) {
        BTITunesTwin *twin = [ordered objectAtIndex:i];
        if ([files fileExistsAtPath:twin.path]) return twin;
    }
    return nil;
}

@end
