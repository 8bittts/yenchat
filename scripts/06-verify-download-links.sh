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
HOME_CLIENT_ASSERTIONS=0
gate_begin 06-verify-download-links

# Verify app/home-client.tsx uses correct patterns
HOME_CLIENT="$REPO_ROOT/app/home-client.tsx"
if [ ! -f "$HOME_CLIENT" ]; then
    echo "ERROR: app/home-client.tsx not found"
    gate_unit_skipped home-client-links "app/home-client.tsx not found"
    gate_unit_skipped version-json-url "not reached"
    gate_end 1
fi

# Check for the /download redirect route (DMG hosted on GitHub Releases).
# The constant must be the /download URL, or the hero check below proves nothing.
DOWNLOAD_CTA="$REPO_ROOT/lib/analytics/download-cta.ts"
if grep -q 'href={DOWNLOAD_HREF}' "$HOME_CLIENT" && \
   grep -q 'export const DOWNLOAD_HREF = "/download";' "$DOWNLOAD_CTA"; then
    HOME_CLIENT_ASSERTIONS=$((HOME_CLIENT_ASSERTIONS + 1))
    echo "OK: app/home-client.tsx: DMG link uses the /download redirect"
else
    echo "ERROR: app/home-client.tsx: DMG link does not use the /download route"
    echo "  Expected pattern: href={DOWNLOAD_HREF} with DOWNLOAD_HREF in lib/analytics/download-cta.ts"
    VERIFICATION_FAILED=1
fi

# Check for dynamic SHA256 link pattern (sha256 file still in git)
if grep -q 'getVersionFilename(version)' "$HOME_CLIENT" && \
   grep -q 'href={\`/stable/yen-\${versionFilename}\.dmg\.sha256\`}' "$HOME_CLIENT"; then
    HOME_CLIENT_ASSERTIONS=$((HOME_CLIENT_ASSERTIONS + 1))
    echo "OK: app/home-client.tsx: SHA256 link is dynamic"
else
    echo "ERROR: app/home-client.tsx: SHA256 link is not dynamic"
    echo "  Expected pattern: shared version filename helper + dynamic checksum href"
    VERIFICATION_FAILED=1
fi

# Check that HomeClient receives version prop
if grep -q 'HomeClientProps' "$HOME_CLIENT" && grep -q 'version: string' "$HOME_CLIENT"; then
    HOME_CLIENT_ASSERTIONS=$((HOME_CLIENT_ASSERTIONS + 1))
    echo "OK: app/home-client.tsx: HomeClient receives version prop"
else
    echo "ERROR: app/home-client.tsx: HomeClient missing version prop"
    VERIFICATION_FAILED=1
fi

if [ "$HOME_CLIENT_ASSERTIONS" -gt 0 ]; then
    gate_unit_ran home-client-links "asserted=$HOME_CLIENT_ASSERTIONS/3"
else
    gate_unit_skipped home-client-links "no assertion passed"
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
