#import <Foundation/Foundation.h>

// Reading a value back out of the saved library.
//
// Everything here asks what a value actually is before using it, and answers
// with nothing when the answer is the wrong kind. The library file is the
// irreplaceable part of BTunes: twenty-five years of ratings, play counts and
// hand-built playlists that the audio cannot be re-derived from. A file that has
// been hand-edited, half-written, or written by a later version should give a
// song with a missing name rather than a crash on the next click.
//
// The name says where the value came from, because that is the whole reason to
// be careful with it. Nothing inside the application is read this way.

NSString *BTSavedString(NSDictionary *saved, NSString *key);
NSArray *BTSavedArray(NSDictionary *saved, NSString *key);
NSInteger BTSavedInteger(NSDictionary *saved, NSString *key);
double BTSavedDouble(NSDictionary *saved, NSString *key);
BOOL BTSavedBool(NSDictionary *saved, NSString *key);

// Seconds since 1970, as the library writes a date. Nothing for a date that was
// never set, which is written as zero rather than left out.
NSDate *BTSavedDate(NSDictionary *saved, NSString *key);
