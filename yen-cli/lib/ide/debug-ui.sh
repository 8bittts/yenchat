# shellcheck shell=bash
# Terminal debugger dashboard over the existing managed-session control plane.

debug_tui_json_for_root() {
    local root="$1"
    local execution_target="$2"
    local tail_lines="$3"
    local status_payload=""

    status_payload=$(debug_status_json_for_root "${root}" "${execution_target}") || return 1
    DEBUG_TUI_STATUS_PAYLOAD="${status_payload}" \
    DEBUG_TUI_TAIL_LINES="${tail_lines}" \
    python3 - <<'PY'
import json
import os
import pathlib
import re
import shlex


def read_json_env(name):
    try:
        return json.loads(os.environ.get(name) or "{}")
    except Exception:
        return {}


def text(value, fallback=""):
    value = "" if value is None else str(value).strip()
    return value if value else fallback


def parse_location(value):
    raw = text(value)
    match = re.match(r"^(.*?):(\d+)(?::(\d+))?$", raw)
    if not match:
        return {"path": "", "line": None, "column": None, "location": raw}
    return {
        "path": text(match.group(1)),
        "line": int(match.group(2)),
        "column": int(match.group(3)) if match.group(3) else None,
        "location": raw,
    }


def transcript_tail(report_path, limit):
    path_text = text(report_path)
    payload = {
        "available": False,
        "reportPath": path_text,
        "tailLines": max(limit, 1),
        "lines": [],
    }
    if not path_text:
        payload["reason"] = "missing-report"
        return payload
    path = pathlib.Path(path_text)
    if not path.is_file():
        payload["reason"] = "missing-report"
        return payload
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except Exception:
        payload["reason"] = "unreadable-report"
        return payload
    payload["available"] = True
    payload["lines"] = lines[-payload["tailLines"] :]
    payload["reason"] = ""
    return payload


def source_excerpt(root, workspace, location, context_lines=2):
    parsed = parse_location(location)
    payload = {
        "available": False,
        "location": parsed["location"],
        "path": parsed["path"],
        "line": parsed["line"],
        "column": parsed["column"],
        "lines": [],
    }
    if text(workspace.get("executionLocation")) == "remote":
        payload["reason"] = "remote-workspace"
        return payload
    if not parsed["path"] or not parsed["line"]:
        payload["reason"] = "missing-location"
        return payload
    root_text = text(root)
    if not root_text:
        payload["reason"] = "missing-root"
        return payload
    root_path = pathlib.Path(root_text)
    candidate = root_path / parsed["path"]
    if not candidate.is_file():
        payload["reason"] = "missing-source"
        return payload
    try:
        rows = candidate.read_text(encoding="utf-8").splitlines()
    except Exception:
        payload["reason"] = "unreadable-source"
        return payload
    start = max(parsed["line"] - context_lines, 1)
    end = min(parsed["line"] + context_lines, len(rows))
    excerpt = []
    for line_number in range(start, end + 1):
        excerpt.append(
            {
                "lineNumber": line_number,
                "current": line_number == parsed["line"],
                "text": rows[line_number - 1],
            }
        )
    payload["available"] = True
    payload["reason"] = ""
    payload["lines"] = excerpt
    payload["absolutePath"] = str(candidate)
    return payload


def build_controls(status):
    workspace = status.get("workspace") or {}
    managed = status.get("managedSession") or {}
    devcontainer = status.get("devcontainerContext") or {}
    execution_target = text(status.get("executionTarget"), "workspace")
    root = text(status.get("root"))
    project_selector = text(workspace.get("requestedTarget") or root)
    devcontainer_selector = text(devcontainer.get("projectSelector") or project_selector)

    def quoted(value):
        return shlex.quote(text(value))

    selectors = {
        "project": quoted(project_selector),
        "devcontainer_project": quoted(devcontainer_selector),
        "target": quoted(text(managed.get("lastStopLocation"), "path/to/file.py:12")),
    }
    if execution_target == "devcontainer":
        status_cmd = f"yen ide debug status --devcontainer --project {selectors['devcontainer_project']}"
        start_cmd = f"yen ide debug start {selectors['target']} --devcontainer --project {selectors['devcontainer_project']}"
        managed_start_cmd = f"{start_cmd} --managed"
    else:
        status_cmd = f"yen ide debug status {selectors['project']}"
        start_cmd = f"yen ide debug start {selectors['target']} --project {selectors['project']}"
        managed_start_cmd = f"{start_cmd} --managed"

    controls = [
        {
            "id": "status",
            "label": "Status",
            "available": True,
            "command": status_cmd,
            "note": "Refresh the debugger dashboard data for this workspace.",
        },
        {
            "id": "start",
            "label": "Start",
            "available": True,
            "command": start_cmd,
            "note": "Launch a one-shot debugger run on the shared semantic target contract.",
        },
        {
            "id": "managed-start",
            "label": "Managed",
            "available": True,
            "command": managed_start_cmd,
            "note": "Launch a live managed session so continue/next/inspect stay on one control plane.",
        },
    ]
    if execution_target == "workspace" and devcontainer.get("debugExecutionAvailable"):
        controls.append(
            {
                "id": "devcontainer-start",
                "label": "Container",
                "available": True,
                "command": (
                    f"yen ide debug start {selectors['target']} --managed --devcontainer "
                    f"--project {selectors['devcontainer_project']}"
                ),
                "note": "Reuse the tracked devcontainer when its trust/health gate is already satisfied.",
            }
        )

    live_controls = [
        ("continue", "Continue"),
        ("next", "Next"),
        ("step", "Step"),
        ("out", "Out"),
        ("stack", "Stack"),
        ("inspect", "Inspect"),
        ("breakpoint add", "Breakpoint"),
        ("watch add", "Watch"),
        ("transcript", "Transcript"),
        ("stop", "Stop"),
    ]
    live_available = bool(managed.get("active"))
    project_flag = selectors["project"]
    for action, label in live_controls:
        command = f"yen ide debug {action} --project {project_flag}"
        if action == "inspect":
            command = f"yen ide debug inspect variable_name --project {project_flag}"
        elif action == "breakpoint add":
            command = f"yen ide debug breakpoint add {selectors['target']} --project {project_flag}"
        elif action == "watch add":
            command = f"yen ide debug watch add variable_name --project {project_flag}"
        elif action == "transcript":
            command = f"yen ide debug transcript --project {project_flag} --tail 40"
        controls.append(
            {
                "id": action.replace(" ", "-"),
                "label": label,
                "available": live_available,
                "command": command,
                "note": "" if live_available else "Requires an active managed debug session.",
            }
        )
    return controls


status = read_json_env("DEBUG_TUI_STATUS_PAYLOAD")
tail_lines = int(os.environ.get("DEBUG_TUI_TAIL_LINES") or "40")
workspace = status.get("workspace") or {}
managed = status.get("managedSession") or {}
last = status.get("lastSession") or {}
session = managed or last or {}
location = text(managed.get("lastStopLocation"))
payload = {
    "schemaVersion": 1,
    "mode": "debug-tui",
    "root": text(status.get("root")),
    "executionTarget": text(status.get("executionTarget"), "workspace"),
    "workspace": workspace,
    "status": status,
    "headline": (
        f"Managed session paused at {location}"
        if managed.get("active") and location
        else "No active managed session; showing the latest debugger evidence."
    ),
    "session": {
        "active": bool(managed.get("active")),
        "status": text(session.get("status"), text(status.get("state"), "stopped")),
        "tool": text(session.get("tool"), text(last.get("tool"))),
        "target": text(session.get("displayTarget") or session.get("target"), text(last.get("displayTarget") or last.get("target"))),
        "location": location,
        "startedAt": text(session.get("startedAt"), text(last.get("startedAt"))),
        "endedAt": text(session.get("endedAt"), text(last.get("endedAt"))),
        "detailsReport": text(last.get("detailsReport")),
        "summaryReport": text(last.get("summaryReport")),
        "outputExcerpt": list(managed.get("outputExcerpt") or []),
        "breakpoints": list(managed.get("breakpoints") or []),
        "watches": list(managed.get("watches") or []),
    },
}
payload["sourceExcerpt"] = source_excerpt(payload["root"], workspace, payload["session"]["location"])
payload["transcriptTail"] = transcript_tail(payload["session"]["detailsReport"], tail_lines)
payload["controls"] = build_controls(status)

print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

debug_tui_text_from_payload() {
    local payload="$1"
    DEBUG_TUI_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os


def text(value, fallback=""):
    value = "" if value is None else str(value).strip()
    return value if value else fallback


payload = json.loads(os.environ.get("DEBUG_TUI_PAYLOAD") or "{}")
status = payload.get("status") or {}
workspace = payload.get("workspace") or {}
session = payload.get("session") or {}
source = payload.get("sourceExcerpt") or {}
transcript = payload.get("transcriptTail") or {}

print("")
print("IDE Debug TUI")
print(f"Project root:       {text(payload.get('root'))}")
print(f"Execution:          {text(workspace.get('executionLocation'), 'local')}")
print(f"Transport:          {text(workspace.get('transport'), 'local')}")
print(f"Execution target:   {text(payload.get('executionTarget'), 'workspace')}")
if workspace.get("identity"):
    print(f"Workspace identity: {text(workspace.get('identity'))}")
print(f"Headline:           {text(payload.get('headline'))}")

print("")
print("Session:")
print(f"  Active:           {'yes' if session.get('active') else 'no'}")
print(f"  Status:           {text(session.get('status'), 'stopped')}")
print(f"  Tool:             {text(session.get('tool'), 'n/a')}")
print(f"  Target:           {text(session.get('target'), 'n/a')}")
print(f"  Location:         {text(session.get('location'), 'n/a')}")
print(f"  Started:          {text(session.get('startedAt'), 'never')}")
print(f"  Ended:            {text(session.get('endedAt'), 'never')}")
print(f"  Summary report:   {text(session.get('summaryReport'), 'missing')}")
print(f"  Details report:   {text(session.get('detailsReport'), 'missing')}")

print("")
print("Source Excerpt:")
if source.get("available"):
    for row in source.get("lines") or []:
        marker = ">" if row.get("current") else " "
        raw_text = "" if row.get("text") is None else str(row.get("text"))
        print(f" {marker} {int(row.get('lineNumber') or 0):>4} | {raw_text}")
else:
    print(f"  Unavailable: {text(source.get('reason'), 'missing-location')}")

print("")
print("Breakpoints:")
breakpoints = session.get("breakpoints") or []
if breakpoints:
    for row in breakpoints:
        print(f"  {text(row.get('id'))}: {text(row.get('location') or row.get('spec'))}")
else:
    print("  None")

print("")
print("Watches:")
watches = session.get("watches") or []
if watches:
    for row in watches:
        value = text(row.get("lastValue"), text(row.get("lastError"), "pending"))
        print(f"  {text(row.get('id'))}: {text(row.get('expression'))} => {value}")
else:
    print("  None")

print("")
print("Recent Output:")
excerpt = session.get("outputExcerpt") or []
if excerpt:
    for line in excerpt:
        print(f"  {text(line)}")
else:
    print("  No managed-session output excerpt yet.")

print("")
print("Transcript Tail:")
if transcript.get("available"):
    for line in transcript.get("lines") or []:
        print(f"  {text(line)}")
else:
    print(f"  Unavailable: {text(transcript.get('reason'), 'missing-report')}")

print("")
print("Controls:")
for row in payload.get("controls") or []:
    status_label = "ready" if row.get("available") else "idle"
    print(f"  [{status_label:<5}] {text(row.get('label'))}: {text(row.get('command'))}")
    if row.get("note"):
        print(f"          {text(row.get('note'))}")

print("")
print("Limits:")
for item in status.get("blockedTopologies") or []:
    print(f"  - {text(item)}")
print("")
PY
}

debug_tui_print_once() {
    local root="$1"
    local execution_target="$2"
    local format="$3"
    local tail_lines="$4"
    local payload=""

    payload=$(debug_tui_json_for_root "${root}" "${execution_target}" "${tail_lines}") || return 1
    case "${format}" in
        json)
            printf "%s\n" "${payload}"
            ;;
        text)
            debug_tui_text_from_payload "${payload}"
            ;;
        *)
            yen_error "Unknown debug tui format: ${format} (expected text|json)"
            return 1
            ;;
    esac
}

