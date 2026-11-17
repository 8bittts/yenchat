#!/bin/bash
#
# apply-overlays.sh
#
# Applies YEN customizations to the clean Ghostty source:
# 1. Applies branding (Ghostty → YEN)
# 2. Restores dependency URLs and fixes user-facing URLs
# 3. Renames files for Zig imports
# 4. Updates Xcode/Info.plist + Sparkle keys
# 5. Copies icons
# 6. Removes ghost emoji
# 7. Copies overlay files (after branding pass, before post-copy patch blocks)
#
# CRITICAL BRANDING EXCLUSIONS:
#   - build.zig.zon: Contains .name = .ghostty for dependency path construction
#   - build.zig.zon.json: Lock file with ghostty URLs that must stay intact
#   Branding these files causes: "yen/pkg/zlib: FileNotFound"
#   See: _docs/05-infrastructure.md → "Overlay Rules"
#
# Usage: ./apply-overlays.sh

set -euo pipefail

# Ensure sed treats input as byte streams. Upstream files can contain mixed UTF-8
# bytes that otherwise trigger "illegal byte sequence" on macOS sed.
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/scripts/lib/python-utils.sh"
source "$REPO_ROOT/scripts/lib/sparkle-runtime-floor.sh"

require_python3 "for overlay patching and plist updates" || exit 1

PATCH_FILE_UTIL="$REPO_ROOT/scripts/lib/patch-file.py"
PATCHES_DIR="$REPO_ROOT/scripts/lib/patches"
if [ ! -f "$PATCH_FILE_UTIL" ]; then
    echo "  ERROR: patch utility missing at $PATCH_FILE_UTIL"
    exit 1
fi

source "$REPO_ROOT/scripts/lib/overlay-patch-runtime.sh"
source "$REPO_ROOT/scripts/lib/overlay-patch-preflight.sh"

source "$REPO_ROOT/scripts/lib/overlay-plist.sh"
source "$REPO_ROOT/scripts/lib/overlay-verification.sh"
source "$REPO_ROOT/scripts/lib/overlay-branding.sh"
source "$REPO_ROOT/scripts/lib/overlay-files.sh"
source "$REPO_ROOT/scripts/lib/overlay-rename-preflight.sh"

cd "$SCRIPT_DIR"

# Phase order is part of the overlay contract; helpers share the same shell state.
OVERLAY_PHASES=(
    "01-branding.sh"
    "02-renames.sh"
    "03-project.sh"
    "04-icons.sh"
    "05-emoji.sh"
    "06-copy.sh"
    "07-patches.sh"
    "08-verification.sh"
)
for phase in "${OVERLAY_PHASES[@]}"; do
    source "$REPO_ROOT/scripts/lib/overlay-phases/$phase"
done

echo "  Overlays applied (${OVERLAY_APPLIED} patched, ${OVERLAY_SKIPPED} idempotent skips)"
