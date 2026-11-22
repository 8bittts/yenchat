#!/bin/bash
# Sourced by bundle-yen-resources.sh in the shared bundling shell.

# Browse wrapper (hides yazi branding from terminal output)
BROWSE_SCRIPT="$CUSTOMIZATIONS_DIR/bin/browse"
if [ -f "$BROWSE_SCRIPT" ]; then
    cp -pf "$BROWSE_SCRIPT" "$APP_PATH/Contents/Resources/bin/"
    chmod 755 "$APP_PATH/Contents/Resources/bin/browse"
    echo "    Bundled browse wrapper"
else
    echo "ERROR: browse wrapper not found at $BROWSE_SCRIPT"
    exit 1
fi

# Quick Look wrapper (guards qlmanage crash-prone media paths)
QUICKLOOK_SCRIPT="$CUSTOMIZATIONS_DIR/bin/yen-quicklook"
if [ -f "$QUICKLOOK_SCRIPT" ]; then
    cp -pf "$QUICKLOOK_SCRIPT" "$APP_PATH/Contents/Resources/bin/"
    chmod 755 "$APP_PATH/Contents/Resources/bin/yen-quicklook"
    echo "    Bundled yen-quicklook wrapper"
else
    echo "ERROR: yen-quicklook wrapper not found at $QUICKLOOK_SCRIPT"
    exit 1
fi

# Yazi editor wrapper (normalizes editor behavior in file-browser edit flows)
YAZI_EDIT_SCRIPT="$CUSTOMIZATIONS_DIR/bin/yen-yazi-edit"
if [ -f "$YAZI_EDIT_SCRIPT" ]; then
    cp -pf "$YAZI_EDIT_SCRIPT" "$APP_PATH/Contents/Resources/bin/"
    chmod 755 "$APP_PATH/Contents/Resources/bin/yen-yazi-edit"
    echo "    Bundled yen-yazi-edit wrapper"
else
    echo "ERROR: yen-yazi-edit wrapper not found at $YAZI_EDIT_SCRIPT"
    exit 1
fi

# Remove legacy dynamic theme generator if present from prior builds.
LEGACY_YAZI_THEME_GENERATOR="$APP_PATH/Contents/Resources/bin/generate-yazi-theme.sh"
if [ -e "$LEGACY_YAZI_THEME_GENERATOR" ]; then
    rm -f "$LEGACY_YAZI_THEME_GENERATOR"
fi

# Yazi configuration (YEN branding via init.lua ind-app-title DDS event,
# plus bundled defaults).
YAZI_CONFIG_DIR="$CUSTOMIZATIONS_DIR/yazi-config"
if [ -d "$YAZI_CONFIG_DIR" ] && [ -f "$YAZI_CONFIG_DIR/yazi.toml" ]; then
    rm -rf "$APP_PATH/Contents/Resources/yazi-config"
    cp -Rp "$YAZI_CONFIG_DIR" "$APP_PATH/Contents/Resources/"
    chmod 644 "$APP_PATH/Contents/Resources/yazi-config/"*.toml || true
    chmod 644 "$APP_PATH/Contents/Resources/yazi-config/"*.lua || true
    # Set permissions on plugin files recursively
    find "$APP_PATH/Contents/Resources/yazi-config/plugins" -name "*.lua" -exec chmod 644 {} \; || true
    # Ensure flavor assets are readable (theme + syntax files + licenses)
    find "$APP_PATH/Contents/Resources/yazi-config/flavors" -type d -exec chmod 755 {} \; 2>/dev/null || true
    find "$APP_PATH/Contents/Resources/yazi-config/flavors" -type f -exec chmod 644 {} \; 2>/dev/null || true
    echo "    Bundled yazi config (YEN branding + git/native preview plugins)"
else
    echo "ERROR: Yazi config not found at $YAZI_CONFIG_DIR/yazi.toml"
    echo "This file should be git-tracked. Check your repository state."
    exit 1
fi

# Verify bundled Yazi flavor assets required for syntax-themed code previews
for flavor in catppuccin-mocha catppuccin-latte; do
    FLAVOR_DIR="$APP_PATH/Contents/Resources/yazi-config/flavors/$flavor.yazi"
    if [ ! -d "$FLAVOR_DIR" ]; then
        echo "ERROR: required Yazi flavor not bundled: $flavor"
        exit 1
    fi
    for req_file in flavor.toml tmtheme.xml LICENSE LICENSE-tmtheme; do
        if [ ! -f "$FLAVOR_DIR/$req_file" ]; then
            echo "ERROR: Yazi flavor missing $req_file: $flavor"
            exit 1
        fi
    done
done

# Verify Yazi config has YEN branding.
# Yazi v26.5.6 removed `title_format`; the YEN window title now comes from
# the `ind-app-title` DDS event subscriber wired up in init.lua.
YAZI_INIT_LUA="$APP_PATH/Contents/Resources/yazi-config/init.lua"
if [ ! -f "$YAZI_INIT_LUA" ]; then
    echo "ERROR: yazi-config/init.lua missing (required for YEN title branding)"
    exit 1
fi
if ! grep -q 'ind-app-title' "$YAZI_INIT_LUA" 2>/dev/null; then
    echo "ERROR: yazi-config/init.lua missing ind-app-title DDS subscriber"
    exit 1
fi
if ! grep -q '"YEN' "$YAZI_INIT_LUA" 2>/dev/null; then
    echo "ERROR: yazi-config/init.lua missing YEN branding string"
    exit 1
fi

: # Keep optional final checks from becoming a failed source command.
