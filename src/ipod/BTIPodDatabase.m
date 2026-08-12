#import "BTIPodDatabase.h"

// Chunk header layout, common to every chunk type:
//   0  four letter type
//   4  header length
//   8  total length, or a child count for the list chunks
#define BT_MHOD_TITLE     1
#define BT_MHOD_LOCATION  2
#define BT_MHOD_ALBUM     3
#define BT_MHOD_ARTIST    4
#define BT_MHOD_GENRE     5
#define BT_MHOD_FILETYPE  6

#define BT_MHBD_HEADER 104
#define BT_MHSD_HEADER 96
#define BT_MHLT_HEADER 92
#define BT_MHIT_HEADER 244
#define BT_MHOD_HEADER 24
#define BT_MHLP_HEADER 92
#define BT_MHYP_HEADER 108
#define BT_MHIP_HEADER 76

#pragma mark - Reading helpers

static uint32_t BTReadU32(NSData *data, NSUInteger offset) {
    if (offset + 4 > [data length]) return 0;
    uint32_t value = 0;
    [data getBytes:&value range:NSMakeRange(offset, 4)];
    return CFSwapInt32LittleToHost(value);
}

static uint64_t BTReadU64(NSData *data, NSUInteger offset) {
    if (offset + 8 > [data length]) return 0;
    uint64_t value = 0;
    [data getBytes:&value range:NSMakeRange(offset, 8)];
    return CFSwapInt64LittleToHost(value);
}

static NSString *BTReadTag(NSData *data, NSUInteger offset) {
    if (offset + 4 > [data length]) return nil;
    char tag[5] = {0};
    [data getBytes:tag range:NSMakeRange(offset, 4)];
    return [NSString stringWithCString:tag encoding:NSASCIIStringEncoding];
}

#pragma mark - Writing helpers

static void BTAppendU32(NSMutableData *data, uint32_t value) {
    uint32_t swapped = CFSwapInt32HostToLittle(value);
    [data appendBytes:&swapped length:4];
}

static void BTAppendU64(NSMutableData *data, uint64_t value) {
    uint64_t swapped = CFSwapInt64HostToLittle(value);
    [data appendBytes:&swapped length:8];
}

static void BTAppendTag(NSMutableData *data, const char *tag) {
    [data appendBytes:tag length:4];
}

static void BTPad(NSMutableData *data, NSUInteger toLength) {
    while ([data length] < toLength) {
        char zero = 0;
        [data appendBytes:&zero length:1];
    }
}

static void BTPatchU32(NSMutableData *data, NSUInteger offset, uint32_t value) {
    uint32_t swapped = CFSwapInt32HostToLittle(value);
    [data replaceBytesInRange:NSMakeRange(offset, 4) withBytes:&swapped];
}

