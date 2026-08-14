#import <Foundation/Foundation.h>

// What an audio CD is, in the terms the rest of the code needs it in.
//
// These are the 1980 standard and they have never moved: 44100 samples a second,
// two channels, sixteen bits each, and seventy-five sectors to the second. Three
// files worked them out separately and spelled them three ways — one as a rate
// and a channel count, one as the bytes a second comes to, and one as a bare
// 44100 times 4 — which is three chances to write down a number that no longer
// describes the same disc.
#define BT_CD_SAMPLE_RATE       44100.0
#define BT_CD_CHANNELS          2
#define BT_CD_BYTES_PER_SAMPLE  2

// A second of stereo, as it sits on the disc and in an AIFF read off it: 176400
// bytes. What a track's length is worked out from, since there is nothing else
// in the file worth counting.
#define BT_CD_BYTES_PER_SECOND \
    (BT_CD_SAMPLE_RATE * (double)BT_CD_CHANNELS * (double)BT_CD_BYTES_PER_SAMPLE)

// A disc is addressed in sectors rather than in seconds, and a burn has to fit
// in a whole number of them.
#define BT_CD_SECTORS_PER_SECOND 75

// Every offset in a table of contents is counted from two seconds before the
// first track, and nothing in the table includes that.
#define BT_CD_PREGAP_SECTORS (2 * BT_CD_SECTORS_PER_SECOND)
