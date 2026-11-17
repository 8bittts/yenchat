# shellcheck shell=bash
# Source-time pure debugger execution-target helpers shared by yen ide.

DEBUG_DEVCONTAINER_WRAPPED_ARGV=()

debug_execution_target_normalize() {
    local raw="${1:-workspace}"
    case "${raw}" in
        ""|workspace)
            printf "workspace\n"
            ;;
        devcontainer)
            printf "devcontainer\n"
            ;;
        *)
            yen_error "Unknown debug execution target: ${raw} (expected workspace|devcontainer)"
            return 1
            ;;
    esac
}

debug_project_selector_for_root() {
    local root="$1"
    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
        printf "%s\n" "${IDE_WORKSPACE_REQUESTED_TARGET:-${IDE_WORKSPACE_IDENTITY:-${root}}}"
        return 0
    fi
    printf "%s\n" "${root}"
}

debug_devcontainer_selector_for_root() {
    local root="$1"
    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
        printf "%s\n" "${IDE_WORKSPACE_IDENTITY:-${root}}"
        return 0
    fi
    printf "%s\n" "${root}"
}

debug_devcontainer_status_json_for_root() {
    local root="$1"
    local selector=""
    selector=$(debug_devcontainer_selector_for_root "${root}")
    cmd_devcontainer_status --project "${selector}" --format json
}

debug_devcontainer_status_shell_vars() {
    local payload="$1"
    local selector="$2"
    python3 - "${payload}" "${selector}" <<'PY'
import json
import shlex
import sys

payload = json.loads(sys.argv[1] or "{}")
fields = {
    "debug_devcontainer_selector": sys.argv[2] or "",
    "debug_devcontainer_execution_location": payload.get("executionLocation") or "local",
    "debug_devcontainer_workspace_identity": payload.get("workspaceIdentity") or "",
    "debug_devcontainer_requested_path": payload.get("requestedPath") or "",
    "debug_devcontainer_remote_authority": payload.get("remoteAuthority") or "",
    "debug_devcontainer_remote_port": payload.get("remotePort") or "",
    "debug_devcontainer_remote_label": payload.get("remoteLabel") or "",
    "debug_devcontainer_lifecycle_mode": payload.get("lifecycleMode") or "",
    "debug_devcontainer_supported": "yes" if payload.get("supported") else "no",
    "debug_devcontainer_trusted": "yes" if payload.get("trusted") else "no",
    "debug_devcontainer_state": payload.get("state") or "stopped",
    "debug_devcontainer_health": payload.get("health") or "inactive",
    "debug_devcontainer_cli": payload.get("cli") or "",
    "debug_devcontainer_spec": payload.get("spec") or "",
    "debug_devcontainer_workspace_folder": payload.get("workspaceFolder") or "",
    "debug_devcontainer_forward_ports": "|".join(str(item) for item in (payload.get("forwardPorts") or []) if str(item)),
    "debug_devcontainer_remote_state_verified": "yes" if payload.get("remoteStateVerified") else "no",
    "debug_devcontainer_spec_matches_tracked_state": "yes" if payload.get("specMatchesTrackedState") else "no",
}
for key, value in fields.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
}

debug_devcontainer_missing_hint() {
    local tool="$1"
    case "${tool}" in
        python-pdb)
            printf "Install Python 3 in the tracked devcontainer image so python3 -m pdb is available.\n"
            ;;
        node-inspect)
            printf "Install Node.js in the tracked devcontainer image so node inspect is available.\n"
            ;;
        lldb)
            printf "Install LLDB in the tracked devcontainer image so executable debugging is available.\n"
            ;;
        *)
            printf "Install the required debugger toolchain in the tracked devcontainer image and rerun.\n"
            ;;
    esac
}

debug_devcontainer_health_ready() {
    local execution_location="$1"
    local health="$2"
    if [[ "${execution_location}" == "remote" ]]; then
        [[ "${health}" == "tracked-remote" ]]
        return $?
    fi
    [[ "${health}" == "healthy" ]]
}

