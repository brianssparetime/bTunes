#import <Foundation/Foundation.h>

@class BTTrack;

// One show, read from a folder inside the podcasts root.
//
// A podcast is not in the library. Its episodes are BTTrack objects, so the
// player, the columns, and the clock all work on them unchanged, but they are
// held here rather than in BTLibrary: six thousand songs and two hundred
// episodes of one show are different kinds of thing, and a search for a word
// that happens to appear in a synopsis should not answer with half of Roman
// history.
//
// Nothing here writes to the folder it read. The audio and the description file
// are the user's, and a show whose episodes cannot be downloaded again is the
// worst possible thing to be clever with.
@interface BTPodcast : NSObject

// What the show is called, and who made it. Both come from podcast.json when it
// is there; the folder's own name stands in for the title when it is not.
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *author;

// The folder's name inside the podcasts root, which is also the first component
// of every episode's path.
@property (nonatomic, readonly) NSString *folderName;

// The episodes, in the order their filenames sort, which is the order the shows
// on disk are numbered in.
@property (nonatomic, readonly) NSArray *episodes;      // BTTrack

// Every show under the podcasts root, or none when no root is set and none when
// the folder is not there. Cheap: it reads directory listings and one small
// description file per show, and opens no audio.
+ (NSArray *)podcastsOnDisk;

// What the show said about an episode, and whether those words came from the
// feed or were written for this library. A show with no description file
// answers nil and NO.
- (NSString *)synopsisForEpisode:(BTTrack *)episode;
- (BOOL)synopsisIsLocalForEpisode:(BTTrack *)episode;

// When the episode was published, or nil where the description file did not say.
- (NSDate *)airDateForEpisode:(BTTrack *)episode;

// The number the show gives the episode, as the show writes it: "029", and
// "003a" where one episode was published in parts. A bonus or an introduction
// carrying no number answers nil rather than a made-up one.
//
// A string rather than a number because the letter is what tells 003a from
// 003b, and because a show that numbers from 001 should not be listed from 1.
- (NSString *)episodeNumberForEpisode:(BTTrack *)episode;

// Opens every episode to find how long it runs, which is the one thing no
// description file records. Slow in proportion to the number of episodes, so it
// is not done while building the list: call it off the main thread and reload
// when it returns. Doing it twice costs nothing, because the second call
// returns at once.
@property (nonatomic, readonly) BOOL durationsAreKnown;
- (void)readDurations;

@end
