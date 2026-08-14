#import "BTSmartPlaylistController.h"
#import "BTPlaylist.h"
#import "BTStyle.h"
#import "BTControls.h"

#define BT_SHEET_WIDTH 540.0

// Every measurement below that follows the type, named so the arithmetic says
// what it is made of. At the size this was drawn for they come to the numbers
// that were written here before: 22, 18, 20, 28, 32, 30, 34.
#define BT_FIELD    ([BTStyle fieldHeight])
#define BT_LABEL    ([BTStyle labelHeight])
#define BT_CHECK    ([BTStyle checkboxHeight])
// A rule row: the controls, and six points of air beneath.
#define BT_ROW_HEIGHT (BT_FIELD + 6.0)
// One row of the sheet to the next.
#define BT_ROW_STEP   (BT_FIELD + 10.0)
#define BT_LIMIT_STEP (BT_CHECK + 10.0)
// The top of the sheet down to the bottom of the first row.
#define BT_FIRST_ROW  (BT_FIELD + 12.0)
// A caption beside a field sits above the field's bottom edge, since the field
// is taller than its words by the bezel drawn round them.
#define BT_CAPTION_RISE 4.0

@implementation BTSmartPlaylistController {
    BTPlaylist *_playlist;
    NSMutableArray *_workingRules;     // BTSmartRule copies being edited
    NSTextField *_nameField;
    NSPopUpButton *_matchPopUp;
    NSButton *_limitCheck;
    NSTextField *_limitField;
    NSView *_rulesContainer;
    // The captions are held rather than looked up. The sheet grows and shrinks
    // with the number of rules, so every one of these is repositioned on each
    // rebuild, and finding them by the words they display breaks the moment two
    // of them read alike.
    NSTextField *_nameLabel;
    NSTextField *_matchLabel;
    NSTextField *_rulesLabel;
    NSTextField *_songsLabel;
}

- (instancetype)initWithPlaylist:(BTPlaylist *)playlist {
    NSRect frame = NSMakeRect(0, 0, BT_SHEET_WIDTH, 240);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSTitledWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:@"Smart Playlist"];

    self = [super initWithWindow:window];
    if (self == nil) return nil;

    _playlist = playlist;
    _workingRules = [NSMutableArray array];
    NSUInteger i;
    for (i = 0; i < [playlist.rules count]; i++) {
        BTSmartRule *source = [playlist.rules objectAtIndex:i];
        [_workingRules addObject:[BTSmartRule ruleWithField:source.field operator:source.op value:source.value]];
    }
    if ([_workingRules count] == 0) {
        [_workingRules addObject:[BTSmartRule ruleWithField:BTRuleFieldArtist
                                                   operator:BTRuleOperatorContains
                                                      value:@""]];
    }

    [self buildInterface];
    return self;
}

// Everything is created without a position. layoutWindow places all of it, so
// each coordinate is written once.
- (void)buildInterface {
    NSView *content = [[self window] contentView];

    _nameLabel = BTLabelWithText(@"Name:", [BTStyle uiFont]);
    _nameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [_nameField setFont:[BTStyle uiFont]];
    [_nameField setStringValue:(_playlist.name ? _playlist.name : @"Smart Playlist")];
    [content addSubview:_nameLabel];
    [content addSubview:_nameField];

    _matchLabel = BTLabelWithText(@"Match", [BTStyle uiFont]);
    _rulesLabel = BTLabelWithText(@"of the following rules:", [BTStyle uiFont]);
    _matchPopUp = [[NSPopUpButton alloc] initWithFrame:NSZeroRect];
    [_matchPopUp addItemsWithTitles:@[@"all", @"any"]];
    [_matchPopUp selectItemAtIndex:(_playlist.matchAll ? 0 : 1)];
    [[_matchPopUp cell] setControlSize:NSSmallControlSize];
    [_matchPopUp setFont:[BTStyle uiFont]];
    [content addSubview:_matchLabel];
    [content addSubview:_matchPopUp];
    [content addSubview:_rulesLabel];

    _rulesContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, BT_SHEET_WIDTH - 40, BT_ROW_HEIGHT)];
    [content addSubview:_rulesContainer];

    _limitCheck = [[NSButton alloc] initWithFrame:NSZeroRect];
    [_limitCheck setButtonType:NSSwitchButton];
    [_limitCheck setTitle:@"Limit to"];
    [_limitCheck setFont:[BTStyle uiFont]];
    [_limitCheck setState:(_playlist.limit > 0 ? NSOnState : NSOffState)];
    [content addSubview:_limitCheck];

    _limitField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [_limitField setFont:[BTStyle uiFont]];
    [_limitField setStringValue:(_playlist.limit > 0 ? [NSString stringWithFormat:@"%ld", (long)_playlist.limit] : @"25")];
    _songsLabel = BTLabelWithText(@"songs", [BTStyle uiFont]);
    [content addSubview:_limitField];
    [content addSubview:_songsLabel];

    [self addButtonsAccepting:@"OK"
                       action:@selector(accept:)
                       cancel:@selector(cancel:)
                      inWidth:BT_SHEET_WIDTH];

    [self rebuildRuleRows];
}