debug_devcontainer_exec_command_from_status() {
    local root="$1"
    local execution_location="$2"
    local cli="$3"
    local remote_authority="$4"
    local remote_port="$5"
    shift 5
    local inner_argv=("$@")
    local command_text=""
    local arg=""

    if [[ "${execution_location}" == "remote" ]]; then
        command_text="${cli} exec --workspace-folder $(shell_quote_single "${root}")"
        for arg in "${inner_argv[@]}"; do
            command_text="${command_text} $(shell_quote_single "${arg}")"
        done
        ide_remote_shell_command "${remote_authority}" "${remote_port}" "${command_text}" "sh"
        return $?
    fi

    command_text="${cli} exec --workspace-folder $(shell_quote_single "${root}")"
    for arg in "${inner_argv[@]}"; do
        command_text="${command_text} $(shell_quote_single "${arg}")"
    done
    bash -lc "${command_text}"
}

debug_devcontainer_tool_probe_shell_vars() {
    local root="$1"
    local execution_location="$2"
    local cli="$3"
    local remote_authority="$4"
    local remote_port="$5"
    local output=""

    output=$(
        debug_devcontainer_exec_command_from_status \
            "${root}" \
            "${execution_location}" \
            "${cli}" \
            "${remote_authority}" \
            "${remote_port}" \
            "sh" \
            "-lc" \
            'python_available=no; command -v python3 >/dev/null 2>&1 && python_available=yes; node_available=no; command -v node >/dev/null 2>&1 && node_available=yes; lldb_available=no; command -v lldb >/dev/null 2>&1 && lldb_available=yes; printf "python=%s\nnode=%s\nlldb=%s\n" "$python_available" "$node_available" "$lldb_available"' \
            2>/dev/null || true
    )

    printf "debug_devcontainer_python_available=%s\n" "$(shell_quote_single "$(printf "%s\n" "${output}" | sed -nE 's/^python=(.*)$/\1/p' | head -n 1)")"
    printf "debug_devcontainer_node_available=%s\n" "$(shell_quote_single "$(printf "%s\n" "${output}" | sed -nE 's/^node=(.*)$/\1/p' | head -n 1)")"
    printf "debug_devcontainer_lldb_available=%s\n" "$(shell_quote_single "$(printf "%s\n" "${output}" | sed -nE 's/^lldb=(.*)$/\1/p' | head -n 1)")"
}

