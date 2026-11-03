# BTunes

BTunes is a music player for the Mac that looks and works like iTunes 4, with a Winamp-style mini mode.

BTunes is not affiliated with or endorsed by Apple, or by whoever owns Winamp these days.  iTunes is a trademark of Apple Inc. and Winamp is a trademark of its owner.  None of their code or artwork is in here.

**BTunes never writes to your audio files or to your iTunes library.**  It reads them, and keeps its own database somewhere else.

## What this is and why it exists

My iTunes library goes back about 25 years.  Ratings, play counts, date added, and a lot of playlists I built by hand.  The ratings are the part I can't replace.

The Mac that plays music in my house is old enough that El Capitan is the last OS it will run.  I wanted iTunes 4 back on it: the plain gray window, the browser columns, search in the corner.  I also wanted the Winamp mini player.

So I wrote my own.

I wanted it to read the existing iTunes library and keep every rating and play count.  I wanted it to look like iTunes 4.  And it had to run on El Capitan.  The last one decided most of the engineering (see Requirements).

## What it does

 - looks like iTunes 4: gray window, search top right, transport top left, readout in between, sources down the left
 - genre / artist / album browser columns across the top of the library
 - smart playlists, built from rules
 - playlist folders (which iTunes 4 didn't have)
 - imports from an iTunes library: songs, ratings, play counts, date added, and playlists
 - mini mode: a small dark panel with a spectrum analyzer that floats over everything, including full screen apps
 - a ten band equalizer
 - plays audio CDs, and rips them to AAC or Apple Lossless
 - burns a playlist to an audio CD, with CD-Text
 - syncs playlists to an iPod

### Sources and playlists

The left pane holds the whole library, Recently Added, your playlists, and folders of playlists.  Recently Added is in the order iTunes recorded the songs being added, newest first, and doesn't sort.

Playlists are grouped by kind: smart playlists first, then folders, then the ones you built by hand.  Within a kind they're alphabetical.  Dragging a playlist only changes which folder it's in.  The same grouping applies inside a folder.

Playing starts from the source selected on the left and stays there.  A playlist plays its own songs and stops at the end.  The library and smart playlists sort by track number within album.  A playlist that is an album plays in album order, and any other playlist plays in the order you built it.

### Mini mode

Shift-Command-M, the round button at the top right, or a double click on the mini panel switches between the two.  The mini panel floats above other windows and over full screen spaces.  Clicking its logo brings the full window back.

### CDs

Put an audio CD in the drive and it appears under the library.  Its songs play from the disc.  The button between the search field and the mini player button rips it, as AAC or Apple Lossless, into a BTunes folder in ~/Music laid out the way iTunes lays one out.

Burn Playlist to Disc (Command-B) makes an audio CD of the selected playlist.  The dialog shows how much of the disc the playlist uses, and the Burn button stays dead until the playlist fits the blank actually in the drive.  You pick the drive, the gap between songs, and whether to verify.  If a playlist can't be burned, it tells you why before it starts.  The playlist name and each song's title and artist go on as CD-Text if the drive supports it.

### iPod

An attached iPod shows up under the library with an eject mark next to it.  Select it and you get the playlists with a checkbox each.  The ones already on the iPod are checked.  Syncing copies the missing songs over and rewrites the iPod's database.  Songs that got onto the iPod some other way are left alone.

## Requirements

The target is macOS 10.11 El Capitan, so the app is Objective-C against the APIs that system has.  The supported audio formats are the ones its Core Audio decodes: mp3, AAC, Apple Lossless, AIFF, WAV, and CAF.  FLAC and Ogg Vorbis aren't supported.  I'd have to bundle a decoder, and I haven't.

There's no Xcode project and there are no nib files.  The whole interface is built in code, and the build is one clang invocation.  Xcode 8 and a current toolchain disagree about nearly everything else, and Swift 3 is a dead end.  Objective-C and one shell script work on both.

## Building

```
./build.sh              # release build into build/BTunes.app
./build.sh --debug      # unoptimized, with symbols
./build.sh --run        # build, then launch
```

The architecture follows the machine doing the build.  Set `ARCH=x86_64` to force an Intel build.

```
./tools/check-1011.sh   # flags anything newer than the target system
./tools/make-logo.sh    # redraws the artwork in resources/logo
```

Run `check-1011.sh` before handing a build to the Xcode 8 machine.  Enum constants compile away, so those are fine.  Anything else newer than 10.11 (classes, methods, named constants) builds fine on a modern Mac and then crashes on the old one.

## Deploying

I use three machines for this.  One edits and commits.  `BUILD` compiles.  It's the only one with an Xcode old enough to make a binary the target will load.  `TARGET` is the old Mac that plays music, and I only ever run the app there.  (I don't run it on the modern Mac, even to check a change.  Launching fine there says nothing about 10.11.)

