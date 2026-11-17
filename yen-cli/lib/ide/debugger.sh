# shellcheck shell=bash
# Source-time pure debugger baseline helpers and command handlers.

debug_clean_value() {
    printf "%s" "$1" | tr '\t\r\n' '   '
}

debug_report_token() {
    printf "%s-%s\n" "$(date -u +"%Y%m%dT%H%M%SZ")" "$(now_ms)"
}

debug_write_details_report() {
    local path="$1"
    local root="$2"
    local tool="$3"
    local display_target="$4"
    local entry_path="$5"
    local started_at="$6"
    local line="$7"
    local column="$8"
    local line_applied="$9"
    local command_text="${10}"
    local notes_output="${11}"

    mkdir -p "$(dirname "${path}")"
    {
        echo "IDE Debug Session"
        echo "Project root: ${root}"
        echo "Tool: ${tool}"
        echo "Target: ${display_target}"
        echo "Entry path: ${entry_path}"
        echo "Line: ${line:-n/a}"
        echo "Column: ${column:-n/a}"
        echo "Line applied: ${line_applied}"
        echo "Started: ${started_at}"
        echo "Command: ${command_text}"
        if [[ -n "${notes_output}" ]]; then
            echo "Notes:"
            while IFS= read -r note || [[ -n "${note}" ]]; do
                [[ -n "${note}" ]] && echo "  - ${note}"
            done <<EOF
${notes_output}
EOF
        fi
        echo "--- output ---"
    } > "${path}"
}

debug_append_details_result() {
    local path="$1"
    local ended_at="$2"
    local runtime_status="$3"
    local exit_code="$4"

    mkdir -p "$(dirname "${path}")"
    {
        echo ""
        echo "--- result ---"
        echo "Ended: ${ended_at}"
        echo "Status: ${runtime_status}"
        echo "Exit code: ${exit_code}"
    } >> "${path}"
}

debug_write_summary_report() {
    local path="$1"
    local ended_at="$2"
    local started_at="$3"
    local tool="$4"
    local runtime_status="$5"
    local exit_code="$6"
    local display_target="$7"
    local entry_path="$8"
    local line="$9"
    local column="${10}"
    local line_applied="${11}"
    local command_text="${12}"

    mkdir -p "$(dirname "${path}")"
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$(debug_clean_value "${ended_at}")" \
        "$(debug_clean_value "${started_at}")" \
        "$(debug_clean_value "${tool}")" \
        "$(debug_clean_value "${runtime_status}")" \
        "$(debug_clean_value "${exit_code}")" \
        "$(debug_clean_value "${display_target}")" \
        "$(debug_clean_value "${entry_path}")" \
        "$(debug_clean_value "${line}")" \
        "$(debug_clean_value "${column}")" \
        "$(debug_clean_value "${line_applied}")" \
        "$(debug_clean_value "${command_text}")" > "${path}"
}

debug_session_helper_script() {
    printf "%s/debug-session-helper.py\n" "${IDE_MODULE_DIR}"
}

debug_managed_socket_file() {
    local root="$1"
    debug_socket_file "${root}"
}

debug_managed_meta_file() {
    local root="$1"
    printf "%s/session-meta.json\n" "$(debug_project_dir "${root}")"
}

debug_managed_request_json() {
    local socket_file="$1"
    local action="$2"
    local value_key="${3:-}"
    local value_text="${4:-}"
    local helper_script=""
    local request_payload=""

    helper_script=$(debug_session_helper_script)
    if [[ ! -f "${helper_script}" ]]; then
        yen_error "Managed debug helper is missing: ${helper_script}"
        return 1
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        yen_error "python3 is required for managed debug sessions."
        return 1
    fi
    request_payload=$(DEBUG_MANAGED_ACTION="${action}" DEBUG_MANAGED_VALUE_KEY="${value_key}" DEBUG_MANAGED_VALUE_TEXT="${value_text}" python3 - <<'PY'
import json
import os

payload = {"action": os.environ.get("DEBUG_MANAGED_ACTION", "")}
key = os.environ.get("DEBUG_MANAGED_VALUE_KEY", "")
if key:
    payload[key] = os.environ.get("DEBUG_MANAGED_VALUE_TEXT", "")
print(json.dumps(payload))
PY
)
    python3 "${helper_script}" request "${socket_file}" "${request_payload}"
}

debug_managed_status_json_for_root() {
    local root="$1"
    local socket_file=""
    local meta_file=""
    local output=""

    socket_file=$(debug_managed_socket_file "${root}")
    meta_file=$(debug_managed_meta_file "${root}")
    if [[ -S "${socket_file}" ]]; then
        output=$(debug_managed_request_json "${socket_file}" "status" 2>/dev/null || true)
        if [[ -n "${output}" ]]; then
            printf "%s\n" "${output}"
            return 0
        fi
    fi
    if [[ -f "${meta_file}" ]]; then
        python3 - "${meta_file}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
try:
    payload = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    payload = {}
print(json.dumps({"ok": True, "session": payload}, indent=2, sort_keys=True))
PY
        return 0
    fi
    printf "{}\n"
}

