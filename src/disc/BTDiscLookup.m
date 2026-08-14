#import "BTDiscLookup.h"
#import "BTAudioDisc.h"
#import <CommonCrypto/CommonDigest.h>

// Every offset on a CD is counted from two seconds before the first track, and
// a second is 75 frames. Nothing in the table of contents includes that, so it
// is added here.
#define BT_CD_PREGAP_FRAMES 150

// The identifier is always a hundred offsets, whatever the disc actually holds:
// the lead-out, then ninety-nine tracks, with nothing standing as zero.
#define BT_TOC_SLOTS 100

@implementation BTDiscLookup

#pragma mark - The disc's own table of contents

+ (NSDictionary *)tableOfContentsAtMountPath:(NSString *)path {
    NSString *file = [path stringByAppendingPathComponent:@".TOC.plist"];
    NSDictionary *toc = [NSDictionary dictionaryWithContentsOfFile:file];
    return [toc isKindOfClass:[NSDictionary class]] ? toc : nil;
}

// The first session holding audio is the one that matters. A disc with a data
// session after the music is common and its session is not what is being asked
// about.
+ (NSDictionary *)audioSessionIn:(NSDictionary *)toc {
    NSArray *sessions = [toc objectForKey:@"Sessions"];
    if (![sessions isKindOfClass:[NSArray class]]) return nil;
    NSUInteger i;
    for (i = 0; i < [sessions count]; i++) {
        NSDictionary *session = [sessions objectAtIndex:i];
        if (![session isKindOfClass:[NSDictionary class]]) continue;
        if ([session objectForKey:@"Track Array"] != nil) return session;
    }
    return nil;
}

+ (NSString *)discIDForTableOfContents:(NSDictionary *)toc {
    NSDictionary *session = [self audioSessionIn:toc];
    if (session == nil) return nil;

    NSInteger first = [[session objectForKey:@"First Track"] integerValue];
    NSInteger last = [[session objectForKey:@"Last Track"] integerValue];
    NSInteger leadout = [[session objectForKey:@"Leadout Block"] integerValue];
    if (first < 1 || last < first || last > 99 || leadout <= 0) return nil;

    // Slot 0 is the lead-out and slots 1 to 99 are the tracks, by their own
    // numbers rather than by where they sit in the array: a disc whose first
    // track is 2 puts its first track in slot 2.
    NSInteger offsets[BT_TOC_SLOTS];
    memset(offsets, 0, sizeof(offsets));
    offsets[0] = leadout + BT_CD_PREGAP_FRAMES;

    NSArray *tracks = [session objectForKey:@"Track Array"];
    if (![tracks isKindOfClass:[NSArray class]]) return nil;
    NSUInteger i;
    for (i = 0; i < [tracks count]; i++) {
        NSDictionary *track = [tracks objectAtIndex:i];
        if (![track isKindOfClass:[NSDictionary class]]) continue;
        NSInteger point = [[track objectForKey:@"Point"] integerValue];
        if (point < 1 || point > 99) continue;
        offsets[point] = [[track objectForKey:@"Start Block"] integerValue] + BT_CD_PREGAP_FRAMES;
    }

    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"%02lX%02lX", (unsigned long)first, (unsigned long)last];
    for (i = 0; i < BT_TOC_SLOTS; i++) {
        [text appendFormat:@"%08lX", (unsigned long)offsets[i]];
    }

    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    NSData *ascii = [text dataUsingEncoding:NSASCIIStringEncoding];
    CC_SHA1([ascii bytes], (CC_LONG)[ascii length], digest);

    NSString *base64 = [[NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH]
                        base64EncodedStringWithOptions:0];
    // The three characters base64 uses that a URL does not.
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"."];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"=" withString:@"-"];
    return base64;
}

#pragma mark - Asking

// Named so the service can see who is asking and get in touch if this ever
// misbehaves, which is what they ask of anyone using it.
static NSString *const BTUserAgent = @"BTunes/1.0 ( https://github.com/ )";

