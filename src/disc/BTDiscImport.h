#import <Foundation/Foundation.h>

@class BTAudioDisc, BTLibrary;

// Taking an audio CD into the library.
//
// Each track is decoded off the disc and encoded again into the BTunes music
// folder, laid out the way iTunes lays one out: artist, then album, then the
// songs. The disc itself is only ever read.
//
// This is slow. cddafs reads a disc at the speed the drive spins, so a full one
// is several minutes whatever the encoder does, and none of it may happen on the
// main thread.
@interface BTDiscImport : NSObject

// Runs off the main thread and calls back on it. Progress arrives as a fraction
// and the name of the song being worked on.
//
// The completion block is given how many songs came across and, when something
// went wrong, what. A failure part way through leaves the songs already imported
// in the library: they are finished files and throwing them away would be worse
// than keeping them.
+ (void)importDisc:(BTAudioDisc *)disc
              into:(BTLibrary *)library
          progress:(void (^)(double fraction, NSString *what))progress
        completion:(void (^)(NSUInteger added, NSString *error))completion;

// Where a song off this disc would be written, below the BTunes music folder.
// Exposed because the import has to say where it is putting things before it
// starts, and because it is the part worth checking without a disc.
// How many of this disc's songs the library already holds, counted by the file
// each would be written to. Nought unless the disc has been taken in before.
+ (NSUInteger)songsOfDisc:(BTAudioDisc *)disc alreadyIn:(BTLibrary *)library;

+ (NSString *)relativePathForTitle:(NSString *)title
                            artist:(NSString *)artist
                             album:(NSString *)album
                            number:(NSInteger)number
                          lossless:(BOOL)lossless;

@end