debug_sync_managed_state_from_json() {
    local root="$1"
    local payload="$2"
    local state_snapshot=""
    local trusted="no"
    local last_tool=""
    local last_target=""
    local last_display_target=""
    local last_line=""
    local last_column=""
    local last_line_applied=""
    local last_started_at=""
    local last_ended_at=""
    local last_exit_code=""
    local last_status=""
    local last_command=""
    local last_summary_report=""
    local last_details_report=""
    local managed_status=""
    local manager_pid=""

    [[ -n "${payload}" ]] || return 0

    state_snapshot=$(debug_state_snapshot "${root}")
    trusted=$(doctor_snapshot_value "${state_snapshot}" "trusted")
    last_tool=$(doctor_snapshot_value "${state_snapshot}" "tool")
    last_target=$(doctor_snapshot_value "${state_snapshot}" "target")
    last_display_target=$(doctor_snapshot_value "${state_snapshot}" "display_target")
    last_line=$(doctor_snapshot_value "${state_snapshot}" "line")
    last_column=$(doctor_snapshot_value "${state_snapshot}" "column")
    last_line_applied=$(doctor_snapshot_value "${state_snapshot}" "line_applied")
    last_started_at=$(doctor_snapshot_value "${state_snapshot}" "last_started_at")
    last_command=$(doctor_snapshot_value "${state_snapshot}" "command")
    last_summary_report=$(doctor_snapshot_value "${state_snapshot}" "summary_report")
    last_details_report=$(doctor_snapshot_value "${state_snapshot}" "details_report")
    last_ended_at=$(DEBUG_MANAGED_STATUS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("DEBUG_MANAGED_STATUS_PAYLOAD") or "{}")
session = payload.get("session") or {}
print(session.get("endedAt") or "")
PY
)
    last_exit_code=$(DEBUG_MANAGED_STATUS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("DEBUG_MANAGED_STATUS_PAYLOAD") or "{}")
session = payload.get("session") or {}
value = session.get("exitCode")
print("" if value is None else value)
PY
)
    managed_status=$(DEBUG_MANAGED_STATUS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("DEBUG_MANAGED_STATUS_PAYLOAD") or "{}")
session = payload.get("session") or {}
print(session.get("status") or "")
PY
)
    manager_pid=$(DEBUG_MANAGED_STATUS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("DEBUG_MANAGED_STATUS_PAYLOAD") or "{}")
session = payload.get("session") or {}
value = session.get("managerPid")
print("" if value is None else value)
PY
)
    if [[ -n "${managed_status}" ]]; then
        debug_state_write "${root}" \
            "root=$(debug_clean_value "${root}")" \
            "trusted=$(debug_clean_value "${trusted}")" \
            "tool=$(debug_clean_value "${last_tool}")" \
            "target=$(debug_clean_value "${last_target}")" \
            "display_target=$(debug_clean_value "${last_display_target}")" \
            "line=$(debug_clean_value "${last_line}")" \
            "column=$(debug_clean_value "${last_column}")" \
            "line_applied=$(debug_clean_value "${last_line_applied}")" \
            "last_started_at=$(debug_clean_value "${last_started_at}")" \
            "last_ended_at=$(debug_clean_value "${last_ended_at}")" \
            "last_exit_code=$(debug_clean_value "${last_exit_code}")" \
            "status=$(debug_clean_value "${managed_status}")" \
            "command=$(debug_clean_value "${last_command}")" \
            "summary_report=$(debug_clean_value "${last_summary_report}")" \
            "details_report=$(debug_clean_value "${last_details_report}")" \
            "pid=$(debug_clean_value "${manager_pid}")" \
            "managed=yes" \
            "session_socket=$(debug_clean_value "$(debug_managed_socket_file "${root}")")" \
            "session_meta=$(debug_clean_value "$(debug_managed_meta_file "${root}")")"
    fi
}

debug_handoff_row_for_target() {
    local root="$1"
    local raw_target="$2"
    local payload=""
    local trusted="no"
    local trust_required="yes"
    local trust_command=""
    local handoff_command=""
    local project_selector=""

    project_selector=$(debug_project_selector_for_root "${root}")

    if is_debug_trusted_project "${root}"; then
        trusted="yes"
        trust_required="no"
    fi
    payload=$(debug_resolve_plan "${raw_target}" "${root}" "auto" 2>/dev/null) || return 1
    trust_command="yen ide debug trust $(shell_quote_single "${project_selector}")"
    handoff_command="yen ide debug start $(shell_quote_single "${raw_target}") --project $(shell_quote_single "${project_selector}")"

    DEBUG_HANDOFF_PAYLOAD="${payload}" \
    DEBUG_HANDOFF_TRUSTED="${trusted}" \
    DEBUG_HANDOFF_TRUST_REQUIRED="${trust_required}" \
    DEBUG_HANDOFF_TRUST_COMMAND="${trust_command}" \
    DEBUG_HANDOFF_COMMAND="${handoff_command}" \
    python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("DEBUG_HANDOFF_PAYLOAD") or "{}")
