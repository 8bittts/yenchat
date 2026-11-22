#!/bin/bash
# Build a native macOS thumbnailer as a universal binary (arm64 + x86_64).
#
# Usage: build-thumb.sh <source_dir> <name> <framework> [<framework> ...]
#
# Compiles <source_dir>/main.swift into <source_dir>/<name> (universal binary).
# Shared recipe behind yen-{pdf,svg,vid}thumb/build.sh.

set -e

source "$(dirname "$0")/../../yen-cli/lib/macos-version.sh"

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
SYSTEM_CHECK="$NAME-minimum-os.o"

# Shared thumbnailer helpers (usage/fail, PNG encode, output-dir-create+write),
# compiled into every yen-*thumb so those pieces can't drift between tools.
# Path is relative to the tool dir (cwd after the `cd "$SOURCE_DIR"` above).
SHARED_SRC="../yen-thumbcommon/ThumbCommon.swift"

cleanup_slices() {
    rm -f "$ARM_SLICE" "$X64_SLICE" "$SYSTEM_CHECK"
}
trap cleanup_slices EXIT

# Link the same direct-launch check as the app, compiled for the same minimum.
xcrun clang -arch arm64 -arch x86_64 "-mmacosx-version-min=$YEN_MIN_MACOS" -c \
    ../yen-terminal/overlays/macos/Sources/App/YENMinimumSystemVersion.m -o "$SYSTEM_CHECK"

# Build arm64
swiftc -O -parse-as-library -target "arm64-apple-macos${YEN_MIN_MACOS}" \
    "${FRAMEWORK_ARGS[@]}" \
    -o "$ARM_SLICE" main.swift "$SHARED_SRC" "$SYSTEM_CHECK"

# Build x86_64
swiftc -O -parse-as-library -target "x86_64-apple-macos${YEN_MIN_MACOS}" \
    "${FRAMEWORK_ARGS[@]}" \
    -o "$X64_SLICE" main.swift "$SHARED_SRC" "$SYSTEM_CHECK"

# Lipo to universal
lipo -create "$ARM_SLICE" "$X64_SLICE" -output "$NAME"

chmod 755 "$NAME"
echo "    Built $NAME ($(file "$NAME" | grep -o 'universal.*'))"
