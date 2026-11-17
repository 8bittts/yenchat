# shellcheck shell=bash
# Source-time pure debugger planning/state helpers and transport context.

debug_resolve_root() {
    local target="$1"
    if declare -F workspace_summary_resolve_target >/dev/null 2>&1; then
        workspace_summary_resolve_target "${target}" >/dev/null || return 1
        printf "%s\n" "${IDE_WORKSPACE_SUMMARY_ROOT}"
        return 0
    fi

    if ! workspace_identity_parse_target "${target}"; then
        yen_error "Unable to resolve debug target: ${target}"
        return 1
    fi

    local root=""
    root=$(find_project_root "${IDE_WORKSPACE_REQUESTED_PATH}")
    if [[ -f "${root}" ]]; then
        dirname "${root}"
        return 0
    fi
    printf "%s\n" "${root}"
}

DEBUG_RESOLVED_ROOT=""

debug_resolve_root_into_shell() {
    local target="$1"

    DEBUG_RESOLVED_ROOT=""
    if declare -F workspace_summary_resolve_target >/dev/null 2>&1; then
        workspace_summary_resolve_target "${target}" >/dev/null || return 1
        DEBUG_RESOLVED_ROOT="${IDE_WORKSPACE_SUMMARY_ROOT}"
        return 0
    fi

    DEBUG_RESOLVED_ROOT=$(debug_resolve_root "${target}") || return 1
}

debug_state_write() {
    local root="$1"
    shift
    local content="schema_version=1"$'\n'
    local line=""

    ensure_state_dirs
    mkdir -p "$(debug_project_dir "${root}")"
    while [[ $# -gt 0 ]]; do
        line="$1"
        content="${content}${line}"$'\n'
        shift
    done
    atomic_write_text "$(debug_state_file "${root}")" "${content}"
}

debug_state_snapshot() {
    local root="$1"
    local file=""

    file=$(debug_state_file "${root}")
    if [[ -f "${file}" ]]; then
        cat "${file}"
    fi
}

debug_state_value() {
    local root="$1"
    local key="$2"
    local snapshot=""

    snapshot=$(debug_state_snapshot "${root}")
    if [[ -z "${snapshot}" ]]; then
        return 0
    fi
    doctor_snapshot_value "${snapshot}" "${key}"
}

debug_runtime_state() {
    local root="$1"
    local status=""
    local pid=""

    status=$(debug_state_value "${root}" "status")
    pid=$(debug_state_value "${root}" "pid")

    if [[ -z "${status}" ]]; then
        printf "stopped\n"
        return 0
    fi

    case "${status}" in
        running|launching)
            if [[ -n "${pid}" ]] && is_pid_running "${pid}"; then
                printf "running\n"
            else
                printf "stale\n"
            fi
            ;;
        *)
            printf "%s\n" "${status}"
            ;;
    esac
}

debug_remote_helper_path() {
    printf "%s/remote-planning-probe.py\n" "${IDE_MODULE_DIR}"
}

debug_remote_probe_json() {
    local requested_path="$1"
    local raw_target="${2:-}"
    ide_remote_python_helper_json \
        "${IDE_WORKSPACE_AUTHORITY}" \
        "${IDE_WORKSPACE_PORT}" \
        "$(debug_remote_helper_path)" \
        "debug" \
        "${requested_path}" \
        "${raw_target}"
}

debug_remote_snapshot_shell_vars() {
    local remote_snapshot="$1"
    python3 - "${remote_snapshot}" <<'PY'
import json
import shlex
import sys

payload = json.loads(sys.argv[1] or "{}")
target = payload.get("target") or {}
available = payload.get("available") or {}
fields = {
    "remote_debug_root": payload.get("root") or "",
    "remote_debug_requested_path": payload.get("requestedPath") or "",
    "remote_debug_project_types": payload.get("projectTypes") or "",
    "remote_debug_python_available": "yes" if available.get("python-pdb") else "no",
    "remote_debug_node_available": "yes" if available.get("node-inspect") else "no",
    "remote_debug_lldb_available": "yes" if available.get("lldb") else "no",
    "remote_debug_target_absolute_path": target.get("absolutePath") or "",
    "remote_debug_target_entry_path": target.get("entryPath") or "",
    "remote_debug_target_display": target.get("displayTarget") or "",
    "remote_debug_target_line": target.get("line") if target.get("line") is not None else "",
    "remote_debug_target_column": target.get("column") if target.get("column") is not None else "",
    "remote_debug_target_extension": target.get("extension") or "",
    "remote_debug_target_is_file": "yes" if target.get("isFile") else "no",
    "remote_debug_target_is_executable": "yes" if target.get("isExecutable") else "no",
}
for key, value in fields.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
}

debug_relative_target_path() {
    local root="$1"
    local absolute_path="$2"

    python3 - "${root}" "${absolute_path}" <<'PY'
import os
import sys

root = os.path.abspath(sys.argv[1] or os.getcwd())
path = os.path.abspath(sys.argv[2] or root)

try:
    common = os.path.commonpath([root, path])
except ValueError:
    common = ""

if common == root:
    rel = os.path.relpath(path, root)
    print(rel if rel and rel != "." else os.path.basename(path))
else:
    print(path)
PY
}

debug_tool_available() {
    local tool="$1"

    case "${tool}" in
        python-pdb)
            command -v python3 >/dev/null 2>&1
            ;;
        node-inspect)
            command -v node >/dev/null 2>&1
            ;;
        lldb)
            command -v lldb >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

debug_tool_missing_hint() {
    local tool="$1"
    case "${tool}" in
        python-pdb)
            printf "Install Python 3 so python3 -m pdb is available on PATH.\n"
            ;;
        node-inspect)
            printf "Install Node.js so node inspect is available on PATH.\n"
            ;;
        lldb)
            printf "Install Xcode Command Line Tools so lldb is available on PATH.\n"
            ;;
        *)
            printf "Install the required local debugger toolchain and rerun.\n"
            ;;
    esac
}

debug_tool_title() {
    local tool="$1"
    case "${tool}" in
        python-pdb)
            printf "Python pdb\n"
            ;;
        node-inspect)
            printf "Node inspect\n"
            ;;
        lldb)
            printf "LLDB\n"
            ;;
        *)
            printf "%s\n" "${tool}"
            ;;
    esac
}

