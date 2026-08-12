#import "BTSmartPlaylistController.h"
#import "BTPlaylist.h"
#import "BTStyle.h"

#define BT_SHEET_WIDTH 540.0
#define BT_ROW_HEIGHT  28.0

@implementation BTSmartPlaylistController {
    BTPlaylist *_playlist;
    NSMutableArray *_workingRules;     // BTSmartRule copies being edited
    NSTextField *_nameField;
    NSPopUpButton *_matchPopUp;
    NSButton *_limitCheck;
    NSTextField *_limitField;
    NSView *_rulesContainer;
    void (^_completion)(BOOL accepted);
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

- (NSTextField *)labelWithText:(NSString *)text frame:(NSRect)frame {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setStringValue:text];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setFont:[BTStyle uiFont]];
    return label;
}

- (void)buildInterface {
    NSView *content = [[self window] contentView];

    _nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(70, 0, BT_SHEET_WIDTH - 90, 22)];
    [_nameField setFont:[BTStyle uiFont]];
    [_nameField setStringValue:(_playlist.name ? _playlist.name : @"Smart Playlist")];
    [content addSubview:[self labelWithText:@"Name:" frame:NSMakeRect(20, 0, 50, 18)]];
    [content addSubview:_nameField];

    _matchPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(58, 0, 60, 22)];
    [_matchPopUp addItemsWithTitles:@[@"all", @"any"]];
    [_matchPopUp selectItemAtIndex:(_playlist.matchAll ? 0 : 1)];
    [[_matchPopUp cell] setControlSize:NSSmallControlSize];
    [_matchPopUp setFont:[BTStyle uiFont]];
    [content addSubview:[self labelWithText:@"Match" frame:NSMakeRect(20, 0, 40, 18)]];
    [content addSubview:_matchPopUp];
    [content addSubview:[self labelWithText:@"of the following rules:" frame:NSMakeRect(124, 0, 200, 18)]];

    _rulesContainer = [[NSView alloc] initWithFrame:NSMakeRect(20, 0, BT_SHEET_WIDTH - 40, BT_ROW_HEIGHT)];
    [content addSubview:_rulesContainer];

    _limitCheck = [[NSButton alloc] initWithFrame:NSMakeRect(20, 0, 90, 20)];
    [_limitCheck setButtonType:NSSwitchButton];
    [_limitCheck setTitle:@"Limit to"];
    [_limitCheck setFont:[BTStyle uiFont]];
    [_limitCheck setState:(_playlist.limit > 0 ? NSOnState : NSOffState)];
    [content addSubview:_limitCheck];

    _limitField = [[NSTextField alloc] initWithFrame:NSMakeRect(110, 0, 60, 20)];
    [_limitField setFont:[BTStyle uiFont]];
    [_limitField setStringValue:(_playlist.limit > 0 ? [NSString stringWithFormat:@"%ld", (long)_playlist.limit] : @"25")];
    [content addSubview:_limitField];
    [content addSubview:[self labelWithText:@"songs" frame:NSMakeRect(176, 0, 60, 18)]];

    NSButton *cancel = [[NSButton alloc] initWithFrame:NSMakeRect(BT_SHEET_WIDTH - 190, 12, 80, 28)];
    [cancel setTitle:@"Cancel"];
    [cancel setBezelStyle:NSRoundedBezelStyle];
    [cancel setFont:[BTStyle uiFont]];
    [cancel setTarget:self];
    [cancel setAction:@selector(cancel:)];
    [cancel setKeyEquivalent:@"\033"];
    [content addSubview:cancel];

    NSButton *ok = [[NSButton alloc] initWithFrame:NSMakeRect(BT_SHEET_WIDTH - 104, 12, 84, 28)];
    [ok setTitle:@"OK"];
    [ok setBezelStyle:NSRoundedBezelStyle];
    [ok setFont:[BTStyle uiFont]];
    [ok setTarget:self];
    [ok setAction:@selector(accept:)];
    [ok setKeyEquivalent:@"\r"];
    [content addSubview:ok];

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

        NSPopUpButton *fieldPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, y, 130, 22)];
        [fieldPopUp addItemsWithTitles:[BTSmartRule fieldNames]];
        [fieldPopUp selectItemAtIndex:rule.field];
        [[fieldPopUp cell] setControlSize:NSSmallControlSize];
        [fieldPopUp setFont:[BTStyle uiFont]];
        [fieldPopUp setTag:(NSInteger)i];
        [fieldPopUp setTarget:self];
        [fieldPopUp setAction:@selector(fieldChanged:)];
        [_rulesContainer addSubview:fieldPopUp];

        NSPopUpButton *opPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(136, y, 140, 22)];
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

        NSTextField *valueField = [[NSTextField alloc] initWithFrame:NSMakeRect(282, y, 160, 22)];
        [valueField setFont:[BTStyle uiFont]];
        [valueField setStringValue:(rule.value ? rule.value : @"")];
        [valueField setTag:(NSInteger)i];
        [valueField setTarget:self];
        [valueField setAction:@selector(valueChanged:)];
        [_rulesContainer addSubview:valueField];

        NSButton *minus = [[NSButton alloc] initWithFrame:NSMakeRect(452, y, 24, 22)];
        [minus setTitle:@"-"];
        [minus setBezelStyle:NSRoundRectBezelStyle];
        [minus setFont:[BTStyle uiFont]];
        [minus setTag:(NSInteger)i];
        [minus setTarget:self];
        [minus setAction:@selector(removeRule:)];
        [minus setEnabled:([_workingRules count] > 1)];
        [_rulesContainer addSubview:minus];

        NSButton *plus = [[NSButton alloc] initWithFrame:NSMakeRect(478, y, 24, 22)];
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

