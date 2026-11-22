#!/bin/bash
# Single declaration of the vendor roster.
#
# WHY THIS EXISTS
# The roster used to be hardcoded in eleven-plus independent enumerations —
# four inside 14-vendor.sh alone (arg parsing, help text, the twelve
# process_binary_vendor call sites with nine to eleven positional args each,
# and the status prefetch), plus arrays in 11-sync-vendor-audit.sh and
# 12-verify-vendor-audit.sh, plus prose copies in the owner docs. Missing one
# copy degrades silently rather than failing: a vendor absent from
# 12-verify-vendor-audit.sh is simply never verified, and one absent from the
# prefetch falls back to a synchronous fetch with no warning.
#
# RECORD FORMAT (pipe-delimited, Bash 3.2 safe — no associative arrays)
#   key|type|title|subtitle|repo|binary|script|companion|require_companion
#
#   key                 vendor name as passed to `14-vendor.sh <key>`
#   type                source | binary | source-built
#   title               display name in run output
#   subtitle            short role description
#   repo                upstream <owner>/<name>; empty for the source vendor,
#                       which resolves through scripts/lib/upstream.sh instead
#   binary              installed executable name under customizations/vendor/<key>/
#   script              per-vendor updater under scripts/
#   companion           optional second executable shipped alongside `binary`
#   require_companion   true when the companion missing forces a rebuild
#
# Derived paths (see the accessors below) follow from `key` and `binary`:
#   yen-terminal/.<key>-baseline
#   yen-terminal/customizations/vendor/<key>/.version
#   yen-terminal/customizations/vendor/<key>/<binary>
#
# Order is the run order and drives the "[n] name" index in the output.
# tests/119 asserts this manifest matches the baseline files on disk and the
# registry tables in the vendor docs.

# Idempotent guard — harmless to source twice.
if [ -n "${_YEN_VENDOR_MANIFEST_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
_YEN_VENDOR_MANIFEST_LOADED=1

YEN_VENDOR_MANIFEST=(
    "ghostty|source|Ghostty|Terminal Engine||||||"
    "yazi|binary|Yazi|File Manager|sxyazi/yazi|yazi|15-vendor-yazi.sh|ya|true"
    "fd|binary|fd|File Finder|sharkdp/fd|fd|16-vendor-fd.sh||false"
    "ripgrep|binary|ripgrep|Content Search|BurntSushi/ripgrep|rg|17-vendor-ripgrep.sh||false"
    "lazygit|binary|lazygit|Git TUI|jesseduffield/lazygit|lazygit|32-vendor-lazygit.sh||false"
    "btop|source-built|btop|System Monitor|aristocratos/btop|btop|34-vendor-btop.sh||false"
    "fastfetch|binary|fastfetch|System Info Display|fastfetch-cli/fastfetch|fastfetch|33-vendor-fastfetch.sh||false"
    "zmx|source-built|zmx|Session Persistence|neurosnap/zmx|zmx|48-vendor-zmx.sh||false"
)

# Field index by name, 1-based to match `cut -d'|' -f<n>`.
_vendor_field_index() {
    case "$1" in
        key)               printf '1' ;;
        type)              printf '2' ;;
        title)             printf '3' ;;
        subtitle)          printf '4' ;;
        repo)              printf '5' ;;
        binary)            printf '6' ;;
        script)            printf '7' ;;
        companion)         printf '8' ;;
        require_companion) printf '9' ;;
        *)                 return 1 ;;
    esac
}

# vendor_manifest_keys [type] — newline-separated keys, in run order.
vendor_manifest_keys() {
    local want_type="${1:-}"
    local record key type
    for record in "${YEN_VENDOR_MANIFEST[@]}"; do
        key="$(printf '%s' "$record" | cut -d'|' -f1)"
        type="$(printf '%s' "$record" | cut -d'|' -f2)"
        if [ -z "$want_type" ] || [ "$type" = "$want_type" ]; then
            printf '%s\n' "$key"
        fi
    done
}

# vendor_manifest_field <key> <field> — empty output + non-zero on unknown key.
vendor_manifest_field() {
    local want_key="$1"
    local field="$2"
    local index record

    index="$(_vendor_field_index "$field")" || {
        echo "vendor_manifest_field: unknown field '$field'" >&2
        return 2
    }

    for record in "${YEN_VENDOR_MANIFEST[@]}"; do
        if [ "$(printf '%s' "$record" | cut -d'|' -f1)" = "$want_key" ]; then
            printf '%s' "$record" | cut -d'|' -f"$index"
            return 0
        fi
    done
    return 1
}

# vendor_manifest_has <key>
vendor_manifest_has() {
    vendor_manifest_field "$1" key >/dev/null 2>&1
}

# vendor_manifest_index <key> — 1-based run position, matching the "[n]" label.
vendor_manifest_index() {
    local want_key="$1"
    local position=0
    local record
    for record in "${YEN_VENDOR_MANIFEST[@]}"; do
        position=$((position + 1))
        if [ "$(printf '%s' "$record" | cut -d'|' -f1)" = "$want_key" ]; then
            printf '%s' "$position"
            return 0
        fi
    done
    return 1
}

# Derived paths. All take <repo_root> <key>.
vendor_baseline_path() {
    printf '%s/yen-terminal/.%s-baseline' "$1" "$2"
}

vendor_version_path() {
    printf '%s/yen-terminal/customizations/vendor/%s/.version' "$1" "$2"
}

vendor_binary_path() {
    local binary
    binary="$(vendor_manifest_field "$2" binary)" || return 1
    printf '%s/yen-terminal/customizations/vendor/%s/%s' "$1" "$2" "$binary"
}

vendor_script_path() {
    local script
    script="$(vendor_manifest_field "$2" script)" || return 1
    [ -n "$script" ] || return 1
    printf '%s/scripts/%s' "$1" "$script"
}

vendor_companion_path() {
    local companion
    companion="$(vendor_manifest_field "$2" companion)" || return 1
    [ -n "$companion" ] || return 1
    printf '%s/yen-terminal/customizations/vendor/%s/%s' "$1" "$2" "$companion"
}

# baseline_value <key> <baseline_file> — the value of `key=` from a baseline,
# or empty. Four near-copies existed (11-sync, 12-verify, 14-vendor and
# lib/vendor-binary.sh) with three different behaviours: 14-vendor.sh omitted
# `head -1`, so a duplicated key returned both lines concatenated, and only the
# vendor-binary.sh copy silenced a missing-file error. This is the defensive
# form; the others now delegate here.
baseline_value() {
    local key="$1"
    local file="$2"
    grep "^${key}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2-
}
