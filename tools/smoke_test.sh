#!/bin/bash
# Build and run the headless checks against a throwaway library.
#
# Usage: ./tools/smoke_test.sh [folder of audio files]
#
# With no argument it generates its own test audio under /tmp. BTUNES_LIBRARY_DIR
# sends the library somewhere temporary so a test run never touches a real one.
# Setting HOME would not do this: the Application Support path comes from the
# user record rather than the environment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/btunes-smoke"
AUDIO="${1:-$WORK/audio}"

rm -rf "$WORK"
mkdir -p "$WORK/library" "$WORK/audio"

if [ "$#" -eq 0 ]; then
    echo "==> Generating test audio"
    say -o "$WORK/audio/one.aiff" "This is the first test song for be tunes" > /dev/null 2>&1
    say -o "$WORK/audio/two.aiff" "This is the second test song, a little longer than the first" > /dev/null 2>&1
    afconvert -f m4af -d aac "$WORK/audio/one.aiff" "$WORK/audio/three-aac.m4a" > /dev/null 2>&1
    afconvert -f m4af -d alac "$WORK/audio/two.aiff" "$WORK/audio/four-alac.m4a" > /dev/null 2>&1
    mkdir -p "$WORK/audio/nested"
    cp "$WORK/audio/one.aiff" "$WORK/audio/nested/five.aiff"
fi

# A stand-in iTunes library: a master list and a category list that must be
# ignored, a folder holding two playlists, one of them smart, a top-level
# playlist, and one locked purchase.
ITUNES_XML="$WORK/iTunes Music Library.xml"
cat > "$ITUNES_XML" <<XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Major Version</key><integer>1</integer>
  <key>Tracks</key>
  <dict>
    <key>101</key>
    <dict>
      <key>Track ID</key><integer>101</integer>
      <key>Name</key><string>First Test Song</string>
      <key>Artist</key><string>Test Artist</string>
      <key>Album</key><string>Test Album</string>
      <key>Genre</key><string>Spoken Word</string>
      <key>Kind</key><string>AIFF audio file</string>
      <key>Total Time</key><integer>4000</integer>
      <key>Track Number</key><integer>1</integer>
      <key>Year</key><integer>2003</integer>
      <key>Date Added</key><date>2003-06-01T12:00:00Z</date>
      <key>Play Count</key><integer>7</integer>
      <key>Rating</key><integer>100</integer>
      <key>Persistent ID</key><string>AAAA000000000001</string>
      <key>Location</key><string>file://$WORK/audio/one.aiff</string>
    </dict>
    <key>102</key>
    <dict>
      <key>Track ID</key><integer>102</integer>
      <key>Name</key><string>Second Test Song</string>
      <key>Artist</key><string>Test Artist</string>
      <key>Album</key><string>Test Album</string>
      <key>Kind</key><string>AIFF audio file</string>
      <key>Total Time</key><integer>6000</integer>
      <key>Track Number</key><integer>2</integer>
      <key>Date Added</key><date>2004-01-15T09:30:00Z</date>
      <key>Persistent ID</key><string>AAAA000000000002</string>
      <key>Location</key><string>file://$WORK/audio/two.aiff</string>
    </dict>
    <key>103</key>
    <dict>
      <key>Track ID</key><integer>103</integer>
      <key>Name</key><string>Bought In 2006</string>
      <key>Artist</key><string>Store Artist</string>
      <key>Album</key><string>Store Album</string>
      <key>Kind</key><string>Protected AAC audio file</string>
      <key>Total Time</key><integer>210000</integer>
      <key>Date Added</key><date>2006-08-20T22:15:00Z</date>
      <key>Play Count</key><integer>12</integer>
      <key>Rating</key><integer>80</integer>
      <key>Protected</key><true/>
      <key>Persistent ID</key><string>AAAA000000000003</string>
      <key>Location</key><string>file://$WORK/audio/bought.m4p</string>
    </dict>
  </dict>
  <key>Playlists</key>
  <array>
    <dict>
      <key>Name</key><string>Library</string>
      <key>Master</key><true/>
      <key>Playlist Persistent ID</key><string>BBBB000000000000</string>
      <key>Playlist Items</key>
      <array>
        <dict><key>Track ID</key><integer>101</integer></dict>
        <dict><key>Track ID</key><integer>102</integer></dict>
        <dict><key>Track ID</key><integer>103</integer></dict>
      </array>
    </dict>
    <dict>
      <key>Name</key><string>Music</string>
      <key>Distinguished Kind</key><integer>4</integer>
      <key>Playlist Persistent ID</key><string>BBBB000000000001</string>
    </dict>
    <dict>
      <key>Name</key><string>Road Trips</string>
      <key>Folder</key><true/>
      <key>Playlist Persistent ID</key><string>BBBB000000000002</string>
    </dict>
    <dict>
      <key>Name</key><string>Long Drive</string>
      <key>Playlist Persistent ID</key><string>BBBB000000000003</string>
      <key>Parent Persistent ID</key><string>BBBB000000000002</string>
      <key>Playlist Items</key>
      <array>
        <dict><key>Track ID</key><integer>101</integer></dict>
        <dict><key>Track ID</key><integer>103</integer></dict>
      </array>
    </dict>
    <dict>
      <key>Name</key><string>Smart Favorites</string>
      <key>Playlist Persistent ID</key><string>BBBB000000000004</string>
      <key>Parent Persistent ID</key><string>BBBB000000000002</string>
      <key>Smart Info</key><data>AQEAAAMAAAA=</data>
      <key>Smart Criteria</key><data>U0xzdAABAAE=</data>
      <key>Playlist Items</key>
      <array>
        <dict><key>Track ID</key><integer>101</integer></dict>
      </array>
    </dict>
    <dict>
      <key>Name</key><string>Quiet</string>
      <key>Playlist Persistent ID</key><string>BBBB000000000005</string>
      <key>Playlist Items</key>
      <array>
        <dict><key>Track ID</key><integer>102</integer></dict>
        <dict><key>Track ID</key><integer>103</integer></dict>
      </array>
    </dict>
  </array>
</dict>
</plist>
XMLEOF

echo "==> Building checks"
SOURCES="$SCRIPT_DIR/tools/smoke_test.m $SCRIPT_DIR/src/model/BTTrack.m $SCRIPT_DIR/src/model/BTPlaylist.m $SCRIPT_DIR/src/model/BTLibrary.m $SCRIPT_DIR/src/model/BTITunesImport.m $SCRIPT_DIR/src/ipod/BTIPodDatabase.m"

clang \
    -mmacosx-version-min=10.11 \
    -fobjc-arc \
    -Wall \
    -Wno-deprecated-declarations \
    -I"$SCRIPT_DIR/src/model" -I"$SCRIPT_DIR/src/ipod" \
    -framework Foundation \
    -framework AVFoundation \
    -framework CoreMedia \
    -framework AudioToolbox \
    -o "$WORK/smoke_test" \
    $SOURCES

echo "==> Running against $AUDIO"
BTUNES_LIBRARY_DIR="$WORK/library" "$WORK/smoke_test" "$AUDIO" "$ITUNES_XML"
