#import <Foundation/Foundation.h>

@class BTPlaylist, BTTrack, DRCDTextBlock, DRDevice;

// A CD runs at 75 sectors a second, and the standard blank holds 80 minutes of
// them. Whether to offer a burn is settled before there is a disc in the drive
// to ask, so it is settled against that nominal figure; the disc itself is
// asked once it is in, and can still refuse a playlist that fits 80 minutes.
extern const NSUInteger BTBurnSectorsPerSecond;
extern const NSUInteger BTBurnNominalDiscSectors;

// Why a playlist cannot be burned. Every one of these is worked out before the
// first byte is written, because after that point the disc is either right or
// it is scrap.
typedef NS_ENUM(NSInteger, BTBurnRefusal) {
    BTBurnRefusalNone = 0,
    BTBurnRefusalEmpty,        // nothing in the playlist to burn
    BTBurnRefusalUnreadable,   // a locked purchase, or a file that has gone
    BTBurnRefusalTooLong       // more than a disc holds, gaps included
};

// One playlist measured against one disc: which songs can be read, how long
// they run with the gaps between them, and whether that fits.
//
// Nothing here touches a drive. It answers from the library alone, so the
// dialog can recompute as the gap changes without going near the hardware.
@interface BTBurnPlan : NSObject

// Whether a source is the kind of thing a disc can be made from at all. A
// folder takes its contents from its children and the library never fits, so
// neither is offered.
+ (BOOL)canBurnPlaylist:(BTPlaylist *)playlist;

+ (instancetype)planForPlaylist:(BTPlaylist *)playlist tracks:(NSArray *)allTracks;

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) NSArray *songs;        // BTTrack, in playlist order
@property (nonatomic, readonly) NSArray *unreadable;   // the ones that stop the burn
// Songs carrying a start or end time. The disc gets what BTunes plays, which
// the framework cannot do from the file alone, so each of these is written out
// as a trimmed copy before the burn and costs time and scratch space.
@property (nonatomic, readonly) NSArray *trimmed;

// None, one second, or two, and two unless something says otherwise. Gaps sit
// between songs, so a playlist of twenty has nineteen of them.
@property (nonatomic, assign) NSUInteger gapSeconds;

- (NSTimeInterval)audioTime;
- (NSTimeInterval)gapTime;
- (NSTimeInterval)totalTime;
- (NSUInteger)sectors;

- (BTBurnRefusal)refusal;
// The reason said outright, or nil when there is nothing to refuse.
- (NSString *)refusalText;

// The tracks the framework will burn, built fresh each time so a file that has
// gone since the dialog opened is caught before anything is written. Nil when
// the framework turns one down, with the reason in *reason.
//
// Slow when the playlist holds trimmed songs, since each one is decoded to a
// copy of the part that plays. Call it off the main thread.
- (NSArray *)buildTracks:(NSString **)reason;

// Whether building the tracks will have to decode anything first, and why the
// scratch space it would need is not there. Both are asked before the reader is
// left waiting on a conversion that cannot finish.
- (BOOL)needsPreparation;
- (NSString *)problemWithScratchSpace;

// Throws away the trimmed copies. Called once the burn is over, since the
// framework reads them for its whole length.
- (void)removeScratch;

// The playlist name on the disc and the title and artist on each track, for
// players that show them. Nil when there is nothing worth writing.
- (DRCDTextBlock *)cdText;

// Drives that can write a CD-R, in the order the system lists them.
+ (NSArray *)writableDevices;

// Why the disc in a drive cannot take this burn, or nil when it can. Asked
// again immediately before writing, since a tray can be opened while a dialog
// is up.
- (NSString *)problemWithDisc:(DRDevice *)device;

// Sectors said as a time, which is how a disc's capacity is read.
+ (NSString *)stringFromSectors:(NSUInteger)sectors;

@end
