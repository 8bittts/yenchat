#!/bin/bash
# Vendor resvg Binary (Universal)
#
# Downloads arm64 and x86_64 resvg release binaries and creates
# a universal binary using the shared vendor library.
#
# Stores at yen-terminal/customizations/vendor/resvg/
#
# Usage: ./scripts/29-vendor-resvg.sh
#        ./scripts/29-vendor-resvg.sh --force

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/vendor-binary.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/29-vendor-resvg.sh [--force]"
    exit 0
fi
FORCE=$(parse_force_flag "$@")

vendor_binary \
    "resvg" \
    "linebender/resvg" \
    "resvg" \
    "resvg" \
    ".resvg-baseline" \
    "resvg-macos-aarch64.zip" \
    "resvg-macos-x86_64.zip" \
    "$FORCE" \
    "zip" \
    "resvg" \
    "resvg"