- (void)layoutWindow {
    CGFloat rulesHeight = NSHeight([_rulesContainer frame]);
    CGFloat height = 52 + 30 + 30 + rulesHeight + 30 + 46;
    NSWindow *window = [self window];
    NSRect frame = [window frame];
    NSRect contentRect = NSMakeRect(NSMinX(frame), NSMinY(frame), BT_SHEET_WIDTH, height);
    [window setFrame:[window frameRectForContentRect:contentRect] display:YES];

    CGFloat y = height - 34;
    NSView *content = [window contentView];
    NSArray *subviews = [content subviews];
    NSUInteger i;

    // Name row.
    for (i = 0; i < [subviews count]; i++) {
        NSView *v = [subviews objectAtIndex:i];
        if (v == _nameField) [v setFrameOrigin:NSMakePoint(70, y)];
    }
    [[self viewWithLabel:@"Name:"] setFrameOrigin:NSMakePoint(20, y + 4)];

    y -= 32;
    [_matchPopUp setFrameOrigin:NSMakePoint(58, y)];
    [[self viewWithLabel:@"Match"] setFrameOrigin:NSMakePoint(20, y + 4)];
    [[self viewWithLabel:@"of the following rules:"] setFrameOrigin:NSMakePoint(124, y + 4)];

    y -= rulesHeight + 6;
    [_rulesContainer setFrameOrigin:NSMakePoint(20, y)];

    y -= 30;
    [_limitCheck setFrameOrigin:NSMakePoint(20, y)];
    [_limitField setFrameOrigin:NSMakePoint(110, y)];
    [[self viewWithLabel:@"songs"] setFrameOrigin:NSMakePoint(176, y + 3)];
}

- (NSView *)viewWithLabel:(NSString *)text {
    NSArray *subviews = [[[self window] contentView] subviews];
    NSUInteger i;
    for (i = 0; i < [subviews count]; i++) {
        NSView *v = [subviews objectAtIndex:i];
        if ([v isKindOfClass:[NSTextField class]] && ![(NSTextField *)v isEditable]) {
            if ([[(NSTextField *)v stringValue] isEqualToString:text]) return v;
        }
    }
    return nil;
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

- (void)beginSheetForWindow:(NSWindow *)parent completion:(void (^)(BOOL accepted))completion {
    _completion = [completion copy];
    [parent beginSheet:[self window] completionHandler:nil];
}

- (void)finishAccepted:(BOOL)accepted {
    NSWindow *sheet = [self window];
    [[sheet sheetParent] endSheet:sheet];
    [sheet orderOut:nil];
    if (_completion) _completion(accepted);
    _completion = nil;
}

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
