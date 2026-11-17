# shellcheck shell=bash
# Source-time pure workspace-capability helpers and command handlers for yen ide.

devcontainer_cli_command() {
    if [[ -n "${YEN_IDE_DEVCONTAINER_CMD:-}" ]]; then
        printf "%s\n" "${YEN_IDE_DEVCONTAINER_CMD}"
        return 0
    fi
    if command -v devcontainer >/dev/null 2>&1; then
        printf "devcontainer\n"
        return 0
    fi
}

devcontainer_state_value() {
    local root="$1"
    local key="$2"
    local state_file
    state_file=$(devcontainer_state_file "${root}")
    if [[ ! -f "${state_file}" ]]; then
        return 0
    fi
    grep -F "${key}=" "${state_file}" 2>/dev/null | head -n 1 | cut -d= -f2-
}

cleanup_devcontainer_state() {
    local root="$1"
    local project_dir=""
    local state_file=""
    project_dir=$(devcontainer_project_dir "${root}")
    state_file=$(devcontainer_state_file "${root}")
    rm -f "${state_file}"
    if [[ -d "${project_dir}" ]] && [[ -z "$(find "${project_dir}" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
        rmdir "${project_dir}" 2>/dev/null || true
    fi
}

devcontainer_spec_summary() {
    local spec_file="$1"
    python3 - "${spec_file}" <<'PY'
import json
import pathlib
import re
import sys

spec_path = pathlib.Path(sys.argv[1])

def strip_jsonc(raw: str) -> str:
    result = []
    index = 0
    in_string = False
    escaped = False
    while index < len(raw):
        char = raw[index]
        next_char = raw[index + 1] if index + 1 < len(raw) else ""
        if in_string:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == "\"":
                in_string = False
            index += 1
            continue
        if char == "\"":
            in_string = True
            result.append(char)
            index += 1
            continue
        if char == "/" and next_char == "/":
            index += 2
            while index < len(raw) and raw[index] not in "\r\n":
                index += 1
            continue
        if char == "/" and next_char == "*":
            index += 2
            while index + 1 < len(raw) and not (raw[index] == "*" and raw[index + 1] == "/"):
                index += 1
            index = min(index + 2, len(raw))
            continue
        result.append(char)
        index += 1

    without_comments = "".join(result)
    result = []
    index = 0
    in_string = False
    escaped = False
    while index < len(without_comments):
        char = without_comments[index]
        if in_string:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == "\"":
                in_string = False
            index += 1
            continue
        if char == "\"":
            in_string = True
            result.append(char)
            index += 1
            continue
        if char == ",":
            lookahead = index + 1
            while lookahead < len(without_comments) and without_comments[lookahead].isspace():
                lookahead += 1
            if lookahead < len(without_comments) and without_comments[lookahead] in "}]":
                index += 1
                continue
        result.append(char)
        index += 1
    return "".join(result)

data = json.loads(strip_jsonc(spec_path.read_text(encoding="utf-8")))

run_args = data.get("runArgs") or []
mounts = data.get("mounts") or []
workspace_mount = data.get("workspaceMount") or ""
features = data.get("features") or {}
unsafe = []
for arg in run_args:
    if arg == "--privileged":
        unsafe.append("runArgs:--privileged")
    if arg.startswith("--cap-add"):
        unsafe.append(f"runArgs:{arg}")
    if arg.startswith("--mount") and ("source=/" in arg or "src=/" in arg):
        unsafe.append(f"runArgs:{arg}")
for mount in mounts:
    mount_text = str(mount)
    if "source=/" in mount_text or "src=/" in mount_text:
        unsafe.append(f"mount:{mount_text}")
if isinstance(workspace_mount, str) and ("source=/" in workspace_mount or "src=/" in workspace_mount):
    unsafe.append(f"workspaceMount:{workspace_mount}")

summary = {
    "name": data.get("name") or spec_path.parent.parent.name,
    "workspaceFolder": data.get("workspaceFolder") or "",
    "remoteUser": data.get("remoteUser") or "",
    "containerUser": data.get("containerUser") or "",
    "dockerFile": data.get("dockerFile") or "",
    "image": data.get("image") or "",
    "dockerComposeFile": data.get("dockerComposeFile") or "",
    "service": data.get("service") or "",
    "mountsCount": len(mounts),
    "runArgsCount": len(run_args),
    "featuresCount": len(features.keys() if isinstance(features, dict) else []),
    "forwardPorts": data.get("forwardPorts") or [],
    "unsafe": unsafe,
}
for key, value in summary.items():
    if isinstance(value, list):
        print(f"{key}={'|'.join(str(item) for item in value)}")
    else:
        print(f"{key}={value}")
PY
}

devcontainer_summary_value() {
    local summary_text="$1"
    local key="$2"
    printf "%s\n" "${summary_text}" | sed -nE "s/^${key}=(.*)$/\\1/p" | head -n 1
}

write_devcontainer_state() {
    local root="$1"
    local status="$2"
    local cli="$3"
    local spec="$4"
    local unsafe="$5"
    local started_at="$6"
    local last_command="$7"
    local health="$8"
    local workspace_folder="$9"
    local forward_ports="${10}"
    local content=""
    content="status=${status}
root=${root}
cli=${cli}
spec=${spec}
unsafe=${unsafe}
started_at=${started_at}
last_command=${last_command}
health=${health}
workspace_folder=${workspace_folder}
forward_ports=${forward_ports}
"
    atomic_write_text "$(devcontainer_state_file "${root}")" "${content}"
}

DEVCONTAINER_TARGET_ROOT=""
DEVCONTAINER_TARGET_EXECUTION_LOCATION=""
DEVCONTAINER_TARGET_WORKSPACE_IDENTITY=""
DEVCONTAINER_TARGET_REQUESTED_PATH=""
DEVCONTAINER_TARGET_REMOTE_AUTHORITY=""
DEVCONTAINER_TARGET_REMOTE_PORT=""
DEVCONTAINER_TARGET_REMOTE_LABEL=""

devcontainer_target_reset() {
    DEVCONTAINER_TARGET_ROOT=""
    DEVCONTAINER_TARGET_EXECUTION_LOCATION=""
    DEVCONTAINER_TARGET_WORKSPACE_IDENTITY=""
    DEVCONTAINER_TARGET_REQUESTED_PATH=""
    DEVCONTAINER_TARGET_REMOTE_AUTHORITY=""
    DEVCONTAINER_TARGET_REMOTE_PORT=""
    DEVCONTAINER_TARGET_REMOTE_LABEL=""
}

devcontainer_target_resolve() {
    local target="$1"
    local fallback_root=""

    devcontainer_target_reset
    if declare -F workspace_summary_resolve_target >/dev/null 2>&1; then
        if workspace_summary_resolve_target "${target}"; then
            DEVCONTAINER_TARGET_ROOT="${IDE_WORKSPACE_SUMMARY_ROOT}"
            DEVCONTAINER_TARGET_EXECUTION_LOCATION="${IDE_WORKSPACE_EXECUTION_LOCATION:-local}"
            DEVCONTAINER_TARGET_WORKSPACE_IDENTITY="${IDE_WORKSPACE_IDENTITY:-}"
            DEVCONTAINER_TARGET_REQUESTED_PATH="${IDE_WORKSPACE_REQUESTED_PATH:-${DEVCONTAINER_TARGET_ROOT}}"
            DEVCONTAINER_TARGET_REMOTE_AUTHORITY="${IDE_WORKSPACE_AUTHORITY:-}"
            DEVCONTAINER_TARGET_REMOTE_PORT="${IDE_WORKSPACE_PORT:-}"
            DEVCONTAINER_TARGET_REMOTE_LABEL="${IDE_WORKSPACE_LABEL:-}"
            return 0
        fi

        if [[ -n "${target}" && "${target}" == ssh://* ]] && declare -F workspace_identity_parse_target >/dev/null 2>&1; then
            if workspace_identity_parse_target "${target}"; then
                fallback_root="${IDE_WORKSPACE_REQUESTED_PATH}"
                if [[ -f "$(devcontainer_state_file "${fallback_root}")" ]]; then
                    DEVCONTAINER_TARGET_ROOT="${fallback_root}"
                    DEVCONTAINER_TARGET_EXECUTION_LOCATION="remote"
                    DEVCONTAINER_TARGET_WORKSPACE_IDENTITY=$(workspace_identity_build_remote_identity "$(workspace_identity_remote_authority_with_port)" "${fallback_root}" "${IDE_WORKSPACE_LABEL}")
                    DEVCONTAINER_TARGET_REQUESTED_PATH="${IDE_WORKSPACE_REQUESTED_PATH:-${fallback_root}}"
                    DEVCONTAINER_TARGET_REMOTE_AUTHORITY="${IDE_WORKSPACE_AUTHORITY:-}"
                    DEVCONTAINER_TARGET_REMOTE_PORT="${IDE_WORKSPACE_PORT:-}"
                    DEVCONTAINER_TARGET_REMOTE_LABEL="${IDE_WORKSPACE_LABEL:-}"
                    return 0
                fi
            fi
        fi
        return 1
    fi

    DEVCONTAINER_TARGET_ROOT=$(find_project_root "${target}")
    DEVCONTAINER_TARGET_EXECUTION_LOCATION="local"
    DEVCONTAINER_TARGET_REQUESTED_PATH="${DEVCONTAINER_TARGET_ROOT}"
}

devcontainer_target_is_remote() {
    [[ "${DEVCONTAINER_TARGET_EXECUTION_LOCATION}" == "remote" ]]
}

devcontainer_remote_helper_path() {
    printf "%s/remote-planning-probe.py\n" "${IDE_MODULE_DIR}"
}

devcontainer_remote_probe_json() {
    ide_remote_python_helper_json \
        "${DEVCONTAINER_TARGET_REMOTE_AUTHORITY}" \
        "${DEVCONTAINER_TARGET_REMOTE_PORT}" \
        "$(devcontainer_remote_helper_path)" \
        "devcontainer" \
        "${DEVCONTAINER_TARGET_REQUESTED_PATH}" \
        "${YEN_IDE_REMOTE_DEVCONTAINER_CMD:-}"
}

devcontainer_remote_snapshot_shell_vars() {
    local remote_snapshot="$1"
    python3 - "${remote_snapshot}" <<'PY'
import json
import shlex
import sys

payload = json.loads(sys.argv[1] or "{}")
summary = payload.get("summary") or {}
fields = {
    "remote_supported": "yes" if payload.get("supported") else "no",
    "remote_cli": payload.get("cli") or "",
    "remote_cli_version": payload.get("cliVersion") or "",
    "remote_spec": payload.get("spec") or "",
    "remote_workspace_folder": summary.get("workspaceFolder") or "",
    "remote_forward_ports": "|".join(str(item) for item in (summary.get("forwardPorts") or []) if str(item)),
    "remote_unsafe": "|".join(str(item) for item in (summary.get("unsafe") or []) if str(item)),
}
for key, value in fields.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
}

devcontainer_remote_execute_command() {
    local command_text="$1"
    ide_remote_shell_command \
        "${DEVCONTAINER_TARGET_REMOTE_AUTHORITY}" \
        "${DEVCONTAINER_TARGET_REMOTE_PORT}" \
        "${command_text}" \
        "sh"
}

devcontainer_remote_runtime_verification() {
    local root="$1"
    local cli="$2"
    local command_text=""
    local output=""
    local status=0
    local failure_label=""

    if [[ -z "${cli}" ]]; then
        printf "verified=no\nhealth=missing-remote-cli\n"
        return 0
    fi

    command_text="${cli} exec --workspace-folder $(shell_quote_single "${root}") true"
    set +e
    output=$(devcontainer_remote_execute_command "${command_text}" 2>&1)
    status=$?
    set -e
    if [[ "${status}" -eq 0 ]]; then
        printf "verified=yes\nhealth=tracked-remote\n"
        return 0
    fi

    failure_label=$(ide_remote_command_failure_label "${status}")
    if [[ "${failure_label}" == "transport-failed" ]]; then
        printf "verified=no\nhealth=disconnected\n"
        return 0
    fi
    printf "verified=no\nhealth=remote-exec-failed\n"
}

devcontainer_remote_status_payload_json() {
    local remote_snapshot="$1"
    local root="$2"
    local trusted="$3"
    local state="$4"
    local started_at="$5"
    local tracked_spec="$6"
    local tracked_workspace_folder="$7"
    local tracked_forward_ports="$8"
    local remote_state_verified="$9"
    local remote_runtime_health="${10}"
    python3 - \
        "${remote_snapshot}" \
        "${root}" \
        "${trusted}" \
        "${state}" \
        "${started_at}" \
        "${tracked_spec}" \
        "${tracked_workspace_folder}" \
        "${tracked_forward_ports}" \
        "${remote_state_verified}" \
        "${remote_runtime_health}" \
        "${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY}" \
        "${DEVCONTAINER_TARGET_REQUESTED_PATH}" \
        "${DEVCONTAINER_TARGET_REMOTE_AUTHORITY}" \
        "${DEVCONTAINER_TARGET_REMOTE_PORT}" \
        "${DEVCONTAINER_TARGET_REMOTE_LABEL}" <<'PY'
import json
import sys

snapshot = json.loads(sys.argv[1] or "{}")
summary = snapshot.get("summary") or {}
supported = bool(snapshot.get("supported"))
cli = snapshot.get("cli") or ""
state = sys.argv[4] or "stopped"
tracked_spec = sys.argv[6] or ""
tracked_workspace = sys.argv[7] or ""
tracked_forward_ports = [item for item in (sys.argv[8] or "").split("|") if item]
remote_state_verified = sys.argv[9] == "yes"
remote_runtime_health = sys.argv[10] or ""
remote_forward_ports = [str(item) for item in (summary.get("forwardPorts") or []) if str(item)]
remote_spec = snapshot.get("spec") or ""
remote_workspace = summary.get("workspaceFolder") or ""
spec_matches_tracked = None

if state == "running":
    comparisons = []
    if tracked_spec:
        comparisons.append(tracked_spec == remote_spec)
    if tracked_workspace:
        comparisons.append(tracked_workspace == remote_workspace)
    if tracked_forward_ports:
        comparisons.append(tracked_forward_ports == remote_forward_ports)
    if comparisons:
        spec_matches_tracked = all(comparisons)

if not supported:
    health = "unsupported"
elif not cli:
    health = "missing-remote-cli"
elif state == "running" and remote_runtime_health in {"disconnected", "remote-exec-failed"}:
    health = remote_runtime_health
elif state == "running" and spec_matches_tracked is False:
    health = "spec-drift"
elif state == "running" and remote_state_verified:
    health = "tracked-remote"
elif state == "running":
    health = "remote-unverified"
else:
    health = "ready"

print(json.dumps(
    {
        "root": sys.argv[2],
        "executionLocation": "remote",
        "workspaceIdentity": sys.argv[11],
        "requestedPath": sys.argv[12],
        "remoteAuthority": sys.argv[13],
        "remotePort": int(sys.argv[14]) if sys.argv[14] else None,
        "remoteLabel": sys.argv[15],
        "metadataSource": snapshot.get("metadataSource") or "remote-probe",
        "stateSource": snapshot.get("stateSource") or "local-ide-state",
        "lifecycleMode": snapshot.get("executionMode") or "status-only",
        "limitations": snapshot.get("limitations") or [],
        "supported": supported,
        "trusted": sys.argv[3] == "yes",
        "trustedMeaning": "local-record-only",
        "state": state,
        "health": health,
        "cli": cli,
        "cliVersion": snapshot.get("cliVersion") or "",
        "spec": remote_spec,
        "unsafe": summary.get("unsafe") or [],
        "startedAt": sys.argv[5],
        "workspaceFolder": remote_workspace,
        "forwardPorts": remote_forward_ports,
        "trackedSpec": tracked_spec,
        "trackedWorkspaceFolder": tracked_workspace,
        "trackedForwardPorts": tracked_forward_ports,
        "specMatchesTrackedState": spec_matches_tracked,
        "remoteStateVerified": remote_state_verified,
    },
    indent=2,
    sort_keys=True,
))
PY
}

devcontainer_remote_unreachable_payload_json() {
    local root="$1"
    local trusted="$2"
    local state="$3"
    local started_at="$4"
    local tracked_spec="$5"
    local tracked_workspace_folder="$6"
    local tracked_forward_ports="$7"
    local tracked_cli="$8"
    python3 - \
        "${root}" \
        "${trusted}" \
        "${state}" \
        "${started_at}" \
        "${tracked_spec}" \
        "${tracked_workspace_folder}" \
        "${tracked_forward_ports}" \
        "${tracked_cli}" \
        "${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY}" \
        "${DEVCONTAINER_TARGET_REQUESTED_PATH}" \
        "${DEVCONTAINER_TARGET_REMOTE_AUTHORITY}" \
        "${DEVCONTAINER_TARGET_REMOTE_PORT}" \
        "${DEVCONTAINER_TARGET_REMOTE_LABEL}" <<'PY'
import json
import sys

tracked_forward_ports = [item for item in (sys.argv[7] or "").split("|") if item]
print(json.dumps(
    {
        "root": sys.argv[1],
        "executionLocation": "remote",
        "workspaceIdentity": sys.argv[9],
        "requestedPath": sys.argv[10],
        "remoteAuthority": sys.argv[11],
        "remotePort": int(sys.argv[12]) if sys.argv[12] else None,
        "remoteLabel": sys.argv[13],
        "metadataSource": "remote-probe-unavailable",
        "stateSource": "local-ide-state",
        "lifecycleMode": "remote-lifecycle",
        "limitations": [
            "Remote metadata is temporarily unavailable; showing the last tracked remote devcontainer state only.",
        ],
        "supported": bool(sys.argv[5]),
        "trusted": sys.argv[2] == "yes",
        "trustedMeaning": "local-record-only",
        "state": sys.argv[3] or "stopped",
        "health": "disconnected" if (sys.argv[3] or "") == "running" else "remote-unavailable",
        "cli": sys.argv[8] or "",
        "cliVersion": "",
        "spec": sys.argv[5] or "",
        "unsafe": [],
        "startedAt": sys.argv[4] or "",
        "workspaceFolder": sys.argv[6] or "",
        "forwardPorts": tracked_forward_ports,
        "trackedSpec": sys.argv[5] or "",
        "trackedWorkspaceFolder": sys.argv[6] or "",
        "trackedForwardPorts": tracked_forward_ports,
        "specMatchesTrackedState": None,
        "remoteStateVerified": False,
    },
    indent=2,
    sort_keys=True,
))
PY
}

ensure_devcontainer_trusted_or_prompt() {
    local root="$1"
    local execution_label="local"
    local trust_target="${root}"
    if is_devcontainer_trusted_project "${root}"; then
        return 0
    fi
    if devcontainer_target_is_remote; then
        execution_label="remote"
        trust_target="${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY:-${root}}"
    fi

    if [[ -t 0 ]]; then
        echo "Project devcontainer execution is untrusted: ${trust_target}" >&2
        echo "Allow YEN to run the ${execution_label} devcontainer CLI for this workspace?" >&2
        echo "  [o] once  [a] always trust  [n] no" >&2
        printf "> " >&2
        local answer=""
        read -r answer
        case "${answer}" in
            a|A|always|ALWAYS)
                trust_devcontainer_project "${root}"
                timeline_log "devcontainer-trust" "${root}" "trusted" "source=prompt"
                return 0
                ;;
            o|O|once|ONCE|y|Y|yes|YES)
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    fi

    yen_error "Project devcontainer execution is untrusted: ${trust_target}"
    yen_info "Run: yen ide devcontainer trust \"${trust_target}\""
    return 1
}

devcontainer_health_status() {
    local root="$1"
    local cli="$2"
    local status=""
    status=$(devcontainer_state_value "${root}" "status")
    if [[ "${status}" != "running" ]]; then
        printf "inactive\n"
        return 0
    fi
    if [[ -z "${cli}" ]]; then
        printf "unavailable-cli\n"
        return 0
    fi
    if bash -lc "${cli} exec --workspace-folder $(shell_quote_single "${root}") true" >/dev/null 2>&1; then
        printf "healthy\n"
    else
        printf "unhealthy\n"
    fi
}

cmd_devcontainer_status() {
    local target=""
    local format="text"
    local root=""
    local supported="no"
    local trusted="no"
    local spec_file=""
    local cli=""
    local state="stopped"
    local health="inactive"
    local unsafe="none"
    local started_at=""
    local workspace_folder=""
    local forward_ports=""
    local summary=""
    local remote_snapshot=""
    local remote_payload=""
    local remote_verify_snapshot=""
    local remote_state_verified="no"
    local remote_runtime_health=""
    local remote_probe_status=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --format=*)
                format="${1#*=}"
                ;;
            --format)
                shift
                format="${1:-text}"
                ;;
            *)
                target="$1"
                ;;
        esac
        shift
    done

    devcontainer_target_resolve "${target}" || return 1
    root="${DEVCONTAINER_TARGET_ROOT}"
    if devcontainer_target_is_remote; then
        if is_devcontainer_trusted_project "${root}"; then
            trusted="yes"
        fi
        state=$(devcontainer_state_value "${root}" "status")
        [[ -z "${state}" ]] && state="stopped"
        started_at=$(devcontainer_state_value "${root}" "started_at")
        workspace_folder=$(devcontainer_state_value "${root}" "workspace_folder")
        local tracked_forward_ports=""
        tracked_forward_ports=$(devcontainer_state_value "${root}" "forward_ports")
        set +e
        remote_snapshot=$(devcontainer_remote_probe_json)
        remote_probe_status=$?
        set -e
        if [[ "${remote_probe_status}" -ne 0 || -z "${remote_snapshot}" ]]; then
            if [[ "${state}" == "running" ]]; then
                remote_payload=$(devcontainer_remote_unreachable_payload_json \
                    "${root}" \
                    "${trusted}" \
                    "${state}" \
                    "${started_at}" \
                    "$(devcontainer_state_value "${root}" "spec")" \
                    "${workspace_folder}" \
                    "${tracked_forward_ports}" \
                    "$(devcontainer_state_value "${root}" "cli")")
            else
                return 1
            fi
        else
            if [[ "${state}" == "running" ]]; then
                eval "$(devcontainer_remote_snapshot_shell_vars "${remote_snapshot}")"
                remote_verify_snapshot=$(devcontainer_remote_runtime_verification "${root}" "${remote_cli}")
                remote_state_verified=$(doctor_snapshot_value "${remote_verify_snapshot}" "verified")
                remote_runtime_health=$(doctor_snapshot_value "${remote_verify_snapshot}" "health")
            fi
            remote_payload=$(devcontainer_remote_status_payload_json \
                "${remote_snapshot}" \
                "${root}" \
                "${trusted}" \
                "${state}" \
                "${started_at}" \
                "$(devcontainer_state_value "${root}" "spec")" \
                "${workspace_folder}" \
                "${tracked_forward_ports}" \
                "${remote_state_verified}" \
                "${remote_runtime_health}")
        fi
        case "${format}" in
            text)
                python3 - "${remote_payload}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
