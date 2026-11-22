#!/bin/bash
# Shared git-review tooling helpers for bundled lazygit resolution.

YEN_GIT_REVIEW_LAZYGIT_BIN="${YEN_RESOURCES}/bin/lazygit"
YEN_GIT_REVIEW_DEV_LAZYGIT_BIN="${YEN_RESOURCES}/../yen-terminal/customizations/vendor/lazygit/lazygit"
YEN_GIT_REVIEW_LAZYGIT_CONFIG="${YEN_RESOURCES}/yen/lazygit/config.yml"

if [[ ! -f "${YEN_GIT_REVIEW_LAZYGIT_CONFIG}" ]]; then
    YEN_GIT_REVIEW_DEV_LAZYGIT_CONFIG="${YEN_RESOURCES}/../yen-terminal/customizations/lazygit/config.yml"
    if [[ -f "${YEN_GIT_REVIEW_DEV_LAZYGIT_CONFIG}" ]]; then
        YEN_GIT_REVIEW_LAZYGIT_CONFIG="${YEN_GIT_REVIEW_DEV_LAZYGIT_CONFIG}"
    fi
fi

yen_git_review_resolve_binary() {
    local bundled_binary="$1"
    local dev_binary="$2"
    local system_binary="$3"

    if [[ -x "${bundled_binary}" ]]; then
        printf "%s" "${bundled_binary}"
        return 0
    fi

    if [[ -x "${dev_binary}" ]]; then
        printf "%s" "${dev_binary}"
        return 0
    fi

    if [[ "${YEN_ALLOW_SYSTEM_BIN_FALLBACK:-}" == "1" ]] && command -v "${system_binary}" >/dev/null 2>&1; then
        command -v "${system_binary}"
        return 0
    fi

    return 1
}

yen_git_review_resolve_lazygit_binary() {
    yen_git_review_resolve_binary \
        "${YEN_GIT_REVIEW_LAZYGIT_BIN}" \
        "${YEN_GIT_REVIEW_DEV_LAZYGIT_BIN}" \
        "lazygit"
}

yen_git_review_build_lazygit_config_files_arg() {
    local lazygit_exec="$1"
    local config_files=""

    if [[ -f "${YEN_GIT_REVIEW_LAZYGIT_CONFIG}" ]]; then
        local config_dir=""
        config_dir=$("${lazygit_exec}" --print-config-dir 2>/dev/null || true)
        if [[ -n "${config_dir}" && -f "${config_dir}/config.yml" ]]; then
            # Keep user customizations, then enforce YEN overrides.
            config_files="${config_dir}/config.yml,${YEN_GIT_REVIEW_LAZYGIT_CONFIG}"
        else
            config_files="${YEN_GIT_REVIEW_LAZYGIT_CONFIG}"
        fi
    fi

    printf "%s" "${config_files}"
}

yen_git_review_run_lazygit() {
    local lazygit_exec="$1"
    shift
    local config_files=""
    config_files=$(yen_git_review_build_lazygit_config_files_arg "${lazygit_exec}")

    if [[ -n "${config_files}" ]]; then
        exec "${lazygit_exec}" --use-config-file "${config_files}" "$@"
    fi

    exec "${lazygit_exec}" "$@"
}

yen_git_review_render_diff_stream() {
    if [[ -t 1 ]] && command -v less >/dev/null 2>&1; then
        less -R
        return $?
    fi

    cat
}

yen_git_review_show_diff_text() {
    local diff_text="$1"
    printf "%s\n" "${diff_text}" | yen_git_review_render_diff_stream
}

