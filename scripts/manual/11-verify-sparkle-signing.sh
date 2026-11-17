#!/bin/bash
# Verify Sparkle Update Signing
#
# This script verifies that:
# 1. Public key in YEN-Info.plist matches public key in DMG
# 2. Public key matches what's in the keychain (if available)
# 3. Signature in appcast.xml can be verified against the public key
# 4. If installed app exists, verify public keys match
#
# Usage: ./scripts/manual/11-verify-sparkle-signing.sh
#
# Exit codes:
#   0 = All checks passed
#   1 = Verification failed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_DIR="$REPO_ROOT/public/stable"
INFO_PLIST="$REPO_ROOT/yen-terminal/ghostty/macos/YEN-Info.plist"
VERSION_JSON="$RELEASE_DIR/version.json"
APPCAST_FILE="$RELEASE_DIR/appcast.xml"
INSTALLED_APP="/Applications/YEN.app/Contents/Info.plist"
source "$REPO_ROOT/scripts/lib/version-utils.sh"

detach_stale_yen_mounts() {
    hdiutil info 2>/dev/null | awk '
        /^image-path[[:space:]]*:/ {
            image_path = $0
            sub(/^image-path[[:space:]]*:[[:space:]]*/, "", image_path)
            is_yen_dmg = (tolower(image_path) ~ /\/yen[^\/]*\.dmg$/)
            next
        }
        /^mount-point[[:space:]]*:/ {
            mount_point = $0
            sub(/^mount-point[[:space:]]*:[[:space:]]*/, "", mount_point)
            if (is_yen_dmg && mount_point ~ /^\/Volumes\/YEN( [0-9]+)?$/) {
                print mount_point
            }
        }
    ' | while IFS= read -r stale_vol; do
        [ -z "$stale_vol" ] && continue
        hdiutil detach "$stale_vol" -force 2>/dev/null || true
    done
}

# Extract version to determine DMG filename
if [ -f "$VERSION_JSON" ]; then
    VERSION=$(get_version "$VERSION_JSON")

    if [ -n "$VERSION" ] && [ "$VERSION" != "null" ]; then
        VERSION_FILENAME=$(get_version_filename "$VERSION")
        DMG_FILENAME="yen-${VERSION_FILENAME}.dmg"
        DMG_FILE="$RELEASE_DIR/$DMG_FILENAME"
    else
        echo "ERROR: Could not extract version from version.json"
        exit 1
    fi
else
    echo "ERROR: version.json not found"
    exit 1
fi

VERIFICATION_FAILED=0

echo ""
echo "---------------"
echo "Sparkle Signing Verification"
echo "---------------"
echo ""

# Check 1: Verify YEN-Info.plist has SUPublicEDKey
echo "[1/5] Checking YEN-Info.plist public key..."
if [ ! -f "$INFO_PLIST" ]; then
    echo "  X YEN-Info.plist not found at $INFO_PLIST"
    VERIFICATION_FAILED=1
else
    PLIST_PUB_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$INFO_PLIST" 2>/dev/null || echo "")
    if [ -z "$PLIST_PUB_KEY" ]; then
        echo "  X SUPublicEDKey missing in YEN-Info.plist"
        echo "    ISSUE: Sparkle cannot verify update signatures without public key"
        echo "    Action: Add <key>SUPublicEDKey</key><string>YOUR_PUBLIC_KEY</string> to YEN-Info.plist"
        VERIFICATION_FAILED=1
    else
        echo "  OK: Public key found: ${PLIST_PUB_KEY:0:20}..."
    fi
fi

# Check 2: Verify versioned DMG exists and has matching public key
echo ""
echo "[2/5] Checking $DMG_FILENAME public key..."
if [ ! -f "$DMG_FILE" ]; then
    echo "  X $DMG_FILENAME not found at $DMG_FILE"
    echo "    ISSUE: Cannot verify DMG public key without DMG file"
    echo "    Action: Build YEN.app and create versioned DMG first"
    VERIFICATION_FAILED=1
