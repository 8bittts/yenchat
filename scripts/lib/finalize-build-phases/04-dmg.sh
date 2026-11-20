#!/bin/bash
# Sourced by finalize-build.sh; shares its working directory, state, and traps.

# ============================================================================
# CREATE DMG
# (DMG notarization covers all code inside — separate app notarization removed)
# ============================================================================

echo "  Creating DMG..."
DMG_FILENAME="yen-${VERSION_FILENAME}.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_FILENAME"
DMG_VOLUME_NAME="YEN"
DMG_WINDOW_BOUNDS_LEFT=200
DMG_WINDOW_BOUNDS_TOP=140
DMG_WINDOW_BOUNDS_RIGHT=800
DMG_WINDOW_BOUNDS_BOTTOM=800
DMG_WINDOW_BOUNDS_RIGHT_JIGGLE=$((DMG_WINDOW_BOUNDS_RIGHT - 10))
DMG_WINDOW_BOUNDS_BOTTOM_JIGGLE=$((DMG_WINDOW_BOUNDS_BOTTOM - 10))
# Full-bleed opaque icons render visually larger in Finder; tune icon size and
# positions to keep the app icon aligned with the option key center.
DMG_ICON_SIZE=108
DMG_TEXT_SIZE=12
# Align app icon center over the keyboard option key in full 600x600 art.
DMG_APP_ICON_X=300
DMG_APP_ICON_Y=241
DMG_APPLICATIONS_ICON_X=300
DMG_APPLICATIONS_ICON_Y=420
# Keep hidden metadata folders aligned below Applications in the lower white
# strip so they stay out of the primary art/drag path.
DMG_HIDDEN_METADATA_X=300
DMG_BACKGROUND_FOLDER_Y=760
DMG_FSEVENTSD_FOLDER_Y=800

# Clean old release files
find "$RELEASE_DIR" -name "yen-*.dmg" -type f ! -name "$DMG_FILENAME" -delete 2>/dev/null || true
find "$RELEASE_DIR" -name "yen-*.dmg.sha256" -type f ! -name "${DMG_FILENAME}.sha256" -delete 2>/dev/null || true

# Create staging directory for DMG contents
STAGING_DIR=$(mktemp -d)
DMG_TEMP=$(mktemp -d)/temp.dmg

require_finalize_source "$REPO_ROOT/scripts/lib/finalize-cleanup.sh"
source "$REPO_ROOT/scripts/lib/finalize-cleanup.sh"

cp -R "$BUILD_PATH" "$STAGING_DIR/YEN.app"

# Clear any runtime custom-icon overrides so DMG always ships canonical app icon.
# Local debug runs can set Finder custom icon metadata on the app bundle.
APP_STAGING_PATH="$STAGING_DIR/YEN.app"
CUSTOM_ICON_PATH="${APP_STAGING_PATH}/"$'Icon\r'
if [ -e "$CUSTOM_ICON_PATH" ]; then
    rm -f "$CUSTOM_ICON_PATH"
fi
SetFile -a c "$APP_STAGING_PATH" 2>/dev/null || true
xattr -d com.apple.ResourceFork "$APP_STAGING_PATH" 2>/dev/null || true

ln -s /Applications "$STAGING_DIR/Applications"

# Add background image if available
BG_DIR="$SCRIPT_DIR/dmg-resources"
if [ -f "$BG_DIR/background.png" ]; then
    mkdir -p "$STAGING_DIR/.background"
    cp "$BG_DIR/background.png" "$STAGING_DIR/.background/"
    if [ -f "$BG_DIR/background@2x.png" ]; then
        cp "$BG_DIR/background@2x.png" "$STAGING_DIR/.background/"
    fi
fi

# Pre-DMG hygiene: detach stale mounts, suppress Spotlight indexing on staging dir
detach_stale_yen_mounts
touch "$STAGING_DIR/.metadata_never_index"

