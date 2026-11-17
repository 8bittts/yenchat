#!/bin/bash
# Sourced by finalize-build.sh; shares its working directory, state, and traps.

# Verify the GitHub CLI is available (used for release uploads)
if ! command -v gh &>/dev/null; then
    echo "  ERROR: gh CLI not installed — required for release uploads"
    echo "  Install with: brew install gh"
    exit 1
fi

# Source shared utilities
require_finalize_source "$REPO_ROOT/scripts/lib/version-utils.sh"
source "$REPO_ROOT/scripts/lib/version-utils.sh"
require_finalize_source "$REPO_ROOT/scripts/lib/python-utils.sh"
source "$REPO_ROOT/scripts/lib/python-utils.sh"
require_finalize_source "$REPO_ROOT/scripts/lib/release-constants.sh"
source "$REPO_ROOT/scripts/lib/release-constants.sh"
require_finalize_source "$REPO_ROOT/scripts/lib/mount-utils.sh"
source "$REPO_ROOT/scripts/lib/mount-utils.sh"
require_finalize_source "$REPO_ROOT/scripts/lib/signature-utils.sh"
source "$REPO_ROOT/scripts/lib/signature-utils.sh"

require_python3 "for release metadata updates" || exit 1

VERSION_JSON="$REPO_ROOT/public/stable/version.json"
RELEASE_DIR="$REPO_ROOT/public/stable"
VERSION_SIGNATURE_FILENAME="version.sig"
# Source shared signing identity (single source of truth)
require_finalize_source "$REPO_ROOT/scripts/lib/signing-constants.sh"
source "$REPO_ROOT/scripts/lib/signing-constants.sh"

# Verify notarization profile exists (fails after 10-20 min build otherwise)
if ! NOTARY_HISTORY="$(xcrun notarytool history --keychain-profile "$NOTARIZATION_PROFILE" --keychain "$NOTARIZATION_KEYCHAIN" 2>/dev/null)"; then
    echo "  ERROR: Notarization profile '$NOTARIZATION_PROFILE' not found in keychain"
    echo "  Run: xcrun notarytool store-credentials \"$NOTARIZATION_PROFILE\" --keychain \"$NOTARIZATION_KEYCHAIN\""
    exit 1
fi
if [ -z "$NOTARY_HISTORY" ]; then
    echo "  ERROR: Notarization credential check returned no positive receipt"
    exit 1
fi

SPARKLE_SIGN_TOOL="$REPO_ROOT/tools/sparkle/bin/sign_update"
SPARKLE_KEY_TOOL="$REPO_ROOT/tools/sparkle/bin/generate_keys"

# ============================================================================
# VERIFY BUILD
# ============================================================================

BUILD_PATH="ghostty/zig-out/YEN.app"
ENTITLEMENTS_PATH="ghostty/macos/YEN.entitlements"

if [ ! -d "$BUILD_PATH" ] || [ ! -f "$BUILD_PATH/Contents/MacOS/yen" ]; then
    echo "  ERROR: YEN.app not found"
    exit 1
fi

if [ ! -f "$ENTITLEMENTS_PATH" ]; then
    echo "  ERROR: YEN.entitlements not found"
    exit 1
fi

# Quick verification of critical components
if [ ! -x "$BUILD_PATH/Contents/Resources/bin/yen" ]; then
    echo "  ERROR: Build verification failed (CLI missing)"
    exit 1
fi

# Get version using shared utilities
if [ ! -f "$VERSION_JSON" ]; then
    echo "  ERROR: version.json not found"
    exit 1
fi
VERSION=$(get_version "$VERSION_JSON")
VERSION_FILENAME=$(get_version_filename "$VERSION")
VERSION_SIGNATURE_PATH="$RELEASE_DIR/$VERSION_SIGNATURE_FILENAME"
