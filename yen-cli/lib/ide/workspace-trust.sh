# shellcheck shell=bash
# Source-time pure workspace-capability helpers and command handlers for yen ide.

trust_center_env_json() {
    local root="$1"
    local trusted="no"
    local files=""
    local file_count="0"

    if is_trusted_project "${root}"; then
        trusted="yes"
    fi
    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
        files="${IDE_WORKSPACE_SUMMARY_ENV_FILES}"
        file_count="${IDE_WORKSPACE_SUMMARY_ENV_COUNT:-0}"
    else
        files=$(collect_env_files "${root}" || true)
        file_count=$(doctor_count_lines "${files}")
    fi

    TRUST_CENTER_ROOT="${root}" TRUST_CENTER_TRUSTED="${trusted}" TRUST_CENTER_FILES="${files}" TRUST_CENTER_FILE_COUNT="${file_count}" python3 - <<'PY'
import json
import os

files = [line for line in (os.environ.get("TRUST_CENTER_FILES") or "").splitlines() if line]

print(
    json.dumps(
        {
            "root": os.environ.get("TRUST_CENTER_ROOT", ""),
            "trusted": os.environ.get("TRUST_CENTER_TRUSTED") == "yes",
            "state": "idle",
            "active": False,
            "fileCount": int(os.environ.get("TRUST_CENTER_FILE_COUNT") or "0"),
            "files": files,
        },
        indent=2,
        sort_keys=True,
    )
)
PY
}

trust_center_lsp_json() {
    local root="$1"

    if ! workspace_identity_is_remote || [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" != "${root}" ]]; then
        cmd_lsp_status --project "${root}" --format json
        return 0
    fi

    local trusted="no"
    local runtime_state=""
    local health=""
    local protocol_status=""
    local diagnostics_status=""

    if is_lsp_trusted_project "${root}"; then
        trusted="yes"
    fi
    runtime_state=$(lsp_runtime_state "${root}")
    case "${runtime_state}" in
        running|starting)
            health="remote-unverified"
            ;;
        stale)
            health="stale"
            ;;
        *)
            health="inactive"
            ;;
    esac
    protocol_status=$(lsp_protocol_status "${root}")
    diagnostics_status=$(lsp_diagnostics_status "${root}")

    python3 - "${root}" "${trusted}" "${runtime_state}" "${health}" "${protocol_status}" "${diagnostics_status}" <<'PY'
import json
import sys

print(json.dumps({
    "root": sys.argv[1],
    "trusted": sys.argv[2] == "yes",
    "runtimeState": sys.argv[3] or "stopped",
    "health": sys.argv[4] or "inactive",
    "resolutionStatus": "remote-summary",
    "resolutionReason": "Remote read-only summary does not resolve remote LSP servers yet.",
    "expectedServer": "",
    "protocolStatus": sys.argv[5],
    "diagnosticsStatus": sys.argv[6],
    "language": "",
}, indent=2, sort_keys=True))
PY
}

trust_center_debug_json() {
    local root="$1"
    debug_status_json_for_root "${root}"
}

trust_center_share_json() {
    local root="$1"
    local trusted="no"
    local state=""
    local transport=""
    local preferred_transport=""
    local available_transports=""
    local mode=""
    local host_identity=""
    local repo_label=""
    local session_id=""
    local started_at=""
    local expires_at=""
    local expires_epoch="0"
    local auth_mode=""
    local share_token=""
    local transport_status=""
    local last_error=""
    local remaining_seconds="0"
    local remaining_text="00:00:00"
    local cli=""
    local web_url=""
    local execution_location=""
    local workspace_identity=""
    local requested_path=""
    local reconnect_target=""
    local remote_authority=""
    local remote_port=""
    local remote_label=""

    if is_share_trusted_project "${root}"; then
        trusted="yes"
    fi
    state=$(share_runtime_state "${root}")
    transport=$(share_state_value "${root}" "transport")
    available_transports=$(share_available_transports_for_root "${root}")
    preferred_transport=$(share_default_transport_from_available "${available_transports}")
    mode=$(share_state_value "${root}" "mode")
    host_identity=$(share_state_value "${root}" "host_identity")
    repo_label=$(share_state_value "${root}" "repo_label")
    session_id=$(share_state_value "${root}" "session_id")
    started_at=$(share_state_value "${root}" "started_at")
    expires_at=$(share_state_value "${root}" "expires_at")
    expires_epoch=$(share_state_value "${root}" "expires_epoch")
    auth_mode=$(share_state_value "${root}" "auth_mode")
    share_token=$(share_state_value "${root}" "share_token")
    last_error=$(share_state_value "${root}" "last_error")
    cli=$(share_state_value "${root}" "cli")
    web_url=$(share_state_value "${root}" "web_url")
    execution_location=$(share_state_value "${root}" "execution_location")
    workspace_identity=$(share_state_value "${root}" "workspace_identity")
    requested_path=$(share_state_value "${root}" "requested_path")
    reconnect_target=$(share_state_value "${root}" "reconnect_target")
    remote_authority=$(share_state_value "${root}" "remote_authority")
    remote_port=$(share_state_value "${root}" "remote_port")
    remote_label=$(share_state_value "${root}" "remote_label")
    [[ -n "${execution_location}" ]] || execution_location=$(share_execution_location_for_root "${root}")
    [[ -n "${workspace_identity}" ]] || workspace_identity=$(share_workspace_identity_for_root "${root}")
    [[ -n "${requested_path}" ]] || requested_path=$(share_requested_path_for_root "${root}")
    [[ -n "${remote_authority}" ]] || remote_authority=$(share_remote_authority_for_root "${root}")
    [[ -n "${remote_port}" ]] || remote_port=$(share_remote_port_for_root "${root}")
    [[ -n "${remote_label}" ]] || remote_label=$(share_remote_label_for_root "${root}")
    [[ ! "${expires_epoch}" =~ ^[0-9]+$ ]] && expires_epoch="0"
    if [[ "${expires_epoch}" -gt 0 ]]; then
        remaining_seconds=$(( expires_epoch - $(date +%s) ))
        if [[ "${remaining_seconds}" -lt 0 ]]; then
            remaining_seconds="0"
        fi
        remaining_text=$(share_format_ttl "${remaining_seconds}")
    fi
    if [[ -z "${transport}" ]]; then
        transport="${preferred_transport:-none}"
    fi
    if [[ "${state}" != "running" ]] && [[ "${state}" != "disconnected" ]]; then
        share_token=""
    fi
    transport_status=$(share_transport_status "${root}" "${state}" "${transport}")

    python3 - "${root}" "${execution_location}" "${workspace_identity}" "${requested_path}" "${trusted}" "${state}" "${transport}" "${transport_status}" "${available_transports}" "${preferred_transport}" "${mode}" "${auth_mode}" "${host_identity}" "${repo_label}" "${reconnect_target}" "${remote_authority}" "${remote_port}" "${remote_label}" "${session_id}" "${started_at}" "${expires_at}" "${remaining_text}" "${share_token}" "${web_url}" "${last_error}" "$(share_state_file "${root}")" "$(share_pid_file "${root}")" "$(share_lock_dir "${root}")" "${cli}" <<'PY'
import json
import sys

print(json.dumps(
    {
        "root": sys.argv[1],
        "executionLocation": sys.argv[2],
        "workspaceIdentity": sys.argv[3],
        "requestedPath": sys.argv[4],
        "trusted": sys.argv[5] == "yes",
        "state": sys.argv[6],
        "transport": sys.argv[7],
        "transportStatus": sys.argv[8],
        "availableTransports": [] if sys.argv[9] == "" else sys.argv[9].split(","),
        "preferredTransport": sys.argv[10],
        "mode": sys.argv[11],
        "auth": sys.argv[12],
        "hostIdentity": sys.argv[13],
        "repoLabel": sys.argv[14],
        "reconnectTarget": sys.argv[15],
        "remoteAuthority": sys.argv[16],
        "remotePort": int(sys.argv[17]) if sys.argv[17] else None,
        "remoteLabel": sys.argv[18],
        "sessionId": sys.argv[19],
        "startedAt": sys.argv[20],
        "expiresAt": sys.argv[21],
        "timeRemaining": sys.argv[22],
        "shareToken": sys.argv[23],
        "webUrl": sys.argv[24],
        "lastError": sys.argv[25],
        "stateFile": sys.argv[26],
        "pidFile": sys.argv[27],
        "lockDir": sys.argv[28],
        "cli": sys.argv[29],
    },
    indent=2,
    sort_keys=True,
))
PY
}

