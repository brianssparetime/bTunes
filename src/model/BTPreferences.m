#import "BTPreferences.h"
#import "BTLibrary.h"

NSString *const BTPreferencesDidChangeNotification = @"BTPreferencesDidChange";

static NSString *const BTBTunesHomeKey = @"BTBTunesHome";
static NSString *const BTITunesHomeKey = @"BTITunesHome";
static NSString *const BTMusicFolderKey = @"BTMusicFolder";
static NSString *const BTDatabaseFolderKey = @"BTDatabaseFolder";
static NSString *const BTITunesLibraryPathKey = @"BTITunesLibraryPath";
static NSString *const BTPurpleModeKey = @"BTPurpleMode";
static NSString *const BTDetuneFolderKey = @"BTDetuneFolder";
static NSString *const BTImportedCDsFolderKey = @"BTBTunesFolder";
static NSString *const BTImportsLosslessKey = @"BTImportsLossless";
static NSString *const BTLooksUpDiscsKey = @"BTLooksUpDiscs";
static NSString *const BTEvensOutVolumeKey = @"BTEvensOutVolume";

// The names of the folders inside the two homes, which are the layout rather
// than a decision anything makes at runtime.
static NSString *const BTDataFolderName = @"BTunes Data";
static NSString *const BTDetuneFolderName = @"detune files";
static NSString *const BTImportedCDsFolderName = @"Imported CDs";
static NSString *const BTPodcastsFolderName = @"Podcasts";
static NSString *const BTAddedMusicFolderName = @"Added Music Files";

// What the config file calls each of them.
static NSString *const BTConfigData = @"data";
static NSString *const BTConfigDetune = @"detune";
static NSString *const BTConfigImportedCDs = @"importedCDs";
static NSString *const BTConfigPodcasts = @"podcasts";
static NSString *const BTConfigAddedMusic = @"addedMusic";
static NSString *const BTConfigMusic = @"music";

// Read once. A folder that could change under a running application would have
// every track's stored path measured from one place and resolved from another,
// so this is settled at the first question and held.
static NSString *BTConfiguredFolder(NSString *key) {
    static NSDictionary *config = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSData *data = [NSData dataWithContentsOfFile:[BTPreferences configFilePath]];
        if (data == nil) return;

        id top = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if ([top isKindOfClass:[NSDictionary class]]) {
            config = top;
        } else {
            NSLog(@"BTunes: %@ is not readable as JSON and was ignored", [BTPreferences configFilePath]);
        }
    });

    id value = [config objectForKey:key];
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return nil;
    return [value stringByExpandingTildeInPath];
}

@implementation BTPreferences

// Every setting here is read from and written to the defaults or worked out
// from a home, so none of them has anything to keep in an ivar.
@dynamic btunesHome, iTunesHome, musicFolder, databaseFolder, detuneFolder;
@dynamic importedCDsFolder, podcastsFolder, addedMusicFolder;
@dynamic importsLossless, looksUpDiscs, evensOutVolume, purpleMode;

+ (instancetype)sharedPreferences {
    static BTPreferences *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[BTPreferences alloc] init]; });
    return shared;
}

+ (NSString *)configFilePath {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                        NSUserDomainMask, YES);
    NSString *base = [dirs count] > 0 ? [dirs objectAtIndex:0] : NSTemporaryDirectory();
    return [[base stringByAppendingPathComponent:@"BTunes"]
            stringByAppendingPathComponent:@"config.json"];
}

- (void)noteChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:BTPreferencesDidChangeNotification
                                                        object:self];
}

// A setting that has been chosen wins over the layout; a setting that has never
// been chosen, or has been cleared, falls back to it.
- (NSString *)savedStringForKey:(NSString *)key {
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    return [saved length] > 0 ? saved : nil;
}

- (void)saveString:(NSString *)value forKey:(NSString *)key {
    [[NSUserDefaults standardUserDefaults] setObject:(value ?: @"") forKey:key];
    [self noteChange];
}

#pragma mark - The two homes