- (void)rebuildRuleRows {
    NSArray *existing = [NSArray arrayWithArray:[_rulesContainer subviews]];
    NSUInteger i;
    for (i = 0; i < [existing count]; i++) {
        [[existing objectAtIndex:i] removeFromSuperview];
    }

    CGFloat containerHeight = BT_ROW_HEIGHT * (CGFloat)[_workingRules count];
    [_rulesContainer setFrameSize:NSMakeSize(BT_SHEET_WIDTH - 40, containerHeight)];

    for (i = 0; i < [_workingRules count]; i++) {
        BTSmartRule *rule = [_workingRules objectAtIndex:i];
        CGFloat y = containerHeight - BT_ROW_HEIGHT * (CGFloat)(i + 1) + 3;

        NSPopUpButton *fieldPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, y, 130, BT_FIELD)];
        [fieldPopUp addItemsWithTitles:[BTSmartRule fieldNames]];
        [fieldPopUp selectItemAtIndex:rule.field];
        [[fieldPopUp cell] setControlSize:NSSmallControlSize];
        [fieldPopUp setFont:[BTStyle uiFont]];
        [fieldPopUp setTag:(NSInteger)i];
        [fieldPopUp setTarget:self];
        [fieldPopUp setAction:@selector(fieldChanged:)];
        [_rulesContainer addSubview:fieldPopUp];

        NSPopUpButton *opPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(136, y, 140, BT_FIELD)];
        [opPopUp addItemsWithTitles:[BTSmartRule operatorNamesForField:rule.field]];
        NSArray *ops = [BTSmartRule operatorsForField:rule.field];
        NSUInteger opIndex = [ops indexOfObject:@(rule.op)];
        [opPopUp selectItemAtIndex:(opIndex == NSNotFound ? 0 : (NSInteger)opIndex)];
        [[opPopUp cell] setControlSize:NSSmallControlSize];
        [opPopUp setFont:[BTStyle uiFont]];
        [opPopUp setTag:(NSInteger)i];
        [opPopUp setTarget:self];
        [opPopUp setAction:@selector(operatorChanged:)];
        [_rulesContainer addSubview:opPopUp];

        NSTextField *valueField = [[NSTextField alloc] initWithFrame:NSMakeRect(282, y, 160, BT_FIELD)];
        [valueField setFont:[BTStyle uiFont]];
        [valueField setStringValue:(rule.value ? rule.value : @"")];
        [valueField setTag:(NSInteger)i];
        [valueField setTarget:self];
        [valueField setAction:@selector(valueChanged:)];
        [_rulesContainer addSubview:valueField];

        NSButton *minus = [[NSButton alloc] initWithFrame:NSMakeRect(452, y, 24, BT_FIELD)];
        [minus setTitle:@"-"];
        [minus setBezelStyle:NSRoundRectBezelStyle];
        [minus setFont:[BTStyle uiFont]];
        [minus setTag:(NSInteger)i];
        [minus setTarget:self];
        [minus setAction:@selector(removeRule:)];
        [minus setEnabled:([_workingRules count] > 1)];
        [_rulesContainer addSubview:minus];

        NSButton *plus = [[NSButton alloc] initWithFrame:NSMakeRect(478, y, 24, BT_FIELD)];
        [plus setTitle:@"+"];
        [plus setBezelStyle:NSRoundRectBezelStyle];
        [plus setFont:[BTStyle uiFont]];
        [plus setTag:(NSInteger)i];
        [plus setTarget:self];
        [plus setAction:@selector(addRule:)];
        [_rulesContainer addSubview:plus];
    }

    [self layoutWindow];
}