notes = "|".join(str(item).replace("\t", " ").replace("\r", " ").replace("\n", " ").strip() for item in (payload.get("notes") or []) if str(item).strip())
print("\t".join([
    (payload.get("displayTarget") or payload.get("target") or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip(),
    (os.environ.get("DEBUG_HANDOFF_COMMAND") or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip(),
    (payload.get("tool") or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip(),
    (payload.get("toolTitle") or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip(),
    "yes" if payload.get("lineApplied") else "no",
    os.environ.get("DEBUG_HANDOFF_TRUSTED", "no"),
    os.environ.get("DEBUG_HANDOFF_TRUST_REQUIRED", "yes"),
    (os.environ.get("DEBUG_HANDOFF_TRUST_COMMAND") or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip(),
    notes,
]))
PY
}

debug_handoff_rows_from_target_rows() {
    local root="$1"
    local seen_groups=""
    local group=""
    local raw_target=""
    local handoff_row=""

    while IFS=$'\t' read -r group raw_target; do
        [[ -n "${group}" ]] || continue
        [[ -n "${raw_target}" ]] || continue
        if printf "%s\n" "${seen_groups}" | grep -Fxq -- "${group}" 2>/dev/null; then
            continue
        fi
        handoff_row=$(debug_handoff_row_for_target "${root}" "${raw_target}" || true)
        if [[ -z "${handoff_row}" ]]; then
            continue
        fi
        printf "%s\t%s\n" "${group}" "${handoff_row}"
        seen_groups="${seen_groups}${group}"$'\n'
    done
}

debug_handoff_rows_from_semantic_report() {
    local root="$1"
    local semantic_report="$2"
    local candidates=""

    [[ -f "${semantic_report}" && -s "${semantic_report}" ]] || return 0
    candidates=$(python3 - "${semantic_report}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
seen = set()

for raw in path.read_text(encoding="utf-8").splitlines():
    if not raw.strip():
        continue
    parts = raw.split("\t")
    if len(parts) < 9:
        continue
    group = parts[1].strip()
    found = parts[3].strip()
    location = parts[8].strip()
    if found != "yes" or not group or not location:
        continue
    key = (group, location)
    if key in seen:
        continue
    seen.add(key)
    print(f"{group}\t{location}")
PY
)
    [[ -n "${candidates}" ]] || return 0
    debug_handoff_rows_from_target_rows "${root}" <<EOF
${candidates}
EOF
}

debug_managed_launch() {
    local root="$1"
    local payload="$2"
    local started_at="$3"
    local command_text="$4"
    local summary_report="$5"
    local details_report="$6"
    local socket_file=""
    local meta_file=""
    local helper_script=""

    socket_file=$(debug_managed_socket_file "${root}")
    meta_file=$(debug_managed_meta_file "${root}")
    helper_script=$(debug_session_helper_script)

    mkdir -p "$(dirname "${socket_file}")"
    rm -f "${socket_file}" "${meta_file}" "${meta_file}.launch.json"
    if [[ ! -f "${helper_script}" ]]; then
        yen_error "Managed debug helper is missing: ${helper_script}"
        return 1
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        yen_error "python3 is required for managed debug sessions."
        return 1
    fi

    YEN_DEBUG_SESSION_PLAN="${payload}" \
    YEN_DEBUG_SESSION_STARTED_AT="${started_at}" \
    YEN_DEBUG_SESSION_COMMAND_TEXT="${command_text}" \
    YEN_DEBUG_SESSION_SUMMARY_REPORT="${summary_report}" \
    YEN_DEBUG_SESSION_DETAILS_REPORT="${details_report}" \
    YEN_DEBUG_SESSION_SOCKET_FILE="${socket_file}" \
    YEN_DEBUG_SESSION_META_FILE="${meta_file}" \
    python3 "${helper_script}" launch
}

debug_managed_action_json() {
    local root="$1"
    local action="$2"
    local value_key="${3:-}"
    local value_text="${4:-}"
    local socket_file=""
    local response=""

    socket_file=$(debug_managed_socket_file "${root}")
    if [[ ! -S "${socket_file}" ]]; then
        yen_error "No active managed debug session for ${root}. Start one with: yen ide debug start <target> --managed --project ${root}"
        return 1
    fi
    response=$(debug_managed_request_json "${socket_file}" "${action}" "${value_key}" "${value_text}") || return 1
    printf "%s\n" "${response}"
}

debug_managed_action_text() {
    local payload="$1"
    DEBUG_MANAGED_ACTION_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("DEBUG_MANAGED_ACTION_PAYLOAD") or "{}")


def text(value, fallback=""):
    value = "" if value is None else str(value).strip()
    return value if value else fallback


if not payload.get("ok"):
    print(text(payload.get("error"), "Managed debug action failed."))
    raise SystemExit(1)

session = payload.get("session") or {}
output = payload.get("outputExcerpt") or []
if output:
    print("")
    print("Managed Debug Action")
    for line in output:
        print(line)
else:
    print("")
    print("Managed Debug Action")
    print(text(payload.get("location"), "No output."))
if session:
    print("")
    print(f"State:      {text(session.get('status'), 'unknown')}")
    print(f"Location:   {text(session.get('lastStopLocation'), 'unknown')}")
print("")
PY
}

debug_state_from_exit_code() {
    local exit_code="$1"
    case "${exit_code}" in
        0)
            printf "success\n"
            ;;
        130)
            printf "interrupted\n"
            ;;
        *)
            printf "failed\n"
            ;;
    esac
}