trust_center_workflow_json() {
    local root="$1"
    local trusted="no"
    local workflow_count="0"

    if is_workflow_trusted_project "${root}"; then
        trusted="yes"
    fi
    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
        workflow_count="${IDE_WORKSPACE_SUMMARY_WORKFLOW_COUNT:-0}"
    elif [[ -d "$(workflow_dir_for_root "${root}")" ]]; then
        workflow_count=$(find "$(workflow_dir_for_root "${root}")" -maxdepth 1 -type f -name '*.toml' 2>/dev/null | wc -l | tr -d '[:space:]')
    fi

    TRUST_CENTER_ROOT="${root}" TRUST_CENTER_TRUSTED="${trusted}" TRUST_CENTER_WORKFLOW_COUNT="${workflow_count}" python3 - <<'PY'
import json
import os

print(
    json.dumps(
        {
            "root": os.environ.get("TRUST_CENTER_ROOT", ""),
            "trusted": os.environ.get("TRUST_CENTER_TRUSTED") == "yes",
            "state": "idle",
            "active": False,
            "workflowCount": int(os.environ.get("TRUST_CENTER_WORKFLOW_COUNT") or "0"),
        },
        indent=2,
        sort_keys=True,
    )
)
PY
}

trust_center_collect_json() {
    local root="$1"
    local env_json=""
    local lsp_json=""
    local debug_json=""
    local devcontainer_json=""
    local share_json=""
    local workflow_json=""
    local timeline_root=""
    local controls_available="yes"

    env_json=$(trust_center_env_json "${root}")
    lsp_json=$(trust_center_lsp_json "${root}")
    debug_json=$(trust_center_debug_json "${root}")
    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
        devcontainer_json=$(python3 - "${root}" "$(is_devcontainer_trusted_project "${root}" && echo yes || echo no)" "$(devcontainer_state_value "${root}" "status")" "$(devcontainer_state_value "${root}" "health")" "${IDE_WORKSPACE_SUMMARY_DEVCONTAINER_SUPPORTED:-no}" "$(devcontainer_state_value "${root}" "workspace_folder")" "$(devcontainer_state_value "${root}" "forward_ports")" <<'PY'
import json
import sys

state = sys.argv[3] or "stopped"
health = sys.argv[4] or ("remote-unverified" if state == "running" else "inactive")
print(json.dumps({
    "root": sys.argv[1],
    "supported": sys.argv[5] == "yes",
    "trusted": sys.argv[2] == "yes",
    "state": state,
    "health": health,
    "cli": "",
    "spec": "",
    "unsafe": [],
    "startedAt": "",
    "workspaceFolder": sys.argv[6],
    "forwardPorts": [] if sys.argv[7] == "" else sys.argv[7].split("|"),
}, indent=2, sort_keys=True))
PY
)
        controls_available="no"
    else
        devcontainer_json=$(cmd_devcontainer_status --project "${root}" --format json)
    fi
    share_json=$(trust_center_share_json "${root}")
    workflow_json=$(trust_center_workflow_json "${root}")
    timeline_root=$(project_timeline_key_for_root "${root}")
    if workspace_identity_is_remote && [[ "${IDE_WORKSPACE_SUMMARY_ROOT}" == "${root}" ]]; then
        controls_available="no"
    fi

    TRUST_CENTER_ROOT="${root}" \
    TRUST_CENTER_TIMELINE_ROOT="${timeline_root}" \
    TRUST_CENTER_CONTROLS_AVAILABLE="${controls_available}" \
    TRUST_CENTER_ENV_JSON="${env_json}" \
    TRUST_CENTER_LSP_JSON="${lsp_json}" \
    TRUST_CENTER_DEBUG_JSON="${debug_json}" \
    TRUST_CENTER_DEVCONTAINER_JSON="${devcontainer_json}" \
    TRUST_CENTER_SHARE_JSON="${share_json}" \
    TRUST_CENTER_WORKFLOW_JSON="${workflow_json}" \
    TRUST_CENTER_TIMELINE_FILE="${IDE_TIMELINE_FILE}" \
    IDE_WORKSPACE_TRANSPORT="${IDE_WORKSPACE_TRANSPORT}" \
    IDE_WORKSPACE_EXECUTION_LOCATION="${IDE_WORKSPACE_EXECUTION_LOCATION}" \
    IDE_WORKSPACE_AUTHORITY="${IDE_WORKSPACE_AUTHORITY}" \
    IDE_WORKSPACE_PORT="${IDE_WORKSPACE_PORT}" \
    IDE_WORKSPACE_REQUESTED_PATH="${IDE_WORKSPACE_REQUESTED_PATH}" \
    IDE_WORKSPACE_LABEL="${IDE_WORKSPACE_LABEL}" \
    IDE_WORKSPACE_IDENTITY="${IDE_WORKSPACE_IDENTITY}" \
    python3 - <<'PY'
import json
import os


def load_payload(name: str):
    raw = os.environ.get(name, "")
    if not raw:
        return {}
    return json.loads(raw)


def read_timeline_rows(path: str, root: str):
    rows = []
    if not path or not os.path.exists(path):
        return rows
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t", 4)
            if len(parts) != 5:
                continue
            timestamp, event, project_root, status, detail = parts
            if project_root != root:
                continue
            rows.append(
                {
                    "time": timestamp,
                    "event": event,
                    "status": status,
                    "detail": detail,
                }
            )
    return rows


def last_event(rows, names):
    for row in reversed(rows):
        if row.get("event") in names:
            return row
    return {"time": "", "event": "", "status": "", "detail": ""}


root = os.environ.get("TRUST_CENTER_ROOT", "")
timeline_root = os.environ.get("TRUST_CENTER_TIMELINE_ROOT", "") or root
controls_available = os.environ.get("TRUST_CENTER_CONTROLS_AVAILABLE", "yes") == "yes"
capabilities = {
    "env": load_payload("TRUST_CENTER_ENV_JSON"),
    "lsp": load_payload("TRUST_CENTER_LSP_JSON"),
    "debug": load_payload("TRUST_CENTER_DEBUG_JSON"),
    "devcontainer": load_payload("TRUST_CENTER_DEVCONTAINER_JSON"),
    "share": load_payload("TRUST_CENTER_SHARE_JSON"),
    "workflow": load_payload("TRUST_CENTER_WORKFLOW_JSON"),
}

capabilities["env"]["state"] = capabilities["env"].get("state") or "idle"
capabilities["env"]["active"] = False
capabilities["lsp"]["state"] = capabilities["lsp"].get("runtimeState") or "stopped"
capabilities["lsp"]["active"] = capabilities["lsp"]["state"] in {"running", "starting"}
capabilities["debug"]["state"] = capabilities["debug"].get("state") or "stopped"
capabilities["debug"]["active"] = bool(capabilities["debug"].get("active"))
capabilities["devcontainer"]["state"] = capabilities["devcontainer"].get("state") or "stopped"
capabilities["devcontainer"]["active"] = capabilities["devcontainer"]["state"] == "running"
capabilities["share"]["state"] = capabilities["share"].get("state") or "stopped"
capabilities["share"]["active"] = capabilities["share"]["state"] in {"running", "disconnected"}
capabilities["workflow"]["state"] = capabilities["workflow"].get("state") or "idle"
capabilities["workflow"]["active"] = False

timeline_rows = read_timeline_rows(os.environ.get("TRUST_CENTER_TIMELINE_FILE", ""), timeline_root)
action_events = {
    "env": {"env-trust"},
    "lsp": {"lsp-trust"},
    "debug": {"debug-trust"},
    "devcontainer": {"devcontainer-trust"},
    "share": {"share-trust"},
    "workflow": {"workflow-trust"},
}
run_events = {
    "env": {"env-load"},
    "lsp": {
        "lsp-start",
        "lsp-stop",
        "lsp-install",
        "lsp-diagnostics",
        "lsp-hover",
        "lsp-definition",
        "lsp-references",
        "lsp-rename",
    },
    "debug": {"debug-start", "debug-stop"},
    "devcontainer": {"devcontainer-up", "devcontainer-down"},
    "share": {"share-host", "share-revoke", "share-join", "share-expire"},
    "workflow": {"workflow"},
}


def capability_summary(name: str, payload: dict) -> str:
    trusted = "trusted" if payload.get("trusted") else "untrusted"
    if name == "env":
        count = int(payload.get("fileCount") or 0)
        if count == 0:
            return "no .env files detected"
        return f"{trusted} ({count} env file(s))"
    if name == "lsp":
        return " / ".join(
            part
            for part in [
                trusted,
                payload.get("runtimeState") or "stopped",
                payload.get("health") or "",
                payload.get("resolutionStatus") or "",
            ]
            if part
        )
    if name == "debug":
        available = sum(1 for family in payload.get("families") or [] if family.get("available"))
        recommended = payload.get("recommendedTool") or ("local-only" if payload.get("localOnly") else "")
        return " / ".join(
            part
            for part in [
                trusted,
                payload.get("state") or "stopped",
                f"{available} family(s) available",
                recommended,
            ]
            if part
        )
    if name == "devcontainer":
        support = "supported" if payload.get("supported") else "unsupported"
        return " / ".join(
            part
            for part in [
                trusted,
                support,
                payload.get("state") or "stopped",
                payload.get("health") or "",
            ]
            if part
        )
    if name == "share":
        return " / ".join(
            part
            for part in [
                trusted,
                payload.get("state") or "stopped",
                payload.get("transportStatus") or "",
                payload.get("transport") or "",
            ]
            if part
        )
    if name == "workflow":
        workflow_count = int(payload.get("workflowCount") or 0)
        return f"{trusted} ({workflow_count} authored workflow(s))"
    return trusted

order = ["env", "lsp", "debug", "devcontainer", "share", "workflow"]
for name in order:
    payload = capabilities.get(name) or {}
    payload["summary"] = capability_summary(name, payload)
    payload["lastAction"] = last_event(timeline_rows, action_events.get(name) or set())
    payload["lastRun"] = last_event(timeline_rows, run_events.get(name) or set())
    payload["controlsAvailable"] = controls_available
    if controls_available:
        payload["revokeCommand"] = f"yen ide trust revoke {name} --project {json.dumps(root)}"
    else:
        payload["revokeCommand"] = ""
    if controls_available and name in {"lsp", "debug", "devcontainer", "share"}:
        payload["supportsReset"] = True
        payload["resetCommand"] = f"yen ide trust reset {name} --project {json.dumps(root)}"
    else:
        payload["supportsReset"] = False
        payload["resetCommand"] = ""

trusted_count = sum(1 for name in order if (capabilities.get(name) or {}).get("trusted"))
active_count = sum(1 for name in order if (capabilities.get(name) or {}).get("active"))

payload = {
    "schemaVersion": 1,
    "root": root,
    "workspace": {
        "executionLocation": os.environ.get("IDE_WORKSPACE_EXECUTION_LOCATION", "local"),
        "transport": os.environ.get("IDE_WORKSPACE_TRANSPORT", "local"),
        "identity": os.environ.get("IDE_WORKSPACE_IDENTITY", ""),
        "requestedPath": os.environ.get("IDE_WORKSPACE_REQUESTED_PATH", ""),
        "authority": os.environ.get("IDE_WORKSPACE_AUTHORITY", ""),
        "port": int(os.environ.get("IDE_WORKSPACE_PORT") or "0") if os.environ.get("IDE_WORKSPACE_PORT") else None,
        "label": os.environ.get("IDE_WORKSPACE_LABEL", ""),
    },
    "evidence": {
        "projectMetadataSource": "remote-probe" if os.environ.get("IDE_WORKSPACE_EXECUTION_LOCATION") == "remote" else "local-filesystem",
        "stateSource": "local-ide-state",
        "timelineSource": "local-ide-state",
        "controlsAvailable": controls_available,
        "note": (
            "Remote trust summaries use a read-only SSH probe for project metadata and local IDE state keyed by workspace identity for trust/runtime evidence."
            if os.environ.get("IDE_WORKSPACE_EXECUTION_LOCATION") == "remote"
            else "Trust summaries use the local workspace plus local IDE state."
        ),
    },
    "summary": {
        "capabilities": len(order),
        "trusted": trusted_count,
        "active": active_count,
    },
    "capabilities": {name: capabilities.get(name) or {} for name in order},
}

print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

merge_readiness_json_for_root() {
    local root="$1"
    local snapshot=""
    local findings=""
    local blocker_count="0"
    local warning_count="0"
    local overall_status="ok"
    local doctor_payload=""
    local trust_payload=""
    local verify_payload=""
    local payload=""
    local review_targets=""
    local review_context_json=""
    local -a review_target_array=()

    snapshot=$(doctor_collect_snapshot "${root}")
    findings=$(doctor_collect_findings "${snapshot}")
    blocker_count=$(doctor_count_findings "${findings}" "blocker")
    warning_count=$(doctor_count_findings "${findings}" "warning")
    overall_status=$(doctor_overall_status "${blocker_count}" "${warning_count}")
    doctor_payload=$(doctor_json_from_snapshot "${snapshot}" "${findings}" "${overall_status}" "${blocker_count}" "${warning_count}")
    trust_payload=$(trust_center_collect_json "${root}")
    verify_payload=$(verify_status_json_for_root "${root}")

    payload=$(
    MERGE_READINESS_ROOT="${root}" \
    MERGE_READINESS_DOCTOR="${doctor_payload}" \
    MERGE_READINESS_TRUST="${trust_payload}" \
    MERGE_READINESS_VERIFY="${verify_payload}" \
    MERGE_READINESS_TIMELINE="${IDE_TIMELINE_FILE}" \
    python3 - <<'PY'
import json
import os
import pathlib
import subprocess


def load_payload(name: str):
    raw = os.environ.get(name, "")
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except Exception:
        return {}


root = os.environ.get("MERGE_READINESS_ROOT", "")
timeline_path = os.environ.get("MERGE_READINESS_TIMELINE", "")
doctor = load_payload("MERGE_READINESS_DOCTOR")
trust = load_payload("MERGE_READINESS_TRUST")
verify = load_payload("MERGE_READINESS_VERIFY")


def run_command(args):
    try:
        completed = subprocess.run(
            args,
            cwd=root or None,
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return 127, "", ""
    return (
        completed.returncode,
        completed.stdout.rstrip("\n"),
        completed.stderr.rstrip("\n"),
    )


def git_output(*args):
    return run_command(["git", *args])


def gh_output(*args):
    return run_command(["gh", *args])


def parse_key_value_blob(text: str):
    values = {}
    for part in (text or "").split(";"):
        if "=" not in part:
            continue
        key, value = part.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key:
            values[key] = value
    return values


def read_timeline_rows(path: str, project_root: str):
    rows = []
    if not path or not os.path.exists(path):
        return rows
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t", 4)
            if len(parts) != 5:
                continue
            timestamp, event, row_root, status, detail = parts
            if row_root != project_root:
                continue
            meta = {}
            meta.update(parse_key_value_blob(status))
            meta.update(parse_key_value_blob(detail))
            rows.append(
                {
                    "time": timestamp,
                    "event": event,
                    "status": status,
                    "detail": detail,
                    "metadata": meta,
                }
            )
    return rows


def latest_event(rows, name: str):
    for row in reversed(rows):
        if row.get("event") == name:
            return row
    return {}


def flatten_nodes(raw):
    if isinstance(raw, list):
        return raw
    if isinstance(raw, dict):
        for key in ("nodes", "edges", "contexts", "results", "items"):
            value = raw.get(key)
            if isinstance(value, list):
                if key == "edges":
                    return [entry.get("node") for entry in value if isinstance(entry, dict) and entry.get("node")]
                return value
            if isinstance(value, dict):
                nested = flatten_nodes(value)
                if nested:
                    return nested
    return []


def unique_list(values):
    seen = set()
    ordered = []
    for value in values:
        if not value or value in seen:
            continue
        seen.add(value)
        ordered.append(value)
    return ordered


def step_category_summary(steps):
    summary = {}
    for step in steps or []:
        category = (step.get("category") or "general").strip() or "general"
        result = (step.get("result") or "unknown").strip() or "unknown"
        bucket = summary.setdefault(
            category,
            {
                "total": 0,
                "pass": 0,
                "warn": 0,
                "fail": 0,
                "steps": [],
            },
        )
        bucket["total"] += 1
        if result in {"pass", "warn", "fail"}:
            bucket[result] += 1
        bucket["steps"].append(step.get("id") or "")
    return summary


def path_risk_tags(path: str):
    tags = []
    lowered = (path or "").lower()
    if path.startswith("public/stable/"):
        tags.append("release")
    if path.startswith("scripts/") or lowered.endswith(".sh"):
        tags.append("shell")
    if path.startswith("supabase/migrations/") or lowered.endswith(".sql"):
        tags.append("schema")
    if path.startswith(".github/workflows/") or path == "vercel.json":
        tags.append("deploy")
    if path.startswith("yen-terminal/customizations/") or path.startswith("yen-terminal/overlays/"):
        tags.append("desktop")
    if "oauth" in lowered or lowered.endswith(".entitlements") or lowered.endswith(".plist"):
        tags.append("auth")
    if path.startswith("yen-cli/"):
        tags.append("cli")
    return unique_list(tags)


def resolve_git_ref(candidates):
    for candidate in candidates:
        if not candidate:
            continue
        code, _, _ = git_output("rev-parse", "--verify", "--quiet", candidate)
        if code == 0:
            return candidate
    return ""


def default_branch_name():
    code, out, _ = gh_output("repo", "view", "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name")
    if code == 0 and out:
        return out.strip()
    code, out, _ = git_output("symbolic-ref", "refs/remotes/origin/HEAD")
    if code == 0 and out:
        return out.rsplit("/", 1)[-1]
    for fallback in ("main", "master"):
        if resolve_git_ref(
            [
                f"origin/{fallback}",
                f"refs/remotes/origin/{fallback}",
                fallback,
                f"refs/heads/{fallback}",
            ]
        ):
            return fallback
    return ""


def collect_pr_payload():
    base = {
        "available": False,
        "reason": "No current-branch pull request detected.",
        "number": 0,
        "title": "",
        "url": "",
        "isDraft": False,
        "reviewDecision": "",
        "mergeStateStatus": "",
        "mergeable": "",
        "baseRefName": "",
        "headRefName": "",
        "changedFiles": 0,
        "additions": 0,
        "deletions": 0,
        "requestedReviewers": [],
        "latestReviews": {
            "approvals": 0,
            "changeRequests": 0,
            "comments": 0,
        },
        "checks": {
            "state": "unavailable",
            "passing": 0,
            "pending": 0,
            "failing": 0,
            "total": 0,
        },
        "pendingApprovals": 0,
    }

    field_sets = [
        [
            "number",
            "title",
            "url",
            "isDraft",
            "reviewDecision",
            "mergeStateStatus",
            "mergeable",
            "reviewRequests",
            "latestReviews",
            "additions",
            "deletions",
            "changedFiles",
            "baseRefName",
            "headRefName",
            "statusCheckRollup",
        ],
        [
            "number",
            "title",
            "url",
            "isDraft",
            "reviewDecision",
            "mergeStateStatus",
            "mergeable",
            "additions",
            "deletions",
            "changedFiles",
            "baseRefName",
            "headRefName",
        ],
    ]

    payload = None
    failure_reason = ""
    for fields in field_sets:
        code, out, err = gh_output("pr", "view", "--json", ",".join(fields))
        if code == 0 and out:
            try:
                payload = json.loads(out)
                break
            except Exception:
                failure_reason = "GitHub returned unreadable PR metadata."
                continue
        if err:
            failure_reason = err

    if payload is None:
        code, _, _ = gh_output("--version")
        if code == 127:
            base["reason"] = "GitHub CLI is not installed."
        elif failure_reason:
            base["reason"] = failure_reason
        return base

    requested_reviewers = []
    for request in flatten_nodes(payload.get("reviewRequests")):
        reviewer = request
        if isinstance(request, dict):
            reviewer = request.get("requestedReviewer") or request.get("requestedReviewerActor") or request
        if isinstance(reviewer, dict):
            requested_reviewers.append(
                reviewer.get("login")
                or reviewer.get("name")
                or reviewer.get("slug")
                or reviewer.get("handle")
                or ""
            )
        elif isinstance(reviewer, str):
            requested_reviewers.append(reviewer)
    requested_reviewers = unique_list(requested_reviewers)

    approvals = 0
    change_requests = 0
    comments = 0
    for review in flatten_nodes(payload.get("latestReviews")):
        if not isinstance(review, dict):
            continue
        state = (review.get("state") or "").upper()
        if state == "APPROVED":
            approvals += 1
        elif state == "CHANGES_REQUESTED":
            change_requests += 1
        elif state in {"COMMENTED", "DISMISSED"}:
            comments += 1

    checks = {
        "state": "unavailable",
        "passing": 0,
        "pending": 0,
        "failing": 0,
        "total": 0,
    }
    for item in flatten_nodes(payload.get("statusCheckRollup")):
        if not isinstance(item, dict):
            continue
        state = (
            item.get("conclusion")
            or item.get("status")
            or item.get("state")
            or item.get("rollupState")
            or ""
        ).upper()
        if not state:
            continue
        checks["total"] += 1
        if state in {"SUCCESS", "SUCCESSFUL", "PASS", "PASSED", "EXPECTED", "NEUTRAL", "SKIPPED"}:
            checks["passing"] += 1
        elif state in {"PENDING", "QUEUED", "IN_PROGRESS", "WAITING", "REQUESTED"}:
            checks["pending"] += 1
        else:
            checks["failing"] += 1

    if checks["total"] > 0:
        if checks["failing"] > 0:
            checks["state"] = "failing"
        elif checks["pending"] > 0:
            checks["state"] = "pending"
        else:
            checks["state"] = "passing"

    review_decision = (payload.get("reviewDecision") or "").upper()
    pending_approvals = len(requested_reviewers)
    if pending_approvals == 0 and review_decision == "REVIEW_REQUIRED":
        pending_approvals = 1

    base.update(
        {
            "available": True,
            "reason": "",
            "number": int(payload.get("number") or 0),
            "title": payload.get("title") or "",
            "url": payload.get("url") or "",
            "isDraft": bool(payload.get("isDraft")),
            "reviewDecision": review_decision,
            "mergeStateStatus": (payload.get("mergeStateStatus") or "").upper(),
            "mergeable": (payload.get("mergeable") or "").upper(),
            "baseRefName": payload.get("baseRefName") or "",
            "headRefName": payload.get("headRefName") or "",
            "changedFiles": int(payload.get("changedFiles") or 0),
            "additions": int(payload.get("additions") or 0),
            "deletions": int(payload.get("deletions") or 0),
            "requestedReviewers": requested_reviewers,
            "latestReviews": {
                "approvals": approvals,
                "changeRequests": change_requests,
                "comments": comments,
            },
            "checks": checks,
            "pendingApprovals": pending_approvals,
        }
    )
    return base


def collect_git_payload(pr_payload):
    base = {
        "available": False,
        "branch": "",
        "head": "",
        "compareBase": "",
        "baseBranch": "",
        "ahead": 0,
        "behind": 0,
        "diff": {
            "changedFiles": 0,
            "additions": 0,
            "deletions": 0,
        },
        "workingTree": {
            "dirty": False,
            "staged": 0,
            "modified": 0,
            "untracked": 0,
            "conflicts": 0,
            "entries": [],
        },
        "changedPaths": [],
        "riskyFiles": [],
    }

    code, out, _ = git_output("rev-parse", "--is-inside-work-tree")
    if code != 0 or out.strip() != "true":
        base["reason"] = "Not inside a git work tree."
        return base

    base["available"] = True
    base["branch"] = git_output("rev-parse", "--abbrev-ref", "HEAD")[1]
    base["head"] = git_output("rev-parse", "HEAD")[1]

    porcelain = git_output("status", "--porcelain=v1", "-z", "--untracked-files=all")[1]
    working_entries = []
    changed_paths = []
    porcelain_entries = [entry for entry in porcelain.split("\0") if entry]
    idx = 0
    while idx < len(porcelain_entries):
        raw = porcelain_entries[idx]
        code_text = raw[:2]
        path_text = raw[3:] if len(raw) > 3 else ""
        orig_path = ""
        if code_text and ("R" in code_text or "C" in code_text) and idx + 1 < len(porcelain_entries):
            orig_path = porcelain_entries[idx + 1]
            idx += 1
        entry = {"code": code_text, "path": path_text}
        if orig_path:
            entry["fromPath"] = orig_path
        working_entries.append(entry)
        changed_paths.append(path_text)
        if orig_path:
            changed_paths.append(orig_path)
        if code_text == "??":
            base["workingTree"]["untracked"] += 1
        elif code_text and code_text[0] not in {" ", "?"}:
            base["workingTree"]["staged"] += 1
        if len(code_text) > 1 and code_text[1] not in {" ", "?"}:
            base["workingTree"]["modified"] += 1
        if "U" in code_text or code_text in {"AA", "DD"}:
            base["workingTree"]["conflicts"] += 1
        idx += 1
    base["workingTree"]["dirty"] = len(working_entries) > 0
    base["workingTree"]["entries"] = working_entries

    base_branch = pr_payload.get("baseRefName") or default_branch_name()
    compare_ref = ""
    if base_branch:
        compare_ref = resolve_git_ref(
            [
                f"origin/{base_branch}",
                f"refs/remotes/origin/{base_branch}",
                base_branch,
                f"refs/heads/{base_branch}",
            ]
        )
    base["baseBranch"] = base_branch
    base["compareBase"] = compare_ref or base_branch

    diff_args = []
    if compare_ref:
        merge_base_code, _, _ = git_output("merge-base", "HEAD", compare_ref)
        if merge_base_code == 0:
            diff_args = ["diff", "--numstat", f"{compare_ref}...HEAD"]
        else:
            diff_args = ["diff", "--numstat", compare_ref]
        code, out, _ = git_output("rev-list", "--left-right", "--count", f"{compare_ref}...HEAD")
        if code == 0 and out:
            parts = out.split()
            if len(parts) == 2:
                try:
                    base["behind"] = int(parts[0])
                    base["ahead"] = int(parts[1])
                except ValueError:
                    pass
    else:
        code, _, _ = git_output("rev-parse", "HEAD^")
        if code == 0:
            diff_args = ["diff", "--numstat", "HEAD^...HEAD"]

    diff_rows = []
    diff_paths = []
    if diff_args:
        _, out, _ = git_output(*diff_args)
        diff_rows = [line for line in out.splitlines() if line.strip()]
        diff_name_args = ["diff", "--name-only", "-z"] + diff_args[2:]
        _, diff_names, _ = git_output(*diff_name_args)
        diff_paths = [entry for entry in diff_names.split("\0") if entry]

    additions = 0
    deletions = 0
    for row in diff_rows:
        parts = row.split("\t")
        if len(parts) < 2:
            continue
        added_text, deleted_text = parts[0], parts[1]
        try:
            additions += int(added_text)
        except ValueError:
            pass
        try:
            deletions += int(deleted_text)
        except ValueError:
            pass

    all_paths = unique_list(diff_paths + changed_paths)
    risky_files = []
    for path in all_paths:
        tags = path_risk_tags(path)
        if not tags:
            continue
        risky_files.append(
            {
                "path": path,
                "tags": tags,
                "score": len(tags),
            }
        )
    risky_files.sort(key=lambda item: (-int(item.get("score") or 0), item.get("path") or ""))

    base["diff"] = {
        "changedFiles": len(diff_paths),
        "additions": additions,
        "deletions": deletions,
    }
    base["changedPaths"] = all_paths
    base["riskyFiles"] = risky_files
    return base


timeline_rows = read_timeline_rows(timeline_path, root)
last_gate = latest_event(timeline_rows, "gate")
last_gate_exec = latest_event(timeline_rows, "gate-exec")
last_pr_review = latest_event(timeline_rows, "pr-review")

pr = collect_pr_payload()
git_state = collect_git_payload(pr)

verify_steps = (verify.get("steps") or []) if isinstance(verify, dict) else []
verify_category_summary = step_category_summary(verify_steps)
if isinstance(verify, dict):
    verify["categorySummary"] = verify_category_summary

doctor_status = (doctor.get("status") or "").lower() if isinstance(doctor, dict) else ""
verify_latest = ((verify.get("latest") or {}).get("status") or "").lower() if isinstance(verify, dict) else ""
verify_readiness = (verify.get("readiness") or {}) if isinstance(verify, dict) else {}
verify_security = (verify.get("security") or {}) if isinstance(verify, dict) else {}
pr_checks = pr.get("checks") or {}
pr_review_decision = (pr.get("reviewDecision") or "").upper()
pr_merge_state = (pr.get("mergeStateStatus") or "").upper()
pr_mergeable = (pr.get("mergeable") or "").upper()
risky_files = git_state.get("riskyFiles") or []
pending_approvals = int(pr.get("pendingApprovals") or 0)

next_action = {
    "label": "needs human check",
    "reason": "Local merge-readiness data is incomplete.",
}

if git_state.get("workingTree", {}).get("conflicts", 0) > 0:
    next_action = {
        "label": "needs human check",
        "reason": "Unresolved merge conflicts are present in the working tree.",
    }
elif int(doctor.get("blockers") or 0) > 0:
    next_action = {
        "label": "needs human check",
        "reason": "Workspace doctor still reports blocking issues.",
    }
elif verify_latest in {"never-run", "report-missing"}:
    next_action = {
        "label": "needs human check",
        "reason": (verify_readiness.get("reason") or "A fresh local verify baseline is still missing.").strip(),
    }
elif (verify_readiness.get("status") or "") == "blocked":
    next_action = {
        "label": "needs human check",
        "reason": (verify_readiness.get("reason") or "Latest local verify run is blocked.").strip(),
    }
elif (verify_security.get("status") or "") == "blocked":
    next_action = {
        "label": "needs human check",
        "reason": (verify_security.get("reason") or "Latest local security checks are blocked.").strip(),
    }
elif pr.get("available"):
    if pr.get("isDraft"):
        next_action = {
            "label": "needs human check",
            "reason": "The current branch PR is still marked draft.",
        }
    elif pr_review_decision == "CHANGES_REQUESTED":
        next_action = {
            "label": "needs human check",
            "reason": "GitHub review decision is changes requested.",
        }
    elif pr_checks.get("state") == "failing":
        next_action = {
            "label": "needs human check",
            "reason": "GitHub status checks are failing.",
        }
    elif pr_checks.get("state") == "pending":
        next_action = {
            "label": "needs human check",
            "reason": "GitHub status checks are still pending.",
        }
    elif pr_mergeable == "CONFLICTING" or pr_merge_state in {"BLOCKED", "DIRTY", "BEHIND", "UNKNOWN", "UNSTABLE"}:
        next_action = {
            "label": "needs human check",
            "reason": "GitHub reports the PR is not in a clean mergeable state.",
        }
    elif git_state.get("workingTree", {}).get("dirty"):
        next_action = {
            "label": "needs human check",
            "reason": "Local working tree changes are not reflected in the current PR.",
        }
    elif (
        verify_readiness.get("mergeReady")
        and int(doctor.get("blockers") or 0) == 0
        and int(doctor.get("warnings") or 0) == 0
        and pending_approvals == 0
        and pr_review_decision == "APPROVED"
        and pr_checks.get("state") in {"passing", "unavailable"}
    ):
        next_action = {
            "label": "safe to merge",
            "reason": "PR approvals, merge state, and local verify data are all clear.",
        }
    else:
        next_action = {
            "label": "safe to review",
            "reason": "Local verify is green; the branch still needs human review or approval.",
        }
else:
    if verify_readiness.get("mergeReady") and int(doctor.get("blockers") or 0) == 0 and not git_state.get("workingTree", {}).get("conflicts"):
        next_action = {
            "label": "safe to review",
            "reason": "Local verify and trust data are in a reviewable state; no current-branch PR was found.",
        }
    elif (verify_readiness.get("status") or "") == "warning" or (verify_security.get("status") or "") == "warning":
        next_action = {
            "label": "needs human check",
            "reason": "Warnings remain in the latest local verify or security snapshot.",
        }
    elif int(doctor.get("warnings") or 0) > 0:
        next_action = {
            "label": "needs human check",
            "reason": "Workspace doctor warnings should be reviewed before merge.",
        }
    elif risky_files:
        next_action = {
            "label": "safe to review",
            "reason": "High-signal paths changed; route them through a human review before merge.",
        }

payload = {
    "schemaVersion": 1,
    "root": root,
    "summary": {
        "status": next_action["label"],
        "reason": next_action["reason"],
        "pendingApprovals": pending_approvals,
        "riskyFiles": len(risky_files),
        "workingTreeDirty": bool(git_state.get("workingTree", {}).get("dirty")),
        "mergeConflicts": int(git_state.get("workingTree", {}).get("conflicts") or 0),
    },
    "project": {
        "branch": git_state.get("branch") or "",
        "compareBase": git_state.get("compareBase") or "",
        "baseBranch": git_state.get("baseBranch") or "",
        "ahead": int(git_state.get("ahead") or 0),
        "behind": int(git_state.get("behind") or 0),
    },
    "git": git_state,
    "doctor": doctor,
    "trust": trust,
    "verify": verify,
    "gate": {
        "lastDecision": last_gate,
        "lastExecution": last_gate_exec,
    },
    "localReview": {
        "lastReview": last_pr_review,
    },
    "pr": pr,
}

print(json.dumps(payload, indent=2, sort_keys=True))
PY
)

    if declare -F review_context_json_for_targets >/dev/null 2>&1; then
        review_targets=$(MERGE_READINESS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

try:
    payload = json.loads(os.environ.get("MERGE_READINESS_PAYLOAD") or "{}")
except Exception:
    payload = {}

seen = []
for item in (payload.get("git") or {}).get("riskyFiles") or []:
    path = (item.get("path") or "").strip()
    if path and path not in seen:
        seen.append(path)
for path in (payload.get("git") or {}).get("changedPaths") or []:
    path = (path or "").strip()
    if path and path not in seen:
        seen.append(path)

for value in seen[:12]:
    print(value)
PY
)
        if [[ -n "${review_targets}" ]]; then
            while IFS= read -r review_target; do
                [[ -n "${review_target}" ]] && review_target_array+=("${review_target}")
            done << EOF
${review_targets}
EOF
        fi
        if [[ ${#review_target_array[@]} -gt 0 ]]; then
            review_context_json=$(review_context_json_for_targets "${root}" "${review_target_array[@]}")
            payload=$(MERGE_READINESS_PAYLOAD="${payload}" MERGE_REVIEW_CONTEXT="${review_context_json}" python3 - <<'PY'
import json
import os

try:
    payload = json.loads(os.environ.get("MERGE_READINESS_PAYLOAD") or "{}")
except Exception:
    payload = {}
try:
    review = json.loads(os.environ.get("MERGE_REVIEW_CONTEXT") or "{}")
except Exception:
    review = {}

entry_map = {}
for entry in review.get("entries") or []:
    path = (entry.get("path") or "").strip()
    if path:
        entry_map[path] = entry

for item in (payload.get("git") or {}).get("riskyFiles") or []:
    context = entry_map.get((item.get("path") or "").strip())
    if context:
        item["reviewContext"] = context

summary = payload.get("summary") or {}
summary["ownerHints"] = sum(1 for entry in review.get("entries") or [] if entry.get("owners"))
summary["historyHints"] = sum(1 for entry in review.get("entries") or [] if entry.get("history"))
summary["debuggableReviewTargets"] = sum(1 for entry in review.get("entries") or [] if entry.get("debugHandoff"))
payload["summary"] = summary
payload["reviewContext"] = {
    "available": bool(review.get("entries")),
    "gitAvailable": bool(review.get("gitAvailable")),
    "codeownersFile": review.get("codeownersFile") or "",
    "paths": review.get("entries") or [],
}

print(json.dumps(payload, indent=2, sort_keys=True))
PY
)
        fi
    fi

    printf "%s\n" "${payload}"
}

merge_readiness_text_from_payload() {
    local payload="$1"
    MERGE_READINESS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os


def load_payload():
    raw = os.environ.get("MERGE_READINESS_PAYLOAD", "")
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except Exception:
        return {}


def text(value, fallback=""):
    value = "" if value is None else str(value).strip()
    return value if value else fallback


def render_event(row):
    if not row:
        return "never"
    event = text(row.get("event"))
    time = text(row.get("time"))
    status = text(row.get("status"))
    detail = text(row.get("detail"))
    parts = [part for part in [time, event, status] if part]
    line = " / ".join(parts) if parts else "never"
    if detail:
        line = f"{line} / {detail}"
    return line


payload = load_payload()
summary = payload.get("summary") or {}
project = payload.get("project") or {}
git_state = payload.get("git") or {}
verify = payload.get("verify") or {}
doctor = payload.get("doctor") or {}
trust = payload.get("trust") or {}
pr = payload.get("pr") or {}
gate = payload.get("gate") or {}
local_review = payload.get("localReview") or {}
review_context = payload.get("reviewContext") or {}
working_tree = git_state.get("workingTree") or {}
diff = git_state.get("diff") or {}
verify_latest = verify.get("latest") or {}
verify_readiness = verify.get("readiness") or {}
verify_security = verify.get("security") or {}
category_summary = verify.get("categorySummary") or {}
trust_summary = trust.get("summary") or {}

print("")
print("IDE Merge Readiness")
print(f"Project root:       {text(payload.get('root'))}")
print(f"Recommended action: {text(summary.get('status'), 'needs human check')}")
print(f"Reason:             {text(summary.get('reason'))}")
print(f"Branch:             {text(project.get('branch'), 'unknown')}")
print(f"Compare base:       {text(project.get('compareBase'), 'unavailable')}")
print(
    "Branch delta:       "
    f"ahead {int(project.get('ahead') or 0)} / behind {int(project.get('behind') or 0)}"
)
print(
    "Diff summary:       "
    f"{int(diff.get('changedFiles') or 0)} file(s), "
    f"+{int(diff.get('additions') or 0)} / -{int(diff.get('deletions') or 0)}"
)
print(
    "Working tree:       "
    f"{'dirty' if working_tree.get('dirty') else 'clean'} "
    f"(staged={int(working_tree.get('staged') or 0)} "
    f"modified={int(working_tree.get('modified') or 0)} "
    f"untracked={int(working_tree.get('untracked') or 0)} "
    f"conflicts={int(working_tree.get('conflicts') or 0)})"
)
print(
    "Risky files:        "
    f"{int(summary.get('riskyFiles') or 0)}"
)
print(
    "Pending approvals:  "
    f"{int(summary.get('pendingApprovals') or 0)}"
)
print("")
print("Verify:")
print(f"  Latest:        {text(verify_latest.get('status'), 'never-run')}")
print(
    f"  Readiness:     {text(verify_readiness.get('status'), 'unavailable')} "
    f"(merge ready={'yes' if verify_readiness.get('mergeReady') else 'no'})"
)
print(f"  Security:      {text(verify_security.get('status'), 'unavailable')}")
for category in ("quality", "build", "test", "security"):
    bucket = category_summary.get(category) or {}
    if not bucket:
        continue
    print(
        f"  {category.capitalize():<13}"
        f"{int(bucket.get('pass') or 0)} pass / "
        f"{int(bucket.get('warn') or 0)} warn / "
        f"{int(bucket.get('fail') or 0)} fail"
    )
print(f"  Summary report: {text(verify_latest.get('summaryReport'), 'missing')}")
print("")
print(
    "Doctor / Trust:    "
    f"{text(doctor.get('status'), 'unknown')} "
    f"(blockers={int(doctor.get('blockers') or 0)} warnings={int(doctor.get('warnings') or 0)}) / "
    f"{int(trust_summary.get('trusted') or 0)} trusted of {int(trust_summary.get('capabilities') or 0)} "
    f"(active={int(trust_summary.get('active') or 0)})"
)

if pr.get("available"):
    checks = pr.get("checks") or {}
    reviews = pr.get("latestReviews") or {}
    print("")
    print("Pull Request:")
    print(f"  PR:            #{int(pr.get('number') or 0)} {text(pr.get('title'))}")
    print(f"  URL:           {text(pr.get('url'))}")
    print(
        f"  Review:        {text(pr.get('reviewDecision'), 'unavailable')} "
        f"(approvals={int(reviews.get('approvals') or 0)} "
        f"changes={int(reviews.get('changeRequests') or 0)})"
    )
    print(
        f"  Merge state:   {text(pr.get('mergeStateStatus'), 'unavailable')} / "
        f"{text(pr.get('mergeable'), 'unavailable')}"
    )
    print(
        f"  Checks:        {text(checks.get('state'), 'unavailable')} "
        f"(pass={int(checks.get('passing') or 0)} "
        f"pending={int(checks.get('pending') or 0)} "
        f"fail={int(checks.get('failing') or 0)})"
    )
    requested = pr.get("requestedReviewers") or []
    if requested:
        print(f"  Requested:     {', '.join(requested[:8])}")
    print(f"  Draft:         {'yes' if pr.get('isDraft') else 'no'}")
else:
    print("")
    print(f"Pull Request:      {text(pr.get('reason'), 'No current-branch pull request detected.')}")

risky_files = git_state.get("riskyFiles") or []
if risky_files:
    print("")
    print("Risky Files:")
    for item in risky_files[:8]:
        context = item.get("reviewContext") or {}
        owners = ", ".join(context.get("owners") or [])
        history = context.get("history") or []
        history_text = ""
        if history:
            latest = history[0]
            history_text = f" / last {text(latest.get('author'))} {text(latest.get('date'))} {text(latest.get('subject'))}"
        owners_text = f" / owners {owners}" if owners else ""
        print(f"  - {text(item.get('path'))} [{', '.join(item.get('tags') or [])}]{owners_text}{history_text}")

review_paths = review_context.get("paths") or []
if review_paths:
    print("")
    print("Review Routing:")
    for entry in review_paths[:6]:
        owners = ", ".join(entry.get("owners") or []) or "unowned"
        history = entry.get("history") or []
        history_text = "no recent git history"
        if history:
            latest = history[0]
            history_text = f"{text(latest.get('author'))} {text(latest.get('date'))} {text(latest.get('subject'))}"
        print(f"  - {text(entry.get('path'))} owners={owners} last={history_text}")
        handoff = entry.get("debugHandoff") or {}
        if handoff:
            print(f"    debug: {text(handoff.get('command'))}")
            if handoff.get("trustRequired"):
                print(f"    trust: {text(handoff.get('trustCommand'))}")

findings = doctor.get("findings") or []
if findings:
    print("")
    print("Top Findings:")
    for finding in findings[:5]:
        print(
            f"  - [{text(finding.get('severity'), 'warning')}] "
            f"{text(finding.get('component'))}: {text(finding.get('summary'))}"
        )

print("")
print(f"Latest gate:       {render_event(gate.get('lastDecision') or {})}")
print(f"Latest gate exec:  {render_event(gate.get('lastExecution') or {})}")
print(f"Latest pr-review:  {render_event(local_review.get('lastReview') or {})}")
print("")
PY
}

cmd_merge_readiness() {
    local target=""
    local format="text"
    local root=""
    local payload=""
    local action_label=""
    local pending_approvals="0"
    local risky_files="0"
    local pr_number=""
    local verify_status=""

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
                if [[ -n "${target}" ]]; then
                    yen_error "merge-readiness accepts at most one project path."
                    return 1
                fi
                target="$1"
                ;;
        esac
        shift
    done

    root=$(find_project_root "${target}")
    payload=$(merge_readiness_json_for_root "${root}")

    case "${format}" in
        json)
            printf "%s\n" "${payload}"
            ;;
        text)
            merge_readiness_text_from_payload "${payload}"
            ;;
        *)
            yen_error "Unknown merge-readiness format: ${format} (expected text|json)"
            return 1
            ;;
    esac

    action_label=$(MERGE_READINESS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

try:
    payload = json.loads(os.environ.get("MERGE_READINESS_PAYLOAD") or "{}")
except Exception:
    payload = {}

print(((payload.get("summary") or {}).get("status") or "needs human check").replace(" ", "-"))
PY
)
    pending_approvals=$(MERGE_READINESS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

try:
    payload = json.loads(os.environ.get("MERGE_READINESS_PAYLOAD") or "{}")
except Exception:
    payload = {}

print(int((payload.get("summary") or {}).get("pendingApprovals") or 0))
PY
)
    risky_files=$(MERGE_READINESS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

try:
    payload = json.loads(os.environ.get("MERGE_READINESS_PAYLOAD") or "{}")
except Exception:
    payload = {}

print(int((payload.get("summary") or {}).get("riskyFiles") or 0))
PY
)
    pr_number=$(MERGE_READINESS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

try:
    payload = json.loads(os.environ.get("MERGE_READINESS_PAYLOAD") or "{}")
except Exception:
    payload = {}

pr = payload.get("pr") or {}
print(int(pr.get("number") or 0))
PY
)
    verify_status=$(MERGE_READINESS_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

try:
    payload = json.loads(os.environ.get("MERGE_READINESS_PAYLOAD") or "{}")
except Exception:
    payload = {}

print(((payload.get("verify") or {}).get("latest") or {}).get("status") or "unknown")
PY
)
    timeline_log "merge-readiness" "${root}" "status=${action_label};pending=${pending_approvals};risky=${risky_files}" "pr=${pr_number};verify=${verify_status};format=${format}"
}

cmd_trust_status() {
    local target=""
    local format="text"
    local root=""
    local payload=""

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

    if ! workspace_summary_resolve_target "${target}"; then
        return 1
    fi
    root="${IDE_WORKSPACE_SUMMARY_ROOT}"
    payload=$(trust_center_collect_json "${root}")

    case "${format}" in
        json)
            printf "%s\n" "${payload}"
            ;;
        env)
            TRUST_CENTER_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("TRUST_CENTER_PAYLOAD") or "{}")
