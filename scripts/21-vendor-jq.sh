#!/bin/bash
# Vendor jq Binary (Universal)
#
# Downloads both arm64 and x86_64 jq release binaries and creates
# a universal binary using the shared vendor library.
# Stores at yen-terminal/customizations/vendor/jq/
#
# Note: jq releases are direct binaries, not archives.
#
# Usage: ./scripts/21-vendor-jq.sh
#        ./scripts/21-vendor-jq.sh --force    # Skip version check

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/vendor-binary.sh"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: ./scripts/21-vendor-jq.sh [--force]"
    exit 0
fi
FORCE=$(parse_force_flag "$@")

vendor_binary \
    "jq" \
    "jqlang/jq" \
    "jq" \
    "jq" \
    ".jq-baseline" \
    "jq-macos-arm64" \
    "jq-macos-amd64" \
    "$FORCE" \
    "direct" \
    "jq" \
    "jq"