// A string object. Every string in the database is one of these.
static NSData *BTStringObject(uint32_t type, NSString *string) {
    NSData *utf16 = [string dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    NSMutableData *data = [NSMutableData data];
    BTAppendTag(data, "mhod");
    BTAppendU32(data, BT_MHOD_HEADER);
    BTAppendU32(data, (uint32_t)(BT_MHOD_HEADER + 16 + [utf16 length]));
    BTAppendU32(data, type);
    BTAppendU32(data, 0);
    BTAppendU32(data, 0);
    BTAppendU32(data, 1);                      // position
    BTAppendU32(data, (uint32_t)[utf16 length]);
    BTAppendU32(data, 0);
    BTAppendU32(data, 0);
    [data appendData:utf16];
    return data;
}

#pragma mark - Model

@implementation BTIPodTrackRef

- (NSString *)filesystemPathUnderMount:(NSString *)mountPath {
    if ([self.location length] == 0) return nil;
    NSString *relative = self.location;
    if ([relative hasPrefix:@":"]) relative = [relative substringFromIndex:1];
    relative = [relative stringByReplacingOccurrencesOfString:@":" withString:@"/"];
    return [mountPath stringByAppendingPathComponent:relative];
}

@end

@implementation BTIPodPlaylistRef

- (id)init {
    self = [super init];
    if (self) _trackIDs = [NSMutableArray array];
    return self;
}

@end

#pragma mark - Database

@interface BTIPodDatabase ()
@property (nonatomic, strong) NSMutableArray *tracks;
@property (nonatomic, strong) NSMutableArray *playlists;
@end

@implementation BTIPodDatabase

+ (instancetype)emptyDatabase {
    BTIPodDatabase *db = [[BTIPodDatabase alloc] init];
    db.tracks = [NSMutableArray array];
    db.playlists = [NSMutableArray array];
    return db;
}

#pragma mark Reading

// Walks the string objects hanging off a track or playlist and hands each one
// to the block. Returns the offset just past the last object read.
+ (NSUInteger)readStringObjects:(NSUInteger)count
                         inData:(NSData *)data
                       atOffset:(NSUInteger)offset
                          block:(void (^)(uint32_t type, NSString *value))block {
    NSUInteger i;
    for (i = 0; i < count; i++) {
        if (![[self class] isTag:@"mhod" inData:data atOffset:offset]) break;

        uint32_t headerLength = BTReadU32(data, offset + 4);
        uint32_t totalLength = BTReadU32(data, offset + 8);
        uint32_t type = BTReadU32(data, offset + 12);
        if (totalLength == 0 || offset + totalLength > [data length]) break;

        if (type <= BT_MHOD_FILETYPE) {
            uint32_t byteCount = BTReadU32(data, offset + headerLength + 4);
            NSUInteger stringStart = offset + headerLength + 16;
            if (byteCount > 0 && stringStart + byteCount <= [data length]) {
                NSData *raw = [data subdataWithRange:NSMakeRange(stringStart, byteCount)];
                NSString *value = [[NSString alloc] initWithData:raw
                                                        encoding:NSUTF16LittleEndianStringEncoding];
                if (value && block) block(type, value);
            }
        }
        offset += totalLength;
    }
    return offset;
}

+ (BOOL)isTag:(NSString *)tag inData:(NSData *)data atOffset:(NSUInteger)offset {
    NSString *found = BTReadTag(data, offset);
    return found != nil && [found isEqualToString:tag];
}

+ (instancetype)databaseWithContentsOfFile:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if ([data length] < BT_MHBD_HEADER) return nil;
    if (![self isTag:@"mhbd" inData:data atOffset:0]) return nil;

    BTIPodDatabase *db = [self emptyDatabase];

    uint32_t rootHeader = BTReadU32(data, 4);
    NSUInteger offset = rootHeader;

    while (offset + 16 <= [data length]) {
        if (![self isTag:@"mhsd" inData:data atOffset:offset]) break;

        uint32_t headerLength = BTReadU32(data, offset + 4);
        uint32_t totalLength = BTReadU32(data, offset + 8);
        uint32_t datasetType = BTReadU32(data, offset + 12);
        if (totalLength == 0 || offset + totalLength > [data length]) break;

        NSUInteger inner = offset + headerLength;
        if (datasetType == 1) {
            [db readTracksFromData:data atOffset:inner];
        } else if (datasetType == 2 || datasetType == 3) {
            // Type 3 is the newer playlist set and wins when both are present.
            if (datasetType == 3 || [db.playlists count] == 0) {
                [db.playlists removeAllObjects];
                [db readPlaylistsFromData:data atOffset:inner];
            }
        }
        offset += totalLength;
    }

    return db;
}

