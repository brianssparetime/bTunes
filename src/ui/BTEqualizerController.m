#import "BTEqualizerController.h"
#import "BTEqualizer.h"
#import "BTStyle.h"
#import "BTControls.h"
#import "BTMainWindowViews.h"

// The panel, laid out the way iTunes laid it out: the preamp on its own at the
// left, the scale it and everything else is read against beside it, then the ten
// bands. The scale sits between the preamp and the bands rather than outside
// them both, which is where the original put it.
#define BT_EQ_PREAMP_WIDTH   46.0
#define BT_EQ_SCALE_WIDTH    42.0
#define BT_EQ_COLUMN         30.0
#define BT_EQ_TRACK_HEIGHT  132.0
#define BT_EQ_GROOVE_WIDTH    5.0
#define BT_EQ_THUMB_WIDTH    15.0
#define BT_EQ_THUMB_HEIGHT   10.0
#define BT_EQ_PAD             6.0
#define BT_EQ_LABEL_GAP       4.0

// The window around it.
#define BT_EQ_MARGIN         16.0
#define BT_EQ_TOP_ROW_GAP    12.0

// The preamp is worked as a slider like any other, so one piece of arithmetic
// places all eleven of them and one mouse handler moves all eleven. It is
// numbered past the last band, where it cannot be mistaken for one.
#define BT_EQ_PREAMP_SLIDER  BT_EQ_BANDS

#pragma mark - The sliders

@interface BTEqualizerSlidersView : NSView
// Which slider the mouse has hold of, or -1 for none. Only the pressed one is
// drawn pressed, so a row of eleven does not all light up together.
@property (nonatomic, assign) NSInteger draggingSlider;
@end

@implementation BTEqualizerSlidersView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) _draggingSlider = -1;
    return self;
}

+ (CGFloat)panelWidth {
    return BT_EQ_PREAMP_WIDTH + BT_EQ_SCALE_WIDTH + (BT_EQ_COLUMN * BT_EQ_BANDS);
}

// Two rows of words, one under the sliders and one over them, with the channel
// between.
+ (CGFloat)panelHeight {
    return BT_EQ_PAD + [BTStyle smallLineHeight] + BT_EQ_LABEL_GAP + BT_EQ_TRACK_HEIGHT
         + BT_EQ_LABEL_GAP + [BTStyle smallLineHeight] + BT_EQ_PAD;
}

- (CGFloat)trackBottom {
    return BT_EQ_PAD + [BTStyle smallLineHeight] + BT_EQ_LABEL_GAP;
}

// Where a thumb's middle sits at the two ends of its travel. The scale is
// written against these rather than against the ends of the channel, since a
// slider pushed all the way up has its middle half a thumb short of the top and
// a scale drawn to the channel would be wrong by that much at both ends.
- (CGFloat)lowestThumbCentre { return [self trackBottom] + BT_EQ_THUMB_HEIGHT / 2.0; }
- (CGFloat)highestThumbCentre {
    return [self trackBottom] + BT_EQ_TRACK_HEIGHT - BT_EQ_THUMB_HEIGHT / 2.0;
}

- (CGFloat)centreXForSlider:(NSUInteger)slider {
    if (slider == BT_EQ_PREAMP_SLIDER) return BT_EQ_PREAMP_WIDTH / 2.0;
    return BT_EQ_PREAMP_WIDTH + BT_EQ_SCALE_WIDTH
         + (BT_EQ_COLUMN * (CGFloat)slider) + BT_EQ_COLUMN / 2.0;
}

- (float)gainForSlider:(NSUInteger)slider {
    BTEqualizer *eq = [BTEqualizer sharedEqualizer];
    if (slider == BT_EQ_PREAMP_SLIDER) return [eq preamp];
    return [eq gainForBand:slider];
}

- (void)setGain:(float)gain forSlider:(NSUInteger)slider {
    BTEqualizer *eq = [BTEqualizer sharedEqualizer];
    if (slider == BT_EQ_PREAMP_SLIDER) {
        [eq setPreamp:gain];
        return;
    }
    [eq setGain:gain forBand:slider];
}

- (NSRect)thumbRectForSlider:(NSUInteger)slider {
    float largest = [BTEqualizer largestGain];
    CGFloat travel = [self highestThumbCentre] - [self lowestThumbCentre];
    CGFloat centre = [self lowestThumbCentre]
                   + travel * (CGFloat)(([self gainForSlider:slider] + largest) / (largest * 2.0));

    return NSMakeRect([self centreXForSlider:slider] - BT_EQ_THUMB_WIDTH / 2.0,
                      centre - BT_EQ_THUMB_HEIGHT / 2.0,
                      BT_EQ_THUMB_WIDTH, BT_EQ_THUMB_HEIGHT);
}

#pragma mark - Drawing

