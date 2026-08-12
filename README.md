# BTunes

A music player for macOS built to look and work like iTunes 4, with a mini mode
shaped like classic Winamp.

## What it does

Sources sit on the left: the whole library, playlists, and folders of playlists.
Three browser columns across the top narrow by genre, then artist, then album.
The track list sorts by any column. Search is in the upper right, transport and
volume in the upper left, and the readout between them. Shuffle and repeat are
at the bottom right.

Smart playlists build themselves from rules. Playlist folders group playlists,
which iTunes 4 could not do.

Mini mode is a compact dark panel with the analyzer bars. Leaving it returns to
the full window.

## Requirements

The target system is macOS 10.11 El Capitan, so the app is written in
Objective-C against APIs that system has. Supported audio formats are the ones
its Core Audio decodes: mp3, AAC, Apple Lossless, AIFF, WAV, and CAF. FLAC and
Ogg Vorbis are deliberately out of scope.

There is no Xcode project and there are no interface files. The interface is
built in code, and the build is a single clang invocation, which is the one
thing an Xcode 8 machine and a current toolchain both understand.

## Building

```
./build.sh              # release build into build/BTunes.app
./build.sh --debug      # unoptimized, with symbols
./build.sh --run        # build, then launch
```

The architecture follows the machine doing the build. Set `ARCH=x86_64` to force
an Intel build.

## Checks

```
./tools/check-1011.sh          # flags anything newer than the target system
```

Enum constants compile away and are safe; classes, methods, and named constants
are not. Run this before handing a build to the Xcode 8 machine.

The library and iPod database checks run from a harness that is kept outside
this repository, along with the tools that seed a test library: they are not
needed to build the application, and the track lists they read describe one
particular collection.

## Using it

The library file lives in `~/Library/Application Support/BTunes/library.json`.
Audio files are read and never modified.

- Add to Library, Command-O, adds files or folders.
- Import iTunes Library reads an iTunes XML file, never writes it, and rebuilds
  its playlists and folders. Ratings, play counts, and date-added come across.
  A smart playlist arrives as an ordinary playlist holding the songs it resolved
  to, because iTunes stores the rules themselves in an undocumented form.
- New Playlist is Command-N, new smart playlist adds Option, new folder adds
  Shift.
- Space plays or pauses. Command-S toggles shuffle, Command-R cycles repeat.
- Shift-Command-M switches to mini mode, and so does double-clicking its panel.
- Drag songs onto a playlist to add them. Drag playlists into a folder to group
  them.
- Delete removes songs from a playlist, or from the library when the library is
  selected. Files on disk are never deleted.