- (void)readTracksFromData:(NSData *)data atOffset:(NSUInteger)offset {
    if (![BTIPodDatabase isTag:@"mhlt" inData:data atOffset:offset]) return;

    uint32_t headerLength = BTReadU32(data, offset + 4);
    uint32_t count = BTReadU32(data, offset + 8);
    NSUInteger cursor = offset + headerLength;

    uint32_t i;
    for (i = 0; i < count; i++) {
        if (![BTIPodDatabase isTag:@"mhit" inData:data atOffset:cursor]) break;

        uint32_t itemHeader = BTReadU32(data, cursor + 4);
        uint32_t itemTotal = BTReadU32(data, cursor + 8);
        uint32_t stringCount = BTReadU32(data, cursor + 12);
        if (itemTotal == 0 || cursor + itemTotal > [data length]) break;

        BTIPodTrackRef *track = [[BTIPodTrackRef alloc] init];
        track.trackID = BTReadU32(data, cursor + 16);
        track.sizeInBytes = BTReadU32(data, cursor + 36);
        track.durationMilliseconds = BTReadU32(data, cursor + 40);
        track.trackNumber = BTReadU32(data, cursor + 44);
        track.year = BTReadU32(data, cursor + 52);
        track.bitRate = BTReadU32(data, cursor + 56);
        track.persistentID = BTReadU64(data, cursor + 128);

        [BTIPodDatabase readStringObjects:stringCount
                                   inData:data
                                 atOffset:cursor + itemHeader
                                    block:^(uint32_t type, NSString *value) {
            switch (type) {
                case BT_MHOD_TITLE:    track.title = value; break;
                case BT_MHOD_LOCATION: track.location = value; break;
                case BT_MHOD_ALBUM:    track.album = value; break;
                case BT_MHOD_ARTIST:   track.artist = value; break;
                case BT_MHOD_GENRE:    track.genre = value; break;
                case BT_MHOD_FILETYPE: track.fileType = value; break;
                default: break;
            }
        }];

        [self.tracks addObject:track];
        cursor += itemTotal;
    }
}

- (void)readPlaylistsFromData:(NSData *)data atOffset:(NSUInteger)offset {
    if (![BTIPodDatabase isTag:@"mhlp" inData:data atOffset:offset]) return;

    uint32_t headerLength = BTReadU32(data, offset + 4);
    uint32_t count = BTReadU32(data, offset + 8);
    NSUInteger cursor = offset + headerLength;

    uint32_t i;
    for (i = 0; i < count; i++) {
        if (![BTIPodDatabase isTag:@"mhyp" inData:data atOffset:cursor]) break;

        uint32_t listHeader = BTReadU32(data, cursor + 4);
        uint32_t listTotal = BTReadU32(data, cursor + 8);
        uint32_t stringCount = BTReadU32(data, cursor + 12);
        uint32_t itemCount = BTReadU32(data, cursor + 16);
        if (listTotal == 0 || cursor + listTotal > [data length]) break;

        BTIPodPlaylistRef *playlist = [[BTIPodPlaylistRef alloc] init];
        playlist.isMaster = (BTReadU32(data, cursor + 20) & 0xFF) != 0;

        NSUInteger afterStrings = [BTIPodDatabase readStringObjects:stringCount
                                                             inData:data
                                                           atOffset:cursor + listHeader
                                                              block:^(uint32_t type, NSString *value) {
            if (type == BT_MHOD_TITLE) playlist.name = value;
        }];

        NSUInteger itemCursor = afterStrings;
        uint32_t j;
        for (j = 0; j < itemCount; j++) {
            if (![BTIPodDatabase isTag:@"mhip" inData:data atOffset:itemCursor]) break;
            uint32_t itemTotal = BTReadU32(data, itemCursor + 8);
            if (itemTotal == 0 || itemCursor + itemTotal > [data length]) break;
            [playlist.trackIDs addObject:@(BTReadU32(data, itemCursor + 24))];
            itemCursor += itemTotal;
        }

        [self.playlists addObject:playlist];
        cursor += listTotal;
    }
}

#pragma mark Lookup

- (NSSet *)playlistNames {
    NSMutableSet *names = [NSMutableSet set];
    NSUInteger i;
    for (i = 0; i < [self.playlists count]; i++) {
        BTIPodPlaylistRef *playlist = [self.playlists objectAtIndex:i];
        if (!playlist.isMaster && [playlist.name length] > 0) [names addObject:playlist.name];
    }
    return names;
}

- (BTIPodTrackRef *)trackWithID:(uint32_t)trackID {
    NSUInteger i;
    for (i = 0; i < [self.tracks count]; i++) {
        BTIPodTrackRef *track = [self.tracks objectAtIndex:i];
        if (track.trackID == trackID) return track;
    }
    return nil;
}

- (uint32_t)nextFreeTrackID {
    uint32_t highest = 0;
    NSUInteger i;
    for (i = 0; i < [self.tracks count]; i++) {
        BTIPodTrackRef *track = [self.tracks objectAtIndex:i];
        if (track.trackID > highest) highest = track.trackID;
    }
    return highest + 1;
}

