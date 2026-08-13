#import <Foundation/Foundation.h>

// The free recording that stands in for one locked purchase.
@interface BTDetuneSubstitute : NSObject
// Below the detune root, never absolute, so the folder stays movable.
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, copy) NSString *format;
@property (nonatomic, readonly, assign) NSTimeInterval duration;
@end


// What the detune project produced, read as a lookup from iTunes persistent id
// to a playable file.
//
// The map answers one question and holds no opinion about anything else. Titles,
// ratings, play counts, and playlist membership still come from the iTunes
// library, which remains the authority on all of them. This says only which file
// to point at instead of the locked one.
//
// Entries naming a file that is not actually there are dropped as the map loads,
// so a lookup that answers has answered with something playable. Importing a
// song that cannot play would be worse than leaving it locked, because it would
// look imported.
@interface BTDetuneMap : NSObject

// The folder holding detune-mapping.json. Returns nil when the folder is unset,
// absent, or holds no usable map, which is the ordinary state before detune has
// published anything and must stay quiet rather than reading as a fault.
+ (instancetype)mapAtRoot:(NSString *)root;

// The same, for wherever the settings currently point. Nil when unset.
+ (instancetype)currentMap;

@property (nonatomic, readonly, copy) NSString *root;
@property (nonatomic, readonly, assign) NSUInteger count;
// Named in the map but missing from the folder. Worth reporting rather than
// hiding: it means the folder is torn, not that the songs were never recorded.
@property (nonatomic, readonly, assign) NSUInteger missingFiles;

- (BTDetuneSubstitute *)substituteFor:(NSString *)persistentID;

@end
