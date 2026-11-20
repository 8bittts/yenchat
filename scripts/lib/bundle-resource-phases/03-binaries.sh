#!/bin/bash
# Sourced by bundle-yen-resources.sh in the shared bundling shell.

# Bundle bin directory (CLI)
echo "  Bundling bin..."
rm -rf "$APP_PATH/Contents/Resources/bin"
mkdir -p "$APP_PATH/Contents/Resources/bin"

bundle_vendor_bin() {
    local vendor_dir="$1"
    local bin_name="$2"
    local display_name="$3"
    local missing_message="$4"
    local vendor_target="${5:-$display_name}"
    local source_path="$vendor_dir/$bin_name"
    local dest_path="$APP_PATH/Contents/Resources/bin/$bin_name"

    if [ ! -f "$source_path" ]; then
        echo "$missing_message"
        echo "Run: ./scripts/14-vendor.sh $vendor_target"
        exit 1
    fi

    cp -pf "$source_path" "$APP_PATH/Contents/Resources/bin/"
    chmod 755 "$dest_path"
    echo "    Bundled $display_name $(cat "$vendor_dir/.version" 2>/dev/null || echo "unknown")"
}

# YEN CLI
cp -pf "$YEN_CLI_DIR/bin/yen" "$APP_PATH/Contents/Resources/bin/"

# Yazi file manager (vendored binary)
YAZI_VENDOR_DIR="$CUSTOMIZATIONS_DIR/vendor/yazi"
bundle_vendor_bin "$YAZI_VENDOR_DIR" "yazi" "yazi" "ERROR: Yazi binary not found at $YAZI_VENDOR_DIR/yazi"
if [ -f "$YAZI_VENDOR_DIR/ya" ]; then
    cp -pf "$YAZI_VENDOR_DIR/ya" "$APP_PATH/Contents/Resources/bin/"
    chmod 755 "$APP_PATH/Contents/Resources/bin/ya"
else
    echo "ERROR: Yazi companion binary not found at $YAZI_VENDOR_DIR/ya"
    echo "Run: ./scripts/14-vendor.sh yazi"
    exit 1
fi

# fd (file finder for yazi search)
FD_VENDOR_DIR="$CUSTOMIZATIONS_DIR/vendor/fd"
bundle_vendor_bin "$FD_VENDOR_DIR" "fd" "fd" "ERROR: fd binary not found — required for file browser search"

# ripgrep (content search for yazi)
RG_VENDOR_DIR="$CUSTOMIZATIONS_DIR/vendor/ripgrep"
bundle_vendor_bin "$RG_VENDOR_DIR" "rg" "rg" "ERROR: ripgrep binary not found — required for file browser grep" "ripgrep"

# fzf (fuzzy finder for yazi)
FZF_VENDOR_DIR="$CUSTOMIZATIONS_DIR/vendor/fzf"
bundle_vendor_bin "$FZF_VENDOR_DIR" "fzf" "fzf" "ERROR: fzf binary not found — required for file browser fuzzy find"

# zoxide (smart directory jump for yazi)
ZOXIDE_VENDOR_DIR="$CUSTOMIZATIONS_DIR/vendor/zoxide"
bundle_vendor_bin "$ZOXIDE_VENDOR_DIR" "zoxide" "zoxide" "ERROR: zoxide binary not found — required for file browser smart jump"

# bat (syntax highlighting for yazi previews)
BAT_VENDOR_DIR="$CUSTOMIZATIONS_DIR/vendor/bat"
bundle_vendor_bin "$BAT_VENDOR_DIR" "bat" "bat" "ERROR: bat binary not found — required for file browser code preview"

# jq (JSON formatting for yazi previews)
JQ_VENDOR_DIR="$CUSTOMIZATIONS_DIR/vendor/jq"
bundle_vendor_bin "$JQ_VENDOR_DIR" "jq" "jq" "ERROR: jq binary not found — required for file browser JSON preview"

# lazygit (git TUI)
LAZYGIT_VENDOR_DIR="$CUSTOMIZATIONS_DIR/vendor/lazygit"
bundle_vendor_bin "$LAZYGIT_VENDOR_DIR" "lazygit" "lazygit" "ERROR: lazygit binary not found — required for git TUI workflow"
if LC_ALL=C grep -aFq "YEN loves:" "$APP_PATH/Contents/Resources/bin/lazygit"; then
    echo "ERROR: lazygit binary contains the retired YEN branding patch (must be pure vendor)"
    echo "Run: ./scripts/14-vendor.sh lazygit --force"
    exit 1