print("")
print("IDE Devcontainer Status")
print(f"Project root:       {payload.get('root', '')}")
print(f"Execution location: {payload.get('executionLocation', '')}")
if payload.get("workspaceIdentity"):
    print(f"Workspace identity: {payload.get('workspaceIdentity', '')}")
if payload.get("requestedPath") and payload.get("requestedPath") != payload.get("root"):
    print(f"Requested path:     {payload.get('requestedPath', '')}")
if payload.get("remoteAuthority"):
    authority = payload.get("remoteAuthority", "")
    port = payload.get("remotePort")
    print(f"Remote authority:   {authority}:{port}" if port else f"Remote authority:   {authority}")
if payload.get("remoteLabel"):
    print(f"Remote label:       {payload.get('remoteLabel', '')}")
print(f"Metadata source:    {payload.get('metadataSource', '')}")
print(f"State source:       {payload.get('stateSource', '')}")
print(f"Lifecycle mode:     {payload.get('lifecycleMode', '')}")
print(f"Supported:          {'yes' if payload.get('supported') else 'no'}")
print(f"Local trust record: {'yes' if payload.get('trusted') else 'no'}")
print(f"State:              {payload.get('state', '')}")
print(f"Health:             {payload.get('health', '')}")
print(f"CLI:                {payload.get('cli', '') or 'missing'}")
if payload.get("cliVersion"):
    print(f"CLI version:        {payload.get('cliVersion', '')}")