+ (void)lookUpDisc:(BTAudioDisc *)disc
        completion:(void (^)(NSString *, NSString *, NSArray *, NSString *))completion {
    void (^answer)(NSString *, NSString *, NSArray *, NSString *) =
        ^(NSString *album, NSString *artist, NSArray *titles, NSString *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(album, artist, titles, error);
        });
    };

    NSDictionary *toc = [self tableOfContentsAtMountPath:[disc mountPath]];
    NSString *discID = [self discIDForTableOfContents:toc];
    if ([discID length] == 0) {
        answer(nil, nil, nil, @"the disc does not say what is on it");
        return;
    }

    NSString *text = [NSString stringWithFormat:
        @"https://musicbrainz.org/ws/2/discid/%@?fmt=json&inc=recordings+artist-credits", discID];
    NSURL *url = [NSURL URLWithString:text];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:BTUserAgent forHTTPHeaderField:@"User-Agent"];
    // Long enough to be worth waiting for and short enough that a disc is not
    // held up by a service that is not answering.
    [request setTimeoutInterval:15.0];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { answer(nil, nil, nil, [error localizedDescription]); return; }

        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]]
            ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (status == 404) {
            answer(nil, nil, nil, @"this disc is not in the list");
            return;
        }
        if (status != 200) {
            answer(nil, nil, nil, [NSString stringWithFormat:@"the list answered %ld", (long)status]);
            return;
        }

        NSString *album = nil, *artist = nil;
        NSArray *titles = nil;
        NSString *why = [self readAnswer:data album:&album artist:&artist titles:&titles];
        answer(album, artist, titles, why);
    }];
    [task resume];
}

// What comes back, taken apart carefully: it is a reply from somewhere else and
// nothing in it can be assumed to be the shape it usually is.
+ (NSString *)readAnswer:(NSData *)data
                   album:(NSString **)outAlbum
                  artist:(NSString **)outArtist
                  titles:(NSArray **)outTitles {
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![root isKindOfClass:[NSDictionary class]]) return @"the answer could not be read";

    NSArray *releases = [root objectForKey:@"releases"];
    if (![releases isKindOfClass:[NSArray class]] || [releases count] == 0) {
        return @"this disc is not in the list";
    }
    // The first is the one to take. A disc id can name several pressings of the
    // same record, and they differ in things this does not use.
    NSDictionary *release = [releases objectAtIndex:0];
    if (![release isKindOfClass:[NSDictionary class]]) return @"the answer could not be read";

    id title = [release objectForKey:@"title"];
    if ([title isKindOfClass:[NSString class]]) *outAlbum = title;

    NSArray *credits = [release objectForKey:@"artist-credit"];
    if ([credits isKindOfClass:[NSArray class]] && [credits count] > 0) {
        NSMutableString *joined = [NSMutableString string];
        NSUInteger i;
        for (i = 0; i < [credits count]; i++) {
            NSDictionary *credit = [credits objectAtIndex:i];
            if (![credit isKindOfClass:[NSDictionary class]]) continue;
            id name = [credit objectForKey:@"name"];
            if ([name isKindOfClass:[NSString class]]) [joined appendString:name];
            id join = [credit objectForKey:@"joinphrase"];
            if ([join isKindOfClass:[NSString class]]) [joined appendString:join];
        }
        if ([joined length] > 0) *outArtist = joined;
    }

    // The medium holding the tracks. A release may be several discs, and only
    // the one that was asked about comes back with its tracks filled in.
    NSArray *media = [release objectForKey:@"media"];
    if (![media isKindOfClass:[NSArray class]]) return @"the answer named no songs";

    NSUInteger m;
    for (m = 0; m < [media count]; m++) {
        NSDictionary *medium = [media objectAtIndex:m];
        if (![medium isKindOfClass:[NSDictionary class]]) continue;
        NSArray *tracks = [medium objectForKey:@"tracks"];
        if (![tracks isKindOfClass:[NSArray class]] || [tracks count] == 0) continue;

        NSMutableArray *found = [NSMutableArray array];
        NSUInteger t;
        for (t = 0; t < [tracks count]; t++) {
            NSDictionary *track = [tracks objectAtIndex:t];
            id name = [track isKindOfClass:[NSDictionary class]] ? [track objectForKey:@"title"] : nil;
            [found addObject:([name isKindOfClass:[NSString class]] ? name : @"")];
        }
        *outTitles = found;
        return nil;
    }
    return @"the answer named no songs";
}

@end
