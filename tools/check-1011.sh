#!/bin/bash
# Flag calls that compile here but would fail on the build machine or crash on
# the target.
#
# This machine builds against a recent SDK; the build machine runs Xcode 8 with
# the 10.12 SDK, and the target runs 10.11. Enum constants are compiled away and
# are safe, so this only looks for classes, methods, and named constants that
# arrived after 10.11.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATUS=0

# name:reason
BANNED=(
    "NSVisualEffectView:10.10 but styled for later systems, avoid"
    "NSGridView:10.12"
    "NSCollectionViewCompositionalLayout:10.15"
    "NSTableViewStyle:10.16"
    "NSControlStateValue:10.13 rename, use NSOnState and NSOffState"
    "NSCompositingOperation.*SourceOver:ok"
    "@available:Xcode 9"
    "NSAppearanceNameDarkAqua:10.14"
    "NSColor.controlAccentColor:10.14"
    "systemSymbolNamed:11.0"
    "NSTextField labelWithString:10.12"
    "NSButton buttonWithTitle:10.12"
    "NSImageSymbolConfiguration:11.0"
    "AVAudioEngine.*FLAC:not decodable on 10.11"
    "kAudioFormatFLAC:10.13"
    "NSPasteboardTypeFileURL:10.13"
    "NSWindowStyleMask:10.12 rename, use NSTitledWindowMask and friends"
    "NSEventModifierFlag:10.12 rename, use NSCommandKeyMask and friends"
    "NSAlertStyleWarning:10.12 rename, use NSWarningAlertStyle"
    "NSControlSizeSmall:10.12 rename, use NSSmallControlSize"
)

echo "==> Checking sources for symbols newer than 10.11"

for entry in "${BANNED[@]}"; do
    pattern="${entry%%:*}"
    reason="${entry#*:}"
    [ "$reason" = "ok" ] && continue

    if grep -rn -- "$pattern" "$SCRIPT_DIR/src" > /dev/null 2>&1; then
        echo "FAIL $pattern ($reason)"
        grep -rn -- "$pattern" "$SCRIPT_DIR/src" | sed 's/^/     /'
        STATUS=1
    fi
done

if [ "$STATUS" -eq 0 ]; then
    echo "clean"
fi
exit "$STATUS"