debug_stop_internal() {
    local root="$1"
    local reason="$2"
    local state_snapshot=""
    local pid=""
    local last_tool=""
    local last_target=""
    local last_display_target=""
    local last_line=""
    local last_column=""
    local last_line_applied=""
    local last_started_at=""
    local last_command=""
    local last_exit_code=""
    local last_summary_report=""
    local last_details_report=""
    local lock_dir=""
    local managed="no"
    local managed_response=""

    state_snapshot=$(debug_state_snapshot "${root}")
    if [[ -z "${state_snapshot}" ]]; then
        return 0
    fi
    pid=$(doctor_snapshot_value "${state_snapshot}" "pid")
    last_tool=$(doctor_snapshot_value "${state_snapshot}" "tool")
    last_target=$(doctor_snapshot_value "${state_snapshot}" "target")
    last_display_target=$(doctor_snapshot_value "${state_snapshot}" "display_target")
    last_line=$(doctor_snapshot_value "${state_snapshot}" "line")
    last_column=$(doctor_snapshot_value "${state_snapshot}" "column")
    last_line_applied=$(doctor_snapshot_value "${state_snapshot}" "line_applied")
    last_started_at=$(doctor_snapshot_value "${state_snapshot}" "last_started_at")
    last_command=$(doctor_snapshot_value "${state_snapshot}" "command")
    last_exit_code=$(doctor_snapshot_value "${state_snapshot}" "last_exit_code")
    last_summary_report=$(doctor_snapshot_value "${state_snapshot}" "summary_report")
    last_details_report=$(doctor_snapshot_value "${state_snapshot}" "details_report")
    managed=$(doctor_snapshot_value "${state_snapshot}" "managed")
    lock_dir=$(debug_lock_dir "${root}")

    if [[ "${managed}" == "yes" ]]; then
        managed_response=$(debug_managed_action_json "${root}" "stop" 2>/dev/null || true)
        if [[ -n "${managed_response}" ]]; then
            debug_sync_managed_state_from_json "${root}" "${managed_response}"
            state_snapshot=$(debug_state_snapshot "${root}")
            last_exit_code=$(doctor_snapshot_value "${state_snapshot}" "last_exit_code")
            last_summary_report=$(doctor_snapshot_value "${state_snapshot}" "summary_report")
            last_details_report=$(doctor_snapshot_value "${state_snapshot}" "details_report")
        fi
    elif [[ -n "${pid}" ]] && is_pid_running "${pid}"; then
        kill "${pid}" >/dev/null 2>&1 || true
    fi

    if ! acquire_state_lock "${lock_dir}" "IDE debug state"; then
        return 1
    fi
    debug_state_write "${root}" \
        "root=$(debug_clean_value "${root}")" \
        "tool=$(debug_clean_value "${last_tool}")" \
        "target=$(debug_clean_value "${last_target}")" \
        "display_target=$(debug_clean_value "${last_display_target}")" \
        "line=$(debug_clean_value "${last_line}")" \
        "column=$(debug_clean_value "${last_column}")" \
        "line_applied=$(debug_clean_value "${last_line_applied}")" \
        "last_started_at=$(debug_clean_value "${last_started_at}")" \
        "last_ended_at=$(iso_now)" \
        "last_exit_code=$(debug_clean_value "${last_exit_code}")" \
        "status=stopped" \
        "command=$(debug_clean_value "${last_command}")" \
        "summary_report=$(debug_clean_value "${last_summary_report}")" \
        "details_report=$(debug_clean_value "${last_details_report}")" \
        "pid=" \
        "managed=no" \
        "session_socket=" \
        "session_meta=" \
        "last_stop_reason=$(debug_clean_value "${reason}")"
    release_state_lock "${lock_dir}"
    timeline_log "debug-stop" "${root}" "stopped" "reason=$(debug_clean_value "${reason}");tool=$(debug_clean_value "${last_tool}");summary=$(debug_clean_value "${last_summary_report}");details=$(debug_clean_value "${last_details_report}")"
}