debug_family_rows_for_root() {
    local root="$1"
    local project_types=""
    local python_recommended="no"
    local node_recommended="no"
    local native_recommended="no"
    local python_available="no"
    local node_available="no"
    local lldb_available="no"
    local python_hint=""
    local node_hint=""
    local lldb_hint=""

    project_types=$(detect_project_types "${root}")
    case ",${project_types}," in
        *,python,*)
            python_recommended="yes"
            ;;
    esac
    case ",${project_types}," in
        *,node,*)
            node_recommended="yes"
            ;;
    esac
    case ",${project_types}," in
        *,go,*|*,rust,*|*,swift,*|*,zig,*)
            native_recommended="yes"
            ;;
    esac

    if debug_tool_available "python-pdb"; then
        python_available="yes"
    else
        python_hint=$(debug_tool_missing_hint "python-pdb")
    fi

    if debug_tool_available "node-inspect"; then
        node_available="yes"
    else
        node_hint=$(debug_tool_missing_hint "node-inspect")
    fi

    if debug_tool_available "lldb"; then
        lldb_available="yes"
    else
        lldb_hint=$(debug_tool_missing_hint "lldb")
    fi

    printf "python-pdb\tPython pdb\t%s\t%s\tfull-line\tpython-entry\tLocal .py entry files using the shared path:line[:col] target contract.\t%s\n" \
        "${python_available}" "${python_recommended}" "${python_hint}"
    printf "node-inspect\tNode inspect\t%s\t%s\tentry-only\tnode-entry\tLocal .js/.mjs/.cjs entry files. Semantic line targets are recorded, but the CLI still opens at program entry.\t%s\n" \
        "${node_available}" "${node_recommended}" "${node_hint}"
    printf "lldb\tLLDB\t%s\t%s\texecutable-only\texecutable\tExplicit local executable targets only. Source-file to binary inference is not shipped yet.\t%s\n" \
        "${lldb_available}" "${native_recommended}" "${lldb_hint}"
}

debug_recommended_tool_for_project_types() {
    local project_types="$1"

    case ",${project_types}," in
        *,python,*)
            if [[ "${project_types}" != *node* ]]; then
                printf "python-pdb\n"
                return 0
            fi
            ;;
    esac
    case ",${project_types}," in
        *,node,*)
            if [[ "${project_types}" != *python* ]]; then
                printf "node-inspect\n"
                return 0
            fi
            ;;
    esac
    case ",${project_types}," in
        *,go,*|*,rust,*|*,swift,*|*,zig,*)
            printf "lldb\n"
            return 0
            ;;
    esac
    printf "\n"
}

debug_blocked_topologies_text() {
    cat <<'EOF'
attach-to-pid flows
TypeScript direct-file launch
Go package debug
Rust package debug
zero-config adapter installs beyond the shipped Python/Node/LLDB baseline
EOF
}

debug_recommended_tool_for_root() {
    local root="$1"
    local project_types=""

    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
        project_types="${IDE_WORKSPACE_SUMMARY_TYPES}"
    else
        project_types=$(detect_project_types "${root}")
    fi
    debug_recommended_tool_for_project_types "${project_types}"
}

debug_root_for_absolute_target() {
    local absolute_path="$1"
    local root=""

    root=$(find_project_root "${absolute_path}")
    if [[ -f "${root}" ]]; then
        dirname "${root}"
        return 0
    fi
    printf "%s\n" "${root}"
}

DEBUG_STATUS_TARGET_ROOT=""

debug_status_resolve_root() {
    local target="$1"

    DEBUG_STATUS_TARGET_ROOT=""
    debug_resolve_root_into_shell "${target}" || return 1
    DEBUG_STATUS_TARGET_ROOT="${DEBUG_RESOLVED_ROOT}"
}

debug_status_family_rows_for_root() {
    local root="$1"
    local execution_target="${2:-workspace}"
    local project_types=""
    local recommended_tool=""
    local python_recommended="no"
    local node_recommended="no"
    local native_recommended="no"
    local remote_snapshot=""
    local remote_hint_prefix=""

    execution_target=$(debug_execution_target_normalize "${execution_target}") || return 1
    if [[ "${execution_target}" == "devcontainer" ]]; then
        debug_devcontainer_family_rows_for_root "${root}"
        return 0
    fi

    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
        remote_snapshot=$(debug_remote_probe_json "${IDE_WORKSPACE_REQUESTED_PATH}") || return 1
        eval "$(debug_remote_snapshot_shell_vars "${remote_snapshot}")"
        project_types="${remote_debug_project_types:-${IDE_WORKSPACE_SUMMARY_TYPES}}"
        recommended_tool=$(debug_recommended_tool_for_project_types "${project_types}")
        [[ "${recommended_tool}" == "python-pdb" ]] && python_recommended="yes"
        [[ "${recommended_tool}" == "node-inspect" ]] && node_recommended="yes"
        [[ "${recommended_tool}" == "lldb" ]] && native_recommended="yes"
        remote_hint_prefix="Run through ssh-backed launch plans with --project ${IDE_WORKSPACE_REQUESTED_TARGET:-${IDE_WORKSPACE_IDENTITY}}."
        printf "python-pdb\tPython pdb\t%s\t%s\tfull-line\tpython-entry\tRemote .py entry files using the shared path:line[:col] target contract over SSH.\t%s %s\n" \
            "${remote_debug_python_available:-no}" "${python_recommended}" \
            "$( [[ "${remote_debug_python_available:-no}" == "yes" ]] && printf "" || debug_tool_missing_hint "python-pdb" )" \
            "${remote_hint_prefix}"
        printf "node-inspect\tNode inspect\t%s\t%s\tentry-only\tnode-entry\tRemote .js/.mjs/.cjs entry files. Semantic line targets are recorded, but the CLI still opens at program entry.\t%s %s\n" \
            "${remote_debug_node_available:-no}" "${node_recommended}" \
            "$( [[ "${remote_debug_node_available:-no}" == "yes" ]] && printf "" || debug_tool_missing_hint "node-inspect" )" \
            "${remote_hint_prefix}"
        printf "lldb\tLLDB\t%s\t%s\texecutable-only\texecutable\tExplicit remote executable targets only. Source-file to binary inference is not shipped yet.\t%s %s\n" \
            "${remote_debug_lldb_available:-no}" "${native_recommended}" \
            "$( [[ "${remote_debug_lldb_available:-no}" == "yes" ]] && printf "" || debug_tool_missing_hint "lldb" )" \
            "${remote_hint_prefix}"
        return 0
    fi

    debug_family_rows_for_root "${root}"
}

