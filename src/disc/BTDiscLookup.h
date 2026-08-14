#import <Foundation/Foundation.h>

@class BTAudioDisc;

// Asking somewhere else what a disc is called.
//
// Most commercial CDs carry no CD-Text, so cddafs names their tracks "Audio
// Track" and BTunes shows "Track 1" and the rest. A dozen of those going into
// twelve thousand songs is close to useless, which is why this exists: it is
// what makes taking a CD in worth doing rather than a nicety on top of it.
//
// The only network code in BTunes. It is optional, it holds nothing up, and a
// disc still imports with numbered tracks when it is turned off, refused, or
// simply fails.
@interface BTDiscLookup : NSObject

// The disc's own table of contents, which macOS writes to a .TOC.plist at the
// root of the mounted volume. So the drive is not touched for this either.
+ (NSDictionary *)tableOfContentsAtMountPath:(NSString *)path;

// The identifier MusicBrainz knows a disc by, worked out from that table.
//
// It is a SHA-1 over the first and last track numbers and a hundred offsets,
// written as capital hex, then base64 with three characters swapped so it can
// travel in a URL. Nil when the table says nothing usable.
+ (NSString *)discIDForTableOfContents:(NSDictionary *)toc;

// What the service sends back, taken apart. Its own method and named here so the
// taking-apart can be checked against a real answer without a network or a disc,
// which is most of what can go wrong with it.
+ (NSString *)readAnswer:(NSData *)data
                   album:(NSString **)outAlbum
                  artist:(NSString **)outArtist
                  titles:(NSArray **)outTitles;

// Looks the disc up and calls back on the main thread with the album, the artist
// and the track titles in disc order, or with nil and a reason.
//
// The titles come back as an array so the caller can decide what to do when the
// disc in the drive and the disc that was found disagree about how many songs
// there are, which happens and must not silently rename the wrong things.
+ (void)lookUpDisc:(BTAudioDisc *)disc
        completion:(void (^)(NSString *album, NSString *artist,
                             NSArray *titles, NSString *error))completion;

@end
