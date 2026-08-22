#import "BTPlaylist.h"
#import "BTSavedValue.h"
#import "BTTrack.h"

@implementation BTSmartRule

+ (instancetype)ruleWithField:(BTRuleField)field operator:(BTRuleOperator)op value:(NSString *)value {
    BTSmartRule *r = [[BTSmartRule alloc] init];
    r.field = field;
    r.op = op;
    r.value = value ? value : @"";
    return r;
}

+ (instancetype)ruleWithDictionary:(NSDictionary *)dict {
    // The value is copied into a string property and then compared as one, so a
    // number saved here would be kept as a number and crash on the comparison.
    return [self ruleWithField:(BTRuleField)BTSavedInteger(dict, @"field")
                      operator:(BTRuleOperator)BTSavedInteger(dict, @"op")
                         value:BTSavedString(dict, @"value")];
}

- (NSDictionary *)dictionaryRepresentation {
    return @{@"field": @(self.field), @"op": @(self.op), @"value": (self.value ? self.value : @"")};
}

+ (NSArray *)fieldNames {
    return @[@"Song Name", @"Artist", @"Album", @"Genre", @"Composer", @"Kind",
             @"Year", @"My Rating", @"Play Count", @"Time", @"Date Added"];
}

+ (BOOL)fieldIsNumeric:(BTRuleField)field {
    switch (field) {
        case BTRuleFieldYear:
        case BTRuleFieldRating:
        case BTRuleFieldPlayCount:
        case BTRuleFieldDuration:
        case BTRuleFieldDateAdded:
            return YES;
        default:
            return NO;
    }
}

+ (NSArray *)operatorsForField:(BTRuleField)field {
    if (field == BTRuleFieldDateAdded) {
        return @[@(BTRuleOperatorInTheLast), @(BTRuleOperatorGreaterThan), @(BTRuleOperatorLessThan)];
    }
    if ([self fieldIsNumeric:field]) {
        return @[@(BTRuleOperatorIs), @(BTRuleOperatorIsNot),
                 @(BTRuleOperatorGreaterThan), @(BTRuleOperatorLessThan)];
    }
    return @[@(BTRuleOperatorContains), @(BTRuleOperatorDoesNotContain),
             @(BTRuleOperatorIs), @(BTRuleOperatorIsNot),
             @(BTRuleOperatorBeginsWith), @(BTRuleOperatorEndsWith)];
}

+ (NSString *)nameForOperator:(BTRuleOperator)op field:(BTRuleField)field {
    switch (op) {
        case BTRuleOperatorContains:       return @"contains";
        case BTRuleOperatorDoesNotContain: return @"does not contain";
        case BTRuleOperatorIs:             return @"is";
        case BTRuleOperatorIsNot:          return @"is not";
        case BTRuleOperatorBeginsWith:     return @"begins with";
        case BTRuleOperatorEndsWith:       return @"ends with";
        case BTRuleOperatorGreaterThan:    return (field == BTRuleFieldDateAdded) ? @"is after" : @"is greater than";
        case BTRuleOperatorLessThan:       return (field == BTRuleFieldDateAdded) ? @"is before" : @"is less than";
        case BTRuleOperatorInTheLast:      return @"in the last (days)";
    }
    return @"is";
}

