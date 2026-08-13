#!/bin/bash
# Build BTunes.app.
#
# Usage: ./build.sh [--debug] [--run]
#
# There is no Xcode project on purpose. The build machine runs Xcode 8, this
# machine runs a much newer toolchain, and a plain clang invocation is the one
# thing both agree on. The interface is built in code, so there are no nibs to
# keep in sync either.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP="$BUILD_DIR/BTunes.app"
DEPLOYMENT_TARGET="10.11"

CONFIG_FLAGS="-O2"
RUN_AFTER=0
BUILD_TOOLS=0

for arg in "$@"; do
    case "$arg" in
        --debug) CONFIG_FLAGS="-O0 -g" ;;
        --run)   RUN_AFTER=1 ;;
        --tools) BUILD_TOOLS=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# Xcode 8 has no arm64 slice, so the architecture follows the machine doing the
# build: x86_64 there, native here.
ARCH="${ARCH:-$(uname -m)}"

echo "==> Compiling (arch $ARCH, deployment target $DEPLOYMENT_TARGET)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=$(find "$SCRIPT_DIR/src" -name '*.m' | sort)
INCLUDES=$(find "$SCRIPT_DIR/src" -type d | sed 's/^/-I/')

clang \
    -arch "$ARCH" \
    -mmacosx-version-min="$DEPLOYMENT_TARGET" \
    -fobjc-arc \
    -fobjc-weak \
    -Wall \
    -Wno-deprecated-declarations \
    $CONFIG_FLAGS \
    $INCLUDES \
    -framework Cocoa \
    -framework AVFoundation \
    -framework CoreMedia \
    -framework AudioToolbox \
    -framework Accelerate \
    -framework DiscRecording \
    -framework DiscRecordingUI \
    -o "$APP/Contents/MacOS/BTunes" \
    $SOURCES

cp "$SCRIPT_DIR/resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ -f "$SCRIPT_DIR/resources/BTunes.icns" ]; then
    cp "$SCRIPT_DIR/resources/BTunes.icns" "$APP/Contents/Resources/BTunes.icns"
fi

# Artwork for the splash and the mini player, copied when it exists so the app
# still builds and runs before the logo is drawn.
for artwork in btunes-splash btunes-mini; do
    if [ -f "$SCRIPT_DIR/resources/logo/$artwork.png" ]; then
        cp "$SCRIPT_DIR/resources/logo/$artwork.png" "$APP/Contents/Resources/$artwork.png"
    fi
done

# Apple Silicon refuses to run an unsigned binary; an ad-hoc signature is enough
# and is a no-op for the Intel build.
if command -v codesign > /dev/null 2>&1; then
    codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "==> Built $APP"

if [ "$BUILD_TOOLS" -eq 1 ]; then
    echo "==> Building command line tools"
    # The whole model, plus the iPod database reader. Found rather than listed,
    # so a new model file does not have to be remembered here as well.
    # The analyzer comes along too. It answers on its own, without a window or a
    # sound card, which makes it the one piece of the audio path testable here.
    MODEL_SOURCES="$(find "$SCRIPT_DIR/src/model" -name '*.m' | sort) $SCRIPT_DIR/src/ipod/BTIPodDatabase.m $SCRIPT_DIR/src/player/BTSpectrum.m"

    # These live in tools/local, which belongs to the machine rather than to the
    # project. Building them is optional and quietly skipped when they are absent.
    for tool in bt-import smoke_test spectrum_check detune_check; do
        if [ ! -f "$SCRIPT_DIR/tools/local/$tool.m" ]; then
            echo "    skipping $tool, not present"
            continue
        fi
        clang \
            -arch "$ARCH" \
            -mmacosx-version-min="$DEPLOYMENT_TARGET" \
            -fobjc-arc \
            -Wall \
            -Wno-deprecated-declarations \
            $CONFIG_FLAGS \
            -I"$SCRIPT_DIR/src/model" \
            -I"$SCRIPT_DIR/src/ipod" \
            -I"$SCRIPT_DIR/src/player" \
            -framework Foundation \
            -framework AVFoundation \
            -framework CoreMedia \
            -framework AudioToolbox \
            -framework Accelerate \
            -o "$BUILD_DIR/$tool" \
            "$SCRIPT_DIR/tools/local/$tool.m" $MODEL_SOURCES
        echo "    $BUILD_DIR/$tool"
    done
fi

if [ "$RUN_AFTER" -eq 1 ]; then
    echo "==> Launching"
    open "$APP"
fi
