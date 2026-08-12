#import "BTTrack.h"

static NSString *BTString(NSDictionary *d, NSString *key) {
    id v = [d objectForKey:key];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

static NSInteger BTInteger(NSDictionary *d, NSString *key) {
    id v = [d objectForKey:key];
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
}

static double BTDouble(NSDictionary *d, NSString *key) {
    id v = [d objectForKey:key];
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0.0;
}

static NSDate *BTDate(NSDictionary *d, NSString *key) {
    id v = [d objectForKey:key];
    if (![v respondsToSelector:@selector(doubleValue)]) return nil;
    double t = [v doubleValue];
    return t > 0 ? [NSDate dateWithTimeIntervalSince1970:t] : nil;
}

@implementation BTTrack

+ (instancetype)trackWithDictionary:(NSDictionary *)dict {
    BTTrack *t = [[BTTrack alloc] init];
    t.trackID = BTString(dict, @"id");
    t.path = BTString(dict, @"path");
    t.persistentID = BTString(dict, @"persistentID");
    t.title = BTString(dict, @"title");
    t.artist = BTString(dict, @"artist");
    t.albumArtist = BTString(dict, @"albumArtist");
    t.album = BTString(dict, @"album");
    t.genre = BTString(dict, @"genre");
    t.composer = BTString(dict, @"composer");
    t.kind = BTString(dict, @"kind");
    t.trackNumber = BTInteger(dict, @"trackNumber");
    t.discNumber = BTInteger(dict, @"discNumber");
    t.year = BTInteger(dict, @"year");
    t.rating = BTInteger(dict, @"rating");
    t.playCount = BTInteger(dict, @"playCount");
    t.duration = BTDouble(dict, @"duration");
    t.fileSize = (long long)BTDouble(dict, @"fileSize");
    t.dateAdded = BTDate(dict, @"dateAdded");
    t.lastPlayed = BTDate(dict, @"lastPlayed");
    t.isProtected = [[dict objectForKey:@"protected"] boolValue];
    if (t.trackID == nil || t.path == nil) return nil;
    return t;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    [d setObject:(self.trackID ? self.trackID : @"") forKey:@"id"];
    [d setObject:(self.path ? self.path : @"") forKey:@"path"];
    if (self.persistentID) [d setObject:self.persistentID forKey:@"persistentID"];
    if (self.isProtected) [d setObject:@YES forKey:@"protected"];
    if (self.title) [d setObject:self.title forKey:@"title"];
    if (self.artist) [d setObject:self.artist forKey:@"artist"];
    if (self.albumArtist) [d setObject:self.albumArtist forKey:@"albumArtist"];
    if (self.album) [d setObject:self.album forKey:@"album"];
    if (self.genre) [d setObject:self.genre forKey:@"genre"];
    if (self.composer) [d setObject:self.composer forKey:@"composer"];
    if (self.kind) [d setObject:self.kind forKey:@"kind"];
    [d setObject:@(self.trackNumber) forKey:@"trackNumber"];
    [d setObject:@(self.discNumber) forKey:@"discNumber"];
    [d setObject:@(self.year) forKey:@"year"];
    [d setObject:@(self.rating) forKey:@"rating"];
    [d setObject:@(self.playCount) forKey:@"playCount"];
    [d setObject:@(self.duration) forKey:@"duration"];
    [d setObject:@((double)self.fileSize) forKey:@"fileSize"];
    if (self.dateAdded) [d setObject:@([self.dateAdded timeIntervalSince1970]) forKey:@"dateAdded"];
    if (self.lastPlayed) [d setObject:@([self.lastPlayed timeIntervalSince1970]) forKey:@"lastPlayed"];
    return d;
}

- (NSURL *)fileURL {
    return self.path ? [NSURL fileURLWithPath:self.path] : nil;
}

- (NSString *)displayTitle {
    if ([self.title length] > 0) return self.title;
    return [[self.path lastPathComponent] stringByDeletingPathExtension];
}

- (NSString *)displayArtist {
    return [self.artist length] > 0 ? self.artist : @"Unknown Artist";
}

- (NSString *)displayAlbum {
    return [self.album length] > 0 ? self.album : @"Unknown Album";
}

- (NSString *)displayGenre {
    return [self.genre length] > 0 ? self.genre : @"Unknown Genre";
}

- (NSString *)durationString {
    if (self.duration <= 0) return @"-:--";
    NSInteger total = (NSInteger)(self.duration + 0.5);
    NSInteger hours = total / 3600;
    NSInteger minutes = (total % 3600) / 60;
    NSInteger seconds = total % 60;
    if (hours > 0) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)seconds];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", (long)minutes, (long)seconds];
}

- (BOOL)matchesSearchString:(NSString *)needle {
    if ([needle length] == 0) return YES;
    NSArray *fields = @[[self displayTitle], [self displayArtist], [self displayAlbum],
                        (self.genre ? self.genre : @""), (self.composer ? self.composer : @"")];
    NSUInteger i;
    for (i = 0; i < [fields count]; i++) {
        NSString *field = [fields objectAtIndex:i];
        NSRange r = [field rangeOfString:needle options:NSCaseInsensitiveSearch];
        if (r.location != NSNotFound) return YES;
    }
    return NO;
}

@end
