#!/bin/bash
# Vendor btop Binary (Universal)
#
# btop does not publish macOS binaries, so this script compiles btop from
# source for arm64 and x86_64, then combines them with lipo. Shares the
# vendor_source_build() scaffolding in lib/vendor-binary.sh with 16-vendor-fd.sh
# and 35-vendor-delta.sh, supplying a CMake-based build callback.
#
# Stores at yen-terminal/customizations/vendor/btop/
#
# Usage: ./scripts/34-vendor-btop.sh
#        ./scripts/34-vendor-btop.sh --force
#        VENDOR_LATEST_TAG=vX.Y.Z ./scripts/34-vendor-btop.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/vendor-binary.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/34-vendor-btop.sh [--force]"
    exit 0
fi
FORCE=$(parse_force_flag "$@")

require_tool "cmake"
require_tool "curl"
require_tool "tar"
require_tool "lipo"
require_tool "file"
require_tool "python3"

if ! xcrun --find clang >/dev/null 2>&1; then
    echo "ERROR: Xcode command line tools are required (clang not found via xcrun)"
    echo "Run: xcode-select --install"
    exit 1
fi

find_btop_binary() {
    local search_dir="$1"
    local candidate

    while IFS= read -r candidate; do
        [ -f "$candidate" ] || continue
        [ -x "$candidate" ] || continue
        if file "$candidate" | grep -q "Mach-O"; then
            echo "$candidate"
            return 0
        fi
    done < <(find "$search_dir" -type f -name "btop" 2>/dev/null)

    return 1
}

build_arch_binary() {
    local source_dir="$1"
    local arch="$2"
    local build_dir="$3"
    # Upstream gates Apple Silicon GPU (IOReport) code on CMAKE_SYSTEM_PROCESSOR,
    # which stays the arm64 host when cross-building x86_64; disable it there.
    local gpu="ON"
    [ "$arch" = "x86_64" ] && gpu="OFF"

    echo "  Configuring $arch build..." >&2
    cmake -S "$source_dir" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DBTOP_GPU="$gpu" >&2

    echo "  Building $arch binary..." >&2
    cmake --build "$build_dir" --config Release --target btop >&2

    find_btop_binary "$build_dir"
}

# Build callback: compile arm64 + x86_64 via CMake, print the two binary paths
# to STDOUT (arm64 first, x86_64 second), all progress to STDERR. See the
# BUILD_FN contract in lib/vendor-binary.sh.
build_btop() {
    local source_dir="$1"
    local temp_dir="$2"
    local arm64 x86
    arm64=$(build_arch_binary "$source_dir" "arm64" "$temp_dir/build-arm64") || return 1
    x86=$(build_arch_binary "$source_dir" "x86_64" "$temp_dir/build-x86_64") || return 1
    echo "$arm64"
    echo "$x86"
}

vendor_source_build "btop" "aristocratos/btop" "btop" ".btop-baseline" "btop" build_btop "$FORCE" ""