cmd_debug_status() {
    local target=""
    local format="text"
    local root=""
    local payload=""
    local execution_target="workspace"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --devcontainer)
                execution_target="devcontainer"
                ;;
            --format=*)
                format="${1#*=}"
                ;;
            --format)
                shift
                format="${1:-text}"
                ;;
            *)
                if [[ -n "${target}" ]]; then
                    yen_error "debug status accepts at most one project path."
                    return 1
                fi
                target="$1"
                ;;
        esac
        shift
    done

    debug_status_resolve_root "${target}" || return 1
    root="${DEBUG_STATUS_TARGET_ROOT}"
    payload=$(debug_status_json_for_root "${root}" "${execution_target}")

    case "${format}" in
        json)
            printf "%s\n" "${payload}"
            ;;
        text)
            debug_status_text_from_payload "${payload}"
            ;;
        *)
            yen_error "Unknown debug status format: ${format} (expected text|json)"
            return 1
            ;;
    esac
}

cmd_debug_start() {
    local project_target=""
    local raw_target=""
    local tool="auto"
    local dry_run="0"
    local managed="0"
    local format="text"
    local root=""
    local payload=""
    local trusted="no"
    local entry_path=""
    local display_target=""
    local line_applied=""
    local command_text=""
    local started_at=""
    local exit_code=0
    local runtime_status=""
    local last_tool=""
    local line=""
    local column=""
    local notes_output=""
    local report_token=""
    local summary_report=""
    local details_report=""
    local ended_at=""
    local trust_target=""
    local execution_target="workspace"
    local -a program_args=()
    local -a argv=()
    local in_program_args="0"

    while [[ $# -gt 0 ]]; do
        if [[ "${in_program_args}" == "1" ]]; then
            program_args+=("$1")
            shift
            continue
        fi

        case "$1" in
            --project|--path)
                shift
                project_target="${1:-}"
                ;;
            --tool)
                shift
                tool="${1:-auto}"
                ;;
            --tool=*)
                tool="${1#*=}"
                ;;
            --dry-run)
                dry_run="1"
                ;;
            --managed)
                managed="1"
                ;;
            --devcontainer)
                execution_target="devcontainer"
                ;;
            --format)
                shift
                format="${1:-text}"
                ;;
            --format=*)
                format="${1#*=}"
                ;;
            --)
                in_program_args="1"
                ;;
            *)
                if [[ -n "${raw_target}" ]]; then
                    yen_error "debug start accepts exactly one semantic target or executable."
                    return 1
                fi
                raw_target="$1"
                ;;
        esac
        shift
    done

    if [[ -z "${raw_target}" ]]; then
        yen_error "debug start requires a target like path/to/file.py:12 or ./bin/app."
        return 1
    fi

    if [[ -n "${project_target}" ]]; then
        debug_resolve_root_into_shell "${project_target}" || return 1
        root="${DEBUG_RESOLVED_ROOT}"
    else
        if [[ "${raw_target}" == ssh://* ]]; then
            yen_error "Remote debugger launch requires --project ssh://user@host/abs/path plus a repo-relative target."
            return 1
        fi
        if ! editor_handoff_parse_target "${raw_target}" "${PWD}"; then
            yen_error "Unable to resolve debug target '${raw_target}'."
            return 1
        fi
        root=$(debug_root_for_absolute_target "${EDITOR_HANDOFF_ABSOLUTE_PATH}") || return 1
    fi
    payload=$(debug_resolve_plan "${raw_target}" "${root}" "${tool}" "${execution_target}" "${program_args[@]}") || return 1

    if [[ "${dry_run}" == "1" ]]; then
        case "${format}" in
            json)
                printf "%s\n" "${payload}"
                ;;
            text)
                debug_plan_text_from_payload "${payload}"
                ;;
            *)
                yen_error "Unknown debug start dry-run format: ${format} (expected text|json)"
                return 1
                ;;
        esac
        return 0
    fi

    if [[ "${format}" != "text" ]]; then
        yen_error "debug start only supports --format when used with --dry-run."
        return 1
    fi

    trust_target="${root}"
    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
        trust_target="${project_target:-${IDE_WORKSPACE_REQUESTED_TARGET:-${IDE_WORKSPACE_IDENTITY}}}"
    fi
    if ! is_debug_trusted_project "${root}"; then
        yen_error "Project is not trusted for debugger actions. Run: yen ide debug trust ${trust_target}"
        return 1
    fi
    trusted="yes"

    entry_path=$(DEBUG_PLAN_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("DEBUG_PLAN_PAYLOAD") or "{}")
print(payload.get("entryPath") or "")
PY
)
    display_target=$(DEBUG_PLAN_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("DEBUG_PLAN_PAYLOAD") or "{}")
print(payload.get("displayTarget") or payload.get("target") or "")
PY
)
    line_applied=$(DEBUG_PLAN_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("DEBUG_PLAN_PAYLOAD") or "{}")
print("yes" if payload.get("lineApplied") else "no")
PY
)
    last_tool=$(DEBUG_PLAN_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("DEBUG_PLAN_PAYLOAD") or "{}")
print(payload.get("tool") or "")
PY
)
    line=$(DEBUG_PLAN_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("DEBUG_PLAN_PAYLOAD") or "{}")
value = payload.get("line")
print("" if value is None else value)
PY
)
    column=$(DEBUG_PLAN_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("DEBUG_PLAN_PAYLOAD") or "{}")