- (NSString *)defaultBTunesHome {
    NSArray *music = NSSearchPathForDirectoriesInDomains(NSMusicDirectory, NSUserDomainMask, YES);
    NSString *folder = ([music count] > 0) ? [music objectAtIndex:0]
                                           : [NSHomeDirectory() stringByAppendingPathComponent:@"Music"];
    return [folder stringByAppendingPathComponent:@"BTunes"];
}

- (NSString *)btunesHome {
    return [self savedStringForKey:BTBTunesHomeKey] ?: [self defaultBTunesHome];
}

- (void)setBtunesHome:(NSString *)home {
    [self saveString:home forKey:BTBTunesHomeKey];
}

- (NSString *)defaultITunesHome {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Music/iTunes"];
}

- (NSString *)iTunesHome {
    return [self savedStringForKey:BTITunesHomeKey] ?: [self defaultITunesHome];
}

- (void)setITunesHome:(NSString *)home {
    [self saveString:home forKey:BTITunesHomeKey];
}

// Where the layout says a folder goes: inside the home under its own name,
// unless the config file points it somewhere else.
- (NSString *)layoutFolderNamed:(NSString *)name configuredAs:(NSString *)configKey {
    NSString *configured = BTConfiguredFolder(configKey);
    if (configured) return configured;
    return [[self btunesHome] stringByAppendingPathComponent:name];
}

// The same, with a folder chosen in preferences before the home existed still
// honoured in between. A saved setting loses to the config file, since the
// config file is a decision made about this machine and the saved one is a
// leftover from when every folder was chosen separately.
- (NSString *)folderNamed:(NSString *)name
             configuredAs:(NSString *)configKey
                  savedAs:(NSString *)savedKey {
    NSString *configured = BTConfiguredFolder(configKey);
    if (configured) return configured;

    NSString *saved = savedKey ? [self savedStringForKey:savedKey] : nil;
    if (saved) return saved;

    return [[self btunesHome] stringByAppendingPathComponent:name];
}

#pragma mark - Where the music is

// The iTunes home holds the music under one of two names, depending on how old
// the library is. The home itself is the answer when neither is there, which
// covers a folder of music that iTunes never laid out.
- (NSString *)defaultMusicFolder {
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *home = [self iTunesHome];
    NSArray *inside = @[@"iTunes Media/Music", @"iTunes Music"];

    NSUInteger i;
    for (i = 0; i < [inside count]; i++) {
        NSString *path = [home stringByAppendingPathComponent:[inside objectAtIndex:i]];
        BOOL isDirectory = NO;
        if ([files fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) return path;
    }
    return home;
}

- (NSString *)musicFolder {
    NSString *configured = BTConfiguredFolder(BTConfigMusic);
    if (configured) return configured;
    return [self savedStringForKey:BTMusicFolderKey] ?: [self defaultMusicFolder];
}

- (void)setMusicFolder:(NSString *)musicFolder {
    [self saveString:musicFolder forKey:BTMusicFolderKey];
}

// The usual names, in the order iTunes has used them.
- (NSString *)defaultITunesLibraryPath {
    NSFileManager *files = [NSFileManager defaultManager];
    NSString *home = [self iTunesHome];
    NSArray *names = @[@"iTunes Music Library.xml", @"iTunes Library.xml"];

    NSUInteger i;
    for (i = 0; i < [names count]; i++) {
        NSString *path = [home stringByAppendingPathComponent:[names objectAtIndex:i]];
        if ([files fileExistsAtPath:path]) return path;
    }
    return [home stringByAppendingPathComponent:[names objectAtIndex:0]];
}

- (NSString *)suggestedAlternateITunesLibraryPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Projects/btunes/itunes-snapshot.xml"];
}

- (NSString *)iTunesLibraryPath {
    return [self savedStringForKey:BTITunesLibraryPathKey] ?: [self defaultITunesLibraryPath];
}

- (void)setITunesLibraryPath:(NSString *)path {
    [self saveString:path forKey:BTITunesLibraryPathKey];
}

#pragma mark - The folders BTunes owns

- (NSString *)defaultDatabaseFolder {
    return [self layoutFolderNamed:BTDataFolderName configuredAs:BTConfigData];
}

- (NSString *)databaseFolder {
    return [self folderNamed:BTDataFolderName
                configuredAs:BTConfigData
                     savedAs:BTDatabaseFolderKey];
}

