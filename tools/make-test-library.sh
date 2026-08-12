#!/bin/bash
# Build a test library: two albums filed under a folder, plus a spread of single
# tracks from unrelated artists.
#
# Usage: ./tools/make-test-library.sh <library dir> [music root]
#
# The music root defaults to this account's iTunes media folder. Nothing under
# it is written to; the files are read and their tags copied.
#
# Run this against a throwaway library directory. It starts by emptying the one
# it is given.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IMPORT="$SCRIPT_DIR/build/bt-import"
LIBRARY="${1:?usage: make-test-library.sh <library dir> [music root]}"
MUSIC="${2:-$HOME/Music/iTunes/iTunes Media/Music}"

if [ ! -x "$IMPORT" ]; then
    echo "bt-import is not built. Run ./build.sh --tools first." >&2
    exit 1
fi
if [ ! -d "$MUSIC" ]; then
    echo "No music at $MUSIC" >&2
    exit 1
fi

# A running BTunes holds the library in memory and writes it back when it quits,
# which silently undoes everything below. Refuse rather than build a library that
# is about to be overwritten.
if pgrep -x BTunes > /dev/null 2>&1; then
    echo "BTunes is running. Quit it first, or it will write its own copy of the" >&2
    echo "library back over this one when it exits." >&2
    exit 1
fi

rm -rf "$LIBRARY"
mkdir -p "$LIBRARY"
export BTUNES_LIBRARY_DIR="$LIBRARY"

echo "==> Albums"
for album in "Moon Hooch/Moon Hooch" \
             "Philip Glass/Koyaanisqatsi (Complete Original Soundtrack)"; do
    if [ -d "$MUSIC/$album" ]; then
        "$IMPORT" "$MUSIC/$album" --playlist "$(basename "$album")" --folder "Albums" | tail -2
    else
        echo "    skipping $album, not present"
    fi
done

echo "==> Singles from a spread of artists"
SINGLES=""
COUNT=0
while IFS= read -r artist; do
    [ "$COUNT" -ge 12 ] && break
    track="$(find "$MUSIC/$artist" -type f \( -name '*.m4a' -o -name '*.mp3' -o -name '*.aif*' \) 2>/dev/null | head -1)"
    [ -z "$track" ] && continue
    SINGLES="$SINGLES
$track"
    COUNT=$((COUNT + 1))
done < <(ls "$MUSIC" | awk 'NR % 97 == 3')

if [ "$COUNT" -gt 0 ]; then
    IFS=$'\n'
    # shellcheck disable=SC2086
    "$IMPORT" $SINGLES --playlist "Odds and Ends" | tail -2
    unset IFS
fi

echo "==> Done: $LIBRARY/library.json"