value = payload.get("column")
print("" if value is None else value)
PY
)
    while IFS= read -r arg || [[ -n "${arg}" ]]; do
        argv+=("${arg}")
    done <<EOF
$(DEBUG_PLAN_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("DEBUG_PLAN_PAYLOAD") or "{}")
for arg in payload.get("argv") or []:
    print(arg)
PY
)
EOF
    command_text=""
    for arg in "${argv[@]}"; do
        if [[ -n "${command_text}" ]]; then
            command_text="${command_text} "
        fi
        command_text="${command_text}$(shell_quote_single "${arg}")"
    done
    started_at=$(iso_now)

    notes_output=$(DEBUG_PLAN_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("DEBUG_PLAN_PAYLOAD") or "{}")
notes = payload.get("notes") or []
for note in notes:
    print(note)
PY
)
    while IFS= read -r note || [[ -n "${note}" ]]; do
        [[ -n "${note}" ]] && yen_info "${note}"
    done <<EOF
${notes_output}
EOF

    report_token=$(debug_report_token)
    summary_report=$(debug_summary_report_file "${root}" "${report_token}")
    details_report=$(debug_details_report_file "${root}" "${report_token}")
    debug_write_details_report "${details_report}" "${root}" "${last_tool}" "${display_target}" "${entry_path}" "${started_at}" "${line}" "${column}" "${line_applied}" "${command_text}" "${notes_output}"

    if [[ "${managed}" == "1" ]]; then
        local managed_payload=""
        local manager_pid=""
        local managed_status=""
        local managed_location=""

        if [[ -S "$(debug_managed_socket_file "${root}")" ]]; then
            yen_error "A managed debug session is already active for ${root}. Stop it first with: yen ide debug stop --project ${root}"
            return 1
        fi
        managed_payload=$(debug_managed_launch "${root}" "${payload}" "${started_at}" "${command_text}" "${summary_report}" "${details_report}") || return 1
        manager_pid=$(DEBUG_MANAGED_LAUNCH="${managed_payload}" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("DEBUG_MANAGED_LAUNCH") or "{}")
print(payload.get("managerPid") or "")
PY
)
        managed_status=$(DEBUG_MANAGED_LAUNCH="${managed_payload}" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("DEBUG_MANAGED_LAUNCH") or "{}")
print(payload.get("status") or "managed-paused")
PY
)
        managed_location=$(DEBUG_MANAGED_LAUNCH="${managed_payload}" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("DEBUG_MANAGED_LAUNCH") or "{}")
print(payload.get("lastStopLocation") or "")
PY
)
        debug_state_write "${root}" \
            "root=$(debug_clean_value "${root}")" \
            "trusted=${trusted}" \
            "tool=$(debug_clean_value "${last_tool}")" \
            "target=$(debug_clean_value "${entry_path}")" \
            "display_target=$(debug_clean_value "${display_target}")" \
            "line=$(debug_clean_value "${line}")" \
            "column=$(debug_clean_value "${column}")" \
            "line_applied=$(debug_clean_value "${line_applied}")" \
            "last_started_at=$(debug_clean_value "${started_at}")" \
            "last_ended_at=" \
            "last_exit_code=" \
            "status=$(debug_clean_value "${managed_status}")" \
            "command=$(debug_clean_value "${command_text}")" \
            "summary_report=$(debug_clean_value "${summary_report}")" \
            "details_report=$(debug_clean_value "${details_report}")" \
            "pid=$(debug_clean_value "${manager_pid}")" \
            "managed=yes" \
            "session_socket=$(debug_clean_value "$(debug_managed_socket_file "${root}")")" \
            "session_meta=$(debug_clean_value "$(debug_managed_meta_file "${root}")")" \
            "last_location=$(debug_clean_value "${managed_location}")"
        timeline_log "debug-start" "${root}" "managed" "tool=$(debug_clean_value "${last_tool}");target=$(debug_clean_value "${display_target}");summary=$(debug_clean_value "${summary_report}");details=$(debug_clean_value "${details_report}")"
        DEBUG_MANAGED_LAUNCH="${managed_payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("DEBUG_MANAGED_LAUNCH") or "{}")