debug_status_json_for_root() {
    local root="$1"
    local execution_target="${2:-workspace}"
    local workspace_execution_location="local"
    local workspace_transport="local"
    local workspace_identity=""
    local workspace_requested_path="${root}"
    local workspace_requested_target="${IDE_WORKSPACE_REQUESTED_TARGET}"
    local workspace_authority=""
    local workspace_port=""
    local workspace_label=""
    local project_metadata_source="local-filesystem"
    local state_source="local-ide-state"
    local timeline_source="local-ide-state"
    local workspace_note="Project metadata and runtime evidence come from the local workspace and local IDE state."
    local trusted="no"
    local runtime_state=""
    local state_snapshot=""
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
    local state_file=""
    local recommended_tool=""
    local family_rows=""
    local blocked=""
    local managed_session=""
    local managed_state=""
    local project_types=""
    local guidance=""
    local devcontainer_context=""
    local local_only="yes"

    execution_target=$(debug_execution_target_normalize "${execution_target}") || return 1

    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
        workspace_execution_location="${IDE_WORKSPACE_EXECUTION_LOCATION:-remote}"
        workspace_transport="${IDE_WORKSPACE_TRANSPORT:-ssh}"
        workspace_identity="${IDE_WORKSPACE_IDENTITY}"
        workspace_requested_path="${IDE_WORKSPACE_REQUESTED_PATH}"
        workspace_requested_target="${IDE_WORKSPACE_REQUESTED_TARGET}"
        workspace_authority="${IDE_WORKSPACE_AUTHORITY}"
        workspace_port="${IDE_WORKSPACE_PORT}"
        workspace_label="${IDE_WORKSPACE_LABEL}"
        project_metadata_source=$(workspace_summary_project_metadata_source)
        state_source=$(workspace_summary_state_source)
        timeline_source=$(workspace_summary_timeline_source)
        workspace_note=$(workspace_summary_note)
        project_types="${IDE_WORKSPACE_SUMMARY_TYPES}"
    else
        workspace_identity=$(workspace_identity_for_root "${root}")
        project_types=$(detect_project_types "${root}")
    fi

    if is_debug_trusted_project "${root}"; then
        trusted="yes"
    fi

    runtime_state=$(debug_runtime_state "${root}")
    state_snapshot=$(debug_state_snapshot "${root}")
    last_tool=$(doctor_snapshot_value "${state_snapshot}" "tool")
    last_target=$(doctor_snapshot_value "${state_snapshot}" "target")
    last_display_target=$(doctor_snapshot_value "${state_snapshot}" "display_target")
    last_line=$(doctor_snapshot_value "${state_snapshot}" "line")
    last_column=$(doctor_snapshot_value "${state_snapshot}" "column")
    last_line_applied=$(doctor_snapshot_value "${state_snapshot}" "line_applied")
    last_started_at=$(doctor_snapshot_value "${state_snapshot}" "last_started_at")
    last_ended_at=$(doctor_snapshot_value "${state_snapshot}" "last_ended_at")
    last_exit_code=$(doctor_snapshot_value "${state_snapshot}" "last_exit_code")
    last_status=$(doctor_snapshot_value "${state_snapshot}" "status")
    last_command=$(doctor_snapshot_value "${state_snapshot}" "command")
    last_summary_report=$(doctor_snapshot_value "${state_snapshot}" "summary_report")
    last_details_report=$(doctor_snapshot_value "${state_snapshot}" "details_report")
    state_file=$(debug_state_file "${root}")
    recommended_tool=$(debug_recommended_tool_for_project_types "${project_types}")
    family_rows=$(debug_status_family_rows_for_root "${root}" "${execution_target}")
    blocked=$(debug_blocked_topologies_text)
    devcontainer_context=$(debug_devcontainer_context_json_for_root "${root}" "$( [[ "${execution_target}" == "devcontainer" ]] && printf "1" || printf "0" )")
    if [[ "${execution_target}" == "devcontainer" ]]; then
        guidance=$(DEBUG_DEVCONTAINER_CONTEXT="${devcontainer_context}" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("DEBUG_DEVCONTAINER_CONTEXT") or "{}")
print(payload.get("guidance") or "")
PY
)
        local_only="no"
    elif [[ "${workspace_execution_location}" == "remote" ]]; then
        guidance="Remote debugger execution now runs through the shared local session helper over SSH. Use yen ide debug start <target> --project ${IDE_WORKSPACE_REQUESTED_TARGET:-${IDE_WORKSPACE_IDENTITY}} and add --managed when you want live controls."
        local_only="no"
    elif DEBUG_DEVCONTAINER_CONTEXT="${devcontainer_context}" python3 - <<'PY' | grep -qx "yes"
import json
import os
payload = json.loads(os.environ.get("DEBUG_DEVCONTAINER_CONTEXT") or "{}")
print("yes" if payload.get("debugExecutionAvailable") else "no")
PY
    then
        guidance=$(DEBUG_DEVCONTAINER_CONTEXT="${devcontainer_context}" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("DEBUG_DEVCONTAINER_CONTEXT") or "{}")
selector = payload.get("projectSelector") or payload.get("root") or ""
print(
    "Tracked devcontainer debugger execution is also available. "
    f"Inspect readiness with yen ide debug status --devcontainer --project {selector} "
    "or launch directly with yen ide debug start <target> --devcontainer."
)
PY
)
        local_only="no"
    fi
    if [[ "$(doctor_snapshot_value "${state_snapshot}" "managed")" == "yes" ]]; then
        managed_session=$(debug_managed_status_json_for_root "${root}")
        if [[ -n "${managed_session}" ]]; then
            debug_sync_managed_state_from_json "${root}" "${managed_session}"
            state_snapshot=$(debug_state_snapshot "${root}")
            runtime_state=$(DEBUG_MANAGED_STATUS_PAYLOAD="${managed_session}" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("DEBUG_MANAGED_STATUS_PAYLOAD") or "{}")
session = payload.get("session") or {}
status = (session.get("status") or "").strip()
if status:
    print(status)
else:
    print("stopped")
