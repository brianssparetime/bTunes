#!/bin/bash
# Build BTunes on BUILD and put it on TARGET.
#
# Usage: ./tools/deploy.sh [--no-run] [--no-sync] [--stop] [--applications]
#                          [--gentle] [--full-speed]
#
#   --no-run        install it but leave it stopped
#   --no-sync       build whatever is already on BUILD, skip the source copy
#   --stop          stop whatever is running on TARGET and do nothing else
#   --gentle        let everything else on BUILD have the machine first
#   --full-speed    build at ordinary priority, whatever env.local.sh says
#   --applications  also put a copy in /Applications on TARGET, and start that
#                   one. Needs sudo without a password there; if sudo asks for
#                   one, this is reported and skipped rather than left hanging.
#
# Two copies are only safe because the database location is a setting rather
# than a guess. With nothing chosen, BTunes takes a BTunes Library folder
# beside the application, so a copy in /Applications would open a different
# library from the one in the home folder and each would collect its own play
# counts. Set the location once, in Preferences, and every copy agrees.
#
# Three machines, three jobs. This one edits and commits; it never runs the app,
# because the system here is not the system BTunes is built for and a clean
# launch here proves nothing. BUILD compiles, because it is the only machine
# with the old Xcode. TARGET plays music and is where the app is actually
# judged.
#
# Host names live in env.local.sh, which is gitignored. See env.example.sh.
#
# The app is copied through this machine rather than straight from BUILD to
# TARGET, so the two of them need no keys for each other.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/env.local.sh"

if [ ! -f "$ENV_FILE" ]; then
    echo "No env.local.sh. Copy env.example.sh to env.local.sh and fill it in." >&2
    exit 2
fi
# shellcheck source=/dev/null
. "$ENV_FILE"

for var in BT_BUILD_HOST BT_BUILD_DIR BT_TARGET_HOST BT_TARGET_DIR; do
    if [ -z "${!var:-}" ]; then
        echo "env.local.sh does not set $var." >&2
        exit 2
    fi
done

RUN_AFTER=1
DO_SYNC=1
STOP_ONLY=0
INSTALL_APPLICATIONS=0
# BUILD is shared. When something long is running there, a compile that takes
# the processor and the disk is felt by it within seconds, so every step of the
# deploy that runs on BUILD can be told to wait its turn instead.
GENTLE=${BT_BUILD_GENTLE:-0}

for arg in "$@"; do
    case "$arg" in
        --no-run)       RUN_AFTER=0 ;;
        --no-sync)      DO_SYNC=0 ;;
        --stop)         STOP_ONLY=1 ;;
        --applications) INSTALL_APPLICATIONS=1 ;;
        --gentle)       GENTLE=1 ;;
        --full-speed)   GENTLE=0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

SSH="ssh -o BatchMode=yes -o ConnectTimeout=10"
TARBALL="/tmp/btunes-build.tgz"

# Stops every copy running on TARGET. Two instances share one database and
# overwrite each other's play counts, so an old one is always stopped before a
# new one starts.
#
# Asked to quit, not killed. The library is written a couple of seconds after a
# change and again when the application is told to stop, and a signal runs
# neither of those: whatever was done in the last moments before a deploy is
# exactly what a signal throws away. A signal is still here, after asking
# politely and waiting, because a deploy that cannot stop the old copy is worse
# than one that stops it rudely. Both fallbacks say so rather than passing for
# an ordinary quit.
stop_target() {
    $SSH "$BT_TARGET_HOST" '
        pgrep -x BTunes >/dev/null 2>&1 || exit 0

        osascript -e "tell application \"BTunes\" to quit" >/dev/null 2>&1 || true

        waited=0
        while pgrep -x BTunes >/dev/null 2>&1 && [ "$waited" -lt 20 ]; do
            sleep 1
            waited=$((waited + 1))
        done
        pgrep -x BTunes >/dev/null 2>&1 || exit 0

        echo "    it did not quit when asked, so signalling it" >&2
        for pid in $(pgrep -x BTunes); do kill "$pid" 2>/dev/null || true; done
        sleep 3
        pgrep -x BTunes >/dev/null 2>&1 || exit 0

        echo "    still running, so forcing it; the library may be a save behind" >&2
        for pid in $(pgrep -x BTunes); do kill -9 "$pid" 2>/dev/null || true; done
    '
}

if [ "$STOP_ONLY" -eq 1 ]; then
    echo "==> Stopping BTunes on TARGET"
    stop_target
    echo "stopped"
    exit 0
fi

echo "==> Checking both machines are up"
$SSH "$BT_BUILD_HOST" 'true'  || { echo "BUILD is not answering." >&2; exit 1; }
$SSH "$BT_TARGET_HOST" 'true' || { echo "TARGET is not answering." >&2; exit 1; }