if payload.get("spec"):
    print(f"Spec:               {payload.get('spec', '')}")
if payload.get("workspaceFolder"):
    print(f"Workspace:          {payload.get('workspaceFolder', '')}")
if payload.get("startedAt"):
    print(f"Started at:         {payload.get('startedAt', '')}")
if payload.get("forwardPorts"):
    print(f"Forward ports:      {'|'.join(str(item) for item in payload.get('forwardPorts') or [])}")
print(f"Unsafe flags:       {'|'.join(str(item) for item in payload.get('unsafe') or []) or 'none'}")
if payload.get("trackedSpec"):
    print(f"Tracked spec:       {payload.get('trackedSpec', '')}")
if payload.get("trackedWorkspaceFolder"):
    print(f"Tracked workspace:  {payload.get('trackedWorkspaceFolder', '')}")
if payload.get("trackedForwardPorts"):
    print(
        f"Tracked ports:      {'|'.join(str(item) for item in payload.get('trackedForwardPorts') or [])}"
    )
if payload.get("specMatchesTrackedState") is not None:
    print(
        f"Tracked spec match: {'yes' if payload.get('specMatchesTrackedState') else 'no'}"
    )
print(f"Remote runtime verified: {'yes' if payload.get('remoteStateVerified') else 'no'}")
limitations = payload.get("limitations") or []
if limitations:
    print("")
    for item in limitations:
        print(f"Limitation:         {item}")