- (void)drawSmallText:(NSString *)text
              inRect:(NSRect)rect
           alignment:(NSTextAlignment)alignment {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    [style setAlignment:alignment];
    NSDictionary *attrs = @{NSFontAttributeName: [BTStyle smallFont],
                            NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.25 alpha:1.0],
                            NSParagraphStyleAttributeName: style};
    [text drawInRect:rect withAttributes:attrs];
}

// One line of words, placed by its middle. A line is laid along the top of the
// rect it is given, so a rect exactly one line tall is the only way to say where
// the words go rather than roughly where.
- (NSRect)lineBandCentredAt:(CGFloat)middle from:(CGFloat)left width:(CGFloat)width {
    CGFloat line = [BTStyle smallLineHeight];
    return NSMakeRect(left, middle - line / 2.0, width, line);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self bounds];
    [BTStyle drawSunkenBezelInRect:bounds radius:4.0 fill:[BTStyle listBackground]];

    CGFloat bandsLeft = BT_EQ_PREAMP_WIDTH + BT_EQ_SCALE_WIDTH;
    CGFloat middleY = ([self lowestThumbCentre] + [self highestThumbCentre]) / 2.0;

    // The line the whole panel is read against: where a slider sits when it is
    // doing nothing. Drawn under the bands only, since running it through the
    // scale would strike out the words.
    [[NSColor colorWithCalibratedWhite:0.78 alpha:1.0] set];
    NSRectFill(NSMakeRect(bandsLeft, floor(middleY) , NSWidth(bounds) - bandsLeft - 2.0, 1.0));

    // The scale, against the ends of the travel rather than the ends of the
    // channel.
    float largest = [BTEqualizer largestGain];
    NSArray *marks = @[@[@([self highestThumbCentre]), [NSString stringWithFormat:@"+%d dB", (int)largest]],
                       @[@(middleY), @"0 dB"],
                       @[@([self lowestThumbCentre]), [NSString stringWithFormat:@"-%d dB", (int)largest]]];
    NSUInteger m;
    for (m = 0; m < [marks count]; m++) {
        NSArray *mark = [marks objectAtIndex:m];
        [self drawSmallText:[mark objectAtIndex:1]
                     inRect:[self lineBandCentredAt:[[mark objectAtIndex:0] doubleValue]
                                               from:BT_EQ_PREAMP_WIDTH
                                              width:BT_EQ_SCALE_WIDTH - 6.0]
                  alignment:NSCenterTextAlignment];
    }

    // The preamp is named above its channel, where iTunes named it, since there
    // is no frequency to write under it.
    CGFloat topRow = [self trackBottom] + BT_EQ_TRACK_HEIGHT + BT_EQ_LABEL_GAP;
    [self drawSmallText:@"Preamp"
                 inRect:NSMakeRect(0, topRow, BT_EQ_PREAMP_WIDTH, [BTStyle smallLineHeight])
              alignment:NSCenterTextAlignment];

    NSUInteger slider;
    for (slider = 0; slider <= BT_EQ_PREAMP_SLIDER; slider++) {
        CGFloat centreX = [self centreXForSlider:slider];
        [BTStyle drawVerticalGrooveInRect:NSMakeRect(centreX - BT_EQ_GROOVE_WIDTH / 2.0,
                                                     [self trackBottom],
                                                     BT_EQ_GROOVE_WIDTH,
                                                     BT_EQ_TRACK_HEIGHT)];

        if (slider < BT_EQ_BANDS) {
            [self drawSmallText:[BTEqualizer labelForBand:slider]
                         inRect:NSMakeRect(centreX - BT_EQ_COLUMN / 2.0, BT_EQ_PAD,
                                           BT_EQ_COLUMN, [BTStyle smallLineHeight])
                      alignment:NSCenterTextAlignment];
        }

        [BTStyle drawSliderThumbInRect:[self thumbRectForSlider:slider]
                               pressed:(self.draggingSlider == (NSInteger)slider)];
    }
}

#pragma mark - The mouse

// Which channel a point belongs to, by the column it falls in rather than by how
// near the thumb is. Clicking anywhere down a slider's column moves that slider,
// which is what a row of narrow channels needs: a hit test against a thumb
// fifteen points wide leaves most of the panel dead.
- (NSInteger)sliderAtPoint:(NSPoint)point {
    if (point.x < BT_EQ_PREAMP_WIDTH) return BT_EQ_PREAMP_SLIDER;

    CGFloat bandsLeft = BT_EQ_PREAMP_WIDTH + BT_EQ_SCALE_WIDTH;
    if (point.x < bandsLeft) return -1;

    NSInteger band = (NSInteger)((point.x - bandsLeft) / BT_EQ_COLUMN);
    if (band < 0 || band >= BT_EQ_BANDS) return -1;
    return band;
}

