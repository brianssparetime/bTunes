#import "BTDetuneMap.h"
#import "BTPreferences.h"

// The schema this reader understands. A higher number means fields have meanings
// it has never been told about, and guessing at them would substitute the wrong
// recording silently. Refused rather than read.
#define BT_DETUNE_VERSION 1

static NSString *const BTDetuneMapName = @"detune-mapping.json";

@interface BTDetuneSubstitute ()
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *format;
@property (nonatomic, assign) NSTimeInterval duration;
@end

@implementation BTDetuneSubstitute
@end


@implementation BTDetuneMap {
    NSDictionary *_byPersistentID;
}

// Every field may be absent in a later version, so nothing is read without
// being asked what it is first.
static NSString *BTDetuneString(NSDictionary *d, NSString *key) {
    id value = [d objectForKey:key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static double BTDetuneNumber(NSDictionary *d, NSString *key) {
    id value = [d objectForKey:key];
    return [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : 0.0;
}

+ (instancetype)currentMap {
    return [self mapAtRoot:[[BTPreferences sharedPreferences] detuneFolder]];
}

+ (instancetype)mapAtRoot:(NSString *)root {
    if ([root length] == 0) return nil;

    NSString *standard = [root stringByStandardizingPath];
    NSString *mapPath = [standard stringByAppendingPathComponent:BTDetuneMapName];

    NSData *data = [NSData dataWithContentsOfFile:mapPath];
    if (data == nil) return nil;

    NSDictionary *top = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![top isKindOfClass:[NSDictionary class]]) return nil;

    NSInteger version = (NSInteger)BTDetuneNumber(top, @"version");
    if (version > BT_DETUNE_VERSION) {
        NSLog(@"BTunes: detune map at %@ is version %ld, which this cannot read", mapPath, (long)version);
        return nil;
    }

    NSArray *tracks = [top objectForKey:@"tracks"];
    if (![tracks isKindOfClass:[NSArray class]]) return nil;

    // The audio may sit beside the map or under a folder of its own, and only
    // joining the two fields handles both.
    NSString *audioRoot = BTDetuneString(top, @"audioRoot") ?: @".";
    NSString *audioBase = [[standard stringByAppendingPathComponent:audioRoot] stringByStandardizingPath];

    BTDetuneMap *map = [[BTDetuneMap alloc] init];
    map->_root = [audioBase copy];

    NSFileManager *files = [NSFileManager defaultManager];
    NSMutableDictionary *byID = [NSMutableDictionary dictionaryWithCapacity:[tracks count]];
    NSUInteger missing = 0, i;

    for (i = 0; i < [tracks count]; i++) {
        NSDictionary *entry = [tracks objectAtIndex:i];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;

        // Orphans carry no library identity and can never match anything read
        // from the XML. They are published so the recordings are not lost, not
        // because they are useful here.
        NSString *persistentID = BTDetuneString(entry, @"persistentID");
        NSString *relative = BTDetuneString(entry, @"path");
        if ([persistentID length] == 0 || [relative length] == 0) continue;

        if (![files fileExistsAtPath:[audioBase stringByAppendingPathComponent:relative]]) {
            missing++;
            continue;
        }

        BTDetuneSubstitute *substitute = [[BTDetuneSubstitute alloc] init];
        substitute.path = relative;
        substitute.format = BTDetuneString(entry, @"format");
        substitute.duration = BTDetuneNumber(entry, @"duration");
        [byID setObject:substitute forKey:persistentID];
    }

    map->_byPersistentID = byID;
    map->_missingFiles = missing;
    if (missing > 0) {
        NSLog(@"BTunes: detune map names %lu files that are not in %@",
              (unsigned long)missing, audioBase);
    }
    return map;
}

- (NSUInteger)count {
    return [_byPersistentID count];
}

- (BTDetuneSubstitute *)substituteFor:(NSString *)persistentID {
    if ([persistentID length] == 0) return nil;
    return [_byPersistentID objectForKey:persistentID];
}

@end