#pragma mark Writing

- (NSData *)trackChunkFor:(BTIPodTrackRef *)track {
    NSMutableData *strings = [NSMutableData data];
    uint32_t stringCount = 0;

    NSArray *pairs = @[@[@(BT_MHOD_TITLE), (track.title ? track.title : @"")],
                       @[@(BT_MHOD_LOCATION), (track.location ? track.location : @"")],
                       @[@(BT_MHOD_ALBUM), (track.album ? track.album : @"")],
                       @[@(BT_MHOD_ARTIST), (track.artist ? track.artist : @"")],
                       @[@(BT_MHOD_GENRE), (track.genre ? track.genre : @"")],
                       @[@(BT_MHOD_FILETYPE), (track.fileType ? track.fileType : @"")]];
    NSUInteger i;
    for (i = 0; i < [pairs count]; i++) {
        NSArray *pair = [pairs objectAtIndex:i];
        NSString *value = [pair objectAtIndex:1];
        if ([value length] == 0) continue;
        [strings appendData:BTStringObject((uint32_t)[[pair objectAtIndex:0] unsignedIntValue], value)];
        stringCount++;
    }

    NSMutableData *item = [NSMutableData data];
    BTAppendTag(item, "mhit");
    BTAppendU32(item, BT_MHIT_HEADER);
    BTAppendU32(item, (uint32_t)(BT_MHIT_HEADER + [strings length]));
    BTAppendU32(item, stringCount);
    BTAppendU32(item, track.trackID);          // 16
    BTAppendU32(item, 1);                      // 20 visible
    BTAppendU32(item, 0);                      // 24 file type, left unset
    BTAppendU32(item, 0);                      // 28 flags
    BTAppendU32(item, 0);                      // 32 date modified
    BTAppendU32(item, track.sizeInBytes);      // 36
    BTAppendU32(item, track.durationMilliseconds);  // 40
    BTAppendU32(item, track.trackNumber);      // 44
    BTAppendU32(item, 0);                      // 48 total tracks
    BTAppendU32(item, track.year);             // 52
    BTAppendU32(item, track.bitRate);          // 56
    BTAppendU32(item, 44100 << 16);            // 60 sample rate
    BTPad(item, 128);
    BTAppendU64(item, track.persistentID);     // 128
    BTPad(item, BT_MHIT_HEADER);
    [item appendData:strings];
    return item;
}

- (NSData *)playlistChunkFor:(BTIPodPlaylistRef *)playlist timestamp:(uint32_t)timestamp {
    NSData *name = BTStringObject(BT_MHOD_TITLE, playlist.name ? playlist.name : @"");

    NSMutableData *items = [NSMutableData data];
    NSUInteger i;
    for (i = 0; i < [playlist.trackIDs count]; i++) {
        NSMutableData *item = [NSMutableData data];
        BTAppendTag(item, "mhip");
        BTAppendU32(item, BT_MHIP_HEADER);
        BTAppendU32(item, BT_MHIP_HEADER);
        BTAppendU32(item, 0);                  // 12 string count
        BTAppendU32(item, 0);                  // 16 podcast grouping
        BTAppendU32(item, (uint32_t)(i + 1));  // 20 group id
        BTAppendU32(item, (uint32_t)[[playlist.trackIDs objectAtIndex:i] unsignedIntValue]);  // 24
        BTAppendU32(item, timestamp);          // 28
        BTPad(item, BT_MHIP_HEADER);
        [items appendData:item];
    }

    NSMutableData *list = [NSMutableData data];
    BTAppendTag(list, "mhyp");
    BTAppendU32(list, BT_MHYP_HEADER);
    BTAppendU32(list, (uint32_t)(BT_MHYP_HEADER + [name length] + [items length]));
    BTAppendU32(list, 1);                                      // 12 one string, the name
    BTAppendU32(list, (uint32_t)[playlist.trackIDs count]);    // 16
    BTAppendU32(list, playlist.isMaster ? 1 : 0);              // 20
    BTAppendU32(list, timestamp);                              // 24
    BTAppendU64(list, playlist.isMaster ? 0x0102030405060708ULL
                                        : (0x1000000000000000ULL + (uint64_t)[playlist.name hash]));
    BTPad(list, BT_MHYP_HEADER);
    [list appendData:name];
    [list appendData:items];
    return list;
}