# Create writable DMG (retry on transient "Resource busy" from FSEvents/Spotlight)
DMG_CREATE_OK=0
for _create_attempt in 1 2 3; do
    # Force HFS+ for the writable staging image. Finder layout persistence is
    # still materially more reliable here than on APFS-backed interstitial DMGs.
    if HDIUTIL_CREATE_OUTPUT=$(hdiutil create -volname "$DMG_VOLUME_NAME" -srcfolder "$STAGING_DIR" -ov -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW "$DMG_TEMP" 2>&1); then
        DMG_CREATE_OK=1
        break
    fi
    if echo "$HDIUTIL_CREATE_OUTPUT" | /usr/bin/grep -q "Resource busy"; then
        echo "  hdiutil create: Resource busy (attempt $_create_attempt/3), retrying in 3s..."
        sleep 3
    else
        break
    fi
done
if [ "$DMG_CREATE_OK" -ne 1 ]; then
    echo "  ERROR: Failed to create DMG"
    echo "$HDIUTIL_CREATE_OUTPUT"
    exit 1
fi

# Configure DMG appearance (fail closed by default).
# Emergency local override only:
#   YEN_ALLOW_DMG_LAYOUT_FALLBACK=1
detach_stale_yen_mounts

detach_dmg_mount() {
    local mount_dir="$1"
    local detach_ok=0
    local attempt
    for attempt in 1 2 3 4 5; do
        if hdiutil detach "$mount_dir" -force > /dev/null 2>&1; then
            detach_ok=1
            break
        fi
        sleep 2
    done
    [ "$detach_ok" -eq 1 ]
}

DMG_ALLOW_LAYOUT_FALLBACK="${YEN_ALLOW_DMG_LAYOUT_FALLBACK:-0}"
DMG_LAYOUT_MAX_ATTEMPTS=5
DMG_LAYOUT_RETRY_DELAY_SECONDS=2
DMG_LAYOUT_VERIFY_SCRIPT="$REPO_ROOT/scripts/manual/14-verify-dmg-layout.sh"

if ! MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen -nobrowse "$DMG_TEMP" 2>&1); then
    echo "  ERROR: Failed to mount writable DMG for Finder layout configuration"
    echo "  $MOUNT_OUTPUT"
    exit 1
fi
MOUNT_DEVICE=$(echo "$MOUNT_OUTPUT" | awk '/^\/dev\/disk/ { print $1; exit }')
MOUNT_DIR=$(echo "$MOUNT_OUTPUT" | sed -nE 's#.*(/Volumes/'"${DMG_VOLUME_NAME}"'( [0-9]+)?)$#\1#p' | tail -1)
if [ -z "$MOUNT_DIR" ] || [ ! -d "$MOUNT_DIR" ]; then
    echo "  ERROR: Could not resolve mounted DMG path from hdiutil output"
    echo "  $MOUNT_OUTPUT"
    if [ -n "$MOUNT_DEVICE" ]; then
        detach_dmg_mount "$MOUNT_DEVICE" || true
    fi
    if [ "$DMG_ALLOW_LAYOUT_FALLBACK" = "1" ]; then
        echo "  WARNING: Continuing due to YEN_ALLOW_DMG_LAYOUT_FALLBACK=1"
    else
        exit 1
    fi