- (void)setDatabaseFolder:(NSString *)databaseFolder {
    [self saveString:databaseFolder forKey:BTDatabaseFolderKey];
}

- (NSString *)defaultDetuneFolder {
    return [self layoutFolderNamed:BTDetuneFolderName configuredAs:BTConfigDetune];
}

- (NSString *)detuneFolder {
    return [self folderNamed:BTDetuneFolderName
                configuredAs:BTConfigDetune
                     savedAs:BTDetuneFolderKey];
}

- (void)setDetuneFolder:(NSString *)detuneFolder {
    [self saveString:detuneFolder forKey:BTDetuneFolderKey];
}

- (NSString *)defaultImportedCDsFolder {
    return [self layoutFolderNamed:BTImportedCDsFolderName configuredAs:BTConfigImportedCDs];
}

- (NSString *)importedCDsFolder {
    return [self folderNamed:BTImportedCDsFolderName
                configuredAs:BTConfigImportedCDs
                     savedAs:BTImportedCDsFolderKey];
}

- (void)setImportedCDsFolder:(NSString *)folder {
    [self saveString:folder forKey:BTImportedCDsFolderKey];
}

- (void)forgetSavedDatabaseFolder {
    if ([self savedStringForKey:BTDatabaseFolderKey] == nil) return;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:BTDatabaseFolderKey];
    [self noteChange];
}

- (void)forgetSavedFoldersThatHaveMoved {
    NSFileManager *files = [NSFileManager defaultManager];
    NSArray *keys = @[BTDetuneFolderKey, BTImportedCDsFolderKey];
    NSArray *layout = @[[self defaultDetuneFolder], [self defaultImportedCDsFolder]];

    NSUInteger i;
    for (i = 0; i < [keys count]; i++) {
        NSString *saved = [self savedStringForKey:[keys objectAtIndex:i]];
        NSString *place = [layout objectAtIndex:i];
        if (saved == nil) continue;
        if ([files fileExistsAtPath:saved]) continue;
        if (![files fileExistsAtPath:place]) continue;

        NSLog(@"BTunes: %@ is gone and %@ is not, so the old choice was dropped", saved, place);
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[keys objectAtIndex:i]];
    }
}

- (NSString *)podcastsFolder {
    return [self folderNamed:BTPodcastsFolderName configuredAs:BTConfigPodcasts savedAs:nil];
}

- (NSString *)addedMusicFolder {
    return [self folderNamed:BTAddedMusicFolderName configuredAs:BTConfigAddedMusic savedAs:nil];
}

#pragma mark - How BTunes behaves

- (BOOL)importsLossless {
    return [[NSUserDefaults standardUserDefaults] boolForKey:BTImportsLosslessKey];
}

- (void)setImportsLossless:(BOOL)lossless {
    [[NSUserDefaults standardUserDefaults] setBool:lossless forKey:BTImportsLosslessKey];
    [self noteChange];
}

// On unless it has been turned off, which is why the stored value is read the
// way round it is: absent means yes.
- (BOOL)looksUpDiscs {
    NSNumber *set = [[NSUserDefaults standardUserDefaults] objectForKey:BTLooksUpDiscsKey];
    return set ? [set boolValue] : YES;
}

- (void)setLooksUpDiscs:(BOOL)looks {
    [[NSUserDefaults standardUserDefaults] setBool:looks forKey:BTLooksUpDiscsKey];
    [self noteChange];
}

- (BOOL)evensOutVolume {
    return [[NSUserDefaults standardUserDefaults] boolForKey:BTEvensOutVolumeKey];
}

- (void)setEvensOutVolume:(BOOL)evens {
    [[NSUserDefaults standardUserDefaults] setBool:evens forKey:BTEvensOutVolumeKey];
    [self noteChange];
}

- (BOOL)purpleMode {
    return [[NSUserDefaults standardUserDefaults] boolForKey:BTPurpleModeKey];
}

- (void)setPurpleMode:(BOOL)purpleMode {
    [[NSUserDefaults standardUserDefaults] setBool:purpleMode forKey:BTPurpleModeKey];
    [self noteChange];
}

@end
