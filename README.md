# BTunes

A music player for macOS built to look and work like iTunes 4, with a mini mode
shaped like classic Winamp.

## What it does

Sources sit on the left: the whole library, playlists, and folders of playlists.
Three browser columns across the top narrow by genre, then artist, then album,
and appear for the library only. The track list sorts by any column. Search is
in the upper right, transport and volume in the upper left, and the readout
between them. New playlist, shuffle and repeat sit at the bottom left.

Smart playlists build themselves from rules. Playlist folders group playlists,
which iTunes 4 could not do.

Playing starts from whatever the left pane has selected and stays inside it, so
a playlist plays its own songs and stops at the end of them. Sorting follows
what a source is: the library and smart playlists by track number within album,
a playlist that is an album in the album's order, and any other playlist in the
order it was built, because that order was chosen.

Mini mode is a compact dark panel with an analyzer, floating above other windows
and over full screen spaces. Clicking its logo returns to the full window.

An attached iPod appears under the library with an eject mark beside its name.
Selecting it opens a pane listing the playlists with a checkbox each, folders
reflecting what is inside them, and the ones already on the device checked, so
what you are looking at is the difference. Syncing copies only what is missing
and rewrites the device's database, keeping songs it did not put there.

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

```
./tools/check-1011.sh   # flags anything newer than the target system
./tools/make-logo.sh    # redraws the artwork in resources/logo
```

Enum constants compile away and are safe; classes, methods, and named constants
are not. Run the first before handing a build to the Xcode 8 machine.

## Deploying

Three machines have three jobs. One edits and commits. `BUILD` compiles, because
it is the only one with an Xcode old enough to produce a binary the target will
load. `TARGET` plays music, and is the only place the app is ever run: a clean
launch on a modern system says nothing about the one it was built for.

```
./tools/deploy.sh                 # copy source to BUILD, compile, install on TARGET, start it
./tools/deploy.sh --no-run        # install it but leave it stopped
./tools/deploy.sh --no-sync       # rebuild what is already on BUILD
./tools/deploy.sh --stop          # stop whatever is running on TARGET
./tools/deploy.sh --applications  # also install into /Applications, and start that copy
```

`--applications` needs sudo without a password on the target. If sudo asks for
one the copy is skipped and the command to run by hand is printed, rather than
the script hanging on a prompt no one can answer.

Host names live in `env.local.sh`, which is not tracked. Copy `env.example.sh`
to it and fill in the two machines:

```
cp env.example.sh env.local.sh
```

The app travels through this machine rather than straight from `BUILD` to
`TARGET`, so those two need no credentials for each other. Installing replaces
only the bundle. The `BTunes Library` folder beside it holds the ratings and
play counts and is never touched. Any copy already running on `TARGET` is
stopped first, because two of them share one database and would overwrite
each other's play counts.

## Settings

Preferences, at Command-comma, holds two locations, kept apart because they move
independently:

- **Music** is the folder the audio sits in, and the root every track's path is
  stored against. A song is recorded as its place below this folder rather than
  in full, so pointing the setting at the same music on another machine opens
  the same library there. A file outside the folder keeps its full path and
  still works. Existing libraries convert themselves the first time they load.
- **Library** is where BTunes keeps its own database: ratings, play counts, and
  playlists. Songs are not moved when it changes.

The database is `btunes_library.json`. Without a setting it sits in a `BTunes Library`
folder beside the application if there is one, and otherwise in
`~/Library/Application Support/BTunes`. `BTUNES_LIBRARY_DIR` overrides both.

Set the Library location explicitly if the app is installed in more than one
place. It is a per-user setting rather than a per-copy one, so once chosen,
every copy opens the same database. Left unchosen, each copy falls back to
whatever sits beside it, which means two of them collecting separate play
counts against separate libraries and no sign that anything is wrong.

Volume, the open state of each folder, the selected source and the highlighted
track carry over between runs.

## Using it

Audio files are read and never modified, and nothing on disk is ever deleted.
BTunes never copies them either: a song is played where it already lives, so
the music stays where it is and BTunes owns only the database.

- Add to Library, Command-O, adds files or folders.
- Import iTunes Library reads an iTunes XML file, never writes it, and rebuilds
  its playlists and folders. Ratings, play counts, and date-added come across.
  A smart playlist arrives as an ordinary playlist holding the songs it resolved
  to, because iTunes stores the rules themselves in an undocumented form.
- New Playlist is Command-N, new smart playlist adds Option, new folder adds
  Shift. Double-click a playlist to rename it.
- Space plays or pauses. Left and right skip tracks, up and down change volume,
  M mutes. On a folder in the source list, left and right close and open it.
- Command-S toggles shuffle, Command-R cycles repeat, Command-F jumps to search.
- Shift-Command-M switches to mini mode, as does the round button at the top
  right and a double click on the mini panel.
- Drag songs onto a playlist to add them. Drag playlists into a folder to group
  them.
- Delete removes songs from a playlist, or from the library when the library is
  selected.
