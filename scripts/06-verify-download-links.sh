#!/bin/bash
# Verify Download Links Script
#
# Verifies that download links use the correct patterns:
# - app/home-client.tsx: Uses /download redirect route for DMG
# - SHA256 link uses dynamic version from version.json
# - HomeClient component receives version prop
#
# Note: app/docs/docs-client.tsx is documentation only, no download links to verify.
#
# Usage: ./scripts/06-verify-download-links.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/scripts/lib/gate-receipt.sh"

# Source shared utilities
source "$REPO_ROOT/scripts/lib/version-utils.sh"

# Read version from version.json
VERSION_JSON="$REPO_ROOT/public/stable/version.json"
if [ ! -f "$VERSION_JSON" ]; then
    echo "ERROR: version.json not found at $VERSION_JSON"
    exit 1
fi

VERSION=$(get_version "$VERSION_JSON")

if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
    echo "ERROR: Could not extract version from version.json"
    exit 1
fi

echo "Verifying download links..."
echo "  Current version: ${VERSION}"
echo ""

VERIFICATION_FAILED=0
gate_begin 06-verify-download-links
if (cd "$REPO_ROOT" && bun scripts/verify-home-downloads.tsx); then
    gate_unit_ran home-client-links "rendered_versions=2"
else
    gate_unit_ran home-client-links "rendered link verification failed"
    VERIFICATION_FAILED=1
fi

# Verify version.json has a GitHub Releases URL
URL=$(get_version_json_string "$VERSION_JSON" "url")

if echo "$URL" | grep -q "^https://github.com/8bittts/yenchat/releases/download/v[0-9.]*/yen-[0-9]*\.dmg$"; then
    echo "OK: version.json: URL points to GitHub Releases"
else
    echo "ERROR: version.json: URL does not point to GitHub Releases"
    echo "  Got: $URL"
    VERIFICATION_FAILED=1
fi

# Note: app/docs/docs-client.tsx is documentation only, no download links to verify

echo ""

gate_unit_ran version-json-url "url_host=$(printf '%s' "$URL" | sed -E 's#^https?://([^/]+).*#\1#')"

if [ "$VERIFICATION_FAILED" -eq 1 ]; then
    echo "X VERIFICATION FAILED: Download links not properly configured"
else
    echo "OK: All download links verified"
fi
gate_end "$VERIFICATION_FAILED"