summary = payload.get("summary") or {}
capabilities = payload.get("capabilities") or {}
order = ["env", "lsp", "debug", "devcontainer", "share", "workflow"]


def emit(name: str, value):
    text = "" if value is None else str(value)
    escaped = text.replace("'", "'\"'\"'")
    print(f"export {name}='{escaped}'")


emit("YEN_IDE_TRUST_ROOT", payload.get("root", ""))
workspace = payload.get("workspace") or {}
evidence = payload.get("evidence") or {}
emit("YEN_IDE_TRUST_EXECUTION_LOCATION", workspace.get("executionLocation", "local"))
emit("YEN_IDE_TRUST_WORKSPACE_IDENTITY", workspace.get("identity", ""))
emit("YEN_IDE_TRUST_REQUESTED_PATH", workspace.get("requestedPath", ""))
emit("YEN_IDE_TRUST_PROJECT_METADATA_SOURCE", evidence.get("projectMetadataSource", "local-filesystem"))
emit("YEN_IDE_TRUST_STATE_SOURCE", evidence.get("stateSource", "local-ide-state"))
emit("YEN_IDE_TRUST_TIMELINE_SOURCE", evidence.get("timelineSource", "local-ide-state"))
emit("YEN_IDE_TRUST_CONTROLS_AVAILABLE", "yes" if evidence.get("controlsAvailable") else "no")
emit("YEN_IDE_TRUST_CAPABILITIES", ",".join(order))
emit("YEN_IDE_TRUST_CAPABILITY_COUNT", summary.get("capabilities", 0))
emit("YEN_IDE_TRUST_TRUSTED_COUNT", summary.get("trusted", 0))
emit("YEN_IDE_TRUST_ACTIVE_COUNT", summary.get("active", 0))