- (NSData *)serializedDataWithDeviceName:(NSString *)deviceName {
    // Mac time: seconds since 1904.
    uint32_t timestamp = (uint32_t)([[NSDate date] timeIntervalSince1970] + 2082844800.0);

    // Track dataset.
    NSMutableData *trackItems = [NSMutableData data];
    NSUInteger i;
    for (i = 0; i < [self.tracks count]; i++) {
        [trackItems appendData:[self trackChunkFor:[self.tracks objectAtIndex:i]]];
    }

    NSMutableData *trackList = [NSMutableData data];
    BTAppendTag(trackList, "mhlt");
    BTAppendU32(trackList, BT_MHLT_HEADER);
    BTAppendU32(trackList, (uint32_t)[self.tracks count]);
    BTPad(trackList, BT_MHLT_HEADER);
    [trackList appendData:trackItems];

    NSMutableData *trackSet = [NSMutableData data];
    BTAppendTag(trackSet, "mhsd");
    BTAppendU32(trackSet, BT_MHSD_HEADER);
    BTAppendU32(trackSet, (uint32_t)(BT_MHSD_HEADER + [trackList length]));
    BTAppendU32(trackSet, 1);
    BTPad(trackSet, BT_MHSD_HEADER);
    [trackSet appendData:trackList];

    // Playlist dataset. The master list holds every track and must come first.
    BTIPodPlaylistRef *master = [[BTIPodPlaylistRef alloc] init];
    master.isMaster = YES;
    master.name = [deviceName length] > 0 ? deviceName : @"BTunes";
    for (i = 0; i < [self.tracks count]; i++) {
        BTIPodTrackRef *track = [self.tracks objectAtIndex:i];
        [master.trackIDs addObject:@(track.trackID)];
    }

    NSMutableArray *ordered = [NSMutableArray arrayWithObject:master];
    for (i = 0; i < [self.playlists count]; i++) {
        BTIPodPlaylistRef *playlist = [self.playlists objectAtIndex:i];
        if (!playlist.isMaster) [ordered addObject:playlist];
    }

    NSMutableData *playlistItems = [NSMutableData data];
    for (i = 0; i < [ordered count]; i++) {
        [playlistItems appendData:[self playlistChunkFor:[ordered objectAtIndex:i] timestamp:timestamp]];
    }

    NSMutableData *playlistList = [NSMutableData data];
    BTAppendTag(playlistList, "mhlp");
    BTAppendU32(playlistList, BT_MHLP_HEADER);
    BTAppendU32(playlistList, (uint32_t)[ordered count]);
    BTPad(playlistList, BT_MHLP_HEADER);
    [playlistList appendData:playlistItems];

    NSMutableData *playlistSet = [NSMutableData data];
    BTAppendTag(playlistSet, "mhsd");
    BTAppendU32(playlistSet, BT_MHSD_HEADER);
    BTAppendU32(playlistSet, (uint32_t)(BT_MHSD_HEADER + [playlistList length]));
    BTAppendU32(playlistSet, 2);
    BTPad(playlistSet, BT_MHSD_HEADER);
    [playlistSet appendData:playlistList];

    // Root.
    NSMutableData *root = [NSMutableData data];
    BTAppendTag(root, "mhbd");
    BTAppendU32(root, BT_MHBD_HEADER);
    BTAppendU32(root, 0);                  // patched below
    BTAppendU32(root, 1);                  // unknown, always one
    BTAppendU32(root, 0x13);               // version, the sixth generation of the format
    BTAppendU32(root, 2);                  // two datasets follow
    BTAppendU64(root, 0x0102030405060708ULL);   // library id
    BTPad(root, BT_MHBD_HEADER);
    [root appendData:trackSet];
    [root appendData:playlistSet];
    BTPatchU32(root, 8, (uint32_t)[root length]);

    return root;
}

@end
