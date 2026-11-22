#!/bin/bash
# Vendor Yazi Binary (arm64)
#
# Downloads the arm64 Yazi release archive and installs `yazi` and its `ya`
# companion using the shared vendor library.
# Stores at yen-terminal/customizations/vendor/yazi/
#
# Usage: ./scripts/15-vendor-yazi.sh
#        ./scripts/15-vendor-yazi.sh --force    # Skip version check

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/vendor-binary.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/15-vendor-yazi.sh [--force]"
    exit 0
fi
FORCE=$(parse_force_flag "$@")

VENDOR_COMPANION_ARCHIVE_BINARY_NAME="ya" \
VENDOR_COMPANION_OUTPUT_BINARY_NAME="ya" \
VENDOR_REQUIRE_COMPANION="true" \
vendor_binary \
    "Yazi" \
    "sxyazi/yazi" \
    "yazi" \
    "yazi" \
    ".yazi-baseline" \
    "yazi-aarch64-apple-darwin.zip" \
    "$FORCE" \
    "zip" \
    "yazi" \
    "yazi"