for name in order:
    capability = capabilities.get(name) or {}
    prefix = f"YEN_IDE_TRUST_{name.upper()}"
    emit(f"{prefix}_TRUSTED", "yes" if capability.get("trusted") else "no")
    emit(f"{prefix}_STATE", capability.get("state") or capability.get("runtimeState") or "")
    emit(f"{prefix}_ACTIVE", "yes" if capability.get("active") else "no")
    emit(f"{prefix}_SUMMARY", capability.get("summary") or "")
    last_action = capability.get("lastAction") or {}
    last_run = capability.get("lastRun") or {}
    emit(f"{prefix}_LAST_ACTION_AT", last_action.get("time") or "")
    emit(f"{prefix}_LAST_ACTION_EVENT", last_action.get("event") or "")
    emit(f"{prefix}_LAST_ACTION_STATUS", last_action.get("status") or "")
    emit(f"{prefix}_LAST_RUN_AT", last_run.get("time") or "")
    emit(f"{prefix}_LAST_RUN_EVENT", last_run.get("event") or "")
    emit(f"{prefix}_LAST_RUN_STATUS", last_run.get("status") or "")
    emit(f"{prefix}_REVOKE_COMMAND", capability.get("revokeCommand") or "")
    emit(f"{prefix}_SUPPORTS_RESET", "yes" if capability.get("supportsReset") else "no")
    emit(f"{prefix}_RESET_COMMAND", capability.get("resetCommand") or "")