PY
)
            managed_state=$(DEBUG_MANAGED_STATUS_PAYLOAD="${managed_session}" python3 - <<'PY'
import json
import os
payload = json.loads(os.environ.get("DEBUG_MANAGED_STATUS_PAYLOAD") or "{}")
print(json.dumps((payload.get("session") or {}), sort_keys=True))
PY
)
            last_ended_at=$(doctor_snapshot_value "${state_snapshot}" "last_ended_at")
            last_exit_code=$(doctor_snapshot_value "${state_snapshot}" "last_exit_code")
            last_status=$(doctor_snapshot_value "${state_snapshot}" "status")
        fi
    fi

    DEBUG_STATUS_ROOT="${root}" \
    DEBUG_STATUS_TRUSTED="${trusted}" \
    DEBUG_STATUS_RUNTIME_STATE="${runtime_state}" \
    DEBUG_STATUS_LAST_TOOL="${last_tool}" \
    DEBUG_STATUS_LAST_TARGET="${last_target}" \
    DEBUG_STATUS_LAST_DISPLAY_TARGET="${last_display_target}" \
    DEBUG_STATUS_LAST_LINE="${last_line}" \
    DEBUG_STATUS_LAST_COLUMN="${last_column}" \
    DEBUG_STATUS_LAST_LINE_APPLIED="${last_line_applied}" \
    DEBUG_STATUS_LAST_STARTED_AT="${last_started_at}" \
    DEBUG_STATUS_LAST_ENDED_AT="${last_ended_at}" \
    DEBUG_STATUS_LAST_EXIT_CODE="${last_exit_code}" \
    DEBUG_STATUS_LAST_STATUS="${last_status}" \
    DEBUG_STATUS_LAST_COMMAND="${last_command}" \
    DEBUG_STATUS_LAST_SUMMARY_REPORT="${last_summary_report}" \
    DEBUG_STATUS_LAST_DETAILS_REPORT="${last_details_report}" \
    DEBUG_STATUS_STATE_FILE="${state_file}" \
    DEBUG_STATUS_RECOMMENDED_TOOL="${recommended_tool}" \
    DEBUG_STATUS_FAMILY_ROWS="${family_rows}" \
    DEBUG_STATUS_BLOCKED="${blocked}" \
    DEBUG_STATUS_MANAGED_SESSION="${managed_state}" \
    DEBUG_STATUS_EXECUTION_TARGET="${execution_target}" \
    DEBUG_STATUS_WORKSPACE_EXECUTION_LOCATION="${workspace_execution_location}" \
    DEBUG_STATUS_WORKSPACE_TRANSPORT="${workspace_transport}" \
    DEBUG_STATUS_WORKSPACE_IDENTITY="${workspace_identity}" \
    DEBUG_STATUS_WORKSPACE_REQUESTED_PATH="${workspace_requested_path}" \
    DEBUG_STATUS_WORKSPACE_REQUESTED_TARGET="${workspace_requested_target}" \
    DEBUG_STATUS_WORKSPACE_AUTHORITY="${workspace_authority}" \
    DEBUG_STATUS_WORKSPACE_PORT="${workspace_port}" \
    DEBUG_STATUS_WORKSPACE_LABEL="${workspace_label}" \
    DEBUG_STATUS_PROJECT_METADATA_SOURCE="${project_metadata_source}" \
    DEBUG_STATUS_STATE_SOURCE="${state_source}" \
    DEBUG_STATUS_TIMELINE_SOURCE="${timeline_source}" \
    DEBUG_STATUS_WORKSPACE_NOTE="${workspace_note}" \
    DEBUG_STATUS_GUIDANCE="${guidance}" \
    DEBUG_STATUS_DEVCONTAINER_CONTEXT="${devcontainer_context}" \
    DEBUG_STATUS_LOCAL_ONLY="${local_only}" \
    python3 - <<'PY'
import json
import os


def load_families(raw: str):
    rows = []
    for line in (raw or "").splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 8:
            continue
        rows.append(
            {
                "id": parts[0],
                "title": parts[1],
                "available": parts[2] == "yes",
                "recommended": parts[3] == "yes",
                "lineMode": parts[4],
                "targetMode": parts[5],
                "detail": parts[6],
                "hint": parts[7],
            }
        )
    return rows


families = load_families(os.environ.get("DEBUG_STATUS_FAMILY_ROWS", ""))
blocked = [line for line in (os.environ.get("DEBUG_STATUS_BLOCKED") or "").splitlines() if line]
active = os.environ.get("DEBUG_STATUS_RUNTIME_STATE") == "running"
try:
    managed_session = json.loads(os.environ.get("DEBUG_STATUS_MANAGED_SESSION") or "{}")
except Exception:
    managed_session = {}
if managed_session.get("active"):
    active = True
try:
    devcontainer_context = json.loads(os.environ.get("DEBUG_STATUS_DEVCONTAINER_CONTEXT") or "{}")
except Exception:
    devcontainer_context = {}

