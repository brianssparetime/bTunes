#import "BTPreferences.h"
#import "BTLibrary.h"

NSString *const BTPreferencesDidChangeNotification = @"BTPreferencesDidChange";

static NSString *const BTMusicFolderKey = @"BTMusicFolder";
static NSString *const BTDatabaseFolderKey = @"BTDatabaseFolder";
static NSString *const BTITunesLibraryPathKey = @"BTITunesLibraryPath";

@implementation BTPreferences

+ (instancetype)sharedPreferences {
    static BTPreferences *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[BTPreferences alloc] init]; });
    return shared;
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
