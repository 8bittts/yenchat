# shellcheck shell=bash
# Source-time pure editor handoff planner shared by yen ide + bundled wrappers.

declare -a EDITOR_HANDOFF_EDITOR_ARGV=()
declare -a EDITOR_HANDOFF_COMMAND_ARGV=()
declare -a EDITOR_HANDOFF_SPLIT_ARGV=()

EDITOR_HANDOFF_EDITOR_BIN=""
EDITOR_HANDOFF_EDITOR_NAME=""
EDITOR_HANDOFF_EDITOR_APP_NAME=""
EDITOR_HANDOFF_FAMILY=""
EDITOR_HANDOFF_ABSOLUTE_PATH=""
EDITOR_HANDOFF_DISPLAY_PATH=""
EDITOR_HANDOFF_LINE=""
EDITOR_HANDOFF_COLUMN=""
EDITOR_HANDOFF_LOCATION=""
EDITOR_HANDOFF_LINE_AWARE="0"
EDITOR_HANDOFF_WAIT_APPLIED="0"
EDITOR_HANDOFF_EXECUTABLE_PATH=""
EDITOR_HANDOFF_NOTE=""

editor_handoff_reset_state() {
    EDITOR_HANDOFF_EDITOR_ARGV=()
    EDITOR_HANDOFF_COMMAND_ARGV=()
    EDITOR_HANDOFF_EDITOR_BIN=""
    EDITOR_HANDOFF_EDITOR_NAME=""
    EDITOR_HANDOFF_EDITOR_APP_NAME=""
    EDITOR_HANDOFF_FAMILY=""
    EDITOR_HANDOFF_ABSOLUTE_PATH=""
    EDITOR_HANDOFF_DISPLAY_PATH=""
    EDITOR_HANDOFF_LINE=""
    EDITOR_HANDOFF_COLUMN=""
    EDITOR_HANDOFF_LOCATION=""
    EDITOR_HANDOFF_LINE_AWARE="0"
    EDITOR_HANDOFF_WAIT_APPLIED="0"
    EDITOR_HANDOFF_EXECUTABLE_PATH=""
    EDITOR_HANDOFF_NOTE=""
}

editor_handoff_shell_quote() {
    printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\"'\"'/g")"
}

editor_handoff_default_command() {
    if [[ -n "${VISUAL:-}" ]]; then
        printf "%s\n" "${VISUAL}"
        return 0
    fi
    if [[ -n "${EDITOR:-}" ]]; then
        printf "%s\n" "${EDITOR}"
        return 0
    fi
    printf "vi\n"
}

editor_handoff_split_command() {
    local command_text="$1"
    local parsed_lines=""
    local token=""

    EDITOR_HANDOFF_SPLIT_ARGV=()

    if [[ -z "${command_text}" ]]; then
        return 1
    fi

    parsed_lines=$(python3 - "${command_text}" <<'PY'
import shlex
import sys

command_text = sys.argv[1]
try:
    argv = shlex.split(command_text, posix=True)
except ValueError:
    raise SystemExit(1)

if not argv:
    raise SystemExit(1)

for arg in argv:
    print(arg)
PY
) || return 1

    while IFS= read -r token || [[ -n "${token}" ]]; do
        EDITOR_HANDOFF_SPLIT_ARGV+=("${token}")
    done <<EOF
${parsed_lines}
EOF

    [[ "${#EDITOR_HANDOFF_SPLIT_ARGV[@]}" -gt 0 ]] || return 1
    return 0
}

editor_handoff_parse_editor_argv() {
    local editor_cmd="$1"
    local app_name=""

    if [[ -z "${editor_cmd}" ]]; then
        editor_cmd=$(editor_handoff_default_command)
    fi

    if ! editor_handoff_split_command "${editor_cmd}"; then
        EDITOR_HANDOFF_NOTE="Unable to parse editor command: ${editor_cmd}"
        return 1
    fi

    EDITOR_HANDOFF_EDITOR_ARGV=("${EDITOR_HANDOFF_SPLIT_ARGV[@]}")
    EDITOR_HANDOFF_EDITOR_BIN="${EDITOR_HANDOFF_EDITOR_ARGV[0]}"
    EDITOR_HANDOFF_EDITOR_NAME="${EDITOR_HANDOFF_EDITOR_BIN##*/}"
    app_name=$(editor_handoff_open_application_name "${EDITOR_HANDOFF_EDITOR_ARGV[@]}" || true)
    EDITOR_HANDOFF_EDITOR_APP_NAME="${app_name}"
    return 0
}