// The sheet is a stack of rows placed from the top down, since only the rules
// block changes height. The buttons stay pinned to the bottom.
- (void)layoutWindow {
    CGFloat rulesHeight = NSHeight([_rulesContainer frame]);
    // The name row, the match row, the rules, the limit row, and the strip the
    // buttons sit in. Each row is a control tall, so the sheet grows with the
    // type rather than closing over it.
    CGFloat height = (BT_FIELD + 30.0) + (BT_FIELD + 8.0) + (BT_FIELD + 8.0)
                   + rulesHeight + (BT_CHECK + 10.0) + 46.0;
    NSWindow *window = [self window];
    NSRect frame = [window frame];
    NSRect contentRect = NSMakeRect(NSMinX(frame), NSMinY(frame), BT_SHEET_WIDTH, height);
    [window setFrame:[window frameRectForContentRect:contentRect] display:YES];

    CGFloat y = height - BT_FIRST_ROW;
    [_nameLabel setFrame:NSMakeRect(20, y + BT_CAPTION_RISE, 50, BT_LABEL)];
    [_nameField setFrame:NSMakeRect(70, y, BT_SHEET_WIDTH - 90, BT_FIELD)];

    y -= BT_ROW_STEP;
    [_matchLabel setFrame:NSMakeRect(20, y + BT_CAPTION_RISE, 40, BT_LABEL)];
    [_matchPopUp setFrame:NSMakeRect(58, y, 60, BT_FIELD)];
    [_rulesLabel setFrame:NSMakeRect(124, y + BT_CAPTION_RISE, 200, BT_LABEL)];

    y -= rulesHeight + 6;
    [_rulesContainer setFrameOrigin:NSMakePoint(20, y)];

    y -= BT_LIMIT_STEP;
    [_limitCheck setFrame:NSMakeRect(20, y, 90, BT_CHECK)];
    [_limitField setFrame:NSMakeRect(110, y, 60, BT_CHECK)];
    [_songsLabel setFrame:NSMakeRect(176, y + 3, 60, BT_LABEL)];
}

#pragma mark - Rule edits

- (void)fieldChanged:(NSPopUpButton *)sender {
    BTSmartRule *rule = [_workingRules objectAtIndex:(NSUInteger)[sender tag]];
    rule.field = (BTRuleField)[sender indexOfSelectedItem];
    NSArray *ops = [BTSmartRule operatorsForField:rule.field];
    rule.op = (BTRuleOperator)[[ops objectAtIndex:0] integerValue];
    [self rebuildRuleRows];
}

- (void)operatorChanged:(NSPopUpButton *)sender {
    BTSmartRule *rule = [_workingRules objectAtIndex:(NSUInteger)[sender tag]];
    NSArray *ops = [BTSmartRule operatorsForField:rule.field];
    NSInteger index = [sender indexOfSelectedItem];
    if (index >= 0 && index < (NSInteger)[ops count]) {
        rule.op = (BTRuleOperator)[[ops objectAtIndex:(NSUInteger)index] integerValue];
    }
}

- (void)valueChanged:(NSTextField *)sender {
    BTSmartRule *rule = [_workingRules objectAtIndex:(NSUInteger)[sender tag]];
    rule.value = [sender stringValue];
}

- (void)addRule:(NSButton *)sender {
    [self commitVisibleValues];
    NSUInteger index = (NSUInteger)[sender tag] + 1;
    [_workingRules insertObject:[BTSmartRule ruleWithField:BTRuleFieldArtist
                                                  operator:BTRuleOperatorContains
                                                     value:@""]
                        atIndex:index];
    [self rebuildRuleRows];
}

- (void)removeRule:(NSButton *)sender {
    if ([_workingRules count] <= 1) return;
    [self commitVisibleValues];
    [_workingRules removeObjectAtIndex:(NSUInteger)[sender tag]];
    [self rebuildRuleRows];
}

- (void)commitVisibleValues {
    NSArray *subviews = [_rulesContainer subviews];
    NSUInteger i;
    for (i = 0; i < [subviews count]; i++) {
        NSView *v = [subviews objectAtIndex:i];
        if ([v isKindOfClass:[NSTextField class]]) {
            NSTextField *field = (NSTextField *)v;
            NSUInteger index = (NSUInteger)[field tag];
            if (index < [_workingRules count]) {
                BTSmartRule *rule = [_workingRules objectAtIndex:index];
                rule.value = [field stringValue];
            }
        }
    }
}

#pragma mark - Sheet

- (void)accept:(id)sender {
    [self commitVisibleValues];

    _playlist.name = [[_nameField stringValue] length] > 0 ? [_nameField stringValue] : @"Smart Playlist";
    _playlist.matchAll = ([_matchPopUp indexOfSelectedItem] == 0);
    _playlist.limit = ([_limitCheck state] == NSOnState) ? [[_limitField stringValue] integerValue] : 0;
    [_playlist.rules removeAllObjects];
    [_playlist.rules addObjectsFromArray:_workingRules];

    [self finishAccepted:YES];
}

- (void)cancel:(id)sender {
    [self finishAccepted:NO];
}

@end
