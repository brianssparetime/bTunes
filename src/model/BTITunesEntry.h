#import <Foundation/Foundation.h>
#import "BTTrack.h"

@class BTDetuneMap;
@class BTITunesTwins;

// Why something cannot be brought across yet. Blocked things are listed and
// shown, greyed, rather than hidden, so it is clear they exist and are waiting.
//
// The reasons are kept apart rather than collapsed into one flag. They all draw
// the same grey today, decided in a single place, so giving one its own colour
// later is a change there and nowhere else.
typedef NS_ENUM(NSInteger, BTITunesBlock) {
    BTITunesBlockNone = 0,
    BTITunesBlockProtected,         // a locked purchase nothing here can decode
    BTITunesBlockNotOnDisk,         // in the cloud, or the file has gone
    BTITunesBlockHoldsProtected,    // a playlist holding a locked song
    BTITunesBlockHoldsNotOnDisk,    // a playlist holding one that is not here
    BTITunesBlockSmart              // rules iTunes does not publish
};


// One entry from an iTunes library, read once, with every question anything asks
// of it already answered: which file BTunes would point at, which root that path
// is measured from, and why it cannot come across if it cannot.
//
// One place, because these answers have to agree. The song comparison, the
// playlist comparison, and the import each used to work eligibility out for
// themselves, which is how a song comes to be judged importable by one of them
// and then imported as its locked original by another. Deciding once and
// carrying the answer makes disagreement impossible rather than unlikely.
//
// Where a locked purchase has a free copy standing in for it, that substitution
// happens here too, and everything downstream sees an ordinary unblocked entry
// that happens to point somewhere else. Two kinds of free copy stand in, and
// they are tried in that order: a recording detune made, which names the
// purchase by its persistent id and so cannot be the wrong song, and then a
// free copy of the same recording already in the iTunes library, which is
// recognised by what it is rather than by an id and so is the weaker claim.
@interface BTITunesEntry : NSObject

// Nil when the entry names no file at all, which is neither a song on disk nor
// a cloud copy and has nothing for a library to record.
//
// A nil detune map means no substitution, which is the ordinary state before
// detune has published anything. A nil twin index means the same.
+ (instancetype)readEntry:(NSDictionary *)entry
                   detune:(BTDetuneMap *)detune
                    twins:(BTITunesTwins *)twins
                    files:(NSFileManager *)files;

@property (nonatomic, readonly, strong) NSDictionary *entry;
@property (nonatomic, readonly, copy) NSString *persistentID;

// Where iTunes says the file is. Nil for a cloud copy, which is a thing BTunes
// has nothing to point at.
@property (nonatomic, readonly, copy) NSString *iTunesPath;

// What BTunes would record: the iTunes file, or the free recording standing in
// for it. Measured against pathRoot, so hand both to setPath:root: together.
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, assign) BTPathRoot pathRoot;
// The same file with its root in front of it, for comparing against what the
// library already holds. Nil when there is no file to point at.
@property (nonatomic, readonly, copy) NSString *resolvedPath;

// Whether a free recording is standing in for a locked purchase.
@property (nonatomic, readonly, assign) BOOL fromDetune;
// Whether a free copy already in the iTunes library is standing in for one.
@property (nonatomic, readonly, assign) BOOL fromTwin;

// What the file BTunes would point at actually is: the entry's own answer,
// unless something stands in for it, in which case these describe the stand-in
// rather than the purchase it replaces. A substituted song plays, so saying
// "Protected AAC audio file" beside it would be plainly wrong, and a free copy
// of the same recording is its own file with its own length and size.
@property (nonatomic, readonly, copy) NSString *fileKind;
@property (nonatomic, readonly, assign) NSTimeInterval fileDuration;
@property (nonatomic, readonly, assign) long long fileSize;

// Whether the file BTunes would point at is locked. A substituted entry is not,
// which is the whole point of substituting it.
@property (nonatomic, readonly, assign) BOOL isProtected;
// Whether the iTunes original was locked, substitution aside.
@property (nonatomic, readonly, assign) BOOL originalIsProtected;

@property (nonatomic, readonly, assign) BTITunesBlock blocked;

@end


// Reading an iTunes entry's fields, one definition rather than one per caller.
NSString *BTITunesString(NSDictionary *entry, NSString *key);
// A locked purchase. Recognised three ways because iTunes has spelled it
// differently over the years and one library spans all of them.
BOOL BTITunesEntryIsProtected(NSDictionary *entry, NSString *path);
// The file:// URL iTunes stores, as a path. Nil when it names no local file.
NSString *BTITunesPathFromLocation(NSString *location);
