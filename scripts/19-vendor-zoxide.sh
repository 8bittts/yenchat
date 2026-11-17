#!/bin/bash
# Vendor zoxide Binary (Universal)
#
# Downloads both arm64 and x86_64 zoxide release binaries and creates
# a universal binary using lipo. Stores at yen-terminal/customizations/vendor/zoxide/
#
# zoxide is a smart directory jumper used by yazi for the z command.
#
# Usage: ./scripts/19-vendor-zoxide.sh
#        ./scripts/19-vendor-zoxide.sh --force    # Skip version check

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/vendor-binary.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/19-vendor-zoxide.sh [--force]"
    exit 0
fi
FORCE=$(parse_force_flag "$@")

vendor_binary \
    "zoxide" \
    "ajeetdsouza/zoxide" \
    "zoxide" \
    "zoxide" \
    ".zoxide-baseline" \
    "zoxide-{VNUM}-aarch64-apple-darwin.tar.gz" \
    "zoxide-{VNUM}-x86_64-apple-darwin.tar.gz" \
    "$FORCE"
