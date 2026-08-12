// Headless check of the parts that have no interface: importing files, reading
// tags, resolving smart playlists and folders, and the library round trip.
//
// Build and run with tools/smoke_test.sh, passing a folder of audio files.

#import <Foundation/Foundation.h>
#import "BTLibrary.h"
#import "BTITunesImport.h"
#import "BTTrack.h"
#import "BTPlaylist.h"
#import "BTIPodDatabase.h"

static int gFailures = 0;

static void Check(BOOL condition, NSString *what) {
    if (condition) {
        printf("  pass  %s\n", [what UTF8String]);
    } else {
        printf("  FAIL  %s\n", [what UTF8String]);
        gFailures++;
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: smoke_test <folder of audio files>\n");
            return 2;
        }
        NSString *folder = [NSString stringWithUTF8String:argv[1]];

        BTLibrary *library = [BTLibrary sharedLibrary];
        __block BOOL done = NO;
        __block NSUInteger added = 0;

        printf("import\n");
        [library importPaths:@[folder] completion:^(NSUInteger count) {
            added = count;
            done = YES;
        }];
        while (!done) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        Check(added > 0, ([NSString stringWithFormat:@"imported %lu tracks", (unsigned long)added]));

        BTTrack *first = [library.tracks count] > 0 ? [library.tracks objectAtIndex:0] : nil;
        Check(first != nil, @"library holds tracks");
        Check(first.duration > 0, ([NSString stringWithFormat:@"duration read (%@)", [first durationString]]));
        Check([first.kind length] > 0, ([NSString stringWithFormat:@"kind read (%@)", first.kind]));
        Check([[first displayTitle] length] > 0, ([NSString stringWithFormat:@"title (%@)", [first displayTitle]]));

        printf("re-import skips duplicates\n");
        done = NO;
        [library importPaths:@[folder] completion:^(NSUInteger count) { added = count; done = YES; }];
        while (!done) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
        Check(added == 0, @"second import adds nothing");

        printf("static playlist\n");
        BTPlaylist *manual = [BTPlaylist playlistWithName:@"Manual" kind:BTPlaylistKindStatic];
        [manual.trackIDs addObject:first.trackID];
        Check([[manual resolveTracks:library.tracks] count] == 1, @"static playlist resolves one track");

        printf("smart playlist\n");
        BTPlaylist *smart = [BTPlaylist playlistWithName:@"Smart" kind:BTPlaylistKindSmart];
        smart.matchAll = YES;
        [smart.rules addObject:[BTSmartRule ruleWithField:BTRuleFieldTitle
                                                 operator:BTRuleOperatorContains
                                                    value:[first displayTitle]]];
        NSArray *smartTracks = [smart resolveTracks:library.tracks];
        Check([smartTracks count] >= 1, @"smart rule matches by title");

        BTPlaylist *impossible = [BTPlaylist playlistWithName:@"None" kind:BTPlaylistKindSmart];
        [impossible.rules addObject:[BTSmartRule ruleWithField:BTRuleFieldTitle
                                                      operator:BTRuleOperatorIs
                                                         value:@"no such song exists here"]];
        Check([[impossible resolveTracks:library.tracks] count] == 0, @"smart rule can match nothing");

        BTPlaylist *recent = [BTPlaylist playlistWithName:@"Recent" kind:BTPlaylistKindSmart];
        [recent.rules addObject:[BTSmartRule ruleWithField:BTRuleFieldDateAdded
                                                  operator:BTRuleOperatorInTheLast
                                                     value:@"1"]];
        Check([[recent resolveTracks:library.tracks] count] == [library.tracks count],
              @"date added in the last day matches everything just imported");

        BTPlaylist *limited = [BTPlaylist playlistWithName:@"Limited" kind:BTPlaylistKindSmart];
        limited.limit = 1;
        Check([[limited resolveTracks:library.tracks] count] == 1, @"limit is honored");

        printf("folder\n");
        BTPlaylist *folderPlaylist = [BTPlaylist playlistWithName:@"Folder" kind:BTPlaylistKindFolder];
        [library addPlaylist:folderPlaylist toFolder:nil];
        [library addPlaylist:manual toFolder:folderPlaylist];
        [library addPlaylist:smart toFolder:folderPlaylist];
        Check([folderPlaylist.children count] == 2, @"folder holds two playlists");
        Check([[folderPlaylist resolveTracks:library.tracks] count] >= 1, @"folder resolves its children");
        Check([manual isDescendantOf:folderPlaylist], @"child knows its parent");

        printf("move rejects a cycle\n");
        [library movePlaylist:folderPlaylist toFolder:manual atIndex:0];
        Check(folderPlaylist.parent == nil, @"a folder cannot move inside its own child");

        printf("save and reload\n");
        [library saveToDisk];
        NSString *path = [library libraryFilePath];
        Check([[NSFileManager defaultManager] fileExistsAtPath:path], @"library file written");

        NSUInteger trackCount = [library.tracks count];
        NSUInteger playlistCount = [library.playlists count];
        [library loadFromDisk];
        Check([library.tracks count] == trackCount, @"tracks survive the round trip");
        Check([library.playlists count] == playlistCount, @"playlists survive the round trip");

        BTPlaylist *reloadedFolder = nil;
        NSUInteger i;
        for (i = 0; i < [library.playlists count]; i++) {
            BTPlaylist *p = [library.playlists objectAtIndex:i];
            if (p.kind == BTPlaylistKindFolder) reloadedFolder = p;
        }
        Check(reloadedFolder != nil && [reloadedFolder.children count] == 2, @"folder contents survive too");

        if (argc >= 3) {
            printf("iTunes import\n");
            NSString *xml = [NSString stringWithUTF8String:argv[2]];
            NSUInteger playlistsBefore = [library.playlists count];
            NSDictionary *result = [library importITunesLibraryAtPath:xml trackLimit:10];

            Check([result objectForKey:@"error"] == nil, @"library file parsed");
            Check([[result objectForKey:@"tracksSkipped"] integerValue] > 0,
                  @"songs already in the library are not duplicated");
            Check([[result objectForKey:@"protectedTracks"] integerValue] == 1,
                  @"the locked purchase is counted");
            Check([[result objectForKey:@"foldersAdded"] integerValue] == 1, @"one folder rebuilt");
            Check([[result objectForKey:@"playlistsAdded"] integerValue] == 3, @"three playlists rebuilt");
            Check([[result objectForKey:@"smartAsStatic"] integerValue] == 1,
                  @"the smart playlist arrived as an ordinary one");

            // The master library and the built-in category list must not appear.
            Check([library.playlists count] == playlistsBefore + 2,
                  @"only the top-level playlist and the folder were added at the root");

            BTPlaylist *imported = nil, *folder = nil;
            for (i = 0; i < [library.playlists count]; i++) {
                BTPlaylist *p = [library.playlists objectAtIndex:i];
                if ([p.name isEqualToString:@"Road Trips"]) folder = p;
                if ([p.name isEqualToString:@"Quiet"]) imported = p;
            }
            Check(folder != nil && folder.kind == BTPlaylistKindFolder, @"the folder came across as a folder");
            Check(folder != nil && [folder.children count] == 2, @"the folder holds its two playlists");
            Check(imported != nil && [[imported resolveTracks:library.tracks] count] == 2,
                  @"playlist membership survived");

            BTTrack *locked = nil;
            for (i = 0; i < [library.tracks count]; i++) {
                BTTrack *t = [library.tracks objectAtIndex:i];
                if (t.isProtected) locked = t;
            }
            Check(locked != nil, @"the locked purchase is in the library");
            Check(locked != nil && locked.rating == 4, @"a rating of 80 became four stars");
            Check(locked != nil && [locked.persistentID length] > 0, @"the iTunes persistent id was kept");
            Check(locked != nil && locked.playCount == 12, @"the play count came across");
            Check(locked != nil && locked.dateAdded != nil, @"the date added came across");
        }

        printf("iPod database round trip\n");
        {
            BTIPodDatabase *db = [BTIPodDatabase emptyDatabase];

            BTIPodTrackRef *one = [[BTIPodTrackRef alloc] init];
            one.trackID = 1;
            one.location = @":iPod_Control:Music:F00:BT010203.mp3";
            one.title = @"First Test Song";
            one.artist = @"Test Artist";
            one.album = @"Test Album";
            one.genre = @"Spoken Word";
            one.fileType = @"MPEG audio file";
            one.sizeInBytes = 123456;
            one.durationMilliseconds = 4000;
            one.trackNumber = 1;
            one.year = 2003;
            one.persistentID = 0x1122334455667788ULL;
            [db.tracks addObject:one];

            BTIPodTrackRef *two = [[BTIPodTrackRef alloc] init];
            two.trackID = 2;
            two.location = @":iPod_Control:Music:F01:BT040506.m4a";
            two.title = @"Second Test Song";
            two.artist = @"Test Artist";
            two.durationMilliseconds = 6000;
            two.trackNumber = 2;
            [db.tracks addObject:two];

            BTIPodPlaylistRef *list = [[BTIPodPlaylistRef alloc] init];
            list.name = @"Moon Hooch";
            [list.trackIDs addObject:@1];
            [list.trackIDs addObject:@2];
            [db.playlists addObject:list];

            NSData *serialized = [db serializedDataWithDeviceName:@"Test iPod"];
            Check([serialized length] > 0, @"database serialized");

            NSString *dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"iTunesDB-roundtrip"];
            [serialized writeToFile:dbPath atomically:YES];

            BTIPodDatabase *reread = [BTIPodDatabase databaseWithContentsOfFile:dbPath];
            Check(reread != nil, @"database parsed back");
            Check([reread.tracks count] == 2, @"both tracks survive");

            BTIPodTrackRef *first = [reread.tracks count] > 0 ? [reread.tracks objectAtIndex:0] : nil;
            Check(first != nil && [first.title isEqualToString:@"First Test Song"], @"title survives");
            Check(first != nil && [first.location isEqualToString:one.location], @"location survives");
            Check(first != nil && [first.artist isEqualToString:@"Test Artist"], @"artist survives");
            Check(first != nil && first.durationMilliseconds == 4000, @"duration survives");
            Check(first != nil && first.trackNumber == 1, @"track number survives");
            Check(first != nil && first.persistentID == 0x1122334455667788ULL, @"persistent id survives");
            Check(first != nil && [[first filesystemPathUnderMount:@"/Volumes/Pod"]
                                   isEqualToString:@"/Volumes/Pod/iPod_Control/Music/F00/BT010203.mp3"],
                  @"location maps back to a path on the device");

            // The master playlist is written first and holds everything.
            Check([reread.playlists count] == 2, @"master playlist plus the one chosen");
            BTIPodPlaylistRef *master = [reread.playlists objectAtIndex:0];
            Check(master.isMaster, @"first playlist is the master list");
            Check([master.trackIDs count] == 2, @"master list holds every track");

            BTIPodPlaylistRef *named = [reread.playlists objectAtIndex:1];
            Check(!named.isMaster, @"the chosen playlist is not marked master");
            Check([named.name isEqualToString:@"Moon Hooch"], @"playlist name survives");
            Check([named.trackIDs count] == 2, @"playlist membership survives");
            Check([[reread playlistNames] containsObject:@"Moon Hooch"],
                  @"playlist names exclude the master list");
        }

        printf("%s\n", gFailures == 0 ? "all checks passed" : "FAILURES PRESENT");
        return gFailures == 0 ? 0 : 1;
    }
}
