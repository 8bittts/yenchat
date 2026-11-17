#!/bin/bash
# Vendor fzf Binary (Universal)
#
# Downloads both arm64 and x86_64 fzf release binaries and creates
# a universal binary using lipo. Stores at yen-terminal/customizations/vendor/fzf/
#
# fzf is a fuzzy finder used by yazi for quick navigation overlays.
#
# Usage: ./scripts/18-vendor-fzf.sh
#        ./scripts/18-vendor-fzf.sh --force    # Skip version check

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/vendor-binary.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/18-vendor-fzf.sh [--force]"
    exit 0
fi
FORCE=$(parse_force_flag "$@")

vendor_binary \
    "fzf" \
    "junegunn/fzf" \
    "fzf" \
    "fzf" \
    ".fzf-baseline" \
    "fzf-{VNUM}-darwin_arm64.tar.gz" \
    "fzf-{VNUM}-darwin_amd64.tar.gz" \
    "$FORCE"