editor_handoff_family_for_command() {
    local command_name="$1"
    local lower_name=""

    lower_name=$(printf "%s" "${command_name}" | tr '[:upper:]' '[:lower:]')
    case "${lower_name}" in
        code|code-insiders|cursor|windsurf|codium|vscode|visual\ studio\ code*|vscodium*)
            printf "code-family\n"
            ;;
        zed|zeditor|zed\ *)
            printf "zed\n"
            ;;
        xed|xcode|xcode\ *)
            printf "xcode\n"
            ;;
        hx|helix)
            printf "helix\n"
            ;;
        nvim|nvr|vim|vi)
            printf "vim-family\n"
            ;;
        micro)
            printf "micro\n"
            ;;
        *)
            printf "plain\n"
            ;;
    esac
}

editor_handoff_open_application_name() {
    local argv=("$@")
    local command_name=""
    local idx=1
    local count="${#argv[@]}"
    local lower_name=""

    [[ "${count}" -gt 0 ]] || return 1
    command_name="${argv[0]##*/}"
    lower_name=$(printf "%s" "${command_name}" | tr '[:upper:]' '[:lower:]')
    if [[ "${lower_name}" != "open" ]]; then
        return 1
    fi

    while [[ "${idx}" -lt "${count}" ]]; do
        if [[ "${argv[$idx]}" == "-a" ]]; then
            idx=$((idx + 1))
            if [[ "${idx}" -ge "${count}" ]]; then
                return 1
            fi
            printf "%s\n" "${argv[$idx]}"
            return 0
        fi
        idx=$((idx + 1))
    done

    return 1
}

editor_handoff_family_for_editor() {
    local command_name="$1"
    local app_name="$2"

    if [[ -n "${app_name}" ]]; then
        editor_handoff_family_for_command "${app_name}"
        return 0
    fi

    editor_handoff_family_for_command "${command_name}"
}

editor_handoff_is_open_application_launcher() {
    local lower_name=""

    lower_name=$(printf "%s" "${EDITOR_HANDOFF_EDITOR_NAME}" | tr '[:upper:]' '[:lower:]')
    [[ -n "${EDITOR_HANDOFF_EDITOR_APP_NAME}" ]] || return 1
    [[ "${lower_name}" == "open" ]]
}

editor_handoff_argv_contains() {
    local needle="$1"
    shift
    local arg=""

    for arg in "$@"; do
        if [[ "${arg}" == "${needle}" ]]; then
            return 0
        fi
    done

    return 1
}

