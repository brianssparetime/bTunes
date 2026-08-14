#import "BTPreferences.h"
#import "BTLibrary.h"

NSString *const BTPreferencesDidChangeNotification = @"BTPreferencesDidChange";

static NSString *const BTMusicFolderKey = @"BTMusicFolder";
static NSString *const BTDatabaseFolderKey = @"BTDatabaseFolder";
static NSString *const BTITunesLibraryPathKey = @"BTITunesLibraryPath";
static NSString *const BTPurpleModeKey = @"BTPurpleMode";
static NSString *const BTDetuneFolderKey = @"BTDetuneFolder";
static NSString *const BTBTunesFolderKey = @"BTBTunesFolder";
static NSString *const BTImportsLosslessKey = @"BTImportsLossless";

@implementation BTPreferences

// Every setting here is read from and written to the defaults, so none of them
// has anything to keep in an ivar.
@dynamic btunesFolder, importsLossless;

+ (instancetype)sharedPreferences {
    static BTPreferences *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[BTPreferences alloc] init]; });
    return shared;
}

- (NSString *)defaultBTunesFolder {
    NSArray *music = NSSearchPathForDirectoriesInDomains(NSMusicDirectory, NSUserDomainMask, YES);
    NSString *home = ([music count] > 0) ? [music objectAtIndex:0]
                                         : [NSHomeDirectory() stringByAppendingPathComponent:@"Music"];
    return [home stringByAppendingPathComponent:@"BTunes"];
}

- (NSString *)btunesFolder {
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:BTBTunesFolderKey];
    return [saved length] > 0 ? saved : [self defaultBTunesFolder];
}

- (void)setBtunesFolder:(NSString *)folder {
    [[NSUserDefaults standardUserDefaults] setObject:(folder ?: @"") forKey:BTBTunesFolderKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BTPreferencesDidChangeNotification object:nil];
}

- (BOOL)importsLossless {
    return [[NSUserDefaults standardUserDefaults] boolForKey:BTImportsLosslessKey];
}

- (void)setImportsLossless:(BOOL)lossless {
    [[NSUserDefaults standardUserDefaults] setBool:lossless forKey:BTImportsLosslessKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BTPreferencesDidChangeNotification object:nil];
}

- (NSString *)defaultMusicFolder {
    NSFileManager *fm = [NSFileManager defaultManager];

    // The iTunes media folder when there is one, since that is where the songs
    // are today.
    NSString *media = [NSHomeDirectory() stringByAppendingPathComponent:
                       @"Music/iTunes/iTunes Media/Music"];
    BOOL isDirectory = NO;
    if ([fm fileExistsAtPath:media isDirectory:&isDirectory] && isDirectory) return media;

    return [NSHomeDirectory() stringByAppendingPathComponent:@"Music"];
}

- (NSString *)defaultDatabaseFolder {
    // Whatever the library would use with no setting at all: the environment
    // override, a folder beside the application, or Application Support.
    return [BTLibrary unconfiguredSupportDirectory];
}

// The usual places, in the order iTunes has used them.
- (NSString *)defaultITunesLibraryPath {
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *folder = [NSHomeDirectory() stringByAppendingPathComponent:@"Music/iTunes"];
    NSArray *names = @[@"iTunes Music Library.xml", @"iTunes Library.xml"];
    NSUInteger i;
    for (i = 0; i < [names count]; i++) {
        NSString *path = [folder stringByAppendingPathComponent:[names objectAtIndex:i]];
        if ([files fileExistsAtPath:path]) return path;
    }
    return [folder stringByAppendingPathComponent:[names objectAtIndex:0]];
}

- (NSString *)iTunesLibraryPath {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:BTITunesLibraryPathKey];
    return [stored length] > 0 ? stored : [self defaultITunesLibraryPath];
}

- (void)setITunesLibraryPath:(NSString *)path {
    [[NSUserDefaults standardUserDefaults] setObject:path forKey:BTITunesLibraryPathKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BTPreferencesDidChangeNotification
                                                        object:self];
}

// No default worth guessing at. A folder that is not there would be indexed on
// every sync and found empty, and a wrong guess would be worse: songs silently
// pointed at recordings of something else.
- (NSString *)detuneFolder {
    return [[NSUserDefaults standardUserDefaults] stringForKey:BTDetuneFolderKey];
}

- (void)setDetuneFolder:(NSString *)detuneFolder {
    [[NSUserDefaults standardUserDefaults] setObject:(detuneFolder ?: @"") forKey:BTDetuneFolderKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BTPreferencesDidChangeNotification
                                                        object:self];
}

- (BOOL)purpleMode {
    return [[NSUserDefaults standardUserDefaults] boolForKey:BTPurpleModeKey];
}

- (void)setPurpleMode:(BOOL)purpleMode {
    [[NSUserDefaults standardUserDefaults] setBool:purpleMode forKey:BTPurpleModeKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BTPreferencesDidChangeNotification
                                                        object:self];
}

- (NSString *)musicFolder {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:BTMusicFolderKey];
    return [stored length] > 0 ? stored : [self defaultMusicFolder];
}

- (void)setMusicFolder:(NSString *)musicFolder {
    [[NSUserDefaults standardUserDefaults] setObject:musicFolder forKey:BTMusicFolderKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BTPreferencesDidChangeNotification
                                                        object:self];
}

- (NSString *)databaseFolder {
    NSString *stored = [[NSUserDefaults standardUserDefaults] stringForKey:BTDatabaseFolderKey];
    return [stored length] > 0 ? stored : [self defaultDatabaseFolder];
}

- (void)setDatabaseFolder:(NSString *)databaseFolder {
    [[NSUserDefaults standardUserDefaults] setObject:databaseFolder forKey:BTDatabaseFolderKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:BTPreferencesDidChangeNotification
                                                        object:self];
}

@end