# nice alone only yields the processor. taskpolicy -b is the part that matters,
# because background priority throttles the disk too, and a compile reading
# every source and writing an object for each is as much a disk job as a
# processor one. Children inherit both, so wrapping the top of each remote step
# covers every clang it starts.
NICE=""
if [ "$GENTLE" -eq 1 ]; then
    if $SSH "$BT_BUILD_HOST" 'test -x /usr/sbin/taskpolicy'; then
        NICE="nice -n 20 /usr/sbin/taskpolicy -b"
    else
        NICE="nice -n 20"
        echo "    no taskpolicy on BUILD, so this yields the processor only" >&2
    fi
    echo "==> Gentle: BUILD's other work comes first, so this will be slow"
fi

if [ "$DO_SYNC" -eq 1 ]; then
    echo "==> Copying source to BUILD"
    # Everything the build needs and nothing that belongs to this machine. The
    # deletes keep a file removed here from lingering there and being compiled.
    rsync -a --delete \
        --rsync-path="${NICE:+$NICE }rsync" \
        --exclude 'build/' \
        --exclude '.git/' \
        --exclude '.claude/' \
        --exclude 'CLAUDE.md' \
        --exclude 'design_docs/' \
        --exclude 'env.local.sh' \
        --exclude '__pycache__/' \
        --exclude '.DS_Store' \
        "$SCRIPT_DIR/" "$BT_BUILD_HOST:$BT_BUILD_DIR/"
fi

echo "==> Building on BUILD"
$SSH "$BT_BUILD_HOST" "cd '$BT_BUILD_DIR' && $NICE ./build.sh"

echo "==> Fetching the app"
$SSH "$BT_BUILD_HOST" "cd '$BT_BUILD_DIR/build' && rm -f '$TARBALL' && $NICE tar czf '$TARBALL' BTunes.app"
rm -f "$TARBALL"
scp -q "$BT_BUILD_HOST:$TARBALL" "$TARBALL"
scp -q "$TARBALL" "$BT_TARGET_HOST:$TARBALL"

echo "==> Stopping the running copy on TARGET"
stop_target

echo "==> Installing on TARGET"
# Only the bundle is replaced. The BTunes Library folder sits beside it and
# holds the ratings and play counts, which are the irreplaceable part.
$SSH "$BT_TARGET_HOST" "
    set -e
    mkdir -p '$BT_TARGET_DIR'
    rm -rf '$BT_TARGET_DIR/BTunes.app'
    tar xzf '$TARBALL' -C '$BT_TARGET_DIR'
    xattr -dr com.apple.quarantine '$BT_TARGET_DIR/BTunes.app' 2>/dev/null || true
"

LAUNCH_PATH="$BT_TARGET_DIR/BTunes.app"

if [ "$INSTALL_APPLICATIONS" -eq 1 ]; then
    echo "==> Installing to /Applications on TARGET"
    # Asked without a password first. A sudo that prompts would sit forever on
    # the far end of an ssh with no terminal attached.
    if $SSH "$BT_TARGET_HOST" 'sudo -n true' 2>/dev/null; then
        $SSH "$BT_TARGET_HOST" "
            set -e
            sudo rm -rf /Applications/BTunes.app
            sudo cp -R \"\$HOME/$BT_TARGET_DIR/BTunes.app\" /Applications/BTunes.app
            sudo xattr -dr com.apple.quarantine /Applications/BTunes.app 2>/dev/null || true
        "
        LAUNCH_PATH="/Applications/BTunes.app"
        echo "    installed"
    else
        echo "    sudo on TARGET wants a password, so /Applications was left alone." >&2
        echo "    Run this on TARGET yourself:" >&2
        echo "        sudo cp -R ~/$BT_TARGET_DIR/BTunes.app /Applications/" >&2
    fi
fi

# A copy in /Applications that this deploy could not reach is worse than no copy
# at all, because it looks current and is not. Say so every time rather than
# leaving it to be discovered by testing the wrong build for an hour.
if $SSH "$BT_TARGET_HOST" "
    [ -d /Applications/BTunes.app ] || exit 1
    here=\$(md5 -q /Applications/BTunes.app/Contents/MacOS/BTunes 2>/dev/null)
    fresh=\$(md5 -q \"\$HOME/$BT_TARGET_DIR/BTunes.app/Contents/MacOS/BTunes\" 2>/dev/null)
    [ \"\$here\" != \"\$fresh\" ]
" 2>/dev/null; then
    echo "==> WARNING: /Applications on TARGET holds a different build" >&2
    echo "    Update it with:" >&2
    echo "        sudo cp -R ~/$BT_TARGET_DIR/BTunes.app /Applications/" >&2
fi

if [ "$RUN_AFTER" -eq 0 ]; then
    echo "==> Installed, left stopped"
    exit 0
fi

echo "==> Starting it on TARGET"
$SSH "$BT_TARGET_HOST" "open '$LAUNCH_PATH'"
sleep 4

if $SSH "$BT_TARGET_HOST" 'pgrep -x BTunes > /dev/null'; then
    echo "==> Running on TARGET"
else
    echo "It did not stay up. Look at the console on TARGET." >&2
    exit 1
fi
