#!/bin/bash
# Build a native macOS thumbnailer as a universal binary (arm64 + x86_64).
#
# Usage: build-thumb.sh <source_dir> <name> <framework> [<framework> ...]
#
# Compiles <source_dir>/main.swift into <source_dir>/<name> (universal binary).
# Shared recipe behind yen-{pdf,svg,vid}thumb/build.sh.

set -e

SOURCE_DIR="$1"
NAME="$2"
shift 2

FRAMEWORK_ARGS=()
for fw in "$@"; do
    FRAMEWORK_ARGS+=(-framework "$fw")
done

cd "$SOURCE_DIR"

echo "  Building $NAME..."

ARM_SLICE="$NAME-arm64"
X64_SLICE="$NAME-x86_64"

# Shared thumbnailer helpers (usage/fail, PNG encode, output-dir-create+write),
# compiled into every yen-*thumb so those pieces can't drift between tools.
# Path is relative to the tool dir (cwd after the `cd "$SOURCE_DIR"` above).
SHARED_SRC="../yen-thumbcommon/ThumbCommon.swift"

cleanup_slices() {
    rm -f "$ARM_SLICE" "$X64_SLICE"
}
trap cleanup_slices EXIT

# Build arm64
swiftc -O -parse-as-library -target arm64-apple-macos13.0 \
    "${FRAMEWORK_ARGS[@]}" \
    -o "$ARM_SLICE" main.swift "$SHARED_SRC"

# Build x86_64
swiftc -O -parse-as-library -target x86_64-apple-macos13.0 \
    "${FRAMEWORK_ARGS[@]}" \
    -o "$X64_SLICE" main.swift "$SHARED_SRC"

# Lipo to universal
lipo -create "$ARM_SLICE" "$X64_SLICE" -output "$NAME"

chmod 755 "$NAME"
echo "    Built $NAME ($(file "$NAME" | grep -o 'universal.*'))"
