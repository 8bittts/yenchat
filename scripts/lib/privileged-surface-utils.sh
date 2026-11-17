#!/bin/bash
# Shared utility for snapshotting the privileged-action surface of
# yen-cli/bin/yen + IntentPermission.swift and diffing against baseline.
#
# Used by:
#   - scripts/03-verify-components.sh (pre-build gate)

# snapshot_privileged_action_surface OUTPUT_FILE CLI_PATH APP_INTENT_PERMISSION_PATH
#
# Writes a sorted, deduplicated surface snapshot to OUTPUT_FILE.
# Callers diff the result against the baseline to detect drift.
snapshot_privileged_action_surface() {
    local output_file="$1"
    local cli_path="$2"
    local app_intent_permission_path="$3"

    : > "$output_file"

    if [ ! -f "$cli_path" ]; then
        echo "missing-cli-entrypoint|$cli_path" >> "$output_file"
    else
        awk '
            /commands\+\=\(/ {
                if ($0 !~ /help[[:space:]]+version[[:space:]]+init/) {
                    next
                }
                line=$0
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
                print "cli-builtins:" line
            }
            /case "\$cmd" in/ { in_case = 1; next }
            in_case && /^[[:space:]]*esac/ { in_case = 0 }
            in_case {
                if ($0 ~ /^[[:space:]]*[A-Za-z0-9_|-]+\)/) {
                    labels = $0
                    sub(/^[[:space:]]*/, "", labels)
                    sub(/\).*/, "", labels)
                    action = ""
                    next
                }
                if (labels == "") {
                    next
                }
                if ($0 ~ /route_command "[^"]+"/) {
                    action = $0
                    sub(/.*route_command "/, "", action)
                    sub(/".*/, "", action)
                    gsub(/[[:space:]]/, "", action)
                    action = "route:" action
                } else if ($0 ~ /show_usage/) {
                    action = "show-usage"
                } else if ($0 ~ /show_version/) {
                    action = "show-version"
                } else if ($0 ~ /show_init/) {
                    action = "show-init"
                } else if ($0 ~ /suggest_command/) {
                    action = "suggest-command"
                } else if ($0 ~ /show_command_help/) {
                    action = "show-command-help"
                }

                if ($0 ~ /;;/) {
                    if (labels != "-h|--help|help" && labels != "-v|--version|version" && labels != "*" && action != "") {
                        split(labels, arr, /\|/)
                        for (i in arr) {
                            cmd = arr[i]
                            if (cmd == "") {
                                continue
                            }
                            print "cli-case:" cmd "->" action
                        }
                    }
                    labels = ""
                    action = ""
                }
            }
        ' "$cli_path" >> "$output_file"
    fi

    if [ ! -f "$app_intent_permission_path" ]; then
        echo "missing-app-intents-policy|$app_intent_permission_path" >> "$output_file"
    else
        awk '
            /^enum IntentPermissionScope:/ { in_scope = 1; next }
            in_scope && /^[[:space:]]*}/ { in_scope = 0 }
            in_scope && /^[[:space:]]*case[[:space:]]+[a-zA-Z0-9_]+/ {
                scope=$0
                sub(/^[[:space:]]*case[[:space:]]+/, "", scope)
                sub(/[^a-zA-Z0-9_].*$/, "", scope)
                print "app-intent-scope:" scope
            }
            /let blockedActions: Set<String> = \[/ { in_blocked = 1; next }
            in_blocked && /\]/ { in_blocked = 0; next }
            in_blocked {
                gsub(/"/, "", $0)
                gsub(/,/, "", $0)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
                if ($0 != "") {
                    print "app-intent-blocked-action:" $0
                }
            }
        ' "$app_intent_permission_path" >> "$output_file"
        if grep -Fq 'guard !normalized.hasPrefix("+")' "$app_intent_permission_path"; then
            echo "app-intent-guard:deny-plus-prefix" >> "$output_file"
        fi
    fi

    LC_ALL=C sort -u "$output_file" -o "$output_file"
}

# diff_privileged_action_surface SNAPSHOT_FILE BASELINE_FILE
#
# Returns 0 if surface matches baseline, 1 if drift detected.
# On drift, prints the diff summary to stdout.
diff_privileged_action_surface() {
    local snapshot_file="$1"
    local baseline_file="$2"
    local baseline_normalized
    local diff_output

    baseline_normalized=$(mktemp)
    diff_output=$(mktemp)

    grep -Ev '^[[:space:]]*(#|$)' "$baseline_file" | LC_ALL=C sort -u > "$baseline_normalized"

    if ! diff -u "$baseline_normalized" "$snapshot_file" > "$diff_output" 2>&1; then
        cat "$diff_output"
        rm -f "$baseline_normalized" "$diff_output"
        return 1
    fi

    rm -f "$baseline_normalized" "$diff_output"
    return 0
}