print("")
PY
                ;;
            env)
                python3 - "${remote_payload}" <<'PY'
import json
import shlex
import sys

payload = json.loads(sys.argv[1] or "{}")

def emit(name, value):
    text = ""
    if value is None:
        text = ""
    elif isinstance(value, bool):
        text = "yes" if value else "no"
    elif isinstance(value, list):
        text = "|".join(str(item) for item in value if str(item))
    else:
        text = str(value)
    print(f"export {name}={shlex.quote(text)}")

emit("YEN_IDE_DEVCONTAINER_ROOT", payload.get("root"))
emit("YEN_IDE_DEVCONTAINER_EXECUTION_LOCATION", payload.get("executionLocation"))
emit("YEN_IDE_DEVCONTAINER_WORKSPACE_IDENTITY", payload.get("workspaceIdentity"))
emit("YEN_IDE_DEVCONTAINER_REQUESTED_PATH", payload.get("requestedPath"))
emit("YEN_IDE_DEVCONTAINER_REMOTE_AUTHORITY", payload.get("remoteAuthority"))
emit("YEN_IDE_DEVCONTAINER_REMOTE_PORT", payload.get("remotePort"))
emit("YEN_IDE_DEVCONTAINER_REMOTE_LABEL", payload.get("remoteLabel"))
emit("YEN_IDE_DEVCONTAINER_METADATA_SOURCE", payload.get("metadataSource"))
emit("YEN_IDE_DEVCONTAINER_STATE_SOURCE", payload.get("stateSource"))
emit("YEN_IDE_DEVCONTAINER_LIFECYCLE_MODE", payload.get("lifecycleMode"))
emit("YEN_IDE_DEVCONTAINER_SUPPORTED", payload.get("supported"))
emit("YEN_IDE_DEVCONTAINER_TRUSTED", payload.get("trusted"))
emit("YEN_IDE_DEVCONTAINER_STATE", payload.get("state"))
emit("YEN_IDE_DEVCONTAINER_HEALTH", payload.get("health"))
emit("YEN_IDE_DEVCONTAINER_CLI", payload.get("cli"))
emit("YEN_IDE_DEVCONTAINER_CLI_VERSION", payload.get("cliVersion"))
emit("YEN_IDE_DEVCONTAINER_SPEC", payload.get("spec"))
emit("YEN_IDE_DEVCONTAINER_UNSAFE", payload.get("unsafe"))
emit("YEN_IDE_DEVCONTAINER_FORWARD_PORTS", payload.get("forwardPorts"))
emit("YEN_IDE_DEVCONTAINER_WORKSPACE_FOLDER", payload.get("workspaceFolder"))
emit("YEN_IDE_DEVCONTAINER_STARTED_AT", payload.get("startedAt"))
emit("YEN_IDE_DEVCONTAINER_TRACKED_SPEC", payload.get("trackedSpec"))
emit("YEN_IDE_DEVCONTAINER_TRACKED_WORKSPACE_FOLDER", payload.get("trackedWorkspaceFolder"))
emit("YEN_IDE_DEVCONTAINER_TRACKED_FORWARD_PORTS", payload.get("trackedForwardPorts"))
emit("YEN_IDE_DEVCONTAINER_SPEC_MATCHES_TRACKED_STATE", payload.get("specMatchesTrackedState"))
emit("YEN_IDE_DEVCONTAINER_REMOTE_STATE_VERIFIED", payload.get("remoteStateVerified"))
emit("YEN_IDE_DEVCONTAINER_LIMITATIONS", payload.get("limitations"))
PY
                ;;
            json)
                printf "%s\n" "${remote_payload}"
                ;;
            *)
                yen_error "Unknown devcontainer status format: ${format} (expected text|env|json)"
                return 1
                ;;
        esac
        return 0
    fi

    spec_file=$(devcontainer_spec_file "${root}")
    if [[ -n "${spec_file}" ]]; then
        supported="yes"
        summary=$(devcontainer_spec_summary "${spec_file}")
        unsafe=$(devcontainer_summary_value "${summary}" "unsafe")
        [[ -z "${unsafe}" ]] && unsafe="none"
        forward_ports=$(devcontainer_summary_value "${summary}" "forwardPorts")
    fi
    if is_devcontainer_trusted_project "${root}"; then
        trusted="yes"
    fi
    cli=$(devcontainer_cli_command)
    state=$(devcontainer_state_value "${root}" "status")
    [[ -z "${state}" ]] && state="stopped"
    started_at=$(devcontainer_state_value "${root}" "started_at")
    workspace_folder=$(devcontainer_state_value "${root}" "workspace_folder")
    local state_forward_ports=""
    state_forward_ports=$(devcontainer_state_value "${root}" "forward_ports")
    if [[ -n "${state_forward_ports}" ]]; then
        forward_ports="${state_forward_ports}"
    fi
    health=$(devcontainer_health_status "${root}" "${cli}")

    case "${format}" in
        text)
            echo ""
            yen_header "IDE Devcontainer Status"
            echo "Project root:  ${root}"
            echo "Supported:     ${supported}"
            echo "Trusted:       ${trusted}"
            echo "State:         ${state}"
            echo "Health:        ${health}"
            echo "CLI:           ${cli:-missing}"
            if [[ -n "${spec_file}" ]]; then
                echo "Spec:          ${spec_file}"
            fi
            if [[ -n "${workspace_folder}" ]]; then
                echo "Workspace:     ${workspace_folder}"
            fi
            if [[ -n "${started_at}" ]]; then
                echo "Started at:    ${started_at}"
            fi
            if [[ -n "${forward_ports}" ]]; then
                echo "Forward ports: ${forward_ports}"
            fi
            echo "Unsafe flags:  ${unsafe}"
            if [[ "${trusted}" != "yes" && "${supported}" == "yes" ]]; then
                echo ""
                echo "Grant consent with: yen ide devcontainer trust \"${root}\""
            fi
            echo ""
            ;;
        env)
            printf "export YEN_IDE_DEVCONTAINER_ROOT=%s\n" "$(shell_quote_single "${root}")"
            printf "export YEN_IDE_DEVCONTAINER_SUPPORTED=%s\n" "$(shell_quote_single "${supported}")"
            printf "export YEN_IDE_DEVCONTAINER_TRUSTED=%s\n" "$(shell_quote_single "${trusted}")"
            printf "export YEN_IDE_DEVCONTAINER_STATE=%s\n" "$(shell_quote_single "${state}")"
            printf "export YEN_IDE_DEVCONTAINER_HEALTH=%s\n" "$(shell_quote_single "${health}")"
            printf "export YEN_IDE_DEVCONTAINER_CLI=%s\n" "$(shell_quote_single "${cli}")"
            printf "export YEN_IDE_DEVCONTAINER_SPEC=%s\n" "$(shell_quote_single "${spec_file}")"
            printf "export YEN_IDE_DEVCONTAINER_UNSAFE=%s\n" "$(shell_quote_single "${unsafe}")"
            printf "export YEN_IDE_DEVCONTAINER_FORWARD_PORTS=%s\n" "$(shell_quote_single "${forward_ports}")"
            ;;
        json)
            python3 - "${root}" "${supported}" "${trusted}" "${state}" "${health}" "${cli}" "${spec_file}" "${unsafe}" "${started_at}" "${workspace_folder}" "${forward_ports}" <<'PY'
