#import <Foundation/Foundation.h>

@class BTTrack;

typedef NS_ENUM(NSInteger, BTPlaylistKind) {
    BTPlaylistKindStatic = 0,
    BTPlaylistKindSmart  = 1,
    BTPlaylistKindFolder = 2
};

typedef NS_ENUM(NSInteger, BTRuleField) {
    BTRuleFieldTitle = 0,
    BTRuleFieldArtist,
    BTRuleFieldAlbum,
    BTRuleFieldGenre,
    BTRuleFieldComposer,
    BTRuleFieldKind,
    BTRuleFieldYear,
    BTRuleFieldRating,
    BTRuleFieldPlayCount,
    BTRuleFieldDuration,
    BTRuleFieldDateAdded
};

typedef NS_ENUM(NSInteger, BTRuleOperator) {
    BTRuleOperatorContains = 0,
    BTRuleOperatorDoesNotContain,
    BTRuleOperatorIs,
    BTRuleOperatorIsNot,
    BTRuleOperatorBeginsWith,
    BTRuleOperatorEndsWith,
    BTRuleOperatorGreaterThan,
    BTRuleOperatorLessThan,
    BTRuleOperatorInTheLast          // value is a day count
};

// One condition inside a smart playlist.
@interface BTSmartRule : NSObject
@property (nonatomic, assign) BTRuleField field;
@property (nonatomic, assign) BTRuleOperator op;
@property (nonatomic, copy) NSString *value;

+ (instancetype)ruleWithField:(BTRuleField)field operator:(BTRuleOperator)op value:(NSString *)value;
+ (instancetype)ruleWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;
- (BOOL)evaluateWithTrack:(BTTrack *)track;

+ (NSArray *)fieldNames;                          // display order matches BTRuleField
+ (NSArray *)operatorNamesForField:(BTRuleField)field;
+ (NSArray *)operatorsForField:(BTRuleField)field; // NSNumber-wrapped BTRuleOperator
+ (BOOL)fieldIsNumeric:(BTRuleField)field;
@end

// A source-list entry. Folders hold other playlists, which is the one place
// BTunes departs from iTunes 4.
@interface BTPlaylist : NSObject

@property (nonatomic, copy) NSString *playlistID;
@property (nonatomic, copy) NSString *name;
// The iTunes persistent id this playlist was built from, or nil when it was
// made in BTunes. A later sync uses it to tell "the same playlist, changed in
// iTunes" from "a BTunes playlist that happens to share a name".
@property (nonatomic, copy) NSString *sourcePersistentID;
@property (nonatomic, assign) BTPlaylistKind kind;
@property (nonatomic, strong) NSMutableArray *trackIDs;   // static playlists
@property (nonatomic, strong) NSMutableArray *children;   // folders
@property (nonatomic, strong) NSMutableArray *rules;      // smart playlists
@property (nonatomic, assign) BOOL matchAll;              // smart: all vs any
@property (nonatomic, assign) NSInteger limit;            // smart: 0 means no limit
@property (nonatomic, weak) BTPlaylist *parent;

// How this playlist was last sorted, so it opens the way it was left rather
// than snapping back to a default every time. Kept with the playlist rather
// than in this machine's settings, so the arrangement follows the library.
// Nil means it has never been sorted by hand.
@property (nonatomic, copy) NSString *sortColumn;
@property (nonatomic, assign) BOOL sortAscending;

+ (instancetype)playlistWithName:(NSString *)name kind:(BTPlaylistKind)kind;
+ (instancetype)playlistWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

// Tracks this playlist resolves to, given the whole library.
- (NSArray *)resolveTracks:(NSArray *)allTracks;

// Moves songs so they come to sit where the song at the given index sits now,
// keeping whatever order they already had relative to each other. The index
// names a place in the playlist as it stands before the move, and a count of
// the songs means the end. Songs not in this playlist are ignored.
- (void)moveTrackIDs:(NSArray *)trackIDs toIndex:(NSInteger)index;

// Renumbers the playlist into album order: albums by name, and within an album
// by disc and then track number. Songs whose files have gone missing keep their
// places at the end rather than being dropped.
- (void)arrangeByAlbumUsingTracks:(NSArray *)allTracks;

- (BOOL)isDescendantOf:(BTPlaylist *)other;

@end