fi
if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
    DMG_MOUNT_NAME=$(basename "$MOUNT_DIR")
    rm -rf "$MOUNT_DIR/.fseventsd" 2>/dev/null || true
    # .metadata_never_index suppresses Spotlight while staging, but if it ships
    # inside the DMG Finder will auto-place it and push the visible icon column
    # downward on reopen.
    rm -f "$MOUNT_DIR/.metadata_never_index" 2>/dev/null || true

    if [ -d "$MOUNT_DIR/.background" ]; then
        chflags hidden "$MOUNT_DIR/.background" 2>/dev/null || true
        SetFile -a V "$MOUNT_DIR/.background" 2>/dev/null || true
    fi

    # Set DMG window appearance (with optional background image).
    BACKGROUND_CMD=""
    if [ -f "$MOUNT_DIR/.background/background.png" ]; then
        BACKGROUND_CMD='set background picture of theViewOptions to file ".background:background.png"'
    fi

    FINDER_DISK_READY=0
    for FINDER_REGISTER_ATTEMPT in 1 2 3 4 5; do
        open "$MOUNT_DIR" >/dev/null 2>&1 || true
        if osascript -e 'tell application "Finder" to get name of every disk' 2>/dev/null \
            | tr ',' '\n' \
            | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
            | grep -Fxq "$DMG_MOUNT_NAME"; then
            FINDER_DISK_READY=1
            break
        fi
        sleep 1
    done
    if [ "$FINDER_DISK_READY" -ne 1 ]; then
        echo "    WARNING: Finder did not list mounted DMG $DMG_MOUNT_NAME before layout attempts"
    fi

    DMG_LAYOUT_APPLIED=0
    OSASCRIPT_OUTPUT=""
    LAYOUT_ATTEMPT=1
    while [ "$LAYOUT_ATTEMPT" -le "$DMG_LAYOUT_MAX_ATTEMPTS" ]; do
        OSASCRIPT_STATUS=0
        OSASCRIPT_OUTPUT=$(osascript <<EOF 2>&1
set dmgDiskName to "$DMG_MOUNT_NAME"
tell application "Finder"
    tell disk dmgDiskName
        open
        delay 1
        tell container window
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set bounds to {$DMG_WINDOW_BOUNDS_LEFT, $DMG_WINDOW_BOUNDS_TOP, $DMG_WINDOW_BOUNDS_RIGHT, $DMG_WINDOW_BOUNDS_BOTTOM}
        end tell
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to $DMG_ICON_SIZE
        set text size of theViewOptions to $DMG_TEXT_SIZE
        $BACKGROUND_CMD
        set position of item "YEN.app" of container window to {$DMG_APP_ICON_X, $DMG_APP_ICON_Y}
        set position of item "Applications" of container window to {$DMG_APPLICATIONS_ICON_X, $DMG_APPLICATIONS_ICON_Y}
        set position of item ".background" of container window to {$DMG_HIDDEN_METADATA_X, $DMG_BACKGROUND_FOLDER_Y}
        try
            set position of item ".fseventsd" of container window to {$DMG_HIDDEN_METADATA_X, $DMG_FSEVENTSD_FOLDER_Y}
        end try
        try
            set selection to {}
        end try
        close
        delay 1
        open
        tell container window
            set statusbar visible to false
            set bounds to {$DMG_WINDOW_BOUNDS_LEFT, $DMG_WINDOW_BOUNDS_TOP, $DMG_WINDOW_BOUNDS_RIGHT_JIGGLE, $DMG_WINDOW_BOUNDS_BOTTOM_JIGGLE}
        end tell
        delay 1
        tell container window
            set statusbar visible to false
            set bounds to {$DMG_WINDOW_BOUNDS_LEFT, $DMG_WINDOW_BOUNDS_TOP, $DMG_WINDOW_BOUNDS_RIGHT, $DMG_WINDOW_BOUNDS_BOTTOM}
        end tell
        delay 3
        close
    end tell
end tell
EOF
        ) || OSASCRIPT_STATUS=$?

        if [ "$OSASCRIPT_STATUS" -eq 0 ]; then
            DMG_LAYOUT_APPLIED=1
            break
        fi

        echo "    WARNING: DMG appearance script attempt $LAYOUT_ATTEMPT/$DMG_LAYOUT_MAX_ATTEMPTS failed (exit $OSASCRIPT_STATUS)"
        echo "    $OSASCRIPT_OUTPUT"
        sleep "$DMG_LAYOUT_RETRY_DELAY_SECONDS"
        LAYOUT_ATTEMPT=$((LAYOUT_ATTEMPT + 1))
    done

    rm -rf "$MOUNT_DIR/.fseventsd" 2>/dev/null || true
    sync
    sleep 2

    if ! detach_dmg_mount "$MOUNT_DIR"; then
        echo "    ERROR: Failed to detach DMG mount — DMG may be corrupt"
        exit 1
    fi

    if [ "$DMG_LAYOUT_APPLIED" -ne 1 ]; then
        if [ "$DMG_ALLOW_LAYOUT_FALLBACK" = "1" ]; then
            echo "  WARNING: DMG layout failed after $DMG_LAYOUT_MAX_ATTEMPTS attempts; continuing due to YEN_ALLOW_DMG_LAYOUT_FALLBACK=1"
            echo "  Last osascript output: $OSASCRIPT_OUTPUT"
        else
            echo "  ERROR: DMG layout failed after $DMG_LAYOUT_MAX_ATTEMPTS attempts; refusing to ship default Finder layout"
            echo "  Last osascript output: $OSASCRIPT_OUTPUT"
            exit 1
        fi
    fi