- (float)gainForY:(CGFloat)y {
    CGFloat travel = [self highestThumbCentre] - [self lowestThumbCentre];
    if (travel <= 0) return 0.0f;

    float largest = [BTEqualizer largestGain];
    float gain = (float)(((y - [self lowestThumbCentre]) / travel) * (largest * 2.0) - largest);
    if (gain > largest) gain = largest;
    if (gain < -largest) gain = -largest;
    return gain;
}

- (void)moveSliderTo:(NSPoint)point {
    if (self.draggingSlider < 0) return;
    [self setGain:[self gainForY:point.y] forSlider:(NSUInteger)self.draggingSlider];
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    self.draggingSlider = [self sliderAtPoint:point];
    [self moveSliderTo:point];
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    [self moveSliderTo:[self convertPoint:[event locationInWindow] fromView:nil]];
}

- (void)mouseUp:(NSEvent *)event {
    self.draggingSlider = -1;
    [self setNeedsDisplay:YES];
}

@end

#pragma mark - The window

@implementation BTEqualizerController {
    NSButton *_onBox;
    NSPopUpButton *_presetMenu;
    BTEqualizerSlidersView *_sliders;
}

+ (instancetype)sharedController {
    static BTEqualizerController *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [[BTEqualizerController alloc] initEqualizer]; });
    return shared;
}

- (instancetype)initEqualizer {
    CGFloat panelWidth = [BTEqualizerSlidersView panelWidth];
    CGFloat panelHeight = [BTEqualizerSlidersView panelHeight];
    CGFloat topRow = [BTStyle fieldHeight];

    NSRect frame = NSMakeRect(0, 0,
                              panelWidth + BT_EQ_MARGIN * 2,
                              panelHeight + BT_EQ_TOP_ROW_GAP + topRow + BT_EQ_MARGIN * 2);
    NSWindow *window = [[BTPanelWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:@"Equalizer"];
    [window center];

    self = [super initWithWindow:window];
    if (self == nil) return nil;

    // The brushed panel the main window is drawn on, so the equalizer looks like
    // part of the same application rather than a system dialog that wandered in.
    BTChromeView *content = [[BTChromeView alloc] initWithFrame:frame];
    [window setContentView:content];

    _sliders = [[BTEqualizerSlidersView alloc] initWithFrame:
                NSMakeRect(BT_EQ_MARGIN, BT_EQ_MARGIN, panelWidth, panelHeight)];
    [content addSubview:_sliders];

    CGFloat rowY = BT_EQ_MARGIN + panelHeight + BT_EQ_TOP_ROW_GAP;

    _onBox = [[NSButton alloc] initWithFrame:NSMakeRect(BT_EQ_MARGIN, rowY, 60, topRow)];
    [_onBox setButtonType:NSSwitchButton];
    [_onBox setFont:[BTStyle uiFont]];
    [_onBox setTitle:@"On"];
    [_onBox setTarget:self];
    [_onBox setAction:@selector(onChanged:)];
    [content addSubview:_onBox];

    CGFloat menuWidth = 190.0;
    _presetMenu = [[NSPopUpButton alloc] initWithFrame:
                   NSMakeRect(NSWidth(frame) - BT_EQ_MARGIN - menuWidth, rowY, menuWidth, topRow)
                                             pullsDown:NO];
    [_presetMenu setFont:[BTStyle uiFont]];
    [_presetMenu addItemsWithTitles:[BTEqualizer presetNames]];
    [_presetMenu setTarget:self];
    [_presetMenu setAction:@selector(presetChosen:)];
    [content addSubview:_presetMenu];

    // The sliders can be moved from here and the preset from the menu, and each
    // has to show what the other did. Listening to the equalizer rather than
    // telling each other keeps that to one path.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(equalizerChanged:)
                                                 name:BTEqualizerDidChangeNotification
                                               object:nil];
    [self refresh];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)refresh {
    BTEqualizer *eq = [BTEqualizer sharedEqualizer];
    [_onBox setState:([eq on] ? NSOnState : NSOffState)];
    [_presetMenu selectItemWithTitle:[eq presetName]];
    [_sliders setNeedsDisplay:YES];
}

- (void)equalizerChanged:(NSNotification *)note {
    [self refresh];
}

- (void)onChanged:(id)sender {
    [[BTEqualizer sharedEqualizer] setOn:([_onBox state] == NSOnState)];
}

// Choosing a preset moves the sliders, and choosing one while the equalizer is
// switched off switches it on. Otherwise picking Rock does nothing audible and
// reads as a menu that is broken.
- (void)presetChosen:(id)sender {
    BTEqualizer *eq = [BTEqualizer sharedEqualizer];
    [eq setPresetName:[_presetMenu titleOfSelectedItem]];
    if (![eq on] && [BTEqualizer gainsForPresetNamed:[eq presetName]] != nil) [eq setOn:YES];
}

@end