debug_last = (capabilities.get("debug") or {}).get("lastSession") or {}
emit("YEN_IDE_TRUST_DEBUG_SUMMARY_REPORT", debug_last.get("summaryReport") or "")
emit("YEN_IDE_TRUST_DEBUG_DETAILS_REPORT", debug_last.get("detailsReport") or "")
emit("YEN_IDE_TRUST_DEBUG_REPORTS_READY", "yes" if debug_last.get("reportsReady") else "no")
PY
            ;;
        text)
            TRUST_CENTER_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("TRUST_CENTER_PAYLOAD") or "{}")
summary = payload.get("summary") or {}
capabilities = payload.get("capabilities") or {}
workspace = payload.get("workspace") or {}
evidence = payload.get("evidence") or {}
order = ["env", "lsp", "debug", "devcontainer", "share", "workflow"]


def render_event(event_payload: dict) -> str:
    if not event_payload or not event_payload.get("event"):
        return "never"
    return " / ".join(
        part
        for part in [
            event_payload.get("time") or "",
            event_payload.get("event") or "",
            event_payload.get("status") or "",
        ]
        if part
    )

print("")
print("IDE Workspace Trust Center")
print(f"Project root:       {payload.get('root', '')}")
print(f"Execution location: {workspace.get('executionLocation', 'local')}")
if workspace.get("identity"):
    print(f"Workspace identity: {workspace.get('identity')}")
