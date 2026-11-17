#!/bin/bash
# Remove only declared, retired files from the generated vendor tree.

remove_overlay_retired_files() {
    local group="$1" manifest="${2:-$REPO_ROOT/scripts/lib/overlay-data/retired-paths.tsv}"
    local entry_group path count=0
    if [ ! -s "$manifest" ]; then
        echo "  ERROR: Retired-path manifest missing or empty: $manifest" >&2
        return 1
    fi
    while IFS="$(printf '\t')" read -r entry_group path || [ -n "$entry_group" ]; do
        [ "$entry_group" = "$group" ] || continue
        case "$path" in
            *'/../'*|*'/..'|ghostty/) echo "  ERROR: Invalid retired path: $path" >&2; return 1 ;;
            ghostty/*) ;;
            *) echo "  ERROR: Invalid retired path: $path" >&2; return 1 ;;
        esac
        rm -f -- "$path"
        count=$((count + 1))
    done < "$manifest"
    if [ "$count" -eq 0 ]; then
        echo "  ERROR: No retired paths declared for $group" >&2
        return 1
    fi
    echo "    Retired files: checked $count paths for $group"
}