cmd_debug_tui() {
    local target=""
    local format="text"
    local execution_target="workspace"
    local root=""
    local tail_lines="40"
    local watch_mode="no"
    local interval_seconds="2"

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
            --tail)
                shift
                tail_lines="${1:-40}"
                ;;
            --watch)
                watch_mode="yes"
                ;;
            --interval)
                shift
                interval_seconds="${1:-2}"
                ;;
            --devcontainer)
                execution_target="devcontainer"
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
    if [[ ! "${interval_seconds}" =~ ^[0-9]+$ ]] || [[ "${interval_seconds}" -lt 1 ]]; then
        yen_error "Invalid --interval '${interval_seconds}'. Use a positive integer."
        return 1
    fi
    if [[ "${watch_mode}" == "yes" && "${format}" != "text" ]]; then
        yen_error "debug tui only supports --watch with --format text."
        return 1
    fi

    debug_status_resolve_root "${target}" || return 1
    root="${DEBUG_STATUS_TARGET_ROOT}"

    if [[ "${watch_mode}" != "yes" ]]; then
        debug_tui_print_once "${root}" "${execution_target}" "${format}" "${tail_lines}"
        return $?
    fi

    while true; do
        if [[ -t 1 ]]; then
            printf '\033[2J\033[H'
        else
            printf "\n--- yen ide debug tui refresh @ %s ---\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        fi
        debug_tui_print_once "${root}" "${execution_target}" "text" "${tail_lines}" || return 1
        sleep "${interval_seconds}"
    done
}
