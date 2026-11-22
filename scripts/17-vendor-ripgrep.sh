#!/bin/bash
# Vendor ripgrep Binary (arm64)
#
# Downloads the arm64 ripgrep release archive and installs `rg`.
# Stores at yen-terminal/customizations/vendor/ripgrep/
#
# ripgrep (rg) is a fast content search tool used by yazi for grep within files.
#
# Usage: ./scripts/17-vendor-ripgrep.sh
#        ./scripts/17-vendor-ripgrep.sh --force    # Skip version check

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/vendor-binary.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/17-vendor-ripgrep.sh [--force]"
    exit 0
fi
FORCE=$(parse_force_flag "$@")

vendor_binary \
    "ripgrep" \
    "BurntSushi/ripgrep" \
    "rg" \
    "ripgrep" \
    ".ripgrep-baseline" \
    "ripgrep-{VERSION}-aarch64-apple-darwin.tar.gz" \
    "$FORCE"
