#!/bin/bash
# Put the engine's NNUE weights in place so the app can be built and can play.
#
# The weights are ~51 MB and deliberately not in git, but Flutter refuses to
# build with a declared asset missing, so CI fetches them.
#
# They come from the Pikafish release matching the pinned submodule, not from
# the Networks repo's rolling "master-net": that one is a different network and
# the engine built from this submodule rejects it outright ("Network evaluation
# parameters compatible with the engine must be available"). Keep RELEASE_TAG
# in step with the submodule when it moves.
set -e

RELEASE_TAG="Pikafish-2026-01-02"
ARCHIVE="Pikafish.2026-01-02.7z"
ARCHIVE_URL="https://github.com/official-pikafish/Pikafish/releases/download/$RELEASE_TAG/$ARCHIVE"
EXPECTED_SHA256="c4026370d7516d9b0f668447f9ca1931241538bdc689cde6fec6a991ac4d5f77"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$SCRIPT_DIR/../app/assets/pikafish.nnue"

sha256_of() {
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

if [ -s "$DEST" ] && [ "$(sha256_of "$DEST")" = "$EXPECTED_SHA256" ]; then
    echo "NNUE already in place and matches $RELEASE_TAG"
    exit 0
fi

mkdir -p "$(dirname "$DEST")"

# An override, for building against a different network on purpose.
if [ -n "$PIKAFISH_NNUE_URL" ]; then
    echo "Downloading NNUE from PIKAFISH_NNUE_URL"
    curl -fsSL --retry 3 "$PIKAFISH_NNUE_URL" -o "$DEST"
    echo "Installed $(sha256_of "$DEST")"
    exit 0
fi

# The release ships everything in one .7z, so 7-Zip has to be around.
find_7z() {
    for candidate in 7zz 7z 7za "/c/Program Files/7-Zip/7z.exe"; do
        if command -v "$candidate" > /dev/null 2>&1; then
            echo "$candidate"
            return 0
        fi
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

if ! SEVEN_ZIP="$(find_7z)"; then
    echo "Installing 7-Zip"
    if command -v brew > /dev/null 2>&1; then
        brew install sevenzip > /dev/null
    elif command -v apt-get > /dev/null 2>&1; then
        sudo apt-get update -qq && sudo apt-get install -y -qq p7zip-full
    fi
    SEVEN_ZIP="$(find_7z)" || {
        echo "No 7-Zip available to unpack $ARCHIVE" >&2
        exit 1
    }
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading $ARCHIVE"
curl -fsSL --retry 3 "$ARCHIVE_URL" -o "$WORK/$ARCHIVE"

echo "Extracting pikafish.nnue"
# -y: no prompts, -r: the net sits in a directory inside the archive.
"$SEVEN_ZIP" e -y -r "$WORK/$ARCHIVE" -o"$WORK" pikafish.nnue > /dev/null

if [ ! -s "$WORK/pikafish.nnue" ]; then
    echo "No pikafish.nnue inside $ARCHIVE" >&2
    exit 1
fi

ACTUAL="$(sha256_of "$WORK/pikafish.nnue")"
if [ "$ACTUAL" != "$EXPECTED_SHA256" ]; then
    echo "NNUE checksum mismatch for $RELEASE_TAG" >&2
    echo "  expected $EXPECTED_SHA256" >&2
    echo "  got      $ACTUAL" >&2
    exit 1
fi

mv "$WORK/pikafish.nnue" "$DEST"
echo "Installed the $RELEASE_TAG network ($(sha256_of "$DEST"))"
