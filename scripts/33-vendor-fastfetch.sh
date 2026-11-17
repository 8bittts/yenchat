#!/bin/bash
# Vendor fastfetch Binary (Universal)
#
# Downloads fastfetch's macOS release archive and installs a universal
# binary using the shared vendor library. Upstream 2.70+ ships one
# pre-merged fastfetch-macos-universal asset instead of per-arch assets,
# so both asset patterns below name it (see vendor-binary.sh).
#
# Stores at yen-terminal/customizations/vendor/fastfetch/
#
# Usage: ./scripts/33-vendor-fastfetch.sh
#        ./scripts/33-vendor-fastfetch.sh --force

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/vendor-binary.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/33-vendor-fastfetch.sh [--force]"
    exit 0
fi
FORCE=$(parse_force_flag "$@")

vendor_binary \
    "fastfetch" \
    "fastfetch-cli/fastfetch" \
    "fastfetch" \
    "fastfetch" \
    ".fastfetch-baseline" \
    "fastfetch-macos-universal.tar.gz" \
    "fastfetch-macos-universal.tar.gz" \
    "$FORCE" \
    "tar.gz" \
    "fastfetch" \
    "fastfetch"
