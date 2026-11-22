#!/bin/bash
# Vendor fd Binary (arm64)
#
# Downloads the arm64 fd release archive and installs the binary using the
# shared vendor library. Stores at yen-terminal/customizations/vendor/fd/
#
# fd is the file finder Yazi runs for name search (`s`).
#
# Usage: ./scripts/16-vendor-fd.sh
#        ./scripts/16-vendor-fd.sh --force    # Skip version check

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/vendor-binary.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/16-vendor-fd.sh [--force]"
    exit 0
fi
FORCE=$(parse_force_flag "$@")

vendor_binary \
    "fd" \
    "sharkdp/fd" \
    "fd" \
    "fd" \
    ".fd-baseline" \
    "fd-{VERSION}-aarch64-apple-darwin.tar.gz" \
    "$FORCE"