fi
echo "    Verified lazygit is pure vendor (no patch marker)"

# delta (git diff renderer)
DELTA_VENDOR_DIR="$CUSTOMIZATIONS_DIR/vendor/delta"
bundle_vendor_bin "$DELTA_VENDOR_DIR" "delta" "delta" "ERROR: delta binary not found — required for bundled git diff rendering"

# zmx (session persistence for terminal panes)
ZMX_VENDOR_DIR="$CUSTOMIZATIONS_DIR/vendor/zmx"
bundle_vendor_bin "$ZMX_VENDOR_DIR" "zmx" "zmx" "ERROR: zmx binary not found — required for persistent terminal sessions"

# btop (system monitor TUI)
BTOP_VENDOR_DIR="$CUSTOMIZATIONS_DIR/vendor/btop"
bundle_vendor_bin "$BTOP_VENDOR_DIR" "btop" "btop" "ERROR: btop binary not found — required for bundled system monitor command"

# fastfetch (system info display)
FASTFETCH_VENDOR_DIR="$CUSTOMIZATIONS_DIR/vendor/fastfetch"
bundle_vendor_bin "$FASTFETCH_VENDOR_DIR" "fastfetch" "fastfetch" "ERROR: fastfetch binary not found — required for bundled system info command"

# Build + bundle native macOS thumbnailers (dir name == binary name == label).
build_and_bundle_thumb() {
    local thumb_name="$1"
    local thumb_dir="$PROJECT_ROOT/$thumb_name"
    local thumb_binary="$thumb_dir/$thumb_name"
    local build_output

    echo "  Building $thumb_name..."
    if ! build_output=$(cd "$thumb_dir" && ./build.sh 2>&1); then
        echo "ERROR: $thumb_name build failed"
        echo "$build_output"
        exit 1
    fi
    echo "$build_output"

    if [ -f "$thumb_binary" ]; then
        cp -pf "$thumb_binary" "$APP_PATH/Contents/Resources/bin/"
        chmod 755 "$APP_PATH/Contents/Resources/bin/$thumb_name"
        echo "    Bundled $thumb_name"
    else
        echo "ERROR: $thumb_name build produced no binary"
        exit 1
    fi
}

# yen-vidthumb (native macOS video thumbnailer — replaces ffmpeg + ffprobe)
build_and_bundle_thumb yen-vidthumb
# yen-pdfthumb (native macOS PDF thumbnailer — replaces pdftoppm)
build_and_bundle_thumb yen-pdfthumb
# yen-svgthumb (native macOS SVG thumbnailer; resvg fallback remains for parity gaps)
build_and_bundle_thumb yen-svgthumb

# Remove legacy weather-helper artifacts during incremental/local builds.
rm -f "$APP_PATH/Contents/Resources/bin/yen-weather" 2>/dev/null || true
rm -f "$APP_PATH/Contents/Resources/bin/yen-weather.entitlements" 2>/dev/null || true
rm -rf "$APP_PATH/Contents/Resources/bin/yen-weather.app" 2>/dev/null || true

# Remove retired companion-service binaries so incremental builds cannot ship
# stale command surfaces from prior app versions.
rm -f "$APP_PATH/Contents/Resources/bin/chat" 2>/dev/null || true
rm -f "$APP_PATH/Contents/Resources/bin/mail" 2>/dev/null || true
rm -f "$APP_PATH/Contents/Resources/bin/email" 2>/dev/null || true
rm -f "$APP_PATH/Contents/Resources/bin/calendar" 2>/dev/null || true

# Native archive previews/extract use macOS bsdtar (libarchive) via Yazi plugins.
# No vendored 7zip binary is bundled.

# resvg (SVG previews for yazi)
RESVG_VENDOR_DIR="$CUSTOMIZATIONS_DIR/vendor/resvg"
bundle_vendor_bin "$RESVG_VENDOR_DIR" "resvg" "resvg" "ERROR: resvg binary not found — required for file browser SVG previews"

: # Keep optional final checks from becoming a failed source command.