if workspace.get("requestedPath"):
    print(f"Requested path:     {workspace.get('requestedPath')}")
print(f"Project metadata:   {evidence.get('projectMetadataSource', 'local-filesystem')}")
print(f"State evidence:     {evidence.get('stateSource', 'local-ide-state')}")
print(f"Timeline evidence:  {evidence.get('timelineSource', 'local-ide-state')}")
if evidence.get("note"):
    print(f"Note:               {evidence.get('note')}")
print(f"Capabilities:       {summary.get('capabilities', 0)}")
print(f"Trusted:            {summary.get('trusted', 0)}")
print(f"Active:             {summary.get('active', 0)}")
print("")
print(f"{'CAPABILITY':<14} {'TRUSTED':<8} {'STATE':<12} {'ACTIVE':<8} SUMMARY")
for name in order:
    capability = capabilities.get(name) or {}
    state = capability.get("state") or capability.get("runtimeState") or "idle"
    print(
        f"{name:<14} "
        f"{('yes' if capability.get('trusted') else 'no'):<8} "
        f"{state:<12} "
        f"{('yes' if capability.get('active') else 'no'):<8} "
        f"{capability.get('summary', '')}"
    )
print("")
print(f"{'CAPABILITY':<14} LAST ACTION")
for name in order:
    capability = capabilities.get(name) or {}
    print(f"{name:<14} {render_event(capability.get('lastAction') or {})}")