debug_devcontainer_context_json_for_root() {
    local root="$1"
    local force="${2:-0}"
    local selector=""
    local status_json=""
    local recommended_tool=""
    local execution_available="no"
    local recommended_available="no"
    local available_count="0"
    local python_available=""
    local node_available=""
    local lldb_available=""
    local guidance=""

    selector=$(debug_devcontainer_selector_for_root "${root}")
    status_json=$(debug_devcontainer_status_json_for_root "${root}" 2>/dev/null || true)
    if [[ -z "${status_json}" ]]; then
        if [[ "${force}" == "1" ]]; then
            status_json='{}'
        else
            printf "{}\n"
            return 0
        fi
    fi

    eval "$(debug_devcontainer_status_shell_vars "${status_json}" "${selector}")"
    if [[ "${force}" != "1" && "${debug_devcontainer_supported}" != "yes" && "${debug_devcontainer_state}" == "stopped" && -z "${debug_devcontainer_workspace_folder}" && -z "${debug_devcontainer_forward_ports}" ]]; then
        printf "{}\n"
        return 0
    fi

    recommended_tool=$(debug_recommended_tool_for_root "${root}")
    if [[ "${debug_devcontainer_supported}" == "yes" ]] && \
       [[ "${debug_devcontainer_trusted}" == "yes" ]] && \
       [[ "${debug_devcontainer_state}" == "running" ]] && \
       [[ -n "${debug_devcontainer_cli}" ]] && \
       debug_devcontainer_health_ready "${debug_devcontainer_execution_location}" "${debug_devcontainer_health}"; then
        eval "$(debug_devcontainer_tool_probe_shell_vars \
            "${root}" \
            "${debug_devcontainer_execution_location}" \
            "${debug_devcontainer_cli}" \
            "${debug_devcontainer_remote_authority}" \
            "${debug_devcontainer_remote_port}")"
    fi
    [[ "${debug_devcontainer_python_available:-}" == "yes" ]] && available_count=$(( available_count + 1 ))
    [[ "${debug_devcontainer_node_available:-}" == "yes" ]] && available_count=$(( available_count + 1 ))
    [[ "${debug_devcontainer_lldb_available:-}" == "yes" ]] && available_count=$(( available_count + 1 ))

    case "${recommended_tool}" in
        python-pdb)
            recommended_available="${debug_devcontainer_python_available:-no}"
            ;;
        node-inspect)
            recommended_available="${debug_devcontainer_node_available:-no}"
            ;;
        lldb)
            recommended_available="${debug_devcontainer_lldb_available:-no}"
            ;;
        *)
            recommended_available="no"
            ;;
    esac

    if [[ "${debug_devcontainer_supported}" != "yes" ]]; then
        guidance="No tracked devcontainer spec is available for ${selector}."
    elif [[ "${debug_devcontainer_trusted}" != "yes" ]]; then
        guidance="Tracked devcontainer execution is untrusted. Run: yen ide devcontainer trust ${selector}"
    elif [[ "${debug_devcontainer_state}" != "running" ]]; then
        guidance="Tracked devcontainer execution is not running. Run: yen ide devcontainer up ${selector}"
    elif [[ -z "${debug_devcontainer_cli}" ]]; then
        if [[ "${debug_devcontainer_execution_location}" == "remote" ]]; then
            guidance="Remote devcontainer CLI is unavailable. Install the reference CLI on the remote host or set YEN_IDE_REMOTE_DEVCONTAINER_CMD."
        else
            guidance="Install the reference devcontainer CLI or set YEN_IDE_DEVCONTAINER_CMD, then rerun."
        fi
    elif ! debug_devcontainer_health_ready "${debug_devcontainer_execution_location}" "${debug_devcontainer_health}"; then
        case "${debug_devcontainer_health}" in
            spec-drift)
                guidance="Tracked devcontainer state drifted from the current spec. Run yen ide devcontainer down ${selector} and then yen ide devcontainer up ${selector}."
                ;;
            disconnected)
                guidance="Tracked remote devcontainer is disconnected. Restore SSH reachability, then rerun yen ide debug status --devcontainer --project ${selector}."
                ;;
            remote-exec-failed)
                guidance="Tracked remote devcontainer could not execute commands. Recheck the remote CLI/runtime, then rerun yen ide debug status --devcontainer --project ${selector}."
                ;;
            unhealthy)
                guidance="Tracked devcontainer exec health is failing. Recheck the container runtime, then rerun yen ide debug status --devcontainer --project ${selector}."
                ;;
            *)
                guidance="Tracked devcontainer execution is not ready yet. Recheck yen ide devcontainer status ${selector} before debugging inside the container."
                ;;
        esac
    elif [[ "${available_count}" -eq 0 ]]; then
        guidance="No shipped debugger tool is available in the tracked devcontainer image. Install Python 3, Node.js, or LLDB in that image and rerun yen ide debug status --devcontainer --project ${selector}."
    else
        execution_available="yes"
        guidance="Tracked devcontainer debugger execution is available. Use yen ide debug start <target> --devcontainer --project ${selector}."
    fi

    python_available="${debug_devcontainer_python_available:-no}"
    node_available="${debug_devcontainer_node_available:-no}"
    lldb_available="${debug_devcontainer_lldb_available:-no}"

    DEBUG_DEVCONTEXT_ROOT="${root}" \
    DEBUG_DEVCONTEXT_SELECTOR="${selector}" \
    DEBUG_DEVCONTEXT_EXECUTION_LOCATION="${debug_devcontainer_execution_location:-local}" \
    DEBUG_DEVCONTEXT_WORKSPACE_IDENTITY="${debug_devcontainer_workspace_identity:-}" \
    DEBUG_DEVCONTEXT_REQUESTED_PATH="${debug_devcontainer_requested_path:-}" \
    DEBUG_DEVCONTEXT_REMOTE_AUTHORITY="${debug_devcontainer_remote_authority:-}" \
    DEBUG_DEVCONTEXT_REMOTE_PORT="${debug_devcontainer_remote_port:-}" \
    DEBUG_DEVCONTEXT_LIFECYCLE_MODE="${debug_devcontainer_lifecycle_mode:-}" \
    DEBUG_DEVCONTEXT_SUPPORTED="${debug_devcontainer_supported:-no}" \
    DEBUG_DEVCONTEXT_TRUSTED="${debug_devcontainer_trusted:-no}" \
    DEBUG_DEVCONTEXT_STATE="${debug_devcontainer_state:-stopped}" \
    DEBUG_DEVCONTEXT_HEALTH="${debug_devcontainer_health:-inactive}" \
    DEBUG_DEVCONTEXT_CLI="${debug_devcontainer_cli:-}" \
    DEBUG_DEVCONTEXT_WORKSPACE_FOLDER="${debug_devcontainer_workspace_folder:-}" \
    DEBUG_DEVCONTEXT_FORWARD_PORTS="${debug_devcontainer_forward_ports:-}" \
    DEBUG_DEVCONTEXT_REMOTE_STATE_VERIFIED="${debug_devcontainer_remote_state_verified:-no}" \
    DEBUG_DEVCONTEXT_SPEC_MATCHES="${debug_devcontainer_spec_matches_tracked_state:-no}" \
    DEBUG_DEVCONTEXT_EXECUTION_AVAILABLE="${execution_available}" \
    DEBUG_DEVCONTEXT_RECOMMENDED_TOOL="${recommended_tool}" \
    DEBUG_DEVCONTEXT_RECOMMENDED_AVAILABLE="${recommended_available}" \
    DEBUG_DEVCONTEXT_AVAILABLE_COUNT="${available_count}" \
    DEBUG_DEVCONTEXT_PYTHON_AVAILABLE="${python_available}" \
    DEBUG_DEVCONTEXT_NODE_AVAILABLE="${node_available}" \
    DEBUG_DEVCONTEXT_LLDB_AVAILABLE="${lldb_available}" \
    DEBUG_DEVCONTEXT_GUIDANCE="${guidance}" \
    python3 - <<'PY'
