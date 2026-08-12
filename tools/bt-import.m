// Adds files or folders to the BTunes library without the interface, and can
// put everything it added into a playlist. Useful for seeding a library on a
// machine with no keyboard in front of it.
//
//   bt-import <path> [<path> ...] [--playlist "Name"]
//
// The library it writes is the one belonging to the current HOME, so redirect
// HOME to keep a test run away from a real library.

#import <Foundation/Foundation.h>
#import "BTLibrary.h"
#import "BTTrack.h"
#import "BTPlaylist.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSMutableArray *paths = [NSMutableArray array];
        NSString *playlistName = nil;
        int i;

        for (i = 1; i < argc; i++) {
            NSString *arg = [NSString stringWithUTF8String:argv[i]];
            if ([arg isEqualToString:@"--playlist"] && i + 1 < argc) {
                playlistName = [NSString stringWithUTF8String:argv[++i]];
            } else {
                [paths addObject:arg];
            }
        }

        if ([paths count] == 0) {
            fprintf(stderr, "usage: bt-import <path> [<path> ...] [--playlist \"Name\"]\n");
            return 2;
        }

        BTLibrary *library = [BTLibrary sharedLibrary];
        [library loadFromDisk];
        NSUInteger before = [library.tracks count];

        __block BOOL done = NO;
        [library importPaths:paths completion:^(NSUInteger added) { done = YES; }];
        while (!done) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }

        NSUInteger i2;
        NSMutableArray *newTracks = [NSMutableArray array];
        for (i2 = before; i2 < [library.tracks count]; i2++) {
            [newTracks addObject:[library.tracks objectAtIndex:i2]];
        }

        printf("added %lu tracks\n", (unsigned long)[newTracks count]);
        for (i2 = 0; i2 < [newTracks count]; i2++) {
            BTTrack *t = [newTracks objectAtIndex:i2];
            printf("  %2ld. %-40s %-24s %-22s %6s  %s\n",
                   (long)t.trackNumber,
                   [[t displayTitle] UTF8String],
                   [[t displayArtist] UTF8String],
                   [[t displayAlbum] UTF8String],
                   [[t durationString] UTF8String],
                   [(t.kind ? t.kind : @"") UTF8String]);
        }

        if (playlistName && [newTracks count] > 0) {
            BTPlaylist *playlist = [BTPlaylist playlistWithName:playlistName kind:BTPlaylistKindStatic];
            for (i2 = 0; i2 < [newTracks count]; i2++) {
                [playlist.trackIDs addObject:[[newTracks objectAtIndex:i2] trackID]];
            }
            [library addPlaylist:playlist toFolder:nil];
            printf("playlist \"%s\" holds %lu tracks\n",
                   [playlistName UTF8String], (unsigned long)[playlist.trackIDs count]);
        }

        [library saveToDisk];
        printf("library: %s (%lu tracks total)\n",
               [[library libraryFilePath] UTF8String], (unsigned long)[library.tracks count]);
        return 0;
    }
}
