#!/bin/bash
# Shared utility for validating non-concurrency warning allowlist metadata.
#
# Used by:
#   - scripts/03-verify-components.sh (pre-build gate)

# validate_non_concurrency_allowlist_metadata ALLOWLIST_FILE FINDINGS_FILE REVIEW_DEADLINE
#
# Validates that each entry in the allowlist has owner/expiry/reason metadata.
# Also checks if the review deadline has passed with remaining entries.
# Writes findings to FINDINGS_FILE. Returns 0 always (findings checked by caller).
validate_non_concurrency_allowlist_metadata() {
    local allowlist_file="$1"
    local findings_file="$2"
    local review_deadline="$3"
    local today_iso
    today_iso=$(date +%Y-%m-%d)

    : > "$findings_file"

    if [ ! -f "$allowlist_file" ]; then
        echo "missing-allowlist|$(echo "$allowlist_file" | sed "s|$REPO_ROOT/||")" >> "$findings_file"
        return 0
    fi

    local current_owner=""
    local current_expiry=""
    local current_reason=""
    local line_no=0
    local line=""
    local trimmed=""

    while IFS= read -r line || [ -n "$line" ]; do
        line_no=$((line_no + 1))
        trimmed=$(echo "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

        case "$trimmed" in
            "")
                continue
                ;;
            \#\ owner:*)
                current_owner=$(echo "$trimmed" | sed 's/^# owner:[[:space:]]*//')
                continue
                ;;
            \#\ expiry:*)
                current_expiry=$(echo "$trimmed" | sed 's/^# expiry:[[:space:]]*//')
                continue
                ;;
            \#\ reason:*)
                current_reason=$(echo "$trimmed" | sed 's/^# reason:[[:space:]]*//')
                continue
                ;;
            \#*)
                continue
                ;;
        esac

        [ -z "$current_owner" ] && echo "metadata-missing-owner|line=$line_no|$trimmed" >> "$findings_file"
        [ -z "$current_expiry" ] && echo "metadata-missing-expiry|line=$line_no|$trimmed" >> "$findings_file"
        [ -z "$current_reason" ] && echo "metadata-missing-reason|line=$line_no|$trimmed" >> "$findings_file"

        if [ -n "$current_expiry" ]; then
            if ! echo "$current_expiry" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
                echo "metadata-invalid-expiry|line=$line_no|expiry=$current_expiry|$trimmed" >> "$findings_file"
            elif [ "$current_expiry" \< "$today_iso" ]; then
                echo "metadata-expired|line=$line_no|expiry=$current_expiry|$trimmed" >> "$findings_file"
            fi
        fi

        current_owner=""
        current_expiry=""
        current_reason=""
    done < "$allowlist_file"

    if [ "$today_iso" \> "$review_deadline" ] || [ "$today_iso" = "$review_deadline" ]; then
        local regex_count=0
        # An empty allowlist is the goal state: grep exits 1 on no match, which
        # aborts callers running under `set -o pipefail`, so tolerate it here.
        regex_count=$({ grep -Ev '^[[:space:]]*(#|$)' "$allowlist_file" || true; } | wc -l | tr -d '[:space:]')
        if [ "$regex_count" -gt 0 ]; then
            echo "review-window-expired|deadline=$review_deadline|remaining_entries=$regex_count" >> "$findings_file"
        fi
    fi
}