payload = {
    "schemaVersion": 1,
    "root": os.environ.get("DEBUG_STATUS_ROOT", ""),
    "executionTarget": os.environ.get("DEBUG_STATUS_EXECUTION_TARGET", "workspace") or "workspace",
    "workspace": {
        "executionLocation": os.environ.get("DEBUG_STATUS_WORKSPACE_EXECUTION_LOCATION", "local"),
        "transport": os.environ.get("DEBUG_STATUS_WORKSPACE_TRANSPORT", "local"),
        "identity": os.environ.get("DEBUG_STATUS_WORKSPACE_IDENTITY", ""),
        "requestedPath": os.environ.get("DEBUG_STATUS_WORKSPACE_REQUESTED_PATH", ""),
        "requestedTarget": os.environ.get("DEBUG_STATUS_WORKSPACE_REQUESTED_TARGET", ""),
        "authority": os.environ.get("DEBUG_STATUS_WORKSPACE_AUTHORITY", ""),
        "port": int(os.environ.get("DEBUG_STATUS_WORKSPACE_PORT") or "0") if os.environ.get("DEBUG_STATUS_WORKSPACE_PORT") else None,
        "label": os.environ.get("DEBUG_STATUS_WORKSPACE_LABEL", ""),
    },
    "evidence": {
        "projectMetadataSource": os.environ.get("DEBUG_STATUS_PROJECT_METADATA_SOURCE", "local-filesystem"),
        "stateSource": os.environ.get("DEBUG_STATUS_STATE_SOURCE", "local-ide-state"),
        "timelineSource": os.environ.get("DEBUG_STATUS_TIMELINE_SOURCE", "local-ide-state"),
        "note": os.environ.get("DEBUG_STATUS_WORKSPACE_NOTE", ""),
    },
    "trusted": os.environ.get("DEBUG_STATUS_TRUSTED") == "yes",
    "state": os.environ.get("DEBUG_STATUS_RUNTIME_STATE", "stopped") or "stopped",
    "active": active,
    "recommendedTool": os.environ.get("DEBUG_STATUS_RECOMMENDED_TOOL", ""),
    "guidance": os.environ.get("DEBUG_STATUS_GUIDANCE", ""),
    "blockedTopologies": blocked,
    "stateFile": os.environ.get("DEBUG_STATUS_STATE_FILE", ""),
    "lastSession": {
        "tool": os.environ.get("DEBUG_STATUS_LAST_TOOL", ""),
        "target": os.environ.get("DEBUG_STATUS_LAST_TARGET", ""),
        "displayTarget": os.environ.get("DEBUG_STATUS_LAST_DISPLAY_TARGET", ""),
        "line": int(os.environ.get("DEBUG_STATUS_LAST_LINE") or "0") if (os.environ.get("DEBUG_STATUS_LAST_LINE") or "").isdigit() else None,
        "column": int(os.environ.get("DEBUG_STATUS_LAST_COLUMN") or "0") if (os.environ.get("DEBUG_STATUS_LAST_COLUMN") or "").isdigit() else None,
        "lineApplied": os.environ.get("DEBUG_STATUS_LAST_LINE_APPLIED", "") == "yes",
        "startedAt": os.environ.get("DEBUG_STATUS_LAST_STARTED_AT", ""),
        "endedAt": os.environ.get("DEBUG_STATUS_LAST_ENDED_AT", ""),
        "exitCode": int(os.environ.get("DEBUG_STATUS_LAST_EXIT_CODE") or "0") if (os.environ.get("DEBUG_STATUS_LAST_EXIT_CODE") or "").strip("-").isdigit() else None,
        "status": os.environ.get("DEBUG_STATUS_LAST_STATUS", ""),
        "command": os.environ.get("DEBUG_STATUS_LAST_COMMAND", ""),
        "summaryReport": os.environ.get("DEBUG_STATUS_LAST_SUMMARY_REPORT", ""),
        "detailsReport": os.environ.get("DEBUG_STATUS_LAST_DETAILS_REPORT", ""),
        "reportsReady": bool(
            os.environ.get("DEBUG_STATUS_LAST_SUMMARY_REPORT")
            and os.path.isfile(os.environ.get("DEBUG_STATUS_LAST_SUMMARY_REPORT", ""))
            and os.environ.get("DEBUG_STATUS_LAST_DETAILS_REPORT")
            and os.path.isfile(os.environ.get("DEBUG_STATUS_LAST_DETAILS_REPORT", ""))
        ),
    },
    "families": families,
    "managedSession": managed_session or None,
    "devcontainerContext": devcontainer_context or None,
    "localOnly": os.environ.get("DEBUG_STATUS_LOCAL_ONLY", "yes") == "yes",
}

print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

debug_status_text_from_payload() {
    local payload="$1"
    DEBUG_STATUS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("DEBUG_STATUS_PAYLOAD") or "{}")
families = payload.get("families") or []
last = payload.get("lastSession") or {}
managed = payload.get("managedSession") or {}
workspace = payload.get("workspace") or {}
evidence = payload.get("evidence") or {}
devcontainer = payload.get("devcontainerContext") or {}


def text(value, fallback=""):
    value = "" if value is None else str(value).strip()
    return value if value else fallback


print("")
print("IDE Debug Baseline")
print(f"Project root:       {text(payload.get('root'))}")
print(f"Execution:          {text(workspace.get('executionLocation'), 'local')}")
print(f"Transport:          {text(workspace.get('transport'), 'local')}")
print(f"Execution target:   {text(payload.get('executionTarget'), 'workspace')}")
if workspace.get("identity"):
    print(f"Workspace identity: {text(workspace.get('identity'))}")
if workspace.get("requestedTarget") and workspace.get("requestedTarget") != payload.get("root"):
    print(f"Requested target:   {text(workspace.get('requestedTarget'))}")
print(f"Trusted:            {'yes' if payload.get('trusted') else 'no'}")
print(f"State:              {text(payload.get('state'), 'stopped')}")
print(f"Recommended tool:   {text(payload.get('recommendedTool'), 'choose per target')}")
print(f"State file:         {text(payload.get('stateFile'), 'missing')}")
if evidence:
    print(f"Metadata source:    {text(evidence.get('projectMetadataSource'), 'local-filesystem')}")
    print(f"State source:       {text(evidence.get('stateSource'), 'local-ide-state')}")
if payload.get("guidance"):
    print(f"Guidance:           {text(payload.get('guidance'))}")
if devcontainer:
    print("")
    print("Devcontainer:")
    print(f"  Supported:        {'yes' if devcontainer.get('supported') else 'no'}")
    print(f"  Trusted:          {'yes' if devcontainer.get('trusted') else 'no'}")
    print(f"  State:            {text(devcontainer.get('state'), 'stopped')}")
    print(f"  Health:           {text(devcontainer.get('health'), 'inactive')}")
    if devcontainer.get("cli"):
        print(f"  CLI:              {text(devcontainer.get('cli'))}")
    if devcontainer.get("workspaceFolder"):
        print(f"  Workspace:        {text(devcontainer.get('workspaceFolder'))}")
    if devcontainer.get("debugExecutionAvailable") is not None:
        print(f"  Debug ready:      {'yes' if devcontainer.get('debugExecutionAvailable') else 'no'}")
    if devcontainer.get("debugRecommendedTool"):
        print(f"  Debug tool:       {text(devcontainer.get('debugRecommendedTool'))}")
        print(f"  Tool ready:       {'yes' if devcontainer.get('debugRecommendedAvailable') else 'no'}")
    if devcontainer.get("guidance"):
        print(f"  Guidance:         {text(devcontainer.get('guidance'))}")
print("")
print("Last Session:")
print(f"  Tool:             {text(last.get('tool'), 'never run')}")
print(f"  Target:           {text(last.get('displayTarget') or last.get('target'), 'never run')}")
print(f"  Line applied:     {'yes' if last.get('lineApplied') else 'no'}")
print(f"  Started:          {text(last.get('startedAt'), 'never')}")
print(f"  Ended:            {text(last.get('endedAt'), 'never')}")
print(f"  Exit code:        {text(last.get('exitCode'), 'n/a')}")
print(f"  Status:           {text(last.get('status'), 'never')}")
print(f"  Command:          {text(last.get('command'), 'n/a')}")
print(f"  Summary report:   {text(last.get('summaryReport'), 'missing')}")
print(f"  Details report:   {text(last.get('detailsReport'), 'missing')}")
if managed:
    print("")
    print("Managed Session:")
    print(f"  Active:           {'yes' if managed.get('active') else 'no'}")
    print(f"  Status:           {text(managed.get('status'), 'unknown')}")
    print(f"  Location:         {text(managed.get('lastStopLocation'), 'unknown')}")
    print(f"  Transcript:       {text(last.get('detailsReport'), 'missing')}")
    breakpoints = managed.get("breakpoints") or []
    watches = managed.get("watches") or []
    print(f"  Breakpoints:      {len(breakpoints)}")
    print(f"  Watches:          {len(watches)}")
    for row in breakpoints[:4]:
        print(f"    bp {text(row.get('id'))}: {text(row.get('location') or row.get('spec'))}")
    for row in watches[:4]:
        value = text(row.get("lastValue"), row.get("lastError"))
        print(f"    watch {text(row.get('id'))}: {text(row.get('expression'))} => {value}")
