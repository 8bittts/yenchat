#!/bin/bash
# Sourced by apply-overlays.sh; inherits its working directory and fail-fast mode.

# ============================================================================
# Copy Icons
# ============================================================================

cd "$SCRIPT_DIR"

# Rename Ghostty.icon directory to YEN.icon
if [ -d "ghostty/images/Ghostty.icon" ]; then
    mv ghostty/images/Ghostty.icon ghostty/images/YEN.icon
fi

# Copy simplified icon.json
if [ -f "customizations/icons/icon.json" ]; then
    cp customizations/icons/icon.json ghostty/images/YEN.icon/icon.json
fi

# Copy YEN logo
if [ -f "customizations/icons/YEN.png" ]; then
    mkdir -p ghostty/images/YEN.icon/Assets
    cp customizations/icons/YEN.png ghostty/images/YEN.icon/Assets/YEN.png
fi

# Copy icon PNGs
if ls customizations/icons/icon_*.png 1>/dev/null 2>&1; then
    cp customizations/icons/icon_*.png ghostty/images/icons/
fi

# Copy pre-compiled .icns
if [ -f "customizations/icons/Yen.icns" ]; then
    cp customizations/icons/Yen.icns ghostty/macos/Yen.icns
fi

# Copy YEN icons to AppIconImage.imageset (used by Settings panel)
APP_ICON_DIR="ghostty/macos/Assets.xcassets/AppIconImage.imageset"
if [ -d "$APP_ICON_DIR" ]; then
    cp customizations/icons/icon_256.png "$APP_ICON_DIR/macOS-AppIcon-256px-128pt@2x.png"
    cp customizations/icons/icon_512.png "$APP_ICON_DIR/macOS-AppIcon-512px.png"
    cp customizations/icons/icon_1024.png "$APP_ICON_DIR/macOS-AppIcon-1024px.png"
fi
