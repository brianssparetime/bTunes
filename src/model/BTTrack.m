#import "BTTrack.h"
#import "BTPreferences.h"

// The roots, asked of the settings each time rather than held, so pointing a
// setting somewhere else takes effect without anything having to be told.
static NSString *BTRootFor(BTPathRoot which) {
    BTPreferences *prefs = [BTPreferences sharedPreferences];
    NSString *root = (which == BTPathRootDetune) ? [prefs detuneFolder] : [prefs musicFolder];
    return [root length] > 0 ? [root stringByStandardizingPath] : nil;
}

// A full path under the given root becomes the part below it. Anything else is
// returned unchanged, which covers both a path already stored relative and a
// file that sits outside the root entirely.
static NSString *BTPathBelowRoot(NSString *path, BTPathRoot which) {
    if (![path hasPrefix:@"/"]) return path;

    NSString *standard = [path stringByStandardizingPath];
    NSString *root = BTRootFor(which);
    if ([root length] == 0) return standard;

    NSString *prefix = [root hasSuffix:@"/"] ? root : [root stringByAppendingString:@"/"];
    if (![standard hasPrefix:prefix]) return standard;

    NSString *below = [standard substringFromIndex:[prefix length]];
    return [below length] > 0 ? below : standard;
}

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

// A month is the average Gregorian year in twelfths and a year is that same
// average, because a library's running time is read at a glance rather than
// counted to a date.
typedef struct { const char *one; const char *many; double seconds; } BTRunningUnit;

static const BTRunningUnit BTRunningUnits[] = {
    { "century", "centuries", 3155695200.0 },
    { "decade",  "decades",    315569520.0 },
    { "year",    "years",       31556952.0 },
    { "month",   "months",       2629746.0 },
    { "day",     "days",           86400.0 },
    { "hour",    "hours",           3600.0 },
    { "minute",  "minutes",           60.0 },
};

// Past a million the digits stop carrying meaning, so they are dropped for a
// word. A trailing nought after the point says nothing either: two million, not
// two point nought million.
static NSString *BTScaledCount(double value, NSString *word) {
    NSString *number = [NSString stringWithFormat:@"%.1f", value];
    if ([number hasSuffix:@".0"]) number = [number substringToIndex:[number length] - 2];
    return [NSString stringWithFormat:@"%@ %@", number, word];
}

static NSString *BTMinuteCount(double minutes) {
    if (minutes >= 1000000000.0) return BTScaledCount(minutes / 1000000000.0, @"billion");
    if (minutes >= 1000000.0)    return BTScaledCount(minutes / 1000000.0, @"million");

    // Grouped, because six figures of unbroken digits is not a number anyone
    // reads at a glance.
    static NSNumberFormatter *formatter = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSNumberFormatter alloc] init];
        [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
        [formatter setMaximumFractionDigits:0];
    });
    return [formatter stringFromNumber:@(llround(minutes))];
}

@implementation BTTrack

+ (NSString *)runningTimeStringFromInterval:(NSTimeInterval)interval {
    if (interval < 0 || isnan(interval)) interval = 0;

    NSUInteger count = sizeof(BTRunningUnits) / sizeof(BTRunningUnits[0]);
    NSUInteger i, chosen = count - 1;      // minutes, when nothing larger reaches two
    for (i = 0; i < count; i++) {
        if (floor(interval / BTRunningUnits[i].seconds) >= 2.0) { chosen = i; break; }
    }

    long long leading = (long long)floor(interval / BTRunningUnits[chosen].seconds);
    const char *word = (leading == 1) ? BTRunningUnits[chosen].one : BTRunningUnits[chosen].many;
    NSString *head = [NSString stringWithFormat:@"%lld %s", leading, word];

    // Saying "5 minutes (5 minutes)" helps nobody.
    if (chosen == count - 1) return head;

    return [NSString stringWithFormat:@"%@ (%@ minutes)", head, BTMinuteCount(interval / 60.0)];
}

@synthesize path = _path;

// Every assignment is normalized, so a caller handing over a full path gets it
// stored below the root without having to know that is the rule. A library
// written before the root existed converts itself the first time it is loaded.
- (void)setPath:(NSString *)path {
    _path = [BTPathBelowRoot(path, self.pathRoot) copy];
}

- (void)setPath:(NSString *)path root:(BTPathRoot)root {
    self.pathRoot = root;
    self.path = path;
}