import json
import sys
print(json.dumps({
    "root": sys.argv[1],
    "supported": sys.argv[2] == "yes",
    "trusted": sys.argv[3] == "yes",
    "state": sys.argv[4],
    "health": sys.argv[5],
    "cli": sys.argv[6],
    "spec": sys.argv[7],
    "unsafe": [] if sys.argv[8] in {"", "none"} else sys.argv[8].split("|"),
    "startedAt": sys.argv[9],
    "workspaceFolder": sys.argv[10],
    "forwardPorts": [] if sys.argv[11] == "" else sys.argv[11].split("|"),
}, indent=2, sort_keys=True))
PY
            ;;
        *)
            yen_error "Unknown devcontainer status format: ${format} (expected text|env|json)"
            return 1
            ;;
    esac
}

cmd_devcontainer_up() {
    local target=""
    local allow_unsafe="0"
    local root=""
    local cli=""
    local spec_file=""
    local summary=""
    local unsafe=""
    local command_text=""
    local output=""
    local remote_snapshot=""
    local status=0
    local failure_label=""
    local tracked_cli=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --allow-unsafe)
                allow_unsafe="1"
                ;;
            *)
                target="$1"
                ;;
        esac
        shift
    done

    devcontainer_target_resolve "${target}" || return 1
    root="${DEVCONTAINER_TARGET_ROOT}"
    if devcontainer_target_is_remote; then
        remote_snapshot=$(devcontainer_remote_probe_json) || return 1
        eval "$(devcontainer_remote_snapshot_shell_vars "${remote_snapshot}")"
        if [[ "${remote_supported}" != "yes" ]]; then
            yen_error "No remote devcontainer spec found for ${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY:-${root}}."
            return 1
        fi
        if ! ensure_devcontainer_trusted_or_prompt "${root}"; then
            return 1
        fi
        if [[ -z "${remote_cli}" ]]; then
            yen_error "Remote devcontainer CLI is not available."
            yen_info "Set YEN_IDE_REMOTE_DEVCONTAINER_CMD or install the reference devcontainer CLI on the remote host."
            return 1
        fi
        unsafe="${remote_unsafe:-}"
        if [[ -n "${unsafe}" && "${allow_unsafe}" != "1" ]]; then
            yen_error "Remote devcontainer spec uses unsafe flags: ${unsafe}"
            yen_info "Re-run with --allow-unsafe only if you explicitly trust this remote spec."
            return 1
        fi
        spec_file="${remote_spec}"
        command_text="${remote_cli} up --workspace-folder $(shell_quote_single "${root}")"
        set +e
        output=$(devcontainer_remote_execute_command "${command_text}" 2>&1)
        status=$?
        set -e
        if [[ "${status}" -ne 0 ]]; then
            failure_label=$(ide_remote_command_failure_label "${status}")
            if [[ "${failure_label}" == "transport-failed" ]]; then
                yen_error "Remote devcontainer up failed because the SSH transport could not reach ${DEVCONTAINER_TARGET_REMOTE_AUTHORITY}."
            else
                yen_error "Remote devcontainer up failed for ${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY:-${root}}."
            fi
            printf "%s\n" "${output}" >&2
            return "${status}"
        fi
        mkdir -p "$(devcontainer_project_dir "${root}")"
        write_devcontainer_state "${root}" "running" "${remote_cli}" "${spec_file}" "${unsafe:-none}" "$(iso_now)" "${command_text}" "unknown" "${remote_workspace_folder}" "${remote_forward_ports}"
        timeline_log "devcontainer-up" "${root}" "running" "location=remote;unsafe=${unsafe:-none};spec=${spec_file};authority=${DEVCONTAINER_TARGET_REMOTE_AUTHORITY}"
        echo ""
        yen_header "IDE Devcontainer Up"
        echo "Project root:       ${root}"
        echo "Execution location: remote"
        echo "Workspace identity: ${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY:-}"
        echo "Remote authority:   ${DEVCONTAINER_TARGET_REMOTE_AUTHORITY}${DEVCONTAINER_TARGET_REMOTE_PORT:+:${DEVCONTAINER_TARGET_REMOTE_PORT}}"
        echo "Spec:               ${spec_file}"
        echo "CLI:                ${remote_cli}"
        echo "Unsafe flags:       ${unsafe:-none}"
        echo "State:              running"
        echo ""
        return 0
    fi
    if ! is_devcontainer_supported_project "${root}"; then
        yen_error "No devcontainer spec found for ${root}."
        return 1
    fi
    if ! ensure_devcontainer_trusted_or_prompt "${root}"; then
        return 1
    fi
    cli=$(devcontainer_cli_command)
    if [[ -z "${cli}" ]]; then
        yen_error "devcontainer CLI is not available."
        yen_info "Set YEN_IDE_DEVCONTAINER_CMD or install the reference devcontainer CLI."
        return 1
    fi
    spec_file=$(devcontainer_spec_file "${root}")
    summary=$(devcontainer_spec_summary "${spec_file}")
    unsafe=$(devcontainer_summary_value "${summary}" "unsafe")
    if [[ -n "${unsafe}" && "${allow_unsafe}" != "1" ]]; then
        yen_error "Devcontainer spec uses unsafe flags: ${unsafe}"
        yen_info "Re-run with --allow-unsafe only if you explicitly trust this spec."
        return 1
    fi
    command_text="${cli} up --workspace-folder $(shell_quote_single "${root}")"
    if ! output=$(bash -lc "${command_text}" 2>&1); then
        yen_error "devcontainer up failed for ${root}"
        printf "%s\n" "${output}" >&2
        return 1
    fi
    mkdir -p "$(devcontainer_project_dir "${root}")"
    write_devcontainer_state "${root}" "running" "${cli}" "${spec_file}" "${unsafe:-none}" "$(iso_now)" "${command_text}" "unknown" "$(devcontainer_summary_value "${summary}" "workspaceFolder")" "$(devcontainer_summary_value "${summary}" "forwardPorts")"
    timeline_log "devcontainer-up" "${root}" "running" "unsafe=${unsafe:-none};spec=${spec_file}"
    echo ""
    yen_header "IDE Devcontainer Up"
    echo "Root:         ${root}"
    echo "Spec:         ${spec_file}"
    echo "CLI:          ${cli}"
    echo "Unsafe flags: ${unsafe:-none}"
    echo "State:        running"
    echo ""
}

