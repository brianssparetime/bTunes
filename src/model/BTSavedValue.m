#import "BTSavedValue.h"

NSString *BTSavedString(NSDictionary *saved, NSString *key) {
    id value = [saved objectForKey:key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

NSArray *BTSavedArray(NSDictionary *saved, NSString *key) {
    id value = [saved objectForKey:key];
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

// A number written as a string still reads as a number, which is what
// integerValue is for. Anything that cannot answer at all counts as nothing.
NSInteger BTSavedInteger(NSDictionary *saved, NSString *key) {
    id value = [saved objectForKey:key];
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

double BTSavedDouble(NSDictionary *saved, NSString *key) {
    id value = [saved objectForKey:key];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.0;
}

BOOL BTSavedBool(NSDictionary *saved, NSString *key) {
    id value = [saved objectForKey:key];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

NSDate *BTSavedDate(NSDictionary *saved, NSString *key) {
    double seconds = BTSavedDouble(saved, key);
    return seconds > 0 ? [NSDate dateWithTimeIntervalSince1970:seconds] : nil;
}