import json
import os

ports = [item for item in (os.environ.get("DEBUG_DEVCONTEXT_FORWARD_PORTS") or "").split("|") if item]
print(json.dumps({
    "root": os.environ.get("DEBUG_DEVCONTEXT_ROOT", ""),
    "projectSelector": os.environ.get("DEBUG_DEVCONTEXT_SELECTOR", ""),
    "executionLocation": os.environ.get("DEBUG_DEVCONTEXT_EXECUTION_LOCATION", "local") or "local",
    "workspaceIdentity": os.environ.get("DEBUG_DEVCONTEXT_WORKSPACE_IDENTITY", ""),
    "requestedPath": os.environ.get("DEBUG_DEVCONTEXT_REQUESTED_PATH", ""),
    "remoteAuthority": os.environ.get("DEBUG_DEVCONTEXT_REMOTE_AUTHORITY", ""),
    "remotePort": os.environ.get("DEBUG_DEVCONTEXT_REMOTE_PORT", ""),
    "lifecycleMode": os.environ.get("DEBUG_DEVCONTEXT_LIFECYCLE_MODE", ""),
    "supported": os.environ.get("DEBUG_DEVCONTEXT_SUPPORTED") == "yes",
    "trusted": os.environ.get("DEBUG_DEVCONTEXT_TRUSTED") == "yes",
    "state": os.environ.get("DEBUG_DEVCONTEXT_STATE", "stopped") or "stopped",
    "health": os.environ.get("DEBUG_DEVCONTEXT_HEALTH", "inactive") or "inactive",
    "cli": os.environ.get("DEBUG_DEVCONTEXT_CLI", ""),
    "workspaceFolder": os.environ.get("DEBUG_DEVCONTEXT_WORKSPACE_FOLDER", ""),
    "forwardPorts": ports,
    "remoteStateVerified": os.environ.get("DEBUG_DEVCONTEXT_REMOTE_STATE_VERIFIED") == "yes",
    "specMatchesTrackedState": os.environ.get("DEBUG_DEVCONTEXT_SPEC_MATCHES") == "yes",
    "debugExecutionAvailable": os.environ.get("DEBUG_DEVCONTEXT_EXECUTION_AVAILABLE") == "yes",
    "debugRecommendedTool": os.environ.get("DEBUG_DEVCONTEXT_RECOMMENDED_TOOL", ""),
    "debugRecommendedAvailable": os.environ.get("DEBUG_DEVCONTEXT_RECOMMENDED_AVAILABLE") == "yes",
    "debugAvailableFamilyCount": int(os.environ.get("DEBUG_DEVCONTEXT_AVAILABLE_COUNT") or "0"),
    "familyAvailability": {
        "python-pdb": os.environ.get("DEBUG_DEVCONTEXT_PYTHON_AVAILABLE") == "yes",
        "node-inspect": os.environ.get("DEBUG_DEVCONTEXT_NODE_AVAILABLE") == "yes",
        "lldb": os.environ.get("DEBUG_DEVCONTEXT_LLDB_AVAILABLE") == "yes",
    },
    "guidance": os.environ.get("DEBUG_DEVCONTEXT_GUIDANCE", ""),
}, sort_keys=True))
PY
}

