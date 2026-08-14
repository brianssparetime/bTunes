#import <Foundation/Foundation.h>

@class BTTrack;

// Posted when an audio CD is put in or taken out.
extern NSString *const BTAudioDiscDidChangeNotification;

// An audio CD in the drive, read as the folder of files the system mounts it as.
//
// Nothing here talks to the drive. macOS mounts an audio CD through cddafs,
// which presents each track as an AIFF file and reads the whole thing on demand,
// so playing a track is opening a file and importing one is copying it. The
// disc is never addressed directly and no CD-reading code exists here.
//
// The names come free with it. cddafs reads the disc's CD-Text and builds the
// filenames out of it, joining an artist and a title with " - " and falling back
// to "Audio Track" where the disc says nothing. The volume takes the album's
// name the same way, falling back to "Audio CD". So CD-Text arrives already
// read, and what is left is taking the pieces back apart.
@interface BTAudioDisc : NSObject

@property (nonatomic, readonly, copy) NSString *mountPath;
// What the left bar shows: the album when the disc named itself, "Audio CD"
// when it did not.
@property (nonatomic, readonly, copy) NSString *name;
// Nil when the disc carried no CD-Text to say.
@property (nonatomic, readonly, copy) NSString *album;
@property (nonatomic, readonly, copy) NSString *artist;

// The tracks, in the order they sit on the disc. Each is an ordinary BTTrack
// holding the full path of its file, so everything that plays a song plays these
// without being told they are different.
@property (nonatomic, readonly) NSArray *tracks;

// Whether the disc named its own tracks, or they are only numbered. What decides
// whether looking the disc up somewhere is worth doing.
@property (nonatomic, readonly) BOOL named;

// The one in the drive, or nil. Found by asking each volume what filesystem it
// is, since only cddafs means an audio CD.
//
// BTUNES_DISC_PATH names a folder to read instead, which is how this is looked
// at without a disc. Only ever set by a harness.
+ (BTAudioDisc *)insertedDisc;

// A disc read from a given folder. The real one arrives this way too, so a
// folder of AIFFs under /tmp stands in for a disc and everything below can be
// exercised without one in the drive.
+ (BTAudioDisc *)discAtMountPath:(NSString *)path;

+ (void)startWatching;

- (BOOL)eject;

@end
