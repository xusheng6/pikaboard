#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIKAFISH_SRC="$SCRIPT_DIR/Pikafish/src"
BRIDGE_SRC="$SCRIPT_DIR/pikafish_bridge"

# Target: macos (static lib, for testing), ios, ios-simulator, or
# macos-exe (standalone Pikafish CLI binary bundled into the macOS desktop app).
TARGET="${1:-macos}"

# The desktop app talks to Pikafish as a subprocess over UCI, so it needs the
# real executable rather than a static library. Build it via Pikafish's own
# Makefile and drop it where the Xcode "Bundle Pikafish Engine" phase expects it.
if [ "$TARGET" = "macos-exe" ]; then
    echo "=== Building Pikafish CLI executable (apple-silicon) ==="
    make -C "$PIKAFISH_SRC" -j build ARCH=apple-silicon COMP=clang
    DEST="$SCRIPT_DIR/app/macos/engine"
    mkdir -p "$DEST"
    cp -f "$PIKAFISH_SRC/pikafish" "$DEST/pikafish"
    chmod +x "$DEST/pikafish"
    echo "=== Done: $DEST/pikafish ==="
    ls -lh "$DEST/pikafish"
    exit 0
fi

if [ "$TARGET" = "ios" ]; then
    BUILD_DIR="$SCRIPT_DIR/build/ios-arm64"
    CXX="xcrun -sdk iphoneos clang++"
    AR="xcrun -sdk iphoneos ar"
    PLATFORM_FLAGS="-miphoneos-version-min=15.0 -fembed-bitcode"
elif [ "$TARGET" = "ios-simulator" ]; then
    BUILD_DIR="$SCRIPT_DIR/build/ios-sim"
    CXX="xcrun -sdk iphonesimulator clang++"
    AR="xcrun -sdk iphonesimulator ar"
    PLATFORM_FLAGS="-miphonesimulator-version-min=15.0"
else
    BUILD_DIR="$SCRIPT_DIR/build/macos-arm64"
    CXX="clang++"
    AR="ar"
    PLATFORM_FLAGS=""
fi

mkdir -p "$BUILD_DIR"

CXXFLAGS="-std=c++17 -fno-exceptions -O3 -funroll-loops \
  -DNDEBUG -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8 -DUSE_NEON_DOTPROD -DUSE_PTHREADS \
  -arch arm64 -march=armv8.2-a+dotprod \
  -I$PIKAFISH_SRC -I$PIKAFISH_SRC/external \
  -I$BRIDGE_SRC \
  $PLATFORM_FLAGS \
  -c"

echo "=== Building Pikafish static library for $TARGET ==="
echo "Build dir: $BUILD_DIR"

# Collect all .cpp source files, excluding main.cpp
SOURCES=$(find "$PIKAFISH_SRC" -name '*.cpp' ! -name 'main.cpp' | sort)

# Count files for progress
TOTAL=$(echo "$SOURCES" | wc -l | tr -d ' ')
COUNT=0

for src in $SOURCES; do
    COUNT=$((COUNT + 1))
    BASENAME=$(basename "$src" .cpp)
    # Handle duplicate basenames by including parent dir
    RELPATH="${src#$PIKAFISH_SRC/}"
    OBJNAME=$(echo "$RELPATH" | sed 's|/|_|g' | sed 's|\.cpp$|.o|')
    OBJ="$BUILD_DIR/$OBJNAME"

    if [ "$OBJ" -nt "$src" ] 2>/dev/null; then
        printf "[%d/%d] Skipping (up to date): %s\n" "$COUNT" "$TOTAL" "$RELPATH"
        continue
    fi

    printf "[%d/%d] Compiling: %s\n" "$COUNT" "$TOTAL" "$RELPATH"
    $CXX $CXXFLAGS -o "$OBJ" "$src"
done

# Compile bridge
echo "Compiling bridge..."
$CXX $CXXFLAGS -o "$BUILD_DIR/pikafish_bridge.o" "$BRIDGE_SRC/pikafish_bridge.cpp"

# Create static library
echo "Creating static library..."
$AR rcs "$BUILD_DIR/libpikafish.a" "$BUILD_DIR"/*.o

echo "=== Done: $BUILD_DIR/libpikafish.a ==="
ls -lh "$BUILD_DIR/libpikafish.a"