editor_handoff_parse_target() {
    local raw_target="$1"
    local anchor_root="$2"
    local parsed=""

    if [[ -z "${raw_target}" ]]; then
        return 1
    fi
    if [[ -z "${anchor_root}" ]]; then
        anchor_root="${PWD}"
    fi

    parsed=$(python3 - "${raw_target}" "${anchor_root}" <<'PY'
import os
import re
import sys

raw_target = sys.argv[1]
anchor_root = os.path.abspath(sys.argv[2] or os.getcwd())
cwd = os.path.abspath(os.getcwd())


def candidate_exists(path_text: str) -> bool:
    if not path_text:
        return False
    if os.path.isabs(path_text):
        return os.path.exists(path_text)
    return os.path.exists(os.path.join(cwd, path_text)) or os.path.exists(os.path.join(anchor_root, path_text))


def resolve_path(path_text: str) -> str:
    if os.path.isabs(path_text):
        return os.path.abspath(path_text)
    cwd_candidate = os.path.abspath(os.path.join(cwd, path_text))
    anchor_candidate = os.path.abspath(os.path.join(anchor_root, path_text))
    if os.path.exists(cwd_candidate):
        return cwd_candidate
    if os.path.exists(anchor_candidate):
        return anchor_candidate
    if anchor_root and anchor_root != cwd:
        return anchor_candidate
    return cwd_candidate


line = ""
column = ""
path_text = raw_target

if not candidate_exists(raw_target):
    match = re.match(r"^(.*?):([0-9]+)(?::([0-9]+))?$", raw_target)
    if match and match.group(1):
        path_text = match.group(1)
        line = match.group(2)
        column = match.group(3) or "1"

absolute_path = resolve_path(path_text)
if not os.path.exists(absolute_path):
    sys.exit(1)
if line and int(line) < 1:
    sys.exit(1)
if column and int(column) < 1:
    sys.exit(1)
display_path = path_text if not os.path.isabs(path_text) else absolute_path
location = absolute_path
if line:
    location = f"{absolute_path}:{line}:{column}" if column else f"{absolute_path}:{line}"

print("\t".join([absolute_path, display_path, line, column, location]))
PY
) || {
        EDITOR_HANDOFF_NOTE="Invalid editor target: ${raw_target}"
        return 1
    }

    IFS=$'\t' read -r EDITOR_HANDOFF_ABSOLUTE_PATH EDITOR_HANDOFF_DISPLAY_PATH EDITOR_HANDOFF_LINE EDITOR_HANDOFF_COLUMN EDITOR_HANDOFF_LOCATION << EOF
${parsed}
EOF

    if [[ -z "${EDITOR_HANDOFF_ABSOLUTE_PATH}" ]]; then
        return 1
    fi

    return 0
}