print("")
print(f"{'FAMILY':<14} {'AVAIL':<6} {'RECOMM':<7} {'LINE MODE':<15} TARGET MODE")
for family in families:
    print(
        f"{text(family.get('id')):<14} "
        f"{('yes' if family.get('available') else 'no'):<6} "
        f"{('yes' if family.get('recommended') else 'no'):<7} "
        f"{text(family.get('lineMode')):<15} "
        f"{text(family.get('targetMode'))}"
    )
    detail = text(family.get("detail"))
    if detail:
        print(f"  {detail}")
    hint = text(family.get("hint"))
    if hint:
        print(f"  {hint}")
print("")
print("Blocked Topologies:")
for item in payload.get("blockedTopologies") or []:
    print(f"  - {text(item)}")
print("")
print("Controls:")
project_selector = text(workspace.get("requestedTarget") or payload.get("root"))
devcontainer_selector = text(devcontainer.get("projectSelector"), project_selector)
if payload.get("executionTarget") == "devcontainer":
    print(f"  Trust:      yen ide debug trust {project_selector}")
    print(f"  Status:     yen ide debug status --devcontainer --project {devcontainer_selector}")
    print(f"  TUI:        yen ide debug tui --devcontainer --project {devcontainer_selector}")
    print(f"  Start:      yen ide debug start src/app.py:12 --devcontainer --project {devcontainer_selector}")
    print(f"  Managed:    yen ide debug start src/app.py:12 --managed --devcontainer --project {devcontainer_selector}")
    print(f"  Continue:   yen ide debug continue --project {project_selector}")
    print(f"  Transcript: yen ide debug transcript --project {project_selector} --tail 80")
    print(f"  Stop:       yen ide debug stop --project {project_selector}")
elif workspace.get("executionLocation") == "remote":
    print(f"  Trust:      yen ide debug trust {project_selector}")
    print(f"  Status:     yen ide debug status {project_selector}")
    print(f"  TUI:        yen ide debug tui {project_selector}")
    print(f"  Start:      yen ide debug start src/app.py:12 --project {project_selector}")
    print(f"  Managed:    yen ide debug start src/app.py:12 --managed --project {project_selector}")
    if devcontainer.get("debugExecutionAvailable"):
        print(f"  Container:  yen ide debug start src/app.py:12 --managed --devcontainer --project {devcontainer_selector}")
    print(f"  Continue:   yen ide debug continue --project {project_selector}")
    print(f"  Transcript: yen ide debug transcript --project {project_selector} --tail 80")
    print(f"  Stop:       yen ide debug stop --project {project_selector}")
else:
    print(f"  Trust:      yen ide debug trust {text(payload.get('root'))}")
    print(f"  TUI:        yen ide debug tui {text(payload.get('root'))}")
    print(f"  Start:      yen ide debug start path/to/file.py:12 --project {text(payload.get('root'))}")
    print(f"  Managed:    yen ide debug start path/to/file.py:12 --managed --project {text(payload.get('root'))}")
    if devcontainer.get("debugExecutionAvailable"):
        print(f"  Container:  yen ide debug start path/to/file.py:12 --managed --devcontainer --project {devcontainer_selector}")
    print(f"  Continue:   yen ide debug continue --project {text(payload.get('root'))}")
    print(f"  Next:       yen ide debug next --project {text(payload.get('root'))}")
    print(f"  Breakpoint: yen ide debug breakpoint add path/to/file.py:12 --project {text(payload.get('root'))}")
    print(f"  Watch:      yen ide debug watch add variable_name --project {text(payload.get('root'))}")
    print(f"  Inspect:    yen ide debug inspect x --project {text(payload.get('root'))}")
    print(f"  Transcript: yen ide debug transcript --project {text(payload.get('root'))} --tail 80")
    print(f"  Stop:       yen ide debug stop --project {text(payload.get('root'))}")
print("")
PY
}

