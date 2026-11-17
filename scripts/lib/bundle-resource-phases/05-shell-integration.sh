#!/bin/bash
# Sourced by bundle-yen-resources.sh in the shared bundling shell.

# Bundle shell integration
# YEN_RESOURCES_DIR points to Resources/yen, so shell integration goes there
echo "  Bundling shell integration..."

# Create directories (only Resources/yen/shell-integration/ is used)
mkdir -p "$APP_PATH/Contents/Resources/yen/shell-integration/zsh"
mkdir -p "$APP_PATH/Contents/Resources/yen/shell-integration/bash"
mkdir -p "$APP_PATH/Contents/Resources/yen/lazygit"

# Bundle lazygit YEN config overlays.
LAZYGIT_CONFIG_SRC="$CUSTOMIZATIONS_DIR/lazygit/config.yml"
LAZYGIT_CONFIG_DEST="$APP_PATH/Contents/Resources/yen/lazygit/config.yml"
if [ ! -f "$LAZYGIT_CONFIG_SRC" ]; then
    echo "ERROR: lazygit config not found at $LAZYGIT_CONFIG_SRC"
    exit 1
fi
cp -f "$LAZYGIT_CONFIG_SRC" "$LAZYGIT_CONFIG_DEST"
chmod 644 "$LAZYGIT_CONFIG_DEST"

# Copy version.json (for welcome banner)
cp -f "$VERSION_JSON" "$APP_PATH/Contents/Resources/yen/version.json"
chmod 644 "$APP_PATH/Contents/Resources/yen/version.json"

# Copy YEN shell integration files (standalone, not wrappers)
cp -f "$CUSTOMIZATIONS_DIR/shell-integration/zsh/.zshenv" \
      "$APP_PATH/Contents/Resources/yen/shell-integration/zsh/.zshenv"
cp -f "$CUSTOMIZATIONS_DIR/shell-integration/zsh/yen-integration.zsh" \
      "$APP_PATH/Contents/Resources/yen/shell-integration/zsh/yen-integration"
cp -f "$CUSTOMIZATIONS_DIR/shell-integration/bash/yen-integration.bash" \
      "$APP_PATH/Contents/Resources/yen/shell-integration/bash/yen.bash"
cp -f "$CUSTOMIZATIONS_DIR/shell-integration/yen-welcome.sh" \
      "$APP_PATH/Contents/Resources/yen/shell-integration/yen-welcome.sh"

# Copy bash-preexec.sh (required by bash integration)
# This is bundled by Zig at Resources/yen/shell-integration/bash/bash-preexec.sh
# Verify it exists after Zig build
if [ ! -f "$APP_PATH/Contents/Resources/yen/shell-integration/bash/bash-preexec.sh" ]; then
    echo "ERROR: bash-preexec.sh not found (should be bundled by Zig build)"
    exit 1
fi

# Set permissions
chmod 644 "$APP_PATH/Contents/Resources/yen/shell-integration/zsh/.zshenv"
chmod +x "$APP_PATH/Contents/Resources/yen/shell-integration/zsh/yen-integration"
chmod +x "$APP_PATH/Contents/Resources/yen/shell-integration/bash/yen.bash"
chmod +x "$APP_PATH/Contents/Resources/yen/shell-integration/yen-welcome.sh"

# Normalize legacy Ghostty shell-integration filenames to YEN naming.
if [ -f "$APP_PATH/Contents/Resources/yen/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish" ]; then
    mv -f \
        "$APP_PATH/Contents/Resources/yen/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish" \
        "$APP_PATH/Contents/Resources/yen/shell-integration/fish/vendor_conf.d/yen-shell-integration.fish"
fi
if [ -f "$APP_PATH/Contents/Resources/yen/shell-integration/elvish/lib/ghostty-integration.elv" ]; then
    mv -f \
        "$APP_PATH/Contents/Resources/yen/shell-integration/elvish/lib/ghostty-integration.elv" \
        "$APP_PATH/Contents/Resources/yen/shell-integration/elvish/lib/yen-integration.elv"
fi
if [ -f "$APP_PATH/Contents/Resources/yen/shell-integration/nushell/vendor/autoload/ghostty.nu" ]; then
    mv -f \
        "$APP_PATH/Contents/Resources/yen/shell-integration/nushell/vendor/autoload/ghostty.nu" \
        "$APP_PATH/Contents/Resources/yen/shell-integration/nushell/vendor/autoload/yen.nu"
fi

# Remove legacy upstream shell entrypoints that YEN replaces.
rm -f "$APP_PATH/Contents/Resources/yen/shell-integration/bash/ghostty.bash"
rm -f "$APP_PATH/Contents/Resources/yen/shell-integration/zsh/ghostty-integration"

# Ensure moved shell scripts keep conservative file permissions.
[ -f "$APP_PATH/Contents/Resources/yen/shell-integration/fish/vendor_conf.d/yen-shell-integration.fish" ] && chmod 644 "$APP_PATH/Contents/Resources/yen/shell-integration/fish/vendor_conf.d/yen-shell-integration.fish"
[ -f "$APP_PATH/Contents/Resources/yen/shell-integration/elvish/lib/yen-integration.elv" ] && chmod 644 "$APP_PATH/Contents/Resources/yen/shell-integration/elvish/lib/yen-integration.elv"
[ -f "$APP_PATH/Contents/Resources/yen/shell-integration/nushell/vendor/autoload/yen.nu" ] && chmod 644 "$APP_PATH/Contents/Resources/yen/shell-integration/nushell/vendor/autoload/yen.nu"

: # Keep optional final checks from becoming a failed source command.