editor_handoff_resolve_executable() {
    local command_name="$1"
    local resolved=""

    if [[ -z "${command_name}" ]]; then
        return 1
    fi

    if [[ "${command_name}" == */* ]]; then
        [[ -x "${command_name}" ]] || return 1
        printf "%s\n" "${command_name}"
        return 0
    fi

    resolved=$(command -v "${command_name}" 2>/dev/null) || return 1
    [[ -n "${resolved}" ]] || return 1
    printf "%s\n" "${resolved}"
}

editor_handoff_has_running_neovim_server() {
    [[ -n "${NVIM:-}" ]] && return 0
    [[ -n "${NVIM_LISTEN_ADDRESS:-}" ]] && return 0
    return 1
}

editor_handoff_finalize_command_plan() {
    local executable_name=""
    local executable_path=""

    executable_name="${EDITOR_HANDOFF_COMMAND_ARGV[0]:-}"
    executable_path=$(editor_handoff_resolve_executable "${executable_name}") || {
        EDITOR_HANDOFF_NOTE="Configured editor launcher is unavailable: ${executable_name}"
        return 1
    }
    EDITOR_HANDOFF_EXECUTABLE_PATH="${executable_path}"
    return 0
}

editor_handoff_command_text() {
    local argv=("$@")
    local rendered=""
    local arg=""

    for arg in "${argv[@]}"; do
        if [[ -n "${rendered}" ]]; then
            rendered="${rendered} "
        fi
        rendered="${rendered}$(editor_handoff_shell_quote "${arg}")"
    done

    printf "%s\n" "${rendered}"
}

editor_handoff_build_plan() {
    local raw_target="$1"
    local anchor_root="$2"
    local editor_override="$3"
    local wait_requested="${4:-0}"
    local family=""
    local path=""
    local location=""
    local line=""
    local column=""
    local goto_suffix=""
    local plan=()

    editor_handoff_reset_state
    editor_handoff_parse_target "${raw_target}" "${anchor_root}" || return 1
    editor_handoff_parse_editor_argv "${editor_override}" || return 1

    if [[ "${EDITOR_HANDOFF_EDITOR_NAME}" == "nvr" ]] && ! editor_handoff_has_running_neovim_server; then
        if editor_handoff_resolve_executable "nvim" >/dev/null 2>&1; then
            EDITOR_HANDOFF_EDITOR_ARGV[0]="nvim"
            EDITOR_HANDOFF_EDITOR_BIN="nvim"
            EDITOR_HANDOFF_EDITOR_NAME="nvim"
            EDITOR_HANDOFF_NOTE="nvr is configured but no running Neovim server was detected; falling back to nvim."
        else
            EDITOR_HANDOFF_NOTE="nvr is configured but no running Neovim server was detected, and nvim is unavailable."
            return 1
        fi
    fi

    family=$(editor_handoff_family_for_editor "${EDITOR_HANDOFF_EDITOR_NAME}" "${EDITOR_HANDOFF_EDITOR_APP_NAME}")
    EDITOR_HANDOFF_FAMILY="${family}"
    path="${EDITOR_HANDOFF_ABSOLUTE_PATH}"
    location="${EDITOR_HANDOFF_LOCATION}"
    line="${EDITOR_HANDOFF_LINE}"
    column="${EDITOR_HANDOFF_COLUMN:-1}"
    plan=("${EDITOR_HANDOFF_EDITOR_ARGV[@]}")

    case "${family}" in
        code-family)
            if editor_handoff_is_open_application_launcher && [[ "${wait_requested}" == "1" || -n "${line}" ]]; then
                if ! editor_handoff_argv_contains "--args" "${plan[@]}"; then
                    plan+=("--args")
                fi
            fi
            if [[ "${wait_requested}" == "1" ]]; then
                plan+=("--wait")
                EDITOR_HANDOFF_WAIT_APPLIED="1"
            fi
            if [[ -n "${line}" ]]; then
                EDITOR_HANDOFF_LINE_AWARE="1"
                plan+=("--goto" "${location}")
            else
                plan+=("${path}")
            fi
            ;;
        zed)
            if editor_handoff_is_open_application_launcher && [[ "${wait_requested}" == "1" || -n "${line}" ]]; then
                if ! editor_handoff_argv_contains "--args" "${plan[@]}"; then
                    plan+=("--args")
                fi
            fi
            if [[ "${wait_requested}" == "1" ]]; then
                plan+=("--wait")
                EDITOR_HANDOFF_WAIT_APPLIED="1"
            fi
            if [[ -n "${line}" ]]; then
                EDITOR_HANDOFF_LINE_AWARE="1"
                plan+=("${location}")
            else
                plan+=("${path}")
            fi
            ;;
        xcode)
            plan=("xed")
            if [[ "${wait_requested}" == "1" ]]; then
                plan+=("--wait")
                EDITOR_HANDOFF_WAIT_APPLIED="1"
            fi
            if [[ -n "${line}" ]]; then
                EDITOR_HANDOFF_LINE_AWARE="1"
                plan+=("--line" "${line}")
            fi
            plan+=("${path}")
            ;;
        helix)
            if [[ -n "${line}" ]]; then
                EDITOR_HANDOFF_LINE_AWARE="1"
                plan+=("${path}:${line}:${column}")
            else
                plan+=("${path}")
            fi
            ;;
        vim-family)
            if [[ -n "${line}" ]]; then
                EDITOR_HANDOFF_LINE_AWARE="1"
                goto_suffix="+call cursor(${line},${column})"
                plan+=("${goto_suffix}" "${path}")
            else
                plan+=("--" "${path}")
            fi
            ;;
        micro)
            plan+=("-ruler" "false" "-softwrap" "true" "-wordwrap" "true")
            if [[ -n "${line}" ]]; then
                EDITOR_HANDOFF_LINE_AWARE="1"
                plan+=("${path}" "+${line}:${column}")
            else
                plan+=("--" "${path}")
            fi
            ;;
        *)
            if [[ -n "${line}" ]]; then
                EDITOR_HANDOFF_NOTE="Editor does not expose a recognized line-aware CLI; opening the resolved file path only."
            fi
            plan+=("--" "${path}")
            ;;
    esac

    EDITOR_HANDOFF_COMMAND_ARGV=("${plan[@]}")
    editor_handoff_finalize_command_plan || return 1
    return 0
}

editor_handoff_payload_json() {
    local raw_target="$1"
    local anchor_root="$2"
    local editor_override="$3"
    local wait_requested="$4"
    local argv_json=""
    local command_text=""

    argv_json=$(python3 - "${EDITOR_HANDOFF_COMMAND_ARGV[@]}" <<'PY'
import json
import sys

print(json.dumps(sys.argv[1:]))
PY
)
    command_text=$(editor_handoff_command_text "${EDITOR_HANDOFF_COMMAND_ARGV[@]}")

    EDITOR_HANDOFF_RAW_TARGET="${raw_target}" \
    EDITOR_HANDOFF_ANCHOR_ROOT="${anchor_root}" \
    EDITOR_HANDOFF_EDITOR_OVERRIDE="${editor_override}" \
    EDITOR_HANDOFF_WAIT_REQUESTED="${wait_requested}" \
    EDITOR_HANDOFF_ABSOLUTE_PATH="${EDITOR_HANDOFF_ABSOLUTE_PATH}" \
    EDITOR_HANDOFF_DISPLAY_PATH="${EDITOR_HANDOFF_DISPLAY_PATH}" \
    EDITOR_HANDOFF_LINE="${EDITOR_HANDOFF_LINE}" \
    EDITOR_HANDOFF_COLUMN="${EDITOR_HANDOFF_COLUMN}" \
    EDITOR_HANDOFF_LOCATION="${EDITOR_HANDOFF_LOCATION}" \
    EDITOR_HANDOFF_EDITOR_BIN="${EDITOR_HANDOFF_EDITOR_BIN}" \
    EDITOR_HANDOFF_EDITOR_NAME="${EDITOR_HANDOFF_EDITOR_NAME}" \
    EDITOR_HANDOFF_FAMILY="${EDITOR_HANDOFF_FAMILY}" \
    EDITOR_HANDOFF_LINE_AWARE="${EDITOR_HANDOFF_LINE_AWARE}" \
    EDITOR_HANDOFF_WAIT_APPLIED="${EDITOR_HANDOFF_WAIT_APPLIED}" \
    EDITOR_HANDOFF_EXECUTABLE_PATH="${EDITOR_HANDOFF_EXECUTABLE_PATH}" \
    EDITOR_HANDOFF_NOTE="${EDITOR_HANDOFF_NOTE}" \
    EDITOR_HANDOFF_ARGV_JSON="${argv_json}" \
    EDITOR_HANDOFF_COMMAND_TEXT="${command_text}" \
    python3 - <<'PY'
import json
import os

payload = {
    "target": {
        "raw": os.environ.get("EDITOR_HANDOFF_RAW_TARGET", ""),
        "path": os.environ.get("EDITOR_HANDOFF_ABSOLUTE_PATH", ""),
        "displayPath": os.environ.get("EDITOR_HANDOFF_DISPLAY_PATH", ""),
        "line": int(os.environ["EDITOR_HANDOFF_LINE"]) if os.environ.get("EDITOR_HANDOFF_LINE") else None,
        "column": int(os.environ["EDITOR_HANDOFF_COLUMN"]) if os.environ.get("EDITOR_HANDOFF_COLUMN") else None,
        "location": os.environ.get("EDITOR_HANDOFF_LOCATION", ""),
        "anchorRoot": os.environ.get("EDITOR_HANDOFF_ANCHOR_ROOT", ""),
    },
    "editor": {
        "command": os.environ.get("EDITOR_HANDOFF_EDITOR_OVERRIDE") or os.environ.get("EDITOR_HANDOFF_EDITOR_NAME", ""),
        "binary": os.environ.get("EDITOR_HANDOFF_EDITOR_BIN", ""),
        "name": os.environ.get("EDITOR_HANDOFF_EDITOR_NAME", ""),
        "family": os.environ.get("EDITOR_HANDOFF_FAMILY", ""),
        "executablePath": os.environ.get("EDITOR_HANDOFF_EXECUTABLE_PATH", ""),
        "lineAware": os.environ.get("EDITOR_HANDOFF_LINE_AWARE", "0") == "1",
        "waitRequested": os.environ.get("EDITOR_HANDOFF_WAIT_REQUESTED", "0") == "1",
        "waitApplied": os.environ.get("EDITOR_HANDOFF_WAIT_APPLIED", "0") == "1",
        "note": os.environ.get("EDITOR_HANDOFF_NOTE", ""),
    },
    "command": {
        "argv": json.loads(os.environ.get("EDITOR_HANDOFF_ARGV_JSON", "[]")),
        "shell": os.environ.get("EDITOR_HANDOFF_COMMAND_TEXT", ""),
    },
}
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

editor_handoff_payload_text() {
    local raw_target="$1"
    local anchor_root="$2"
    local wait_requested="$3"
    local command_text=""

    command_text=$(editor_handoff_command_text "${EDITOR_HANDOFF_COMMAND_ARGV[@]}")

    echo ""
    echo "IDE Editor Handoff"
    echo "Target:          ${raw_target}"
    echo "Anchor root:     ${anchor_root}"
    echo "Resolved path:   ${EDITOR_HANDOFF_ABSOLUTE_PATH}"
    if [[ -n "${EDITOR_HANDOFF_LINE}" ]]; then
        echo "Location:        ${EDITOR_HANDOFF_LOCATION}"
    fi
    echo "Editor family:   ${EDITOR_HANDOFF_FAMILY}"
    echo "Editor command:  ${EDITOR_HANDOFF_EDITOR_BIN}"
    echo "Executable:      ${EDITOR_HANDOFF_EXECUTABLE_PATH}"
    echo "Line-aware:      $([[ "${EDITOR_HANDOFF_LINE_AWARE}" == "1" ]] && echo "yes" || echo "no")"
    echo "Wait requested:  $([[ "${wait_requested}" == "1" ]] && echo "yes" || echo "no")"
    echo "Wait applied:    $([[ "${EDITOR_HANDOFF_WAIT_APPLIED}" == "1" ]] && echo "yes" || echo "no")"
    if [[ -n "${EDITOR_HANDOFF_NOTE}" ]]; then
        echo "Note:            ${EDITOR_HANDOFF_NOTE}"
    fi
    echo "Command:         ${command_text}"
    echo ""
}

cmd_open() {
    local target=""
    local project_path=""
    local editor_override=""
    local dry_run="0"
    local wait_requested="0"
    local format="text"
    local anchor_root=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                project_path="${1:-}"
                ;;
            --editor)
                shift
                editor_override="${1:-}"
                ;;
            --editor=*)
                editor_override="${1#*=}"
                ;;
            --wait)
                wait_requested="1"
                ;;
            --dry-run)
                dry_run="1"
                ;;
            --format)
                shift
                format="${1:-text}"
                ;;
            --format=*)
                format="${1#*=}"
                ;;
            *)
                if [[ -n "${target}" ]]; then
                    yen_error "open accepts exactly one target path:line[:col]."
                    return 1
                fi
                target="$1"
                ;;
        esac
        shift
    done

    if [[ -z "${target}" ]]; then
        yen_error "open requires a target path or path:line[:col]."
        return 1
    fi

    if [[ "${dry_run}" != "1" && "${format}" != "text" ]]; then
        yen_error "--format is only supported together with --dry-run."
        return 1
    fi

    if [[ -n "${project_path}" ]]; then
        anchor_root=$(find_project_root "${project_path}")
    else
        anchor_root=$(find_project_root "")
    fi

    if ! editor_handoff_build_plan "${target}" "${anchor_root}" "${editor_override}" "${wait_requested}"; then
        if [[ -n "${EDITOR_HANDOFF_NOTE}" ]]; then
            yen_error "${EDITOR_HANDOFF_NOTE}"
        else
            yen_error "Unable to build an editor handoff plan for '${target}'."
        fi
        return 1
    fi

    if [[ "${dry_run}" == "1" ]]; then
        case "${format}" in
            json)
                editor_handoff_payload_json "${target}" "${anchor_root}" "${editor_override}" "${wait_requested}"
                ;;
            text)
                editor_handoff_payload_text "${target}" "${anchor_root}" "${wait_requested}"
                ;;
            *)
                yen_error "Unknown open format: ${format} (expected text|json)"
                return 1
                ;;
        esac
        return 0
    fi

    "${EDITOR_HANDOFF_COMMAND_ARGV[@]}"
}
