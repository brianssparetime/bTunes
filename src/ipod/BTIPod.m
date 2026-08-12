#import "BTIPod.h"
#import <AppKit/AppKit.h>

NSString *const BTIPodDidChangeNotification = @"BTIPodDidChange";

@interface BTIPod ()
@property (nonatomic, copy) NSString *mountPath;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) BOOL usesFAT;
@property (nonatomic, assign) long long capacity;
@property (nonatomic, assign) long long freeSpace;
@end

@implementation BTIPod

+ (BTIPod *)iPodAtMountPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *control = [path stringByAppendingPathComponent:@"iPod_Control"];
    BOOL isDirectory = NO;
    if (![fm fileExistsAtPath:control isDirectory:&isDirectory] || !isDirectory) return nil;

    BTIPod *pod = [[BTIPod alloc] init];
    pod.mountPath = path;
    pod.name = [path lastPathComponent];

    NSDictionary *attrs = [fm attributesOfFileSystemForPath:path error:NULL];
    pod.capacity = [[attrs objectForKey:NSFileSystemSize] longLongValue];
    pod.freeSpace = [[attrs objectForKey:NSFileSystemFreeSize] longLongValue];

    // A Windows formatted iPod has no HFS+ metadata folder at the root. The
    // distinction decides how file names have to be written later.
    NSString *hfsMarker = [path stringByAppendingPathComponent:@".HFS+ Private Directory Data\r"];
    pod.usesFAT = ![fm fileExistsAtPath:hfsMarker];

    return pod;
}

+ (BTIPod *)attachedIPod {
    NSArray *volumes = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Volumes" error:NULL];
    NSUInteger i;
    for (i = 0; i < [volumes count]; i++) {
        NSString *path = [@"/Volumes" stringByAppendingPathComponent:[volumes objectAtIndex:i]];
        BTIPod *pod = [self iPodAtMountPath:path];
        if (pod) return pod;
    }
    return nil;
}

+ (void)startWatching {
    NSNotificationCenter *nc = [[NSWorkspace sharedWorkspace] notificationCenter];
    [nc addObserverForName:NSWorkspaceDidMountNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        [[NSNotificationCenter defaultCenter] postNotificationName:BTIPodDidChangeNotification object:nil];
    }];
    [nc addObserverForName:NSWorkspaceDidUnmountNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
        [[NSNotificationCenter defaultCenter] postNotificationName:BTIPodDidChangeNotification object:nil];
    }];
}

- (NSString *)controlPath {
    return [self.mountPath stringByAppendingPathComponent:@"iPod_Control"];
}

- (NSString *)musicPath {
    return [[self controlPath] stringByAppendingPathComponent:@"Music"];
}

- (NSString *)databasePath {
    return [[[self controlPath] stringByAppendingPathComponent:@"iTunes"]
            stringByAppendingPathComponent:@"iTunesDB"];
}

- (BOOL)eject:(NSError **)error {
    return [[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtPath:self.mountPath];
}

@end