yen_git_review_parse_location_ref() {
    local ref="$1"
    if [[ "${ref}" =~ ^(.+):([0-9]+):([0-9]+)$ ]]; then
        printf "%s\t%s\t%s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
        return 0
    fi
    if [[ "${ref}" =~ ^(.+):([0-9]+)$ ]]; then
        printf "%s\t%s\t1\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

yen_git_review_emit_hunk_rows() {
    local target_file="${1:-}"
    awk -v target="${target_file}" '
        function normalize_path(value) {
            sub(/^a\//, "", value)
            sub(/^b\//, "", value)
            return value
        }
        function parse_count(raw) {
            if (raw == "") {
                return 1
            }
            return raw + 0
        }
        function clamp_line(value) {
            if (value < 1) {
                return 1
            }
            return value
        }
        function emit_pending_hunk(    location_line) {
            if (!pending_open || pending_file == "") {
                return
            }
            location_line = clamp_line(pending_location_line)
            if (!pending_addition_found && pending_deletion_found) {
                if (pending_new_count > 0) {
                    location_line = pending_deletion_new_line
                    if (location_line < pending_new_start) {
                        location_line = pending_new_start
                    }
                    if (location_line >= pending_new_start + pending_new_count) {
                        location_line = pending_new_start + pending_new_count - 1
                    }
                    location_line = clamp_line(location_line)
                } else {
                    location_line = clamp_line(pending_deletion_line)
                }
            }
            printf "%s\t%d\t%d\t%d\t%d\t%d\t%s:%d:1\t%s\n", pending_file, pending_hunk_index, pending_old_start, pending_old_count, pending_new_start, pending_new_count, pending_file, location_line, pending_header
            pending_open = 0
        }
        function parse_hunk_header(line,    body, marker_pos, range_part, context_part, comma_pos, old_range, new_range) {
            if (index(line, "@@ -") != 1) {
                return 0
            }
            body = line
            sub(/^@@ -/, "", body)
            marker_pos = index(body, " @@")
            if (marker_pos == 0) {
                return 0
            }
            range_part = substr(body, 1, marker_pos - 1)
            context_part = substr(body, marker_pos + 3)

            old_range = range_part
            sub(/ \+.*/, "", old_range)
            new_range = range_part
            sub(/^.* \+/, "", new_range)

            parsed_old_start = old_range
            parsed_old_count = ""
            comma_pos = index(old_range, ",")
            if (comma_pos > 0) {
                parsed_old_start = substr(old_range, 1, comma_pos - 1)
                parsed_old_count = substr(old_range, comma_pos + 1)
            }

            parsed_new_start = new_range
            parsed_new_count = ""
            comma_pos = index(new_range, ",")
            if (comma_pos > 0) {
                parsed_new_start = substr(new_range, 1, comma_pos - 1)
                parsed_new_count = substr(new_range, comma_pos + 1)
            }

            parsed_old_start += 0
            parsed_old_count = parse_count(parsed_old_count)
            parsed_new_start += 0
            parsed_new_count = parse_count(parsed_new_count)
            parsed_header = "@@ -" range_part " @@" context_part
            return 1
        }
        BEGIN {
            current_file = ""
            current_match = 0
            hunk_index = 0
            pending_open = 0
        }
        {
            if (index($0, "diff --git ") == 1) {
                emit_pending_hunk()
                old_path = normalize_path($3)
                new_path = normalize_path($4)
                current_file = new_path
                if (current_file == "") {
                    current_file = old_path
                }
                current_match = (target == "" || old_path == target || new_path == target)
                hunk_index = 0
                next
            }

            if (!current_match) {
                next
            }

            if (parse_hunk_header($0)) {
                emit_pending_hunk()
                hunk_index += 1
                pending_open = 1
                pending_file = current_file
                pending_hunk_index = hunk_index
                pending_old_start = parsed_old_start
                pending_old_count = parsed_old_count
                pending_new_start = parsed_new_start
                pending_new_count = parsed_new_count
                pending_header = parsed_header
                gsub(/\t/, "    ", pending_header)
                pending_location_line = pending_new_start
                if (pending_new_count == 0) {
                    pending_location_line = pending_old_start
                }
                pending_addition_found = 0
                pending_deletion_found = 0
                pending_deletion_line = pending_old_start
                pending_deletion_new_line = pending_new_start
                current_old_line = pending_old_start
                current_new_line = pending_new_start
                next
            }

            if (!pending_open) {
                next
            }

            if (!pending_addition_found && index($0, "+") == 1) {
                pending_location_line = current_new_line
                pending_addition_found = 1
            }
            if (!pending_deletion_found && index($0, "-") == 1) {
                pending_deletion_line = current_old_line
                pending_deletion_new_line = current_new_line
                pending_deletion_found = 1
            }

            if (index($0, " ") == 1) {
                current_old_line += 1
                current_new_line += 1
            } else if (index($0, "+") == 1) {
                current_new_line += 1
            } else if (index($0, "-") == 1) {
                current_old_line += 1
            }
        }
        END {
            emit_pending_hunk()
        }
    '
}

yen_git_review_find_hunk_row_for_line() {
    local target_file="$1"
    local target_line="$2"
    awk -F '\t' -v target_file="${target_file}" -v target_line="${target_line}" '
        function matches(old_start, old_count, new_start, new_count, requested) {
            if (new_count > 0) {
                return (requested >= new_start && requested < (new_start + new_count))
            }
            if (old_count > 0) {
                return requested == old_start
            }
            return 0
        }
        BEGIN {
            found = 0
        }
        $1 == target_file {
            old_start = $3 + 0
            old_count = $4 + 0
            new_start = $5 + 0
            new_count = $6 + 0
            if (matches(old_start, old_count, new_start, new_count, target_line + 0)) {
                found = 1
                print $0
                exit 0
            }
        }
        END {
            if (!found) {
                exit 1
            }
        }
    '
}

yen_git_review_extract_hunk_from_file_diff() {
    local target_line="$1"
    awk -v target_line="${target_line}" '
        function parse_count(raw) {
            if (raw == "") {
                return 1
            }
            return raw + 0
        }
        function matches(old_start, old_count, new_start, new_count, requested) {
            if (new_count > 0) {
                return (requested >= new_start && requested < (new_start + new_count))
            }
            if (old_count > 0) {
                return requested == old_start
            }
            return 0
        }
        function parse_hunk_header(line,    body, marker_pos, range_part, comma_pos, old_range, new_range) {
            if (index(line, "@@ -") != 1) {
                return 0
            }
            body = line
            sub(/^@@ -/, "", body)
            marker_pos = index(body, " @@")
            if (marker_pos == 0) {
                return 0
            }
            range_part = substr(body, 1, marker_pos - 1)

            old_range = range_part
            sub(/ \+.*/, "", old_range)
            new_range = range_part
            sub(/^.* \+/, "", new_range)

            parsed_old_start = old_range
            parsed_old_count = ""
            comma_pos = index(old_range, ",")
            if (comma_pos > 0) {
                parsed_old_start = substr(old_range, 1, comma_pos - 1)
                parsed_old_count = substr(old_range, comma_pos + 1)
            }

            parsed_new_start = new_range
            parsed_new_count = ""
            comma_pos = index(new_range, ",")
            if (comma_pos > 0) {
                parsed_new_start = substr(new_range, 1, comma_pos - 1)
                parsed_new_count = substr(new_range, comma_pos + 1)
            }

            parsed_old_start += 0
            parsed_old_count = parse_count(parsed_old_count)
            parsed_new_start += 0
            parsed_new_count = parse_count(parsed_new_count)
            return 1
        }
        BEGIN {
            preamble_count = 0
            printing = 0
            emitted = 0
            seen_hunk = 0
        }
        {
            if (parse_hunk_header($0)) {
                seen_hunk = 1
                if (printing == 1) {
                    exit 0
                }
                old_start = parsed_old_start
                old_count = parsed_old_count
                new_start = parsed_new_start
                new_count = parsed_new_count
                if (matches(old_start, old_count, new_start, new_count, target_line + 0)) {
                    emitted = 1
                    printing = 1
                    for (idx = 1; idx <= preamble_count; idx++) {
                        print preamble[idx]
                    }
                    print $0
                } else {
                    printing = 0
                }
                next
            }

            if (printing == 1) {
                print
                next
            }

            if (emitted == 0 && seen_hunk == 0) {
                preamble_count += 1
                preamble[preamble_count] = $0
            }
        }
        END {
            if (!emitted) {
                exit 1
            }
        }
    '
}

yen_git_review_print_hunk_rows_table() {
    local rows="$1"
    printf "%-40s %-4s %-22s %s\n" "FILE" "HUNK" "LOCATION" "HEADER"
    printf "%-40s %-4s %-22s %s\n" "----" "----" "--------" "------"

    if [[ -z "${rows}" ]]; then
        return 0
    fi

    local file_path=""
    local hunk_index=""
    local old_start=""
    local old_count=""
    local new_start=""
    local new_count=""
    local location=""
    local header=""
    while IFS=$'\t' read -r file_path hunk_index old_start old_count new_start new_count location header; do
        [[ -n "${file_path}" ]] || continue
        printf "%-40s %-4s %-22s %s\n" "${file_path}" "${hunk_index}" "${location}" "${header}"
    done << EOF
${rows}
EOF
}
