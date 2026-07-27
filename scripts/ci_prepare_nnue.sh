#!/bin/bash
# Put the engine's NNUE weights in place so the app can be built and can play.
#
# The weights are ~50 MB and deliberately not in git, but Flutter refuses to
# build with a declared asset missing, so CI fetches them.
#
# The network and the engine are a matched pair: each rejects the other's
# network outright ("Network evaluation parameters compatible with the engine
# must be available") and terminates. The submodule tracks Pikafish master, so
# the network is master-net, which upstream republishes in place whenever the
# architecture changes. That is why a mismatch against the recorded checksum is
# a loud warning rather than a failure: it means upstream has moved and the
# submodule probably needs to move with it.
set -e

NNUE_URL="https://github.com/official-pikafish/Networks/releases/download/master-net/pikafish.nnue"
# The network this app is currently developed and tested against.
KNOWN_SHA256="3cd15292bf8c979884262f57fc723959fc0dea43b4d8d544f88db5ceb2479e24"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$SCRIPT_DIR/../app/assets/pikafish.nnue"

sha256_of() {
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

if [ -s "$DEST" ] && [ "$(sha256_of "$DEST")" = "$KNOWN_SHA256" ]; then
    echo "NNUE already in place"
    exit 0
fi

mkdir -p "$(dirname "$DEST")"

# An override, for building against a particular network on purpose.
URL="${PIKAFISH_NNUE_URL:-$NNUE_URL}"
echo "Downloading NNUE from $URL"
curl -fsSL --retry 3 "$URL" -o "$DEST"

if [ ! -s "$DEST" ]; then
    echo "Downloaded network is empty" >&2
    exit 1
fi

ACTUAL="$(sha256_of "$DEST")"
if [ "$ACTUAL" = "$KNOWN_SHA256" ]; then
    echo "Installed the expected network ($ACTUAL)"
elif [ -n "$PIKAFISH_NNUE_URL" ]; then
    echo "Installed a network from PIKAFISH_NNUE_URL ($ACTUAL)"
else
    echo "::warning::master-net has changed since this build was last verified."
    echo "::warning::  expected $KNOWN_SHA256"
    echo "::warning::  got      $ACTUAL"
    echo "::warning::If the engine now rejects it, move the Pikafish submodule"
    echo "::warning::to a commit matching this network and update KNOWN_SHA256."
fi
