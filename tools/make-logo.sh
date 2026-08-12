#!/bin/sh
# Regenerate the BTunes logo artwork and the application icon.
#
# Writes:
#   resources/logo/btunes-1024.png, -512, -256, -128
#   resources/logo/btunes-splash.png   (480x480 startup splash)
#   resources/BTunes.icns              (built with iconutil)
#
# Requires python3 with Pillow, and iconutil (part of macOS).

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
LOGO_DIR="$ROOT/resources/logo"
ICONSET="$ROOT/build/BTunes.iconset"
ICNS="$ROOT/resources/BTunes.icns"

PYTHON=${PYTHON:-python3}

if ! command -v "$PYTHON" >/dev/null 2>&1; then
    echo "error: python3 was not found on PATH" >&2
    exit 1
fi

if ! "$PYTHON" -c "import PIL" >/dev/null 2>&1; then
    echo "error: Pillow is not installed for $PYTHON" >&2
    echo "       install it with: $PYTHON -m pip install --user Pillow" >&2
    exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
    echo "error: iconutil was not found; the .icns cannot be built" >&2
    exit 1
fi

mkdir -p "$LOGO_DIR" "$ROOT/build"
rm -rf "$ICONSET"

"$PYTHON" "$SCRIPT_DIR/make_logo.py" --iconset "$ICONSET" "$LOGO_DIR"

iconutil -c icns -o "$ICNS" "$ICONSET"
rm -rf "$ICONSET"
echo "wrote $ICNS"