fi

# Convert to compressed DMG
rm -f "$DMG_PATH"
if ! HDIUTIL_CONVERT_OUTPUT=$(hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" 2>&1); then
    echo "  ERROR: Failed to convert DMG"
    echo "$HDIUTIL_CONVERT_OUTPUT"
    exit 1
fi

# Verify final DMG integrity
if ! hdiutil verify "$DMG_PATH" >/dev/null 2>&1; then
    echo "    ERROR: DMG integrity check failed — compressed DMG is corrupt"
    exit 1
fi

if [ ! -x "$DMG_LAYOUT_VERIFY_SCRIPT" ]; then
    echo "    ERROR: DMG layout verification script missing or not executable: $DMG_LAYOUT_VERIFY_SCRIPT"
    exit 1
fi
if ! DMG_LAYOUT_VERIFY_OUTPUT=$("$DMG_LAYOUT_VERIFY_SCRIPT" --dmg "$DMG_PATH" 2>&1); then
    echo "    ERROR: Final DMG layout verification failed"
    echo "$DMG_LAYOUT_VERIFY_OUTPUT"
    exit 1
fi
echo "    DMG layout verified"

# Sign DMG with timestamp
if ! sign_with_retry "$DMG_PATH"; then
    echo "  ERROR: Failed to sign DMG"
    exit 1
fi
echo "    DMG signed"
echo ""

# Notarize DMG (required for Gatekeeper/Sparkle updates)
echo "  Notarizing DMG..."
if NOTARIZE_DMG_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARIZATION_PROFILE" --keychain "$NOTARIZATION_KEYCHAIN" --wait 2>&1); then
    :
else
    NOTARIZE_DMG_STATUS=$?
    echo "  ERROR: DMG notarization failed (exit code $NOTARIZE_DMG_STATUS)"
    echo "$NOTARIZE_DMG_OUTPUT"
    exit 1
fi

# Verify notarization was actually accepted (notarytool can exit 0 with Invalid status)
if ! echo "$NOTARIZE_DMG_OUTPUT" | command grep -q "status: Accepted"; then
    echo "  ERROR: DMG notarization did not return 'Accepted' status"
    echo "$NOTARIZE_DMG_OUTPUT"
    exit 1
fi

# Staple ticket to DMG
if ! STAPLE_OUTPUT=$(xcrun stapler staple "$DMG_PATH" 2>&1); then
    echo "  ERROR: DMG stapling failed"
    echo "  $STAPLE_OUTPUT"
    exit 1
fi

# Verify stapled ticket is valid
if ! VALIDATE_OUTPUT=$(xcrun stapler validate "$DMG_PATH" 2>&1); then
    echo "  ERROR: DMG staple validation failed (ticket may be corrupt)"
    echo "  $VALIDATE_OUTPUT"
    exit 1
fi

chmod 644 "$DMG_PATH"
echo "    Notarized and stapled"
zip_notify "Notarized" "DMG signed, notarized, and stapled"
echo ""
