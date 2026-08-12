#import <Foundation/Foundation.h>

// Posted when an iPod is attached or removed.
extern NSString *const BTIPodDidChangeNotification;

// A mounted iPod, found by looking for the iPod_Control folder at the top of a
// volume. Nothing here writes to the device.
@interface BTIPod : NSObject

@property (nonatomic, readonly) NSString *mountPath;    // /Volumes/Name
@property (nonatomic, readonly) NSString *name;         // volume name
@property (nonatomic, readonly) long long capacity;
@property (nonatomic, readonly) long long freeSpace;

- (NSString *)controlPath;      // <mount>/iPod_Control
- (NSString *)musicPath;        // <mount>/iPod_Control/Music
- (NSString *)databasePath;     // <mount>/iPod_Control/iTunes/iTunesDB

+ (BTIPod *)attachedIPod;       // nil when none is mounted
+ (void)startWatching;          // posts the change notification on mount and unmount

// Unmounts the device. The workspace reports only success or failure, with no
// reason attached, so there is nothing more to hand back than a flag.
- (BOOL)eject;

@end
