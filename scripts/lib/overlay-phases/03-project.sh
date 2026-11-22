#!/bin/bash
# Sourced by apply-overlays.sh; inherits its working directory and fail-fast mode.

# ============================================================================
# Xcode & Info.plist Configuration
# ============================================================================

# Update Xcode project. This block also strips retired Calendar permission
# declarations so generated Info.plist output does not reintroduce a dead
# prompt surface. The scrub MUST run on the post-rename $PBXPROJ here — the
# early PBXPROJ_PATH points at the pre-rename Ghostty.xcodeproj, which no
# longer exists by this point in a fresh vendor run, so a standalone scrub
# keyed off it silently no-ops.
configure_overlay_project

# Update module.modulemap
if [ -f "include/module.modulemap" ]; then
    sed -i '' \
        -e 's/module GhosttyKit/module YENKit/g' \
        -e 's/umbrella header "ghostty\.h"/umbrella header "yen.h"/g' \
        include/module.modulemap
fi

# Update Info.plist keys (keep all Info.plist changes in this block)
INFO_PLIST="macos/YEN-Info.plist"
if [ -f "$INFO_PLIST" ]; then
    sed -i '' \
        -e 's/<key>GhosttyBuild<\/key>/<key>YENBuild<\/key>/g' \
        -e 's/<key>GhosttyCommit<\/key>/<key>YENCommit<\/key>/g' \
        -e 's/<key>GHOSTTY_MAC_LAUNCH_SOURCE<\/key>/<key>YEN_MAC_LAUNCH_SOURCE<\/key>/g' \
        "$INFO_PLIST"

    # Update Sparkle public key to YEN's key
    sed -i '' \
        -e 's|wsNcGf5hirwtdXMVnYoxRIX/SqZQLMOsYlD3q3imeok=|0Gr0zoQweDjkOPIj9VSnNZzlTSTrnHlHnAIcwaXbmkU=|g' \
        "$INFO_PLIST"

    # CRITICAL: Verify YEN's EdDSA public key is present after replacement.
    # Wrong key = ALL Sparkle updates fail signature verification permanently.
    if ! grep -q "0Gr0zoQweDjkOPIj9VSnNZzlTSTrnHlHnAIcwaXbmkU=" "$INFO_PLIST"; then
        echo "  ERROR: YEN EdDSA public key not found in Info.plist after replacement"
        echo "         Upstream may have changed their key string. Check apply-overlays.sh."
        exit 1
    fi
    echo "  EdDSA public key verified in Info.plist"

    # Ensure Sparkle feed + installer keys are set at vendor time (build-time, not post-build)
    plist_upsert "$INFO_PLIST" "SUFeedURL" "string" "https://yen.chat/stable/appcast.xml"
    plist_upsert "$INFO_PLIST" "SUEnableInstallerLauncherService" "bool" "true"

    # Remove SUEnableAutomaticChecks so Sparkle uses its built-in first-launch permission
    # dialog (best practice). When absent, Sparkle asks the user on first launch whether to
    # enable automatic update checks. Explicit `auto-update` config values override in AppDelegate.
    plist_delete "$INFO_PLIST" "SUEnableAutomaticChecks"

    # Ensure minimum supported macOS is explicit in app metadata.
    plist_upsert "$INFO_PLIST" "LSMinimumSystemVersion" "string" "$YEN_MIN_MACOS"

    # Add Photos usage description for the Moving Wallpaper shuffle
    plist_upsert "$INFO_PLIST" "NSPhotoLibraryUsageDescription" "string" "YEN uses Photos to shuffle videos when you choose Shuffle from Photos for your wallpaper."

    # Add microphone usage description for dictation feature
    plist_upsert "$INFO_PLIST" "NSMicrophoneUsageDescription" "string" "YEN uses your microphone for Option + Space speech-to-text dictation in any app."

    # Add speech recognition usage description for dictation feature
    plist_upsert "$INFO_PLIST" "NSSpeechRecognitionUsageDescription" "string" "YEN uses speech recognition to convert speech to text when you hold Option + Space to dictate."

    # Remove camera usage description (Hands-Free Pointer removed; no YEN code uses camera)
    plist_delete "$INFO_PLIST" "NSCameraUsageDescription"

    # Remove screen capture usage description: own-window screenshot capture does not request
    # system-wide screen recording permission, so this key only broadens prompt surface.
    plist_delete "$INFO_PLIST" "NSScreenCaptureUsageDescription"
fi
