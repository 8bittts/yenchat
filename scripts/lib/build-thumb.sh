#!/bin/bash
# Build a native macOS thumbnailer as an arm64 binary.
#
# Usage: build-thumb.sh <source_dir> <name> <framework> [<framework> ...]
#
# Compiles <source_dir>/main.swift into <source_dir>/<name> (arm64 only: YEN
# requires macOS 27, which runs only on Apple silicon).
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

SYSTEM_CHECK="$NAME-minimum-os.o"

# Shared thumbnailer helpers (usage/fail, PNG encode, output-dir-create+write),
# compiled into every yen-*thumb so those pieces can't drift between tools.
# Path is relative to the tool dir (cwd after the `cd "$SOURCE_DIR"` above).
SHARED_SRC="../yen-thumbcommon/ThumbCommon.swift"

cleanup_objects() {
    rm -f "$SYSTEM_CHECK"
}
trap cleanup_objects EXIT

# Link the same direct-launch check as the app, compiled for the same minimum.
xcrun clang -arch arm64 "-mmacosx-version-min=$YEN_MIN_MACOS" -c \
    ../yen-terminal/overlays/macos/Sources/App/YENMinimumSystemVersion.m -o "$SYSTEM_CHECK"

swiftc -O -parse-as-library -target "arm64-apple-macos${YEN_MIN_MACOS}" \
    "${FRAMEWORK_ARGS[@]}" \
    -o "$NAME" main.swift "$SHARED_SRC" "$SYSTEM_CHECK"

chmod 755 "$NAME"
echo "    Built $NAME ($(lipo -archs "$NAME"))"
