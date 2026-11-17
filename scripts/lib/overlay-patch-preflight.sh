#!/bin/bash
# Validate every target before applying any post-copy patch.

verify_overlay_patch_targets() {
    local manifest="$1"
    if [ ! -s "$manifest" ]; then
        echo "  ERROR: patch-target manifest missing or empty: $manifest" >&2
        return 1
    fi
    local patch_target total=0 missing=0 seen=$'\n'
    while IFS= read -r patch_target || [ -n "$patch_target" ]; do
        case "$patch_target" in
            ''|\#*) continue ;;
        esac
        case "$seen" in
            *$'\n'"$patch_target"$'\n'*)
                echo "  ERROR: duplicate patch target: $patch_target" >&2
                return 1
                ;;
        esac
        seen="${seen}${patch_target}"$'\n'
        total=$((total + 1))
        if [ ! -f "$patch_target" ]; then
            if [ "$missing" -eq 0 ]; then
                echo "  ERROR: upstream patch targets missing after branding — upstream moved or renamed them:"
            fi
            echo "    $patch_target"
            missing=$((missing + 1))
        fi
    done < "$manifest"
    if [ "$total" -eq 0 ]; then
        echo "  ERROR: patch-target manifest contains no targets: $manifest" >&2
        return 1
    fi
    if [ "$missing" -gt 0 ]; then
        echo "  ${missing} of ${total} patch targets could not be resolved."
        echo "  Re-anchor the affected patches and update $manifest, then re-run the vendor bump."
        return 1
    fi
    printf '    Patch-target preflight: verified %s targets\n' "$total"
}
