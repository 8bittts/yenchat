#!/bin/bash
# Sourced by finalize-build.sh; shares its working directory, state, and traps.

# ============================================================================
# SIGN APP
# ============================================================================

echo "  Signing..."

# Sign all binaries in Resources/bin/ (dynamic scan — no hardcoded list to drift)
BIN_DIR="$BUILD_PATH/Contents/Resources/bin"
if [ -d "$BIN_DIR" ]; then
    BIN_COUNT=0
    for BIN_FILE in "$BIN_DIR"/*; do
        [ -f "$BIN_FILE" ] || continue
        # Only sign Mach-O binaries (skip shell scripts like yen, browse)
        if file "$BIN_FILE" | grep -q "Mach-O"; then
            BIN_NAME=$(basename "$BIN_FILE")
            BIN_ENT="$BIN_DIR/${BIN_NAME}.entitlements"
            if [ -f "$BIN_ENT" ]; then
                if ! sign_with_retry "$BIN_FILE" "$BIN_ENT"; then
                    echo "  ERROR: Failed to sign $BIN_NAME (with entitlements)"
                    exit 1
                fi
                echo "    Signed $BIN_NAME (with per-binary entitlements)"
            else
                if ! sign_with_retry "$BIN_FILE"; then
                    echo "  ERROR: Failed to sign $BIN_NAME"
                    exit 1
                fi
            fi
            BIN_COUNT=$((BIN_COUNT + 1))
        fi
    done
    echo "    Signed $BIN_COUNT binaries in Resources/bin/"
fi

# Sign Sparkle framework first (it comes with ad-hoc signature, needs Developer ID)
SPARKLE_FRAMEWORK="$BUILD_PATH/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    SPARKLE_SIGN_FAILED=0

    # Sign nested bundles and binaries first (XPC services, helper apps, bare binaries)
    for nested in "$SPARKLE_FRAMEWORK/Versions/B/XPCServices"/*.xpc "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate.app" "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate" "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"; do
        if [ -e "$nested" ]; then
            if ! sign_with_retry "$nested"; then
                echo "  ERROR: Failed to sign: $(basename "$nested")"
                SPARKLE_SIGN_FAILED=1
            fi
        fi
    done

    # Then sign the framework itself
    if ! sign_with_retry "$SPARKLE_FRAMEWORK"; then
        echo "  ERROR: Failed to sign Sparkle framework"
        SPARKLE_SIGN_FAILED=1
    fi

    if [ $SPARKLE_SIGN_FAILED -eq 1 ]; then
        exit 1
    fi
fi

# Sign embedded plugins (e.g. DockTilePlugin for custom app icon)
PLUGINS_DIR="$BUILD_PATH/Contents/PlugIns"
if [ -d "$PLUGINS_DIR" ]; then
    for PLUGIN in "$PLUGINS_DIR"/*.plugin; do
        [ -d "$PLUGIN" ] || continue
        PLUGIN_NAME=$(basename "$PLUGIN")
        if ! sign_with_retry "$PLUGIN"; then
            echo "  ERROR: Failed to sign plugin: $PLUGIN_NAME"
            exit 1
        fi
        echo "    Signed plugin: $PLUGIN_NAME"
    done
fi

# Sign the main app with entitlements (required for microphone, speech recognition, etc.)
if ! sign_with_retry "$BUILD_PATH" "$ENTITLEMENTS_PATH"; then
    echo "  ERROR: Failed to sign main app bundle"
    exit 1
fi
if ! VERIFY_OUTPUT=$(codesign --verify --deep --strict "$BUILD_PATH" 2>&1); then
    echo "  ERROR: Signature verification failed"
    echo "  $VERIFY_OUTPUT"
    exit 1
fi

# Verify entitlements actually embedded (silent --entitlements failure = broken dictation)
echo "  Verifying entitlements embedding..."
if ! ENT_DUMP=$(codesign -d --entitlements - "$BUILD_PATH" 2>&1); then
    echo "  ERROR: Failed to read embedded entitlements"
    echo "  $ENT_DUMP"
    exit 1
fi
if [ -z "$ENT_DUMP" ]; then
    echo "  ERROR: codesign returned empty entitlements — app may not be signed"
    exit 1
fi
if ! printf '%s\n' "$ENT_DUMP" | grep -q "com.apple.security.device.audio-input"; then
    echo "  ERROR: Audio input entitlement not embedded — dictation will not work"
    echo "  Verify YEN.entitlements exists and --entitlements flag is correct"
    exit 1
fi
if ! printf '%s\n' "$ENT_DUMP" | grep -q "com.apple.security.personal-information.speech-recognition"; then
    echo "  ERROR: Speech recognition entitlement not embedded — speech permission prompt may not appear"
    exit 1
fi
if ! printf '%s\n' "$ENT_DUMP" | grep -q "com.apple.security.automation.apple-events"; then
    echo "  ERROR: Apple events entitlement not embedded — osascript IPC will not work"
    exit 1
fi
echo "    Entitlements verified (audio-input, speech-recognition, apple-events present)"

# Verify Sparkle helper entitlements
for SPARKLE_HELPER in "$BUILD_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate.app" "$BUILD_PATH/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"; do
    if [ -d "$SPARKLE_HELPER" ]; then
        HELPER_NAME=$(basename "$SPARKLE_HELPER")
        HELPER_SIG=$(codesign -dvv "$SPARKLE_HELPER" 2>&1)
        if echo "$HELPER_SIG" | grep -q "Signature=adhoc"; then
            echo "  ERROR: Sparkle helper $HELPER_NAME has ad-hoc signature"
            exit 1
        fi
        if ! echo "$HELPER_SIG" | grep -q "TeamIdentifier=$TEAM_ID"; then
            echo "  ERROR: Sparkle helper $HELPER_NAME not signed with team $TEAM_ID"
            exit 1
        fi
        echo "  Sparkle helper $HELPER_NAME: signed with team $TEAM_ID"
    fi
done

# ============================================================================
# POST-SIGN VERIFICATION (catch ad-hoc or unsigned binaries before they ship)
# ============================================================================

echo "  Verifying signatures..."
VERIFY_FAIL_LOG=$(mktemp)

# Check every Mach-O binary in the bundle (bash 3.2 compatible, space-safe)
find "$BUILD_PATH" -type f -perm +111 -exec sh -c '
    VERIFY_FAIL_LOG="$1"; TEAM_ID="$2"; shift 2
    for MACHO_FILE; do
        file "$MACHO_FILE" | grep -q "Mach-O" || continue
        SIGN_INFO=$(codesign -dvv "$MACHO_FILE" 2>&1)
        if echo "$SIGN_INFO" | grep -q "Signature=adhoc"; then
            echo "  ERROR: Ad-hoc signature: $MACHO_FILE" | tee -a "$VERIFY_FAIL_LOG"
        elif ! echo "$SIGN_INFO" | grep -q "TeamIdentifier=$TEAM_ID"; then
            echo "  ERROR: Wrong/missing team ID: $MACHO_FILE" | tee -a "$VERIFY_FAIL_LOG"
        fi
    done
' _ "$VERIFY_FAIL_LOG" "$TEAM_ID" {} +

# Also check frameworks (space-safe) — verify ad-hoc and team ID
find "$BUILD_PATH/Contents/Frameworks" \( -name "*.framework" -o -name "*.xpc" -o -name "*.app" \) -exec sh -c '
    VERIFY_FAIL_LOG="$1"; TEAM_ID="$2"; shift 2
    for FW_FILE; do
        ITEM_NAME=$(basename "$FW_FILE")
        SIG_INFO=$(codesign -dvv "$FW_FILE" 2>&1)
        if echo "$SIG_INFO" | grep -q "Signature=adhoc"; then
            echo "  ERROR: Ad-hoc signature: $FW_FILE" | tee -a "$VERIFY_FAIL_LOG"
        elif ! echo "$SIG_INFO" | grep -q "TeamIdentifier=$TEAM_ID"; then
            echo "  ERROR: Wrong team for $ITEM_NAME" | tee -a "$VERIFY_FAIL_LOG"
            echo "  $SIG_INFO" | grep "TeamIdentifier" >> "$VERIFY_FAIL_LOG" 2>/dev/null || true
        fi
    done
' _ "$VERIFY_FAIL_LOG" "$TEAM_ID" {} + 2>/dev/null

if [ -s "$VERIFY_FAIL_LOG" ]; then
    rm -f "$VERIFY_FAIL_LOG"
    echo "  ERROR: Post-sign verification failed — unsigned code would ship"
    exit 1
fi
rm -f "$VERIFY_FAIL_LOG"
echo "    All signatures verified (Developer ID, hardened runtime)"
echo "    App signed and verified"
echo ""