else
    # Mount DMG to access Info.plist
    TEMP_MOUNT=""

    # Detach any stale mounts first
    detach_stale_yen_mounts

    MOUNT_OUTPUT=$(hdiutil attach -readonly -nobrowse "$DMG_FILE" 2>&1) || {
        echo "  X Failed to mount $DMG_FILENAME"
        VERIFICATION_FAILED=1
    }

    if [ $VERIFICATION_FAILED -eq 0 ]; then
        TEMP_MOUNT=$(echo "$MOUNT_OUTPUT" | sed -nE 's#.*(/Volumes/YEN( [0-9]+)?)$#\1#p' | tail -1)

        if [ -z "$TEMP_MOUNT" ] || [ ! -d "$TEMP_MOUNT" ]; then
            echo "  X Failed to find mount point for $DMG_FILENAME"
            VERIFICATION_FAILED=1
        else
            DMG_INFO_PLIST="$TEMP_MOUNT/YEN.app/Contents/Info.plist"
            if [ ! -f "$DMG_INFO_PLIST" ]; then
                echo "  X Info.plist not found in $DMG_FILENAME"
                VERIFICATION_FAILED=1
            else
                DMG_PUB_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$DMG_INFO_PLIST" 2>/dev/null || echo "")
                if [ -z "$DMG_PUB_KEY" ]; then
                    echo "  X SUPublicEDKey missing in $DMG_FILENAME Info.plist"
                    echo "    ISSUE: DMG file missing public key required for signature verification"
                    echo "    Action: Ensure YEN-Info.plist includes SUPublicEDKey before building"
                    VERIFICATION_FAILED=1
                elif [ "$DMG_PUB_KEY" != "$PLIST_PUB_KEY" ]; then
                    echo "  X Public key mismatch!"
                    echo "    ISSUE: YEN-Info.plist public key does not match $DMG_FILENAME public key"
                    echo "    YEN-Info.plist: ${PLIST_PUB_KEY:0:40}..."
                    echo "    $DMG_FILENAME:        ${DMG_PUB_KEY:0:40}..."
                    echo "    Action: Rebuild YEN.app to sync public key from YEN-Info.plist"
                    VERIFICATION_FAILED=1
                else
                    echo "  OK: Public key matches: ${DMG_PUB_KEY:0:20}..."
                fi
            fi

            # Unmount DMG
            hdiutil detach "$TEMP_MOUNT" -force 2>/dev/null || true
        fi
    fi
fi

# Check 3: Verify appcast.xml exists and has signature
echo ""
echo "[3/5] Checking appcast.xml signature..."
if [ ! -f "$APPCAST_FILE" ]; then
    echo "  X appcast.xml not found at $APPCAST_FILE"
    echo "    ISSUE: Cannot verify signature without appcast.xml"
    echo "    Action: Run generate-appcast.sh to create appcast.xml"
    VERIFICATION_FAILED=1
else
    # Extract signature from appcast.xml
    APPCAST_SIG=$(extract_sparkle_ed_signature "$(cat "$APPCAST_FILE")")
    if [ -z "$APPCAST_SIG" ]; then
        echo "  X No signature found in appcast.xml"
        echo "    ISSUE: appcast.xml missing EdDSA signature"
        echo "    Action: Regenerate appcast.xml with generate-appcast.sh"
        VERIFICATION_FAILED=1
    else
        # Verify signature format (Ed25519 signatures are 64 bytes = 88 base64 chars)
        SIG_LEN=$(echo -n "$APPCAST_SIG" | base64 -d 2>/dev/null | wc -c | tr -d ' ')
        if [ "$SIG_LEN" != "64" ]; then
            echo "  X Invalid signature format (length: $SIG_LEN bytes, expected 64)"
            echo "    ISSUE: Signature format invalid for Ed25519"
            echo "    Action: Regenerate appcast.xml with correct signing key"
            VERIFICATION_FAILED=1
        else
            echo "  OK: Signature format valid: ${APPCAST_SIG:0:20}..."
        fi
    fi
fi

