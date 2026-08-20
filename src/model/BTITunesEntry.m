#import "BTITunesEntry.h"
#import "BTDetuneMap.h"
#import "BTITunesTwins.h"

NSString *BTITunesString(NSDictionary *entry, NSString *key) {
    id value = [entry objectForKey:key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

NSString *BTITunesPathFromLocation(NSString *location) {
    if ([location length] == 0) return nil;
    NSURL *url = [NSURL URLWithString:location];
    if (url == nil || ![url isFileURL]) return nil;
    return [[url path] stringByStandardizingPath];
}

BOOL BTITunesEntryIsProtected(NSDictionary *entry, NSString *path) {
    if ([[entry objectForKey:@"Protected"] boolValue]) return YES;
    if ([[[path pathExtension] lowercaseString] isEqualToString:@"m4p"]) return YES;
    NSString *kind = BTITunesString(entry, @"Kind");
    return kind && [kind rangeOfString:@"Protected"
                               options:NSCaseInsensitiveSearch].location != NSNotFound;
}

@interface BTITunesEntry ()
@property (nonatomic, strong) NSDictionary *entry;
@property (nonatomic, copy) NSString *persistentID;
@property (nonatomic, copy) NSString *iTunesPath;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) BTPathRoot pathRoot;
@property (nonatomic, copy) NSString *resolvedPath;
@property (nonatomic, assign) BOOL fromDetune;
@property (nonatomic, assign) BOOL fromTwin;
@property (nonatomic, copy) NSString *fileKind;
@property (nonatomic, assign) NSTimeInterval fileDuration;
@property (nonatomic, assign) long long fileSize;
@property (nonatomic, assign) BOOL isProtected;
@property (nonatomic, assign) BOOL originalIsProtected;
@property (nonatomic, assign) BTITunesBlock blocked;
@end

@implementation BTITunesEntry

// A song is blocked if it is locked, or if there is no file here to point at.
// Not being on disk covers both a cloud copy and a file that has since gone:
// either way there is nothing to play.
static BTITunesBlock BTBlockForOriginal(NSDictionary *entry, NSString *path, NSFileManager *files) {
    if (path == nil) return BTITunesBlockNotOnDisk;
    // Before asking the filesystem, because a locked file is blocked whether it
    // is sitting there or not, and asking is the slow part of a sync.
    if (BTITunesEntryIsProtected(entry, path)) return BTITunesBlockProtected;
    if (![files fileExistsAtPath:path]) return BTITunesBlockNotOnDisk;
    return BTITunesBlockNone;
}

static NSTimeInterval BTEntrySeconds(NSDictionary *entry) {
    id value = [entry objectForKey:@"Total Time"];
    if (![value respondsToSelector:@selector(doubleValue)]) return 0.0;
    return [value doubleValue] / 1000.0;
}

static long long BTEntryBytes(NSDictionary *entry) {
    id value = [entry objectForKey:@"Size"];
    return [value respondsToSelector:@selector(longLongValue)] ? [value longLongValue] : 0;
}

+ (instancetype)readEntry:(NSDictionary *)entry
                   detune:(BTDetuneMap *)detune
                    twins:(BTITunesTwins *)twins
                    files:(NSFileManager *)files {
    if (![entry isKindOfClass:[NSDictionary class]]) return nil;

    NSString *location = BTITunesString(entry, @"Location");
    if ([location length] == 0) return nil;    // no file and no cloud copy either

    BTITunesEntry *read = [[BTITunesEntry alloc] init];
    read.entry = entry;
    read.persistentID = BTITunesString(entry, @"Persistent ID");
    read.iTunesPath = BTITunesPathFromLocation(location);
    read.originalIsProtected = (read.iTunesPath != nil &&
                                BTITunesEntryIsProtected(entry, read.iTunesPath));
    // What iTunes says, until something stands in and answers for itself.
    read.fileKind = BTITunesString(entry, @"Kind");
    read.fileDuration = BTEntrySeconds(entry);
    read.fileSize = BTEntryBytes(entry);

    BTITunesBlock original = BTBlockForOriginal(entry, read.iTunesPath, files);

    // A playable original is left alone. The map is consulted only for what
    // could not come across otherwise, so a song that plays perfectly well is
    // never quietly swapped for a re-recording of itself.
    if (original == BTITunesBlockNone) {
        read.path = read.iTunesPath;
        read.resolvedPath = read.iTunesPath;
        read.pathRoot = BTPathRootMusic;
        read.blocked = BTITunesBlockNone;
        read.isProtected = NO;
        return read;
    }

    BTDetuneSubstitute *substitute = [detune substituteFor:read.persistentID];
    if (substitute) {
        read.path = [substitute path];
        read.resolvedPath = [[detune root] stringByAppendingPathComponent:[substitute path]];
        read.pathRoot = BTPathRootDetune;
        read.fromDetune = YES;
        read.fileKind = @"AAC audio file";
        read.blocked = BTITunesBlockNone;
        read.isProtected = NO;
        return read;
    }

    // A free copy of the same recording, already in the library. Only for a
    // locked purchase: a song that is merely in the cloud is one the listener
    // can still fetch from iTunes, and pointing it at a different file would
    // decide that for them.
    if (original == BTITunesBlockProtected) {
        BTITunesTwin *twin = [twins twinForEntry:entry files:files];
        if (twin) {
            read.path = [twin path];
            read.resolvedPath = [twin path];
            read.pathRoot = BTPathRootMusic;
            read.fromTwin = YES;
            // The free copy is its own file, of its own kind and length. Taking
            // these from the purchase would describe a file that is not there.
            read.fileKind = [twin kind];
            if ([twin duration] > 0.0) read.fileDuration = [twin duration];
            if ([twin fileSize] > 0) read.fileSize = [twin fileSize];
            read.blocked = BTITunesBlockNone;
            read.isProtected = NO;
            return read;
        }
    }

    // Nothing standing in for it, so it stays as iTunes left it.
    read.path = read.iTunesPath;
    read.resolvedPath = read.iTunesPath;
    read.pathRoot = BTPathRootMusic;
    read.blocked = original;
    read.isProtected = read.originalIsProtected;
    return read;
}

@end