debug_resolve_plan() {
    local raw_target="$1"
    local root="$2"
    local requested_tool="$3"
    local execution_target="workspace"
    if [[ $# -gt 3 ]]; then
        execution_target="${4:-workspace}"
        shift 4
    else
        shift 3
    fi
    local program_args=("$@")
    local absolute_path=""
    local display_path=""
    local line=""
    local column=""
    local tool=""
    local entry_path=""
    local line_applied="no"
    local -a argv=()
    local -a notes=()
    local note_text=""
    local extension=""
    local remote_snapshot=""
    local remote_command=""
    local ssh_bin=""
    local devcontainer_context=""

    execution_target=$(debug_execution_target_normalize "${execution_target}") || return 1
    if [[ "${execution_target}" == "devcontainer" ]]; then
        devcontainer_context=$(debug_devcontainer_context_json_for_root "${root}" "1")
        eval "$(debug_devcontainer_context_shell_vars "${devcontainer_context}")"
        if [[ "${debug_devcontainer_execution_available:-no}" != "yes" ]]; then
            yen_error "${debug_devcontainer_guidance:-Tracked devcontainer execution is unavailable.}"
            return 1
        fi
    fi

    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
        remote_snapshot=$(debug_remote_probe_json "${IDE_WORKSPACE_REQUESTED_PATH}" "${raw_target}") || return 1
        eval "$(debug_remote_snapshot_shell_vars "${remote_snapshot}")"

        absolute_path="${remote_debug_target_absolute_path}"
        display_path="${remote_debug_target_display:-${raw_target}}"
        line="${remote_debug_target_line}"
        column="${remote_debug_target_column}"
        extension=$(printf "%s" "${remote_debug_target_extension}" | tr '[:upper:]' '[:lower:]')
        entry_path="${remote_debug_target_entry_path}"
    else
        if ! editor_handoff_parse_target "${raw_target}" "${root}"; then
            yen_error "Unable to resolve debug target '${raw_target}'."
            return 1
        fi

        absolute_path="${EDITOR_HANDOFF_ABSOLUTE_PATH}"
        display_path="${EDITOR_HANDOFF_LOCATION}"
        line="${EDITOR_HANDOFF_LINE}"
        column="${EDITOR_HANDOFF_COLUMN}"
        extension=$(printf "%s" "${absolute_path##*.}" | tr '[:upper:]' '[:lower:]')
    fi

    tool="${requested_tool}"
    if [[ -z "${tool}" || "${tool}" == "auto" ]]; then
        case "${extension}" in
            py)
                tool="python-pdb"
                ;;
            js|mjs|cjs)
                tool="node-inspect"
                ;;
            ts|tsx|jsx)
                yen_error "Direct ${extension} debugger launch is not shipped. Use a runnable JavaScript entry file or an external editor debugger for now."
                return 1
                ;;
            *)
                if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
                    if [[ "${remote_debug_target_is_executable:-no}" == "yes" ]]; then
                        tool="lldb"
                    else
                        yen_error "Unable to infer a shipped debugger family for '${display_path}'. Supported targets are .py files, .js/.mjs/.cjs files, or explicit executables in the selected workspace."
                        return 1
                    fi
                elif [[ -f "${absolute_path}" && -x "${absolute_path}" ]]; then
                    tool="lldb"
                else
                    yen_error "Unable to infer a shipped debugger family for '${display_path}'. Supported targets are .py files, .js/.mjs/.cjs files, or explicit executables in the selected workspace."
                    return 1
                fi
                ;;
        esac
    fi

    case "${tool}" in
        python-pdb)
            if [[ "${execution_target}" == "devcontainer" ]]; then
                if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
                    if [[ "${remote_debug_target_is_file:-no}" != "yes" || "${extension}" != "py" ]]; then
                        yen_error "python-pdb only supports remote .py entry files."
                        return 1
                    fi
                else
                    if [[ ! -f "${absolute_path}" || "${extension}" != "py" ]]; then
                        yen_error "python-pdb only supports local .py entry files."
                        return 1
                    fi
                    entry_path=$(debug_relative_target_path "${root}" "${absolute_path}")
                fi
                if [[ "${debug_devcontainer_python_available:-no}" != "yes" ]]; then
                    yen_error "$(debug_devcontainer_missing_hint "${tool}")"
                    return 1
                fi
            elif workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
                if [[ "${remote_debug_target_is_file:-no}" != "yes" || "${extension}" != "py" ]]; then
                    yen_error "python-pdb only supports remote .py entry files."
                    return 1
                fi
                if [[ "${remote_debug_python_available:-no}" != "yes" ]]; then
                    yen_error "$(debug_tool_missing_hint "${tool}")"
                    return 1
                fi
            else
                if [[ ! -f "${absolute_path}" || "${extension}" != "py" ]]; then
                    yen_error "python-pdb only supports local .py entry files."
                    return 1
                fi
                if ! debug_tool_available "${tool}"; then
                    yen_error "$(debug_tool_missing_hint "${tool}")"
                    return 1
                fi
                entry_path=$(debug_relative_target_path "${root}" "${absolute_path}")
            fi
            argv=("python3" "-m" "pdb")
            if [[ -n "${line}" ]] && [[ "${line}" =~ ^[0-9]+$ ]] && [[ "${line}" -gt 1 ]]; then
                argv+=("-c" "until ${line}")
                line_applied="yes"
                notes+=("pdb will run until line ${line} in the entry script before handing control to the terminal.")
            fi
            argv+=("${entry_path}")
            ;;
        node-inspect)
            if [[ "${execution_target}" == "devcontainer" ]]; then
                if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
                    if [[ "${remote_debug_target_is_file:-no}" != "yes" || ( "${extension}" != "js" && "${extension}" != "mjs" && "${extension}" != "cjs" ) ]]; then
                        yen_error "node-inspect only supports remote .js/.mjs/.cjs entry files."
                        return 1
                    fi
                else
                    if [[ ! -f "${absolute_path}" || ( "${extension}" != "js" && "${extension}" != "mjs" && "${extension}" != "cjs" ) ]]; then
                        yen_error "node-inspect only supports local .js/.mjs/.cjs entry files."
                        return 1
                    fi
                    entry_path=$(debug_relative_target_path "${root}" "${absolute_path}")
                fi
                if [[ "${debug_devcontainer_node_available:-no}" != "yes" ]]; then
                    yen_error "$(debug_devcontainer_missing_hint "${tool}")"
                    return 1
                fi
            elif workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
                if [[ "${remote_debug_target_is_file:-no}" != "yes" || ( "${extension}" != "js" && "${extension}" != "mjs" && "${extension}" != "cjs" ) ]]; then
                    yen_error "node-inspect only supports remote .js/.mjs/.cjs entry files."
                    return 1
                fi
                if [[ "${remote_debug_node_available:-no}" != "yes" ]]; then
                    yen_error "$(debug_tool_missing_hint "${tool}")"
                    return 1
                fi
            else
                if [[ ! -f "${absolute_path}" || ( "${extension}" != "js" && "${extension}" != "mjs" && "${extension}" != "cjs" ) ]]; then
                    yen_error "node-inspect only supports local .js/.mjs/.cjs entry files."
                    return 1
                fi
                if ! debug_tool_available "${tool}"; then
                    yen_error "$(debug_tool_missing_hint "${tool}")"
                    return 1
                fi
                entry_path=$(debug_relative_target_path "${root}" "${absolute_path}")
            fi
            argv=("node" "inspect" "--port=0" "${entry_path}")
            if [[ -n "${line}" ]]; then
                notes+=("node inspect still opens at program entry; the semantic line target is recorded for editor context but is not auto-applied.")
            fi
            ;;
        lldb)
            if [[ "${execution_target}" == "devcontainer" ]]; then
                if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
                    if [[ "${remote_debug_target_is_file:-no}" != "yes" || "${remote_debug_target_is_executable:-no}" != "yes" ]]; then
                        yen_error "lldb only supports explicit remote executable targets in this baseline."
                        return 1
                    fi
                else
                    if [[ ! -f "${absolute_path}" || ! -x "${absolute_path}" ]]; then
                        yen_error "lldb only supports explicit local executable targets in this baseline."
                        return 1
                    fi
                    entry_path=$(debug_relative_target_path "${root}" "${absolute_path}")
                fi
                if [[ "${debug_devcontainer_lldb_available:-no}" != "yes" ]]; then
                    yen_error "$(debug_devcontainer_missing_hint "${tool}")"
                    return 1
                fi
            elif workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
                if [[ "${remote_debug_target_is_file:-no}" != "yes" || "${remote_debug_target_is_executable:-no}" != "yes" ]]; then
                    yen_error "lldb only supports explicit remote executable targets in this baseline."
                    return 1
                fi
                if [[ "${remote_debug_lldb_available:-no}" != "yes" ]]; then
                    yen_error "$(debug_tool_missing_hint "${tool}")"
                    return 1
                fi
            else
                if [[ ! -f "${absolute_path}" || ! -x "${absolute_path}" ]]; then
                    yen_error "lldb only supports explicit local executable targets in this baseline."
                    return 1
                fi
                if ! debug_tool_available "${tool}"; then
                    yen_error "$(debug_tool_missing_hint "${tool}")"
                    return 1
                fi
                entry_path=$(debug_relative_target_path "${root}" "${absolute_path}")
            fi
            if [[ -n "${line}" || -n "${column}" ]]; then
                yen_error "Executable-only LLDB launch does not accept source line targets yet. Point yen ide debug start at the executable itself."
                return 1
            fi
            argv=("lldb" "--" "${entry_path}")
            ;;
        *)
            yen_error "Unknown debug tool: ${tool} (expected auto|python-pdb|node-inspect|lldb)"
            return 1
            ;;
    esac

    if [[ -n "${column}" ]]; then
        notes+=("Current debugger families stop at line granularity; column ${column} is recorded but not applied.")
    fi

    if [[ "${#program_args[@]}" -gt 0 ]]; then
        argv+=("${program_args[@]}")
    fi

    if [[ "${execution_target}" == "devcontainer" ]]; then
        debug_devcontainer_wrap_argv \
            "${root}" \
            "${debug_devcontainer_execution_location:-local}" \
            "${debug_devcontainer_cli}" \
            "${debug_devcontainer_remote_authority:-}" \
            "${debug_devcontainer_remote_port:-}" \
            "${argv[@]}" || return 1
        argv=("${DEBUG_DEVCONTAINER_WRAPPED_ARGV[@]}")
        if [[ "${debug_devcontainer_execution_location:-local}" == "remote" ]]; then
            notes+=("Tracked remote devcontainer debugger execution runs over SSH while trust, timeline, and evidence stay local under the shared workspace identity.")
        else
            notes+=("Tracked devcontainer debugger execution reuses the shared local trust, timeline, and evidence model instead of a second debugger registry.")
        fi
    elif workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
        remote_command="cd $(shell_quote_single "${root}") && exec"
        local arg=""
        for arg in "${argv[@]}"; do
            remote_command="${remote_command} $(shell_quote_single "${arg}")"
        done
        ssh_bin=$(ide_remote_ssh_binary) || {
            yen_error "ssh is required for remote debugger execution."
            return 1
        }
        argv=("${ssh_bin}")
        if [[ -n "${IDE_WORKSPACE_PORT}" ]]; then
            argv+=("-p" "${IDE_WORKSPACE_PORT}")
        fi
        argv+=("${IDE_WORKSPACE_AUTHORITY}" "sh" "-lc" "${remote_command}")
        notes+=("Remote debugger execution runs over SSH while trust, timeline, and evidence stay local under the shared workspace identity.")
    fi

    note_text=""
    if [[ "${#notes[@]}" -gt 0 ]]; then
        note_text=$(printf "%s\n" "${notes[@]}" | paste -sd '|' -)
    fi

    DEBUG_PLAN_ROOT="${root}" \
    DEBUG_PLAN_EXECUTION_TARGET="${execution_target}" \
    DEBUG_PLAN_TOOL="${tool}" \
    DEBUG_PLAN_TITLE="$(debug_tool_title "${tool}")" \
    DEBUG_PLAN_TARGET="${absolute_path}" \
    DEBUG_PLAN_DISPLAY_TARGET="${display_path}" \
    DEBUG_PLAN_ENTRY_PATH="${entry_path}" \
    DEBUG_PLAN_LINE="${line}" \
    DEBUG_PLAN_COLUMN="${column}" \
    DEBUG_PLAN_LINE_APPLIED="${line_applied}" \
    DEBUG_PLAN_NOTES="${note_text}" \
    python3 - "${argv[@]}" <<'PY'