print("")
print(f"{'CAPABILITY':<14} LAST RUN")
for name in order:
    capability = capabilities.get(name) or {}
    print(f"{name:<14} {render_event(capability.get('lastRun') or {})}")

debug_last = (capabilities.get("debug") or {}).get("lastSession") or {}
if debug_last.get("summaryReport") or debug_last.get("detailsReport"):
    print("")
    print("Debug Evidence:")
    print(f"  Summary report: {debug_last.get('summaryReport') or 'missing'}")
    print(f"  Details report: {debug_last.get('detailsReport') or 'missing'}")
    print(f"  Reports ready:  {'yes' if debug_last.get('reportsReady') else 'no'}")
print("")
print("Controls:")
if evidence.get("controlsAvailable"):
    print(
        f"  Revoke trust: yen ide trust revoke <env|lsp|debug|devcontainer|share|workflow|all> --project {payload.get('root', '')}"
    )
    print(
        f"  Reset state:  yen ide trust reset <lsp|debug|devcontainer|share|all> --project {payload.get('root', '')}"
    )
else:
    print("  Remote trust controls remain read-only until remote lifecycle parity ships.")
print("")
PY
            ;;
        *)
            yen_error "Unknown trust status format: ${format} (expected text|env|json)"
            return 1
            ;;
    esac
}

