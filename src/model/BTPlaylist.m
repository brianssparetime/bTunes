#import "BTPlaylist.h"
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
    return [self ruleWithField:(BTRuleField)[[dict objectForKey:@"field"] integerValue]
                      operator:(BTRuleOperator)[[dict objectForKey:@"op"] integerValue]
                         value:[dict objectForKey:@"value"]];
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
            double days = [self.value doubleValue];
            if (self.op == BTRuleOperatorInTheLast) {
                if (days <= 0) return NO;
                return lhs > [[NSDate date] timeIntervalSince1970] - days * 86400.0;
            }
            // "is after" and "is before" compare against a day offset from now.
            double cutoff = [[NSDate date] timeIntervalSince1970] - days * 86400.0;
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


@implementation BTPlaylist

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
    BTPlaylist *p = [self playlistWithName:[dict objectForKey:@"name"]
                                      kind:(BTPlaylistKind)[[dict objectForKey:@"kind"] integerValue]];
    NSString *pid = [dict objectForKey:@"id"];
    if (pid) p.playlistID = pid;
    p.sourcePersistentID = [dict objectForKey:@"sourcePersistentID"];
    p.matchAll = [[dict objectForKey:@"matchAll"] boolValue];
    p.limit = [[dict objectForKey:@"limit"] integerValue];

    id sort = [dict objectForKey:@"sortColumn"];
    if ([sort isKindOfClass:[NSString class]] && [sort length] > 0) {
        p.sortColumn = sort;
        // A playlist saved before the direction was recorded was ascending.
        id ascending = [dict objectForKey:@"sortAscending"];
        p.sortAscending = ascending ? [ascending boolValue] : YES;
    }

    NSArray *ids = [dict objectForKey:@"trackIDs"];
    if ([ids isKindOfClass:[NSArray class]]) [p.trackIDs addObjectsFromArray:ids];

    NSArray *ruleDicts = [dict objectForKey:@"rules"];
    NSUInteger i;
    if ([ruleDicts isKindOfClass:[NSArray class]]) {
        for (i = 0; i < [ruleDicts count]; i++) {
            [p.rules addObject:[BTSmartRule ruleWithDictionary:[ruleDicts objectAtIndex:i]]];
        }
    }

    NSArray *childDicts = [dict objectForKey:@"children"];
    if ([childDicts isKindOfClass:[NSArray class]]) {
        for (i = 0; i < [childDicts count]; i++) {
            BTPlaylist *child = [BTPlaylist playlistWithDictionary:[childDicts objectAtIndex:i]];
            child.parent = p;
            [p.children addObject:child];
        }
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
            if ([self.rules count] == 0) matched = YES;
            if (matched) [out addObject:t];
            if (self.limit > 0 && (NSInteger)[out count] >= self.limit) break;
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

- (BOOL)isDescendantOf:(BTPlaylist *)other {
    BTPlaylist *p = self.parent;
    while (p) {
        if (p == other) return YES;
        p = p.parent;
    }
    return NO;
}

@end
