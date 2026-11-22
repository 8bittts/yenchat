#!/bin/bash
# Vendor lazygit Binary (arm64)
#
# Downloads the arm64 lazygit release archive and installs the binary.
# Pure vendor — no modifications are applied to the binary;
# YEN behavior is layered via config overrides
# (yen-terminal/customizations/lazygit/config.yml) and alias wrappers only.
#
# Stores at yen-terminal/customizations/vendor/lazygit/
#
# Usage: ./scripts/32-vendor-lazygit.sh
#        ./scripts/32-vendor-lazygit.sh --force

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/vendor-binary.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/32-vendor-lazygit.sh [--force]"
    exit 0
fi
FORCE=$(parse_force_flag "$@")

vendor_binary \
    "lazygit" \
    "jesseduffield/lazygit" \
    "lazygit" \
    "lazygit" \
    ".lazygit-baseline" \
    "lazygit_{VNUM}_darwin_arm64.tar.gz" \
    "$FORCE" \
    "tar.gz" \
    "lazygit" \
    "lazygit"