import json
import os
import sys

notes = [line for line in (os.environ.get("DEBUG_PLAN_NOTES") or "").split("|") if line]

payload = {
    "schemaVersion": 1,
    "root": os.environ.get("DEBUG_PLAN_ROOT", ""),
    "executionTarget": os.environ.get("DEBUG_PLAN_EXECUTION_TARGET", "workspace") or "workspace",
    "tool": os.environ.get("DEBUG_PLAN_TOOL", ""),
    "toolTitle": os.environ.get("DEBUG_PLAN_TITLE", ""),
    "target": os.environ.get("DEBUG_PLAN_TARGET", ""),
    "displayTarget": os.environ.get("DEBUG_PLAN_DISPLAY_TARGET", ""),
    "entryPath": os.environ.get("DEBUG_PLAN_ENTRY_PATH", ""),
    "line": int(os.environ.get("DEBUG_PLAN_LINE") or "0") if (os.environ.get("DEBUG_PLAN_LINE") or "").isdigit() else None,
    "column": int(os.environ.get("DEBUG_PLAN_COLUMN") or "0") if (os.environ.get("DEBUG_PLAN_COLUMN") or "").isdigit() else None,
    "lineApplied": os.environ.get("DEBUG_PLAN_LINE_APPLIED") == "yes",
    "argv": sys.argv[1:],
    "notes": notes,
}

print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

debug_plan_text_from_payload() {
    local payload="$1"
    DEBUG_PLAN_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os
import shlex

payload = json.loads(os.environ.get("DEBUG_PLAN_PAYLOAD") or "{}")


def text(value, fallback=""):
    value = "" if value is None else str(value).strip()
    return value if value else fallback


argv = payload.get("argv") or []
command = " ".join(shlex.quote(str(part)) for part in argv) if argv else ""

print("")
print("IDE Debug Launch Plan")
print(f"Project root:       {text(payload.get('root'))}")
print(f"Execution target:   {text(payload.get('executionTarget'), 'workspace')}")
print(f"Tool:               {text(payload.get('toolTitle') or payload.get('tool'))}")
print(f"Target:             {text(payload.get('displayTarget') or payload.get('target'))}")
print(f"Entry path:         {text(payload.get('entryPath'))}")
print(f"Line applied:       {'yes' if payload.get('lineApplied') else 'no'}")
print(f"Command:            {text(command, 'unavailable')}")
notes = payload.get("notes") or []
if notes:
    print("")
    print("Notes:")
    for note in notes:
        print(f"  - {text(note)}")
print("")
PY
}
