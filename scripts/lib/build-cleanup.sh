#!/bin/bash
# Cleanup helpers for checkout-owned build outputs.

# Robustly remove a directory even when a macOS daemon (Finder/mds/QuickLook)
# recreates .DS_Store mid-delete. A plain `rm -rf` empties the tree then rmdir's
# the root; if .DS_Store reappears in that window, rmdir fails with "Directory
# not empty" and — under set -e — aborts the whole build. zig-out is especially
# prone because the documented local-test step opens it in Finder. Sweep the
# metadata cruft and retry a few times before surfacing a real failure.
remove_dir_robust() {
    local target="$1" _attempt
    [ -e "$target" ] || return 0
    for _attempt in 1 2 3; do
        find "$target" -name '.DS_Store' -type f -delete 2>/dev/null || true
        rm -rf "$target" 2>/dev/null || true
        [ -e "$target" ] || return 0
        sleep 1
    done
    # Final attempt runs unguarded so a genuine (non-race) failure still aborts.
    find "$target" -name '.DS_Store' -type f -delete 2>/dev/null || true
    rm -rf "$target"
}

remove_project_derived_data() {
    local project_path="$1" derived_root="$2"
    local expected_project candidate recorded_project
    expected_project=$(cd "$project_path" && pwd -P) || return 1
    for candidate in "$derived_root"/YEN-*; do
        [ -d "$candidate" ] && [ ! -L "$candidate" ] || continue
        recorded_project=$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$candidate/info.plist" 2>/dev/null || true)
        [ -d "$recorded_project" ] || continue
        recorded_project=$(cd "$recorded_project" && pwd -P) || continue
        [ "$recorded_project" = "$expected_project" ] || continue
        remove_dir_robust "$candidate"
    done
}
