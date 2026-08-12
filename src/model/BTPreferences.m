#import "BTPreferences.h"
#import "BTLibrary.h"

NSString *const BTPreferencesDidChangeNotification = @"BTPreferencesDidChange";

static NSString *const BTMusicFolderKey = @"BTMusicFolder";
static NSString *const BTDatabaseFolderKey = @"BTDatabaseFolder";

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