print("")
print("Managed Debug Session")
print(f"Tool:               {(payload.get('tool') or '').strip()}")
print(f"Status:             {(payload.get('status') or '').strip()}")
print(f"Location:           {(payload.get('lastStopLocation') or '').strip() or 'unknown'}")
print(f"Manager PID:        {payload.get('managerPid') or ''}")
print("")
PY
        return 0
    fi

    debug_state_write "${root}" \
        "root=$(debug_clean_value "${root}")" \
        "trusted=${trusted}" \
        "tool=$(debug_clean_value "${last_tool}")" \
        "target=$(debug_clean_value "${entry_path}")" \
        "display_target=$(debug_clean_value "${display_target}")" \
        "line=$(debug_clean_value "${line}")" \
        "column=$(debug_clean_value "${column}")" \
        "line_applied=$(debug_clean_value "${line_applied}")" \
        "last_started_at=$(debug_clean_value "${started_at}")" \
        "last_ended_at=" \
        "last_exit_code=" \
        "status=launching" \
        "command=$(debug_clean_value "${command_text}")" \
        "summary_report=$(debug_clean_value "${summary_report}")" \
        "details_report=$(debug_clean_value "${details_report}")" \
        "pid="
    timeline_log "debug-start" "${root}" "launched" "tool=$(debug_clean_value "${last_tool}");target=$(debug_clean_value "${display_target}");line_applied=${line_applied};summary=$(debug_clean_value "${summary_report}");details=$(debug_clean_value "${details_report}")"

    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
        "${argv[@]}" 2>&1 | tee -a "${details_report}"
    else
        {
            cd "${root}" || exit 1
            "${argv[@]}"
        } 2>&1 | tee -a "${details_report}"
    fi
    exit_code=${PIPESTATUS[0]}

    runtime_status=$(debug_state_from_exit_code "${exit_code}")
    ended_at=$(iso_now)
    debug_append_details_result "${details_report}" "${ended_at}" "${runtime_status}" "${exit_code}"
    debug_write_summary_report "${summary_report}" "${ended_at}" "${started_at}" "${last_tool}" "${runtime_status}" "${exit_code}" "${display_target}" "${entry_path}" "${line}" "${column}" "${line_applied}" "${command_text}"
    debug_state_write "${root}" \
        "root=$(debug_clean_value "${root}")" \
        "trusted=${trusted}" \
        "tool=$(debug_clean_value "${last_tool}")" \
        "target=$(debug_clean_value "${entry_path}")" \
        "display_target=$(debug_clean_value "${display_target}")" \
        "line=$(debug_clean_value "${line}")" \
        "column=$(debug_clean_value "${column}")" \
        "line_applied=$(debug_clean_value "${line_applied}")" \
        "last_started_at=$(debug_clean_value "${started_at}")" \
        "last_ended_at=$(debug_clean_value "${ended_at}")" \
        "last_exit_code=${exit_code}" \
        "status=${runtime_status}" \
        "command=$(debug_clean_value "${command_text}")" \
        "summary_report=$(debug_clean_value "${summary_report}")" \
        "details_report=$(debug_clean_value "${details_report}")" \
        "pid="
    timeline_log "debug-stop" "${root}" "status=${runtime_status};exit=${exit_code}" "tool=$(debug_clean_value "${last_tool}");target=$(debug_clean_value "${display_target}");summary=$(debug_clean_value "${summary_report}");details=$(debug_clean_value "${details_report}")"

    return "${exit_code}"
}

cmd_debug_stop() {
    local target=""
    local root=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            *)
                if [[ -n "${target}" ]]; then
                    yen_error "debug stop accepts at most one project path."
                    return 1
                fi
                target="$1"
                ;;
        esac
        shift
    done

    debug_resolve_root_into_shell "${target}" || return 1
    root="${DEBUG_RESOLVED_ROOT}"
    if [[ ! -f "$(debug_state_file "${root}")" ]]; then
        yen_info "No tracked debug state for ${root}."
        return 0
    fi

    debug_stop_internal "${root}" "manual-stop" || return 1
    yen_success "Cleared tracked debug state: ${root}"
}

debug_collection_text_from_payload() {
    local payload="$1"
    local heading="$2"
    local key="$3"
    DEBUG_COLLECTION_PAYLOAD="${payload}" python3 - "${heading}" "${key}" <<'PY'
import json
import os
import sys

payload = json.loads(os.environ.get("DEBUG_COLLECTION_PAYLOAD") or "{}")
heading = sys.argv[1]
key = sys.argv[2]
if not payload.get("ok", True):
    print((payload.get("error") or "Managed debug action failed.").strip())
    raise SystemExit(1)
rows = payload.get(key) or []

print("")
print(heading)
if not rows:
    print("  none")
    print("")
    raise SystemExit(0)
for row in rows:
    label = (row.get("location") or row.get("expression") or row.get("spec") or "").strip()
    value = (row.get("lastValue") or row.get("lastError") or "").strip()
    line = f"  {str(row.get('id') or '').strip()}: {label}".rstrip()
    if value:
        line = f"{line} => {value}"
    print(line)
print("")
PY
}