+ (instancetype)trackWithDictionary:(NSDictionary *)dict {
    BTTrack *t = [[BTTrack alloc] init];
    t.trackID = BTString(dict, @"id");
    // The root before the path, because the path is measured against it.
    t.pathRoot = [BTString(dict, @"pathRoot") isEqualToString:@"detune"]
        ? BTPathRootDetune : BTPathRootMusic;
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
    t.usesStartTime = [[dict objectForKey:@"usesStartTime"] boolValue];
    t.startTime = BTDouble(dict, @"startTime");
    t.usesEndTime = [[dict objectForKey:@"usesEndTime"] boolValue];
    t.endTime = BTDouble(dict, @"endTime");
    if (t.trackID == nil || t.path == nil) return nil;
    return t;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    [d setObject:(self.trackID ? self.trackID : @"") forKey:@"id"];
    [d setObject:(self.path ? self.path : @"") forKey:@"path"];
    // Written only when it is not the ordinary one, so a library holding no
    // substituted songs reads exactly as it did before they were possible.
    if (self.pathRoot == BTPathRootDetune) [d setObject:@"detune" forKey:@"pathRoot"];
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
    // Written only when in use, so a library carries nothing for the songs that
    // play whole, which is nearly all of them.
    if (self.usesStartTime) {
        [d setObject:@YES forKey:@"usesStartTime"];
        [d setObject:@(self.startTime) forKey:@"startTime"];
    }
    if (self.usesEndTime) {
        [d setObject:@YES forKey:@"usesEndTime"];
        [d setObject:@(self.endTime) forKey:@"endTime"];
    }
    return d;
}

- (NSString *)resolvedPath {
    if ([self.path length] == 0) return nil;
    if ([self.path hasPrefix:@"/"]) return self.path;

    NSString *root = BTRootFor(self.pathRoot);
    return root ? [root stringByAppendingPathComponent:self.path] : self.path;
}

- (NSTimeInterval)playbackStart {
    if (!self.usesStartTime || self.startTime <= 0) return 0.0;
    return self.startTime;
}

- (NSTimeInterval)playbackEnd {
    if (!self.usesEndTime || self.endTime <= 0) return self.duration;
    return self.endTime;
}

// Ninety seconds may be written 90, 1:30, 1m30s, or 90s. Hours are allowed as
// 1:02:30. Anything else is refused rather than being read as zero, so a typing
// slip does not quietly set a song to start at the beginning.
+ (NSTimeInterval)timeFromText:(NSString *)text {
    NSString *trimmed = [[text stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceCharacterSet]] lowercaseString];
    if ([trimmed length] == 0) return -1.0;

    if ([trimmed rangeOfString:@":"].location != NSNotFound) {
        NSArray *parts = [trimmed componentsSeparatedByString:@":"];
        if ([parts count] < 2 || [parts count] > 3) return -1.0;
        NSTimeInterval total = 0.0;
        NSUInteger i;
        for (i = 0; i < [parts count]; i++) {
            NSString *part = [parts objectAtIndex:i];
            if ([part length] == 0) return -1.0;
            if ([part rangeOfCharacterFromSet:
                 [[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) {
                return -1.0;
            }
            total = total * 60.0 + [part doubleValue];
        }
        return total;
    }

    if ([trimmed rangeOfString:@"m"].location != NSNotFound ||
        [trimmed rangeOfString:@"h"].location != NSNotFound ||
        [trimmed rangeOfString:@"s"].location != NSNotFound) {
        NSScanner *scanner = [NSScanner scannerWithString:trimmed];
        NSTimeInterval total = 0.0;
        BOOL read = NO;
        while (![scanner isAtEnd]) {
            double value = 0.0;
            if (![scanner scanDouble:&value]) return -1.0;
            NSString *unit = nil;
            if (![scanner scanCharactersFromSet:[NSCharacterSet letterCharacterSet]
                                     intoString:&unit]) return -1.0;
            if ([unit isEqualToString:@"h"]) total += value * 3600.0;
            else if ([unit isEqualToString:@"m"]) total += value * 60.0;
            else if ([unit isEqualToString:@"s"]) total += value;
            else return -1.0;
            read = YES;
        }
        return read ? total : -1.0;
    }

    NSScanner *plain = [NSScanner scannerWithString:trimmed];
    double seconds = 0.0;
    if (![plain scanDouble:&seconds] || ![plain isAtEnd]) return -1.0;
    return seconds;
}

+ (NSString *)textFromTime:(NSTimeInterval)time {
    if (time < 0) time = 0;
    NSInteger total = (NSInteger)(time + 0.5);
    if (total >= 3600) {
        return [NSString stringWithFormat:@"%ld:%02ld:%02ld",
                (long)(total / 3600), (long)((total % 3600) / 60), (long)(total % 60)];
    }
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

- (NSURL *)fileURL {
    NSString *resolved = [self resolvedPath];
    return [resolved length] > 0 ? [NSURL fileURLWithPath:resolved] : nil;
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