cmd_devcontainer_shell() {
    local target=""
    local root=""
    local cli=""
    local command_args=()
    local quoted_args=""
    local remote_snapshot=""
    local remote_command=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --)
                shift
                command_args=("$@")
                break
                ;;
            *)
                target="$1"
                ;;
        esac
        shift
    done

    devcontainer_target_resolve "${target}" || return 1
    root="${DEVCONTAINER_TARGET_ROOT}"
    if devcontainer_target_is_remote; then
        remote_snapshot=$(devcontainer_remote_probe_json) || return 1
        eval "$(devcontainer_remote_snapshot_shell_vars "${remote_snapshot}")"
        if ! ensure_devcontainer_trusted_or_prompt "${root}"; then
            return 1
        fi
        if [[ -z "${remote_cli}" ]]; then
            yen_error "Remote devcontainer CLI is not available."
            return 1
        fi
        if [[ "$(devcontainer_state_value "${root}" "status")" != "running" ]]; then
            yen_error "No active remote devcontainer session for ${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY:-${root}}. Run: yen ide devcontainer up \"${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY:-${root}}\""
            return 1
        fi
        if [[ ${#command_args[@]} -eq 0 ]]; then
            if [[ -t 0 && -t 1 ]]; then
                remote_command="${remote_cli} exec --workspace-folder $(shell_quote_single "${root}") sh -lc 'exec \${SHELL:-/bin/sh} -l'"
            else
                remote_command="${remote_cli} exec --workspace-folder $(shell_quote_single "${root}") pwd"
            fi
            devcontainer_remote_execute_command "${remote_command}"
            return $?
        fi
        for arg in "${command_args[@]}"; do
            quoted_args="${quoted_args} $(shell_quote_single "${arg}")"
        done
        remote_command="${remote_cli} exec --workspace-folder $(shell_quote_single "${root}")${quoted_args}"
        devcontainer_remote_execute_command "${remote_command}"
        return $?
    fi
    if ! ensure_devcontainer_trusted_or_prompt "${root}"; then
        return 1
    fi
    cli=$(devcontainer_cli_command)
    if [[ -z "${cli}" ]]; then
        yen_error "devcontainer CLI is not available."
        return 1
    fi
    if [[ "$(devcontainer_state_value "${root}" "status")" != "running" ]]; then
        yen_error "No active devcontainer session for ${root}. Run: yen ide devcontainer up \"${root}\""
        return 1
    fi
    if [[ ${#command_args[@]} -eq 0 ]]; then
        if [[ -t 0 && -t 1 ]]; then
            bash -lc "${cli} exec --workspace-folder $(shell_quote_single "${root}") sh -lc 'exec \${SHELL:-/bin/sh} -l'"
        else
            bash -lc "${cli} exec --workspace-folder $(shell_quote_single "${root}") pwd"
        fi
        return $?
    fi
    for arg in "${command_args[@]}"; do
        quoted_args="${quoted_args} $(shell_quote_single "${arg}")"
    done
    bash -lc "${cli} exec --workspace-folder $(shell_quote_single "${root}")${quoted_args}"
}

cmd_devcontainer_down() {
    local target=""
    local root=""
    local cli=""
    local command_text=""
    local output=""
    local remote_snapshot=""
    local status=0
    local failure_label=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            *)
                target="$1"
                ;;
        esac
        shift
    done

    devcontainer_target_resolve "${target}" || return 1
    root="${DEVCONTAINER_TARGET_ROOT}"
    if devcontainer_target_is_remote; then
        if [[ "$(devcontainer_state_value "${root}" "status")" != "running" ]]; then
            cleanup_devcontainer_state "${root}"
            yen_info "Remote devcontainer already stopped for ${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY:-${root}}."
            return 0
        fi
        tracked_cli=$(devcontainer_state_value "${root}" "cli")
        if [[ -n "${tracked_cli}" ]]; then
            remote_cli="${tracked_cli}"
        else
            remote_snapshot=$(devcontainer_remote_probe_json) || return 1
            eval "$(devcontainer_remote_snapshot_shell_vars "${remote_snapshot}")"
        fi
        if [[ -z "${remote_cli}" ]]; then
            yen_error "Remote devcontainer CLI is unavailable; keeping tracked state intact for ${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY:-${root}}."
            return 1
        fi
        command_text="${remote_cli} down --workspace-folder $(shell_quote_single "${root}")"
        set +e
        output=$(devcontainer_remote_execute_command "${command_text}" 2>&1)
        status=$?
        set -e
        if [[ "${status}" -ne 0 ]]; then
            failure_label=$(ide_remote_command_failure_label "${status}")
            if [[ "${failure_label}" == "transport-failed" ]]; then
                yen_error "Remote devcontainer down failed because the SSH transport could not reach ${DEVCONTAINER_TARGET_REMOTE_AUTHORITY}; tracked state was preserved."
            else
                yen_error "Remote devcontainer down failed for ${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY:-${root}}; tracked state was preserved."
            fi
            printf "%s\n" "${output}" >&2
            return "${status}"
        fi
        cleanup_devcontainer_state "${root}"
        timeline_log "devcontainer-down" "${root}" "stopped" "location=remote;cli=${remote_cli}"
        yen_success "Remote devcontainer stopped: ${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY:-${root}}"
        return 0
    fi
    cli=$(devcontainer_cli_command)
    if [[ "$(devcontainer_state_value "${root}" "status")" != "running" ]]; then
        cleanup_devcontainer_state "${root}"
        yen_info "Devcontainer already stopped for ${root}."
        return 0
    fi
    if [[ -n "${cli}" ]]; then
        command_text="${cli} down --workspace-folder $(shell_quote_single "${root}")"
        if ! output=$(bash -lc "${command_text}" 2>&1); then
            yen_warn "devcontainer down reported an error; clearing tracked state anyway."
            printf "%s\n" "${output}" >&2
        fi
    fi
    cleanup_devcontainer_state "${root}"
    timeline_log "devcontainer-down" "${root}" "stopped" "cli=${cli:-missing}"
    yen_success "Devcontainer stopped: ${root}"
}

cmd_devcontainer() {
    local sub="${1:-status}"
    shift || true
    case "${sub}" in
        status)
            cmd_devcontainer_status "$@"
            ;;
        up)
            cmd_devcontainer_up "$@"
            ;;
        shell)
            cmd_devcontainer_shell "$@"
            ;;
        down|stop)
            cmd_devcontainer_down "$@"
            ;;
        trust)
            local root=""
            devcontainer_target_resolve "${1:-}" || return 1
            root="${DEVCONTAINER_TARGET_ROOT}"
            trust_devcontainer_project "${root}"
            timeline_log "devcontainer-trust" "${root}" "trusted" "source=manual;location=${DEVCONTAINER_TARGET_EXECUTION_LOCATION:-local}"
            if devcontainer_target_is_remote; then
                yen_success "Trusted remote workspace for devcontainer actions: ${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY:-${root}}"
            else
                yen_success "Trusted project for devcontainer actions: ${root}"
            fi
            ;;
        untrust)
            local root=""
            local down_target=""
            devcontainer_target_resolve "${1:-}" || return 1
            root="${DEVCONTAINER_TARGET_ROOT}"
            if [[ "$(devcontainer_state_value "${root}" "status")" == "running" ]]; then
                down_target="${root}"
                if devcontainer_target_is_remote; then
                    down_target="${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY:-${root}}"
                fi
                if ! cmd_devcontainer_down --project "${down_target}"; then
                    return 1
                fi
            fi
            untrust_devcontainer_project "${root}"
            timeline_log "devcontainer-trust" "${root}" "untrusted" "source=manual;location=${DEVCONTAINER_TARGET_EXECUTION_LOCATION:-local}"
            if devcontainer_target_is_remote; then
                yen_success "Removed remote devcontainer trust: ${DEVCONTAINER_TARGET_WORKSPACE_IDENTITY:-${root}}"
            else
                yen_success "Removed devcontainer trust: ${root}"
            fi
            ;;
        trusted)
            ensure_state_dirs
            if [[ ! -s "${IDE_DEVCONTAINER_TRUST_FILE}" ]]; then
                yen_info "No devcontainer-trusted projects."
                return 0
            fi
            echo ""
            yen_header "Trusted Devcontainer Projects"
            nl -ba "${IDE_DEVCONTAINER_TRUST_FILE}"
            echo ""
            ;;
        *)
            yen_error "Unknown devcontainer subcommand: ${sub}"
            return 1
            ;;
    esac
}

