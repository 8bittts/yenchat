#!/bin/bash
# Vendor bat Binary (Universal)
#
# Downloads both arm64 and x86_64 bat release binaries and creates
# a universal binary using lipo. Stores at yen-terminal/customizations/vendor/bat/
#
# bat is a syntax-highlighted cat replacement used by yazi for code previews.
#
# Usage: ./scripts/20-vendor-bat.sh
#        ./scripts/20-vendor-bat.sh --force    # Skip version check

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/vendor-binary.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/20-vendor-bat.sh [--force]"
    exit 0
fi
FORCE=$(parse_force_flag "$@")

vendor_binary \
    "bat" \
    "sharkdp/bat" \
    "bat" \
    "bat" \
    ".bat-baseline" \
    "bat-{VERSION}-aarch64-apple-darwin.tar.gz" \
    "bat-{VERSION}-x86_64-apple-darwin.tar.gz" \
    "$FORCE"
