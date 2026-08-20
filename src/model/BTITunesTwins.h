#import <Foundation/Foundation.h>

// A free copy of a locked purchase, already sitting in the same iTunes library.
//
// Twenty-five years of buying music twice leaves a library holding the same
// recording as a purchase and as a rip of the disc it came on. The purchase is
// locked and the rip is not, so the song is playable and BTunes would still
// call it blocked. This is the free half of such a pair.
@interface BTITunesTwin : NSObject

// Where the free copy is, absolute, and on disk at the moment it was chosen.
@property (nonatomic, readonly, copy) NSString *path;
// What the free copy is, which is what a listener should be told rather than
// the "Protected AAC audio file" of the purchase it stands in for.
@property (nonatomic, readonly, copy) NSString *kind;
@property (nonatomic, readonly, assign) NSTimeInterval duration;
@property (nonatomic, readonly, assign) long long fileSize;

@end


// Every free song in an iTunes library, indexed by what it is a recording of,
// so a locked purchase can be asked whether the library already answers it.
//
// Matching on artist and title alone is not safe, and each rule below was
// learned from a pair that broke without it. A candidate must run within about
// three seconds of the purchase, widened only where the album name also agrees,
// which covers a remaster trimming the silence differently. A live recording
// never stands in for a studio one whatever the timings say: the live Folsom
// Prison "Folsom Prison Blues" and the studio take on a greatest-hits record
// are four seconds apart and are not the same performance. Words in brackets
// are part of what a recording is rather than noise, so "(Live)" and
// "(Acoustic Version)" have to agree, while "(feat. ...)" names a performer on
// the same recording and is dropped before comparing.
//
// Nothing here asks the filesystem while indexing. A library of twelve thousand
// songs would cost twelve thousand questions to sort into free and gone, and
// only the few hundred locked purchases ever need the answer.
@interface BTITunesTwins : NSObject

// Nil is a usable answer everywhere a map is: it means nothing was indexed and
// no purchase will find a twin.
+ (instancetype)twinsInEntries:(NSDictionary *)entries;

// The free copy of this entry, or nil. The file is confirmed present here,
// because a twin that is not on disk would swap one unplayable song for
// another.
- (BTITunesTwin *)twinForEntry:(NSDictionary *)entry files:(NSFileManager *)files;

// How many free songs were indexed. Worth reporting when a sync explains
// itself; nothing decides anything by it.
@property (nonatomic, readonly, assign) NSUInteger count;

@end