debug_devcontainer_context_shell_vars() {
    local payload="$1"
    python3 - "${payload}" <<'PY'
import json
import shlex
import sys

payload = json.loads(sys.argv[1] or "{}")
family = payload.get("familyAvailability") or {}
fields = {
    "debug_devcontainer_selector": payload.get("projectSelector") or "",
    "debug_devcontainer_execution_location": payload.get("executionLocation") or "local",
    "debug_devcontainer_workspace_identity": payload.get("workspaceIdentity") or "",
    "debug_devcontainer_requested_path": payload.get("requestedPath") or "",
    "debug_devcontainer_remote_authority": payload.get("remoteAuthority") or "",
    "debug_devcontainer_remote_port": payload.get("remotePort") or "",
    "debug_devcontainer_lifecycle_mode": payload.get("lifecycleMode") or "",
    "debug_devcontainer_supported": "yes" if payload.get("supported") else "no",
    "debug_devcontainer_trusted": "yes" if payload.get("trusted") else "no",
    "debug_devcontainer_state": payload.get("state") or "stopped",
    "debug_devcontainer_health": payload.get("health") or "inactive",
    "debug_devcontainer_cli": payload.get("cli") or "",
    "debug_devcontainer_workspace_folder": payload.get("workspaceFolder") or "",
    "debug_devcontainer_forward_ports": "|".join(str(item) for item in (payload.get("forwardPorts") or []) if str(item)),
    "debug_devcontainer_remote_state_verified": "yes" if payload.get("remoteStateVerified") else "no",
    "debug_devcontainer_spec_matches_tracked_state": "yes" if payload.get("specMatchesTrackedState") else "no",
    "debug_devcontainer_execution_available": "yes" if payload.get("debugExecutionAvailable") else "no",
    "debug_devcontainer_recommended_tool": payload.get("debugRecommendedTool") or "",
    "debug_devcontainer_recommended_available": "yes" if payload.get("debugRecommendedAvailable") else "no",
    "debug_devcontainer_available_family_count": str(payload.get("debugAvailableFamilyCount") or 0),
    "debug_devcontainer_python_available": "yes" if family.get("python-pdb") else "no",
    "debug_devcontainer_node_available": "yes" if family.get("node-inspect") else "no",
    "debug_devcontainer_lldb_available": "yes" if family.get("lldb") else "no",
    "debug_devcontainer_guidance": payload.get("guidance") or "",
}
for key, value in fields.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
}