trust_center_normalize_capability() {
    local raw="$1"
    case "${raw}" in
        env|lsp|debug|devcontainer|share|workflow|all)
            printf "%s\n" "${raw}"
            ;;
        *)
            return 1
            ;;
    esac
}

trust_center_resettable_capability() {
    local raw="$1"
    case "${raw}" in
        lsp|debug|devcontainer|share|all)
            printf "%s\n" "${raw}"
            ;;
        *)
            return 1
            ;;
    esac
}

trust_center_revoke_capability() {
    local capability="$1"
    local root="$2"

    case "${capability}" in
        env)
            cmd_env untrust "${root}"
            ;;
        lsp)
            cmd_lsp untrust "${root}"
            ;;
        debug)
            cmd_debug untrust "${root}"
            ;;
        devcontainer)
            cmd_devcontainer untrust "${root}"
            ;;
        share)
            cmd_share untrust "${root}"
            ;;
        workflow)
            cmd_workflow untrust "${root}"
            ;;
        *)
            yen_error "Unsupported trust revoke capability: ${capability}"
            return 1
            ;;
    esac
}

trust_center_reset_capability() {
    local capability="$1"
    local root="$2"

    case "${capability}" in
        lsp)
            cmd_lsp stop "${root}"
            ;;
        debug)
            cmd_debug stop "${root}"
            ;;
        devcontainer)
            cmd_devcontainer down "${root}"
            ;;
        share)
            cmd_share revoke "${root}"
            ;;
        *)
            yen_error "Unsupported trust reset capability: ${capability}"
            return 1
            ;;
    esac
}

cmd_trust() {
    local sub="${1:-status}"
    shift || true
    case "${sub}" in
        status)
            cmd_trust_status "$@"
            ;;
        revoke)
            local capability=""
            local normalized=""
            local target=""
            local root=""
            local failures=0
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --project|--path)
                        shift
                        target="${1:-}"
                        ;;
                    *)
                        if [[ -n "${capability}" ]]; then
                            yen_error "trust revoke accepts one capability or 'all'."
                            return 1
                        fi
                        capability="$1"
                        ;;
                esac
                shift
            done
            if [[ -z "${capability}" ]]; then
                yen_error "trust revoke requires <env|lsp|debug|devcontainer|share|workflow|all>."
                return 1
            fi
            normalized=$(trust_center_normalize_capability "${capability}" || true)
            if [[ -z "${normalized}" ]]; then
                yen_error "Unknown trust revoke capability: ${capability}"
                return 1
            fi
            root=$(find_project_root "${target}")
            if [[ "${normalized}" == "all" ]]; then
                local item=""
                for item in share lsp debug devcontainer workflow env; do
                    if ! trust_center_revoke_capability "${item}" "${root}"; then
                        failures=$((failures + 1))
                    else
                        timeline_log "trust-center" "${root}" "revoke" "capability=${item}"
                    fi
                done
                if [[ "${failures}" -gt 0 ]]; then
                    yen_error "Workspace trust revoke completed with ${failures} failure(s)."
                    return 1
                fi
                yen_success "Workspace trust revoked across all capabilities: ${root}"
                return 0
            fi
            if ! trust_center_revoke_capability "${normalized}" "${root}"; then
                return 1
            fi
            timeline_log "trust-center" "${root}" "revoke" "capability=${normalized}"
            ;;
        reset)
            local capability=""
            local normalized=""
            local target=""
            local root=""
            local failures=0
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --project|--path)
                        shift
                        target="${1:-}"
                        ;;
                    *)
                        if [[ -n "${capability}" ]]; then
                            yen_error "trust reset accepts one capability or 'all'."
                            return 1
                        fi
                        capability="$1"
                        ;;
                esac
                shift
            done
            if [[ -z "${capability}" ]]; then
                yen_error "trust reset requires <lsp|debug|devcontainer|share|all>."
                return 1
            fi
            normalized=$(trust_center_resettable_capability "${capability}" || true)
            if [[ -z "${normalized}" ]]; then
                yen_error "Unknown trust reset capability: ${capability} (expected lsp|debug|devcontainer|share|all)"
                return 1
            fi
            root=$(find_project_root "${target}")
            if [[ "${normalized}" == "all" ]]; then
                local item=""
                for item in lsp debug devcontainer share; do
                    if ! trust_center_reset_capability "${item}" "${root}"; then
                        failures=$((failures + 1))
                    else
                        timeline_log "trust-center" "${root}" "reset" "capability=${item}"
                    fi
                done
                if [[ "${failures}" -gt 0 ]]; then
                    yen_error "Workspace trust reset completed with ${failures} failure(s)."
                    return 1
                fi
                yen_success "Workspace trust reset across active capabilities: ${root}"
                return 0
            fi
            if ! trust_center_reset_capability "${normalized}" "${root}"; then
                return 1
            fi
            timeline_log "trust-center" "${root}" "reset" "capability=${normalized}"
            ;;
        *)
            yen_error "Unknown trust command: ${sub}"
            return 1
            ;;
    esac
}
