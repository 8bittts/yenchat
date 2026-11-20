#!/bin/bash
# Shared required bundled binary inventory for YEN.app Resources/bin/.
# Keep this list aligned with _docs/04-security.md bundled binary inventory.

set_required_app_bins() {
    REQUIRED_APP_BINS=(
        "yazi"
        "ya"
        "fd"
        "rg"
        "fzf"
        "zoxide"
        "bat"
        "jq"
        "lazygit"
        "delta"
        "btop"
        "fastfetch"
        "zmx"
        "yen-vidthumb"
        "yen-pdfthumb"
        "yen-svgthumb"
        "resvg"
    )
}

required_app_bin_path() {
    local bin_name="$1"
    echo "$bin_name"
}