// A year, a year and a month, or a whole day. Read by hand rather than by a
// date formatter, because a formatter follows the reader's region and a rule
// saved on one machine would then mean something else on another.
+ (NSDate *)dateFromText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceCharacterSet]];
    NSArray *parts = [trimmed componentsSeparatedByString:@"-"];
    if ([parts count] < 1 || [parts count] > 3) return nil;

    NSInteger numbers[3] = {0, 1, 1};
    NSUInteger i;
    for (i = 0; i < [parts count]; i++) {
        NSString *part = [parts objectAtIndex:i];
        if ([part length] == 0) return nil;
        if ([part rangeOfCharacterFromSet:
             [[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) {
            return nil;
        }
        numbers[i] = [part integerValue];
    }
    if (numbers[0] < 1 || numbers[1] < 1 || numbers[1] > 12 ||
        numbers[2] < 1 || numbers[2] > 31) {
        return nil;
    }

    NSDateComponents *when = [[NSDateComponents alloc] init];
    [when setYear:numbers[0]];
    [when setMonth:numbers[1]];
    [when setDay:numbers[2]];
    return [[NSCalendar currentCalendar] dateFromComponents:when];
}

+ (NSString *)valueHintForField:(BTRuleField)field operator:(BTRuleOperator)op {
    if (field != BTRuleFieldDateAdded) return @"";
    return (op == BTRuleOperatorInTheLast) ? @"days" : @"2003-06-01";
}

+ (NSArray *)operatorNamesForField:(BTRuleField)field {
    NSArray *ops = [self operatorsForField:field];
    NSMutableArray *names = [NSMutableArray array];
    NSUInteger i;
    for (i = 0; i < [ops count]; i++) {
        BTRuleOperator op = (BTRuleOperator)[[ops objectAtIndex:i] integerValue];
        [names addObject:[self nameForOperator:op field:field]];
    }
    return names;
}

- (NSString *)stringValueForTrack:(BTTrack *)track {
    switch (self.field) {
        case BTRuleFieldTitle:    return [track displayTitle];
        case BTRuleFieldArtist:   return [track displayArtist];
        case BTRuleFieldAlbum:    return [track displayAlbum];
        case BTRuleFieldGenre:    return track.genre ? track.genre : @"";
        case BTRuleFieldComposer: return track.composer ? track.composer : @"";
        case BTRuleFieldKind:     return track.kind ? track.kind : @"";
        default:                  return @"";
    }
}

- (double)numericValueForTrack:(BTTrack *)track {
    switch (self.field) {
        case BTRuleFieldYear:      return (double)track.year;
        case BTRuleFieldRating:    return (double)track.rating;
        case BTRuleFieldPlayCount: return (double)track.playCount;
        case BTRuleFieldDuration:  return track.duration;
        case BTRuleFieldDateAdded: return track.dateAdded ? [track.dateAdded timeIntervalSince1970] : 0.0;
        default:                   return 0.0;
    }
}

- (BOOL)evaluateWithTrack:(BTTrack *)track {
    if ([BTSmartRule fieldIsNumeric:self.field]) {
        double lhs = [self numericValueForTrack:track];
        if (self.field == BTRuleFieldDateAdded) {
            // Counting days is what "in the last" is for.
            if (self.op == BTRuleOperatorInTheLast) {
                double days = [self.value doubleValue];
                if (days <= 0) return NO;
                return lhs > [[NSDate date] timeIntervalSince1970] - days * 86400.0;
            }

            // "is after" and "is before" mean a date, and say so. A date that
            // cannot be read matches nothing: a rule nobody can satisfy is
            // plainer than one that quietly takes in the whole library.
            NSDate *when = [BTSmartRule dateFromText:self.value];
            if (when == nil) return NO;
            double cutoff = [when timeIntervalSince1970];
            return (self.op == BTRuleOperatorGreaterThan) ? (lhs > cutoff) : (lhs < cutoff);
        }
        double rhs = [self.value doubleValue];
        switch (self.op) {
            case BTRuleOperatorIs:          return lhs == rhs;
            case BTRuleOperatorIsNot:       return lhs != rhs;
            case BTRuleOperatorGreaterThan: return lhs > rhs;
            case BTRuleOperatorLessThan:    return lhs < rhs;
            default:                        return NO;
        }
    }

    NSString *lhs = [self stringValueForTrack:track];
    NSString *rhs = self.value ? self.value : @"";
    NSStringCompareOptions opts = NSCaseInsensitiveSearch;
    switch (self.op) {
        case BTRuleOperatorContains:
            return [lhs rangeOfString:rhs options:opts].location != NSNotFound;
        case BTRuleOperatorDoesNotContain:
            return [lhs rangeOfString:rhs options:opts].location == NSNotFound;
        case BTRuleOperatorIs:
            return [lhs compare:rhs options:opts] == NSOrderedSame;
        case BTRuleOperatorIsNot:
            return [lhs compare:rhs options:opts] != NSOrderedSame;
        case BTRuleOperatorBeginsWith:
            return [lhs rangeOfString:rhs options:(opts | NSAnchoredSearch)].location != NSNotFound;
        case BTRuleOperatorEndsWith:
            return [lhs rangeOfString:rhs options:(opts | NSAnchoredSearch | NSBackwardsSearch)].location != NSNotFound;
        default:
            return NO;
    }
}

@end


@interface BTPlaylist ()
+ (void)enumerate:(NSArray *)playlists
       usingBlock:(void (^)(BTPlaylist *playlist, BOOL *stop))block
             stop:(BOOL *)stop;
@end

// A date that is not there sorts as long ago, so a song nobody has played does
// not win "most recently played" by having no answer at all.
static double BTWhen(NSDate *date) {
    return date ? [date timeIntervalSince1970] : -DBL_MAX;
}

// The best songs first, for whichever meaning of best the limit was given.
//
// Every ordering falls back to the title, since a library holds thousands of
// songs played nought times and a tie that breaks differently on each rebuild
// is a playlist whose contents change while nothing about it did.
static NSComparator BTComparatorForLimit(BTSmartLimitOrder order) {
    return ^NSComparisonResult(id a, id b) {
        BTTrack *left = a, *right = b;
        double mine = 0, theirs = 0;

        // Every "least" is the matching "most" with the sign turned over, and
        // nothing else changes. Swapping the two songs round instead turns it
        // over a second time and leaves the ordering exactly as it was, which
        // is what "least recently added" did until a check said so.
        switch (order) {
            case BTSmartLimitMostRecentlyAdded:
                mine = BTWhen(left.dateAdded); theirs = BTWhen(right.dateAdded); break;
            case BTSmartLimitLeastRecentlyAdded:
                mine = -BTWhen(left.dateAdded); theirs = -BTWhen(right.dateAdded); break;
            case BTSmartLimitMostOftenPlayed:
                mine = (double)left.playCount; theirs = (double)right.playCount; break;
            case BTSmartLimitLeastOftenPlayed:
                mine = -(double)left.playCount; theirs = -(double)right.playCount; break;
            case BTSmartLimitHighestRated:
                mine = (double)left.rating; theirs = (double)right.rating; break;
            case BTSmartLimitMostRecentlyPlayed:
                mine = BTWhen(left.lastPlayed); theirs = BTWhen(right.lastPlayed); break;
            case BTSmartLimitLeastRecentlyPlayed:
                mine = -BTWhen(left.lastPlayed); theirs = -BTWhen(right.lastPlayed); break;
        }

        if (mine > theirs) return NSOrderedAscending;    // more of it comes first
        if (mine < theirs) return NSOrderedDescending;
        return [[left displayTitle] caseInsensitiveCompare:[right displayTitle]];
    };
}

@implementation BTPlaylist

+ (void)enumerate:(NSArray *)playlists usingBlock:(void (^)(BTPlaylist *playlist, BOOL *stop))block {
    BOOL stop = NO;
    [self enumerate:playlists usingBlock:block stop:&stop];
}

+ (void)enumerate:(NSArray *)playlists
       usingBlock:(void (^)(BTPlaylist *playlist, BOOL *stop))block
             stop:(BOOL *)stop {
    NSUInteger i;
    for (i = 0; i < [playlists count] && !*stop; i++) {
        BTPlaylist *playlist = [playlists objectAtIndex:i];
        block(playlist, stop);
        if (*stop) return;
        if ([playlist.children count] > 0) {
            [self enumerate:playlist.children usingBlock:block stop:stop];
        }
    }
}

+ (NSArray *)limitOrderNames {
    return @[@"most recently added", @"least recently added",
             @"most often played", @"least often played",
             @"highest rated",
             @"most recently played", @"least recently played"];
}

+ (instancetype)playlistWithName:(NSString *)name kind:(BTPlaylistKind)kind {
    BTPlaylist *p = [[BTPlaylist alloc] init];
    p.playlistID = [[NSUUID UUID] UUIDString];
    p.name = name;
    p.kind = kind;
    p.trackIDs = [NSMutableArray array];
    p.children = [NSMutableArray array];
    p.rules = [NSMutableArray array];
    p.matchAll = YES;
    p.limit = 0;
    p.sortAscending = YES;
    return p;
}

+ (instancetype)playlistWithDictionary:(NSDictionary *)dict {
    BTPlaylist *p = [self playlistWithName:BTSavedString(dict, @"name")
                                      kind:(BTPlaylistKind)BTSavedInteger(dict, @"kind")];
    NSString *pid = BTSavedString(dict, @"id");
    if ([pid length] > 0) p.playlistID = pid;
    p.sourcePersistentID = BTSavedString(dict, @"sourcePersistentID");
    p.matchAll = BTSavedBool(dict, @"matchAll");
    p.limit = BTSavedInteger(dict, @"limit");
    // A playlist saved before a limit had anything to choose by takes the
    // ordering anybody would have meant: the newest of what matched.
    p.limitOrder = (BTSmartLimitOrder)BTSavedInteger(dict, @"limitOrder");

    NSString *sort = BTSavedString(dict, @"sortColumn");
    if ([sort length] > 0) {
        p.sortColumn = sort;
        // A playlist saved before the direction was recorded was ascending.
        id ascending = [dict objectForKey:@"sortAscending"];
        p.sortAscending = ascending ? BTSavedBool(dict, @"sortAscending") : YES;
    }

    NSUInteger i;
    NSArray *ids = BTSavedArray(dict, @"trackIDs");
    for (i = 0; i < [ids count]; i++) {
        // A track id is looked up as a string everywhere else, so anything that
        // is not one would sit in the playlist matching nothing.
        NSString *trackID = [ids objectAtIndex:i];
        if ([trackID isKindOfClass:[NSString class]]) [p.trackIDs addObject:trackID];
    }

    NSArray *ruleDicts = BTSavedArray(dict, @"rules");
    for (i = 0; i < [ruleDicts count]; i++) {
        NSDictionary *rule = [ruleDicts objectAtIndex:i];
        if (![rule isKindOfClass:[NSDictionary class]]) continue;
        [p.rules addObject:[BTSmartRule ruleWithDictionary:rule]];
    }

    NSArray *childDicts = BTSavedArray(dict, @"children");
    for (i = 0; i < [childDicts count]; i++) {
        NSDictionary *childDict = [childDicts objectAtIndex:i];
        if (![childDict isKindOfClass:[NSDictionary class]]) continue;
        BTPlaylist *child = [BTPlaylist playlistWithDictionary:childDict];
        child.parent = p;
        [p.children addObject:child];
    }
    return p;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    [d setObject:(self.playlistID ? self.playlistID : @"") forKey:@"id"];
    [d setObject:(self.name ? self.name : @"") forKey:@"name"];
    if (self.sourcePersistentID) [d setObject:self.sourcePersistentID forKey:@"sourcePersistentID"];
    [d setObject:@(self.kind) forKey:@"kind"];
    [d setObject:@(self.matchAll) forKey:@"matchAll"];
    [d setObject:@(self.limit) forKey:@"limit"];
    // Written only where it means something, so a playlist with no limit reads
    // exactly as it did before there was anything to choose by.
    if (self.limit > 0) [d setObject:@(self.limitOrder) forKey:@"limitOrder"];
    [d setObject:self.trackIDs forKey:@"trackIDs"];
    // Left out entirely until the playlist has been sorted by hand, so an
    // untouched playlist keeps opening the way its kind suggests.
    if ([self.sortColumn length] > 0) {
        [d setObject:self.sortColumn forKey:@"sortColumn"];
        [d setObject:@(self.sortAscending) forKey:@"sortAscending"];
    }

    NSMutableArray *ruleDicts = [NSMutableArray array];
    NSUInteger i;
    for (i = 0; i < [self.rules count]; i++) {
        [ruleDicts addObject:[[self.rules objectAtIndex:i] dictionaryRepresentation]];
    }
    [d setObject:ruleDicts forKey:@"rules"];

    NSMutableArray *childDicts = [NSMutableArray array];
    for (i = 0; i < [self.children count]; i++) {
        [childDicts addObject:[[self.children objectAtIndex:i] dictionaryRepresentation]];
    }
    [d setObject:childDicts forKey:@"children"];
    return d;
}

- (NSArray *)resolveTracks:(NSArray *)allTracks {
    NSUInteger i, j;

    if (self.kind == BTPlaylistKindFolder) {
        // A folder plays everything its children hold, in order, without repeats.
        NSMutableArray *out = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet set];
        for (i = 0; i < [self.children count]; i++) {
            NSArray *childTracks = [[self.children objectAtIndex:i] resolveTracks:allTracks];
            for (j = 0; j < [childTracks count]; j++) {
                BTTrack *t = [childTracks objectAtIndex:j];
                if (![seen containsObject:t.trackID]) {
                    [seen addObject:t.trackID];
                    [out addObject:t];
                }
            }
        }
        return out;
    }

    if (self.kind == BTPlaylistKindSmart) {
        // A playlist with no rules at all holds nothing. Read as "all of
        // nothing", every song matches and the whole library arrives under a
        // name somebody meant to fill in, which is a surprise rather than an
        // answer. The sheet will not let a rule list empty; a library file
        // edited by hand can.
        if ([self.rules count] == 0) return @[];

        NSMutableArray *out = [NSMutableArray array];
        for (i = 0; i < [allTracks count]; i++) {
            BTTrack *t = [allTracks objectAtIndex:i];
            BOOL matched = self.matchAll;
            for (j = 0; j < [self.rules count]; j++) {
                BOOL one = [[self.rules objectAtIndex:j] evaluateWithTrack:t];
                if (self.matchAll) {
                    if (!one) { matched = NO; break; }
                } else {
                    if (one) { matched = YES; break; }
                }
            }
            if (matched) [out addObject:t];
        }

        // The limit is applied to everything that matched, not to the first few
        // the scan reached. Cutting the scan short took whichever songs the
        // library file happened to list first, which is not an order anybody
        // chose and not one anybody could see.
        if (self.limit > 0 && (NSInteger)[out count] > self.limit) {
            NSArray *best = [out sortedArrayUsingComparator:BTComparatorForLimit(self.limitOrder)];
            return [best subarrayWithRange:NSMakeRange(0, (NSUInteger)self.limit)];
        }
        return out;
    }

    NSMutableDictionary *byID = [NSMutableDictionary dictionaryWithCapacity:[allTracks count]];
    for (i = 0; i < [allTracks count]; i++) {
        BTTrack *t = [allTracks objectAtIndex:i];
        [byID setObject:t forKey:t.trackID];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (i = 0; i < [self.trackIDs count]; i++) {
        BTTrack *t = [byID objectForKey:[self.trackIDs objectAtIndex:i]];
        if (t) [out addObject:t];
    }
    return out;
}

- (void)moveTrackIDs:(NSArray *)trackIDs toIndex:(NSInteger)index {
    if ([trackIDs count] == 0) return;

    // Gathered in the order this playlist already holds them, so songs moved
    // together keep their arrangement relative to each other rather than taking
    // the order they happened to be picked in.
    NSMutableArray *moving = [NSMutableArray array];
    NSUInteger i, liftedFromAbove = 0;
    for (i = 0; i < [self.trackIDs count]; i++) {
        NSString *trackID = [self.trackIDs objectAtIndex:i];
        if (![trackIDs containsObject:trackID]) continue;
        [moving addObject:trackID];
        if ((NSInteger)i < index) liftedFromAbove++;
    }
    if ([moving count] == 0) return;

    // Songs taken from above the destination close the gap behind them, so the
    // place they are going moves back by however many those were.
    [self.trackIDs removeObjectsInArray:moving];
    index -= (NSInteger)liftedFromAbove;
    if (index < 0) index = 0;
    if (index > (NSInteger)[self.trackIDs count]) index = (NSInteger)[self.trackIDs count];

    [self.trackIDs insertObjects:moving
                       atIndexes:[NSIndexSet indexSetWithIndexesInRange:
                                  NSMakeRange((NSUInteger)index, [moving count])]];
}

- (void)arrangeByAlbumUsingTracks:(NSArray *)allTracks {
    NSArray *resolved = [self resolveTracks:allTracks];

    // Disc comes between album and track: track one of the second disc belongs
    // after track twelve of the first, not before it.
    NSArray *sorted = [resolved sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        BTTrack *left = a, *right = b;
        NSComparisonResult result = [[left displayAlbum] caseInsensitiveCompare:[right displayAlbum]];
        if (result != NSOrderedSame) return result;

        NSInteger leftDisc = [left orderingDiscNumber], rightDisc = [right orderingDiscNumber];
        if (leftDisc != rightDisc) {
            return leftDisc < rightDisc ? NSOrderedAscending : NSOrderedDescending;
        }
        if (left.trackNumber != right.trackNumber) {
            return left.trackNumber < right.trackNumber ? NSOrderedAscending : NSOrderedDescending;
        }
        return [[left displayTitle] caseInsensitiveCompare:[right displayTitle]];
    }];

    NSMutableArray *arranged = [NSMutableArray arrayWithCapacity:[self.trackIDs count]];
    NSUInteger i;
    for (i = 0; i < [sorted count]; i++) {
        [arranged addObject:[[sorted objectAtIndex:i] trackID]];
    }

    // Anything the library could not resolve is kept. Rearranging a playlist is
    // not a reason to lose a song whose file happens to be missing today.
    for (i = 0; i < [self.trackIDs count]; i++) {
        NSString *trackID = [self.trackIDs objectAtIndex:i];
        if (![arranged containsObject:trackID]) [arranged addObject:trackID];
    }

    [self.trackIDs removeAllObjects];
    [self.trackIDs addObjectsFromArray:arranged];
}

- (BOOL)isDescendantOf:(BTPlaylist *)other {
    BTPlaylist *p = self.parent;
    while (p) {
        if (p == other) return YES;
        p = p.parent;
    }
    return NO;
}

@end
