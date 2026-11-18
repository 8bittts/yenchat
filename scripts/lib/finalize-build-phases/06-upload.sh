#!/bin/bash
# Sourced by finalize-build.sh; shares its working directory, state, and traps.

# ============================================================================
# UPLOAD TO GITHUB RELEASES
# ============================================================================

echo "  Uploading to GitHub Release $RELEASE_TAG..."

# Idempotency check — skip upload if the published SHA256 matches local
REMOTE_SHA256=$(curl -sL "$RELEASE_DMG_URL.sha256" 2>/dev/null | tr -d '[:space:]' || true)
if [ "$REMOTE_SHA256" = "$DMG_SHA256" ]; then
    echo "    Published SHA256 matches local — skipping upload"
else
    if ! ensure_github_release "$RELEASE_TAG" "YEN $VERSION" "Release notes: https://blog.yen.chat/releases"; then
        exit 1
    fi

    if ! upload_github_release_asset_retry "DMG" "$DMG_PATH" "$RELEASE_TAG"; then
        exit 1
    fi

    if ! upload_github_release_asset_retry "DMG checksum" "$RELEASE_DIR/${DMG_FILENAME}.sha256" "$RELEASE_TAG"; then
        exit 1
    fi

    echo "    Uploaded: $RELEASE_DMG_URL"
fi

verify_public_url "DMG" "$RELEASE_DMG_URL" HEAD
verify_remote_content_length "DMG" "$RELEASE_DMG_URL" "$DMG_PATH"
verify_public_url "DMG checksum" "$RELEASE_DMG_URL.sha256"
verify_remote_content_length "DMG checksum" "$RELEASE_DMG_URL.sha256" "$RELEASE_DIR/${DMG_FILENAME}.sha256"
echo "    DMG artifact verified (remote URL + size)"
echo ""