cmd_debug_managed_action() {
    local action="$1"
    shift || true
    local target=""
    local format="text"
    local extra=""
    local key=""
    local root=""
    local payload=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --format)
                shift
                format="${1:-text}"
                ;;
            --format=*)
                format="${1#*=}"
                ;;
            *)
                if [[ -n "${extra}" ]]; then
                    yen_error "debug ${action} accepts at most one argument."
                    return 1
                fi
                extra="$1"
                ;;
        esac
        shift
    done

    debug_resolve_root_into_shell "${target}" || return 1
    root="${DEBUG_RESOLVED_ROOT}"
    case "${action}" in
        inspect)
            key="expression"
            ;;
        breakpoint-add)
            key="spec"
            ;;
        breakpoint-remove|watch-remove)
            key="identifier"
            ;;
        watch-add)
            key="expression"
            ;;
    esac
    payload=$(debug_managed_action_json "${root}" "${action}" "${key}" "${extra}") || return 1
    debug_sync_managed_state_from_json "${root}" "${payload}"
    case "${format}" in
        json)
            printf "%s\n" "${payload}"
            ;;
        text)
            case "${action}" in
                breakpoint-list)
                    debug_collection_text_from_payload "${payload}" "Managed Breakpoints" "breakpoints"
                    ;;
                watch-list)
                    debug_collection_text_from_payload "${payload}" "Managed Watches" "watches"
                    ;;
                *)
                    debug_managed_action_text "${payload}"
                    ;;
            esac
            ;;
        *)
            yen_error "Unknown debug ${action} format: ${format} (expected text|json)"
            return 1
            ;;
    esac
}

cmd_debug_transcript() {
    local target=""
    local tail_lines="80"
    local root=""
    local helper_script=""
    local report_path=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --tail)
                shift
                tail_lines="${1:-80}"
                ;;
            *)
                target="$1"
                ;;
        esac
        shift
    done

    if [[ ! "${tail_lines}" =~ ^[0-9]+$ ]] || [[ "${tail_lines}" -lt 1 ]]; then
        yen_error "Invalid --tail '${tail_lines}'. Use a positive integer."
        return 1
    fi
    debug_resolve_root_into_shell "${target}" || return 1
    root="${DEBUG_RESOLVED_ROOT}"
    report_path=$(debug_state_value "${root}" "details_report")
    if [[ -z "${report_path}" || ! -f "${report_path}" ]]; then
        yen_error "No managed debug transcript is available for ${root}."
        return 1
    fi
    helper_script=$(debug_session_helper_script)
    python3 "${helper_script}" transcript "${report_path}" "${tail_lines}"
}

cmd_debug() {
    local sub="${1:-status}"
    shift || true

    case "${sub}" in
        status)
            cmd_debug_status "$@"
            ;;
        start|run)
            cmd_debug_start "$@"
            ;;
        continue|c)
            cmd_debug_managed_action "continue" "$@"
            ;;
        next|n)
            cmd_debug_managed_action "next" "$@"
            ;;
        step|s)
            cmd_debug_managed_action "step" "$@"
            ;;
        out|finish)
            cmd_debug_managed_action "out" "$@"
            ;;
        stack|bt)
            cmd_debug_managed_action "stack" "$@"
            ;;
        inspect)
            cmd_debug_managed_action "inspect" "$@"
            ;;
        breakpoint)
            local bp_sub="${1:-list}"
            shift || true
            case "${bp_sub}" in
                add)
                    cmd_debug_managed_action "breakpoint-add" "$@"
                    ;;
                list|ls)
                    cmd_debug_managed_action "breakpoint-list" "$@"
                    ;;
                remove|rm|delete)
                    cmd_debug_managed_action "breakpoint-remove" "$@"
                    ;;
                *)
                    yen_error "Unknown debug breakpoint command: ${bp_sub}"
                    return 1
                    ;;
            esac
            ;;
        watch)
            local watch_sub="${1:-list}"
            shift || true
            case "${watch_sub}" in
                add)
                    cmd_debug_managed_action "watch-add" "$@"
                    ;;
                list|ls)
                    cmd_debug_managed_action "watch-list" "$@"
                    ;;
                remove|rm|delete)
                    cmd_debug_managed_action "watch-remove" "$@"
                    ;;
                *)
                    yen_error "Unknown debug watch command: ${watch_sub}"
                    return 1
                    ;;
            esac
            ;;
        transcript)
            cmd_debug_transcript "$@"
            ;;
        tui|ui|dashboard)
            cmd_debug_tui "$@"
            ;;
        stop)
            cmd_debug_stop "$@"
            ;;
        trust)
            local root=""
            debug_status_resolve_root "${1:-}" || return 1
            root="${DEBUG_STATUS_TARGET_ROOT}"
            trust_debug_project "${root}" || return 1
            timeline_log "debug-trust" "${root}" "trusted" "source=manual"
            yen_success "Trusted project for debugger actions: ${root}"
            ;;
        untrust)
            local root=""
            debug_status_resolve_root "${1:-}" || return 1
            root="${DEBUG_STATUS_TARGET_ROOT}"
            debug_stop_internal "${root}" "untrust" || return 1
            untrust_debug_project "${root}" || return 1
            timeline_log "debug-trust" "${root}" "untrusted" "source=manual"
            yen_success "Removed debugger trust: ${root}"
            ;;
        trusted|list-trusted)
            ensure_state_dirs
            if [[ ! -s "${IDE_DEBUG_TRUST_FILE}" ]]; then
                yen_info "No debug-trusted projects."
                return 0
            fi
            echo ""
            yen_header "Debug-Trusted Projects"
            nl -ba "${IDE_DEBUG_TRUST_FILE}"
            echo ""
            ;;
        *)
            yen_error "Unknown debug command: ${sub}"
            return 1
            ;;
    esac
}