```
./tools/deploy.sh                 # copy source to BUILD, compile, install on TARGET, start it
./tools/deploy.sh --no-run        # install it but leave it stopped
./tools/deploy.sh --no-sync       # rebuild what is already on BUILD
./tools/deploy.sh --stop          # stop whatever is running on TARGET
./tools/deploy.sh --applications  # also install into /Applications, and start that copy
```

`--applications` needs passwordless sudo on the target.  If sudo asks for a password, the script skips that step and prints the command for you to run by hand.

Host names live in `env.local.sh`, which isn't tracked.  Copy `env.example.sh` and fill in the two machines:

```
cp env.example.sh env.local.sh
```

The app goes through the editing machine on its way from `BUILD` to `TARGET`, so those two don't need credentials for each other.  Installing replaces only the bundle; the `BTunes Library` folder beside it (ratings, play counts) is left alone.  Any copy already running on `TARGET` is stopped first.  Two copies share one database, and the second one to save overwrites the first.

## Settings

Preferences (Command-comma) has four locations, plus a switch for purple mode (the main window draws in purple instead of blue).

- **Music** is the folder the audio sits in, and the root every track's path is stored against.  A song is stored as its path below this folder.  Point the setting at the same music on another machine and the same library opens there.  A file outside the folder keeps its full path and still works.  Existing libraries convert themselves the first time they load.
- **Library** is where BTunes keeps its own database: ratings, play counts, playlists.  Changing it doesn't move any songs.
- **iTunes** is the library file a sync reads.  I point mine at a copy while I'm testing.
- **Detune** is an optional second music folder, with a `detune-mapping.json` that joins its audio to iTunes entries by persistent id.  Songs from it are recorded by their place below that folder, same as ordinary music is below the music folder.  If you don't have one, leave it empty.

The database is `btunes_library.json`.  With no setting it lives in a `BTunes Library` folder beside the app if there is one, otherwise in `~/Library/Application Support/BTunes`.  `BTUNES_LIBRARY_DIR` overrides both.

**If you install the app in more than one place, set the Library location explicitly.**  It's a per-user setting, not a per-copy one, and every copy opens the database it names.  Without it, each copy uses the folder beside it, and you get two sets of play counts and no warning.

Volume, which folders are open, the selected source, and the highlighted track all carry over between runs.

At startup BTunes checks that every song is still where it was.  Anything that moved is looked up in the iTunes library by persistent id and pointed at its new location (this covers reorganizing a media folder, or a tag edit that renamed the file).  Anything really gone is reported, in the dialog if there are fewer than ten, and in full in `missing-files.log` next to the database.  BTunes doesn't delete anything over this; a file that's missing might just be on a volume that isn't mounted.

## Usage:

- Add to Library (Command-O) adds files or folders.
- iTunes Sync, in the File menu and on the button at the bottom right, compares the iTunes library against this one and shows what's new.  Check the songs and playlists you want and only those come across, with their ratings, play counts, and date added.  A smart playlist arrives as a plain playlist holding the songs it resolved to.  iTunes stores the actual rules in an undocumented binary blob.  Anything you left unchecked starts unchecked next time.
- New Playlist is Command-N.  Add Option for a smart playlist, Shift for a folder.  Double click a playlist to rename it.
- Space plays or pauses.  Left and right skip tracks, up and down change volume, M mutes.  On a folder in the source list, left and right close and open it.
- Command-S toggles shuffle, Command-R cycles repeat, Command-F jumps to search.
- Drag songs onto a playlist to add them.  Drag playlists into a folder to group them.
- Delete removes songs from a playlist, or from the library when the library is selected.
- Hover over a row in the song list and a play mark appears at the left end, where the speaker icon sits for the song that's playing.  Click anywhere in that column to start the song.

## AI disclosure

A lot of the code in here was written with AI.  The spec, the design, and every decision about what it does and how it looks are mine.

## License

GPL v3 or later.  Full text in `LICENSE`.