debug_devcontainer_family_rows_for_root() {
    local root="$1"
    local context_json="${2:-}"
    local recommended_tool=""
    local guidance=""
    local python_available="no"
    local node_available="no"
    local lldb_available="no"
    local python_recommended="no"
    local node_recommended="no"
    local native_recommended="no"
    local python_hint=""
    local node_hint=""
    local lldb_hint=""

    if [[ -z "${context_json}" ]]; then
        context_json=$(debug_devcontainer_context_json_for_root "${root}" "1")
    fi
    eval "$(debug_devcontainer_context_shell_vars "${context_json}")"

    recommended_tool=$(debug_recommended_tool_for_root "${root}")
    [[ "${recommended_tool}" == "python-pdb" ]] && python_recommended="yes"
    [[ "${recommended_tool}" == "node-inspect" ]] && node_recommended="yes"
    [[ "${recommended_tool}" == "lldb" ]] && native_recommended="yes"

    python_available="${debug_devcontainer_python_available:-no}"
    node_available="${debug_devcontainer_node_available:-no}"
    lldb_available="${debug_devcontainer_lldb_available:-no}"
    guidance="${debug_devcontainer_guidance:-}"

    if [[ "${debug_devcontainer_execution_available:-no}" != "yes" ]]; then
        python_available="no"
        node_available="no"
        lldb_available="no"
        python_hint="${guidance}"
        node_hint="${guidance}"
        lldb_hint="${guidance}"
    else
        [[ "${python_available}" == "yes" ]] || python_hint=$(debug_devcontainer_missing_hint "python-pdb")
        [[ "${node_available}" == "yes" ]] || node_hint=$(debug_devcontainer_missing_hint "node-inspect")
        [[ "${lldb_available}" == "yes" ]] || lldb_hint=$(debug_devcontainer_missing_hint "lldb")
    fi

    printf "python-pdb\tPython pdb\t%s\t%s\tfull-line\tpython-entry\tTracked devcontainer .py entry files over the shared path:line[:col] target contract.\t%s\n" \
        "${python_available}" "${python_recommended}" "${python_hint}"
    printf "node-inspect\tNode inspect\t%s\t%s\tentry-only\tnode-entry\tTracked devcontainer .js/.mjs/.cjs entry files. Semantic line targets are recorded, but the CLI still opens at program entry.\t%s\n" \
        "${node_available}" "${node_recommended}" "${node_hint}"
    printf "lldb\tLLDB\t%s\t%s\texecutable-only\texecutable\tExplicit executable targets through the tracked devcontainer only. Source-file to binary inference is not shipped yet.\t%s\n" \
        "${lldb_available}" "${native_recommended}" "${lldb_hint}"
}

debug_devcontainer_wrap_argv() {
    local root="$1"
    local execution_location="$2"
    local cli="$3"
    local remote_authority="$4"
    local remote_port="$5"
    shift 5
    local inner_argv=("$@")
    local command_text=""
    local arg=""
    local ssh_bin=""

    DEBUG_DEVCONTAINER_WRAPPED_ARGV=()
    command_text="${cli} exec --workspace-folder $(shell_quote_single "${root}")"
    for arg in "${inner_argv[@]}"; do
        command_text="${command_text} $(shell_quote_single "${arg}")"
    done
    if [[ "${execution_location}" == "remote" ]]; then
        ssh_bin=$(ide_remote_ssh_binary) || {
            yen_error "ssh is required for remote devcontainer debugger execution."
            return 1
        }
        DEBUG_DEVCONTAINER_WRAPPED_ARGV=("${ssh_bin}")
        if [[ -n "${remote_port}" ]]; then
            DEBUG_DEVCONTAINER_WRAPPED_ARGV+=("-p" "${remote_port}")
        fi
        DEBUG_DEVCONTAINER_WRAPPED_ARGV+=("${remote_authority}" "sh" "-lc" "${command_text}")
        return 0
    fi

    DEBUG_DEVCONTAINER_WRAPPED_ARGV=("bash" "-lc" "${command_text}")
}
