#!/bin/bash
# Sourced by finalize-build.sh; shares its working directory, state, and traps.

# ============================================================================
# CHECKSUM
# ============================================================================

echo "  Computing checksum..."

DMG_SHA256=$(get_sha256 "$DMG_PATH")
echo "$DMG_SHA256" > "$RELEASE_DIR/${DMG_FILENAME}.sha256"
chmod 644 "$RELEASE_DIR/${DMG_FILENAME}.sha256"

# Update version.json with DMG sha256 and GitHub Release asset URL
RELEASE_TAG="$(github_release_tag "$VERSION")"
RELEASE_DMG_URL="$(github_release_asset_url "$VERSION" "$DMG_FILENAME")"
python3 "$REPO_ROOT/scripts/lib/json-utils.py" update "$VERSION_JSON" \
    "sha256=$DMG_SHA256" \
    "url=$RELEASE_DMG_URL"
chmod 644 "$VERSION_JSON"
sync
sleep 1

# Sign version.json so CLI update checks can verify trusted metadata.
if [ ! -x "$SPARKLE_SIGN_TOOL" ]; then
    echo "  ERROR: Sparkle sign_update tool not found: $SPARKLE_SIGN_TOOL"
    exit 1
fi
if [ ! -x "$SPARKLE_KEY_TOOL" ]; then
    echo "  ERROR: Sparkle generate_keys tool not found: $SPARKLE_KEY_TOOL"
    exit 1
fi
if ! "$SPARKLE_KEY_TOOL" -p >/dev/null 2>&1; then
    echo "  ERROR: EdDSA private key not found in keychain (required for signed version metadata)"
    exit 1
fi

APP_INFO_PLIST="$BUILD_PATH/Contents/Info.plist"
VERSION_PUBLIC_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP_INFO_PLIST" 2>/dev/null | tr -d '[:space:]' || true)
if [ -z "$VERSION_PUBLIC_KEY" ]; then
    echo "  ERROR: SUPublicEDKey missing from app Info.plist"
    exit 1
fi
VERSION_METADATA_SIGNED=0
for VERSION_SIGN_ATTEMPT in 1 2 3; do
    if ! VERSION_SIGN_OUTPUT=$("$SPARKLE_SIGN_TOOL" "$VERSION_JSON" 2>&1); then
        echo "  ERROR: Failed to sign version.json"
        echo "$VERSION_SIGN_OUTPUT"
        exit 1
    fi
    VERSION_SIGNATURE=$(extract_sparkle_ed_signature "$VERSION_SIGN_OUTPUT")
    if [ -z "$VERSION_SIGNATURE" ]; then
        echo "  ERROR: Failed to extract signature for version.json"
        echo "$VERSION_SIGN_OUTPUT"
        exit 1
    fi
    echo "$VERSION_SIGNATURE" > "$VERSION_SIGNATURE_PATH"
    chmod 644 "$VERSION_SIGNATURE_PATH"
    sync
    sleep 1

    if [ -z "$(tr -d '[:space:]' < "$VERSION_SIGNATURE_PATH")" ]; then
        echo "  ERROR: version.sig is empty after signing version.json"
        exit 1
    fi

    if verify_signed_metadata_round_trip "$VERSION_JSON" "$VERSION_SIGNATURE_PATH" "$VERSION_PUBLIC_KEY"; then
        VERSION_METADATA_SIGNED=1
        break
    fi

    if [ "$VERSION_SIGN_ATTEMPT" -lt 3 ]; then
        echo "  WARNING: version.json signature round-trip check failed (attempt $VERSION_SIGN_ATTEMPT/3); retrying..."
        sleep 1
    fi
done
if [ "$VERSION_METADATA_SIGNED" -ne 1 ]; then
    echo "  WARNING: version.json signature round-trip could not be confirmed inside finalize-build.sh"
    echo "  Deferring authoritative metadata verification to scripts/05-detect-failures.sh"
fi

echo "    Checksum: $DMG_SHA256"
echo "    Signed metadata: $(basename "$VERSION_SIGNATURE_PATH")"
if [ "$VERSION_METADATA_SIGNED" -eq 1 ]; then
    echo "    Metadata signature round-trip verified"
else
    echo "    Metadata signature round-trip NOT confirmed in-process — DEFERRED."
    echo "    scripts/05-detect-failures.sh MUST pass before publishing this release."
fi
echo ""
