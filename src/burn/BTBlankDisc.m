#import "BTBlankDisc.h"
#import "BTBurnPlan.h"
#import <DiscRecording/DiscRecording.h>

NSString *const BTBlankDiscDidChangeNotification = @"BTBlankDiscDidChange";

@implementation BTBlankDisc

// The last answer given out, so the notification is posted when it changes
// rather than every time a drive mentions anything. A drive says a great deal
// while a disc spins up.
static BOOL sPresent = NO;
static BOOL sWatching = NO;

+ (BOOL)look {
    NSArray *devices = [BTBurnPlan writableDevices];
    NSUInteger i;
    for (i = 0; i < [devices count]; i++) {
        DRDevice *device = [devices objectAtIndex:i];
        if (![device mediaIsPresent] || [device mediaIsTransitioning]) continue;
        if (![device mediaIsBlank]) continue;

        NSString *media = [device mediaType];
        if ([media isEqualToString:DRDeviceMediaTypeCDR] ||
            [media isEqualToString:DRDeviceMediaTypeCDRW]) {
            return YES;
        }
    }
    return NO;
}

+ (BOOL)present {
    // Asked afresh rather than trusted, since the first caller may arrive before
    // the drive has said anything at all.
    if (!sWatching) return [self look];
    return sPresent;
}

+ (void)deviceSaidSomething:(NSNotification *)note {
    BOOL now = [self look];
    if (now == sPresent) return;
    sPresent = now;
    [[NSNotificationCenter defaultCenter] postNotificationName:BTBlankDiscDidChangeNotification
                                                        object:nil];
}

+ (void)startWatching {
    if (sWatching) return;
    sWatching = YES;
    sPresent = [self look];

    // DiscRecording's own centre rather than the workspace's: a blank disc never
    // mounts, so nothing about it arrives as a volume.
    DRNotificationCenter *centre = [DRNotificationCenter currentRunLoopCenter];
    [centre addObserver:self selector:@selector(deviceSaidSomething:)
                   name:DRDeviceStatusChangedNotification object:nil];
    [centre addObserver:self selector:@selector(deviceSaidSomething:)
                   name:DRDeviceAppearedNotification object:nil];
    [centre addObserver:self selector:@selector(deviceSaidSomething:)
                   name:DRDeviceDisappearedNotification object:nil];
}

@end
