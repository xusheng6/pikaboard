#!/bin/bash
# Put a pikafish.nnue in place so the app can be built.
#
# The real weights are ~51 MB and are deliberately not in git. A build only
# needs the file to exist, since Flutter refuses to build with a declared
# asset missing, so CI downloads the real thing when a URL is configured and
# otherwise writes a placeholder. A placeholder builds but cannot play: never
# ship an artifact produced from one.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$SCRIPT_DIR/../app/assets/pikafish.nnue"

if [ -s "$DEST" ]; then
    echo "NNUE already present: $DEST"
    exit 0
fi

mkdir -p "$(dirname "$DEST")"

if [ -n "$PIKAFISH_NNUE_URL" ]; then
    echo "Downloading NNUE from $PIKAFISH_NNUE_URL"
    curl -fsSL "$PIKAFISH_NNUE_URL" -o "$DEST"
    echo "Downloaded $(du -h "$DEST" | cut -f1)"
else
    echo "PIKAFISH_NNUE_URL is not set — writing a placeholder."
    echo "The build will succeed; the engine in it cannot evaluate."
    : > "$DEST"
    # A megabyte of nothing, so anything checking for a non-empty file passes.
    dd if=/dev/zero of="$DEST" bs=1024 count=1024 2>/dev/null
fi