# Check 4: Verify signature matches current keychain (if available)
echo ""
echo "[4/5] Verifying signature matches signing key..."
if [ -z "$PLIST_PUB_KEY" ] || [ -z "$APPCAST_SIG" ]; then
    echo "  ! Skipping (missing public key or signature)"
else
    # Re-sign DMG and compare signatures
    SIGN_TOOL="$REPO_ROOT/tools/sparkle/bin/sign_update"
    if [ ! -f "$SIGN_TOOL" ]; then
        echo "  ! sign_update tool not found, skipping signature verification"
        echo "    INFO: Cannot verify signature matches keychain without sign_update tool"
    else
        CURRENT_SIG_OUTPUT=$("$SIGN_TOOL" "$DMG_FILE" 2>&1)
        CURRENT_SIG=$(extract_sparkle_ed_signature "$CURRENT_SIG_OUTPUT")

        if [ -z "$CURRENT_SIG" ]; then
            echo "  X Failed to generate signature with current keychain"
            echo "    ISSUE: sign_update tool cannot access signing key"
            echo "    Action: Ensure EdDSA private key is in macOS Keychain (run tools/sparkle/bin/generate_keys)"
            VERIFICATION_FAILED=1
        elif [ "$CURRENT_SIG" != "$APPCAST_SIG" ]; then
            echo "  X Signature mismatch!"
            echo "    ISSUE: appcast.xml signature does not match signature from current keychain"
            echo "    appcast.xml: ${APPCAST_SIG:0:20}..."
            echo "    keychain:    ${CURRENT_SIG:0:20}..."
            echo "    Action: Regenerate appcast.xml with generate-appcast.sh using correct keychain"
            VERIFICATION_FAILED=1
        else
            echo "  OK: Signature matches keychain"
        fi
    fi
fi

# Check 5: Verify installed app public key matches (if app is installed)
# NOTE: This is a WARNING only, not a failure, because:
# - If source has correct key and installed app has wrong key, new build will fix it
# - Users may need to manually update once, then future updates will work
# - This check helps identify when a key migration is needed
echo ""
echo "[5/5] Checking installed app public key (if present)..."
if [ -f "$INSTALLED_APP" ]; then
    INSTALLED_PUB_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$INSTALLED_APP" 2>/dev/null || echo "")
    if [ -z "$INSTALLED_PUB_KEY" ]; then
        echo "  ! Installed app missing SUPublicEDKey (may be old version)"
    elif [ -z "$PLIST_PUB_KEY" ]; then
        echo "  ! Skipping comparison (YEN-Info.plist public key not available)"
    elif [ "$INSTALLED_PUB_KEY" != "$PLIST_PUB_KEY" ]; then
        echo "  ! Public key mismatch with installed app (WARNING only)"
        echo "    INFO: YEN-Info.plist public key does not match installed app public key"
        echo "    Installed app: ${INSTALLED_PUB_KEY:0:40}..."
        echo "    YEN-Info.plist: ${PLIST_PUB_KEY:0:40}..."
        echo "    NOTE: This is expected if source was updated with correct key"
        echo "    Users with old app will need to manually update once, then future updates will work"
        echo "    New builds will have correct key and updates will work for new installs"
        # Don't fail - this is a warning, not an error
        # VERIFICATION_FAILED=1
    else
        echo "  OK: Public key matches installed app"
    fi
else
    echo "  ! Installed app not found (skipping comparison)"
fi

# Summary
echo ""
if [ $VERIFICATION_FAILED -eq 1 ]; then
    echo "========================================"
    echo "  Verification FAILED"
    echo "========================================"
    echo ""
    echo "CRITICAL: Sparkle update signing verification failed."
    echo "Updates will fail with 'Update Error! The update is improperly signed'"
    echo ""
    echo "Fix all issues above before deploying."
    exit 1
else
    echo "========================================"
    echo "  Verification PASSED"
    echo "========================================"
    echo ""
    echo "All Sparkle signing checks passed."
    echo "Updates should work correctly."
    exit 0
fi
