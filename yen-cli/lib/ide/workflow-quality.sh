# shellcheck shell=bash
# Source-time pure workflow/quality helpers and command handlers for yen ide.

workflow_dir_for_root() {
    local root="$1"
    printf "%s/.yen/workflows\n" "${root}"
}

declared_node_package_manager() {
    local root="$1"
    if [[ -f "${root}/bun.lockb" || -f "${root}/bun.lock" ]]; then
        printf "bun\n"
        return 0
    fi
    if [[ -f "${root}/pnpm-lock.yaml" ]]; then
        printf "pnpm\n"
        return 0
    fi
    if [[ -f "${root}/yarn.lock" ]]; then
        printf "yarn\n"
        return 0
    fi
    if [[ -f "${root}/package.json" ]]; then
        printf "npm\n"
        return 0
    fi
    printf "none\n"
}

node_package_manager_available() {
    local manager="$1"
    case "${manager}" in
        bun|pnpm|yarn|npm)
            command -v "${manager}" >/dev/null 2>&1
            return $?
            ;;
    esac
    return 1
}

native_task_category() {
    local name="$1"
    local command="$2"
    local definition="$3"
    local blob=""
    blob=$(printf "%s %s %s" "${name}" "${command}" "${definition}" | tr '[:upper:]' '[:lower:]')

    if [[ "${blob}" == *"lint"* ]] || [[ "${blob}" == *"eslint"* ]] || [[ "${blob}" == *"ruff"* ]] || [[ "${blob}" == *"clippy"* ]] || [[ "${blob}" == *"checkstyle"* ]]; then
        printf "lint\n"
        return 0
    fi
    if [[ "${blob}" == *"test"* ]] || [[ "${blob}" == *"pytest"* ]] || [[ "${blob}" == *"go test"* ]] || [[ "${blob}" == *"cargo test"* ]] || [[ "${blob}" == *"swift test"* ]] || [[ "${blob}" == *"zig build test"* ]] || [[ "${blob}" == *"bun test"* ]] || [[ "${blob}" == *"npm test"* ]] || [[ "${blob}" == *"pnpm test"* ]] || [[ "${blob}" == *"yarn test"* ]]; then
        printf "test\n"
        return 0
    fi
    if [[ "${blob}" == *"format"* ]] || [[ "${blob}" == *"fmt"* ]] || [[ "${blob}" == *"prettier"* ]] || [[ "${blob}" == *"rustfmt"* ]] || [[ "${blob}" == *"gofmt"* ]] || [[ "${blob}" == *"biome format"* ]]; then
        printf "format\n"
        return 0
    fi
    if [[ "${blob}" == *"build"* ]] || [[ "${blob}" == *"compile"* ]] || [[ "${blob}" == *"bundle"* ]] || [[ "${blob}" == *"tsc"* ]]; then
        printf "build\n"
        return 0
    fi
    if [[ "${blob}" == *"dev"* ]] || [[ "${blob}" == *"start"* ]] || [[ "${blob}" == *"serve"* ]] || [[ "${blob}" == *"watch"* ]]; then
        printf "dev\n"
        return 0
    fi
    printf "custom\n"
}

exact_case_file_exists() {
    local candidate_path="$1"
    python3 - "${candidate_path}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
parent = path.parent
if not parent.is_dir():
    sys.exit(1)

names = {child.name for child in parent.iterdir()}
sys.exit(0 if path.name in names else 1)
PY
}

WORKFLOW_TARGET_ROOT=""
WORKFLOW_TARGET_EXECUTION_LOCATION=""
WORKFLOW_TARGET_WORKSPACE_IDENTITY=""
WORKFLOW_TARGET_REQUESTED_PATH=""
WORKFLOW_TARGET_REMOTE_AUTHORITY=""
WORKFLOW_TARGET_REMOTE_PORT=""
WORKFLOW_TARGET_REMOTE_LABEL=""

workflow_target_reset() {
    WORKFLOW_TARGET_ROOT=""
    WORKFLOW_TARGET_EXECUTION_LOCATION=""
    WORKFLOW_TARGET_WORKSPACE_IDENTITY=""
    WORKFLOW_TARGET_REQUESTED_PATH=""
    WORKFLOW_TARGET_REMOTE_AUTHORITY=""
    WORKFLOW_TARGET_REMOTE_PORT=""
    WORKFLOW_TARGET_REMOTE_LABEL=""
}

workflow_target_resolve() {
    local target="$1"

    workflow_target_reset
    if declare -F workspace_summary_resolve_target >/dev/null 2>&1; then
        workspace_summary_resolve_target "${target}" || return 1
        WORKFLOW_TARGET_ROOT="${IDE_WORKSPACE_SUMMARY_ROOT}"
        WORKFLOW_TARGET_EXECUTION_LOCATION="${IDE_WORKSPACE_EXECUTION_LOCATION:-local}"
        WORKFLOW_TARGET_WORKSPACE_IDENTITY="${IDE_WORKSPACE_IDENTITY:-}"
        WORKFLOW_TARGET_REQUESTED_PATH="${IDE_WORKSPACE_REQUESTED_PATH:-${WORKFLOW_TARGET_ROOT}}"
        WORKFLOW_TARGET_REMOTE_AUTHORITY="${IDE_WORKSPACE_AUTHORITY:-}"
        WORKFLOW_TARGET_REMOTE_PORT="${IDE_WORKSPACE_PORT:-}"
        WORKFLOW_TARGET_REMOTE_LABEL="${IDE_WORKSPACE_LABEL:-}"
        return 0
    fi

    WORKFLOW_TARGET_ROOT=$(find_project_root "${target}")
    WORKFLOW_TARGET_EXECUTION_LOCATION="local"
    WORKFLOW_TARGET_REQUESTED_PATH="${WORKFLOW_TARGET_ROOT}"
}

workflow_target_is_remote() {
    [[ "${WORKFLOW_TARGET_EXECUTION_LOCATION}" == "remote" ]]
}

workflow_remote_helper_path() {
    printf "%s/remote-planning-probe.py\n" "${IDE_MODULE_DIR}"
}

workflow_remote_probe_json() {
    ide_remote_python_helper_json \
        "${WORKFLOW_TARGET_REMOTE_AUTHORITY}" \
        "${WORKFLOW_TARGET_REMOTE_PORT}" \
        "$(workflow_remote_helper_path)" \
        "workflow" \
        "${WORKFLOW_TARGET_REQUESTED_PATH}"
}

native_task_risk_target() {
    local definition="$1"
    local command="$2"

    if [[ -n "${definition}" ]]; then
        printf "%s %s\n" "${definition}" "${command}"
        return 0
    fi
    printf "%s\n" "${command}"
}

emit_package_script_candidate_rows() {
    local root="$1"
    local package_path="${root}/package.json"
    local manager=""
    local runnable="no"
    local availability=""

    [[ -f "${package_path}" ]] || return 0

    manager=$(declared_node_package_manager "${root}")
    availability="missing-${manager}"
    if node_package_manager_available "${manager}"; then
        runnable="yes"
        availability="available"
    fi

    python3 - "${package_path}" "${manager}" "${runnable}" "${availability}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1]).resolve()
manager = sys.argv[2]
runnable = sys.argv[3]
availability = sys.argv[4]

try:
    payload = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    payload = {}

scripts = payload.get("scripts")
if not isinstance(scripts, dict):
    scripts = {}

def clean(value):
    return str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ")

def command_for(manager, name):
    if manager == "bun":
        return f"bun run {name}"
    if manager == "pnpm":
        return f"pnpm run {name}"
    if manager == "yarn":
        return f"yarn run {name}"
    return f"npm run {name}"

for name in sorted(scripts.keys()):
    print("\t".join([
        "package.json",
        clean(name),
        str(path),
        clean(scripts.get(name)),
        manager,
        runnable,
        availability,
        command_for(manager, name),
    ]))
PY
}

emit_makefile_candidate_rows() {
    local root="$1"
    local makefile_path="${root}/Makefile"
    local runnable="no"
    local availability="missing-make"

    [[ -f "${makefile_path}" ]] || return 0
    if command -v make >/dev/null 2>&1; then
        runnable="yes"
        availability="available"
    fi

    python3 - "${makefile_path}" "${runnable}" "${availability}" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1]).resolve()
runnable = sys.argv[2]
availability = sys.argv[3]
lines = path.read_text(encoding="utf-8").splitlines()

targets = []
current_name = None
current_recipe = []

def clean(value):
    return str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ")

def flush():
    global current_name, current_recipe
    if not current_name:
        return
    recipe = " ; ".join(current_recipe)
    targets.append((current_name, recipe))
    current_name = None
    current_recipe = []

for raw in lines:
    line = raw.rstrip("\n")
    stripped = line.strip()
    if current_name and (line.startswith("\t") or re.match(r"^[ ]{2,}\S", line)):
        current_recipe.append(stripped)
        continue
    match = re.match(r"^([A-Za-z0-9_.-]+)\s*:(?![=])", line)
    if stripped and not stripped.startswith("#") and match and "%" not in match.group(1) and not match.group(1).startswith("."):
        flush()
        current_name = match.group(1)
        current_recipe = []
        continue
    if stripped and not line.startswith("\t"):
        flush()

flush()

seen = set()
for name, recipe in targets:
    if name in seen:
        continue
    seen.add(name)
    print("\t".join([
        "Makefile",
        clean(name),
        str(path),
        clean(recipe),
        "make",
        runnable,
        availability,
        f"make {name}",
    ]))
PY
}

emit_just_candidate_rows_for_file() {
    local source_id="$1"
    local justfile_path="$2"
    local runnable="no"
    local availability="missing-just"

    exact_case_file_exists "${justfile_path}" || return 0
    if command -v just >/dev/null 2>&1; then
        runnable="yes"
        availability="available"
    fi

    python3 - "${source_id}" "${justfile_path}" "${runnable}" "${availability}" <<'PY'
import pathlib
import re
import shlex
import sys

source_id = sys.argv[1]
path = pathlib.Path(sys.argv[2]).resolve()
runnable = sys.argv[3]
availability = sys.argv[4]
lines = path.read_text(encoding="utf-8").splitlines()

recipes = []
current_name = None
current_header = ""
current_body = []

def clean(value):
    return str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ")

def flush():
    global current_name, current_header, current_body
    if not current_name:
        current_header = ""
        current_body = []
        return
    definition = " ; ".join(line for line in current_body if line)
    if not definition:
        definition = current_header
    recipes.append((current_name, clean(definition)))
    current_name = None
    current_header = ""
    current_body = []

for raw in lines:
    line = raw.rstrip("\n")
    stripped = line.strip()

    if current_name and (line.startswith("\t") or line.startswith("    ")):
        if stripped:
            current_body.append(stripped)
        continue

    if current_name and stripped == "":
        continue

    if current_name:
        flush()

    if not stripped or stripped.startswith("#"):
        continue
    if line.startswith(" ") or line.startswith("\t"):
        continue
    if stripped.startswith("[") and stripped.endswith("]"):
        continue
    if stripped.startswith("set ") or stripped.startswith("alias ") or stripped.startswith("export ") or stripped.startswith("import ") or stripped.startswith("mod "):
        continue
    if ":=" in stripped:
        continue
    if ":" not in stripped:
        continue

    header, remainder = stripped.split(":", 1)
    tokens = header.split()
    if not tokens:
        continue
    name = tokens[0].lstrip("@+")
    if not re.match(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$", name):
        continue

    current_name = name
    current_header = remainder.strip()
    current_body = []

flush()

seen = set()
for name, definition in sorted(recipes, key=lambda item: item[0]):
    if name in seen:
        continue
    seen.add(name)
    print("\t".join([
        source_id,
        clean(name),
        str(path),
        definition,
        "just",
        runnable,
        availability,
        f"just --justfile {shlex.quote(str(path))} {shlex.quote(name)}",
    ]))
PY
}

emit_just_candidate_rows() {
    local root="$1"
    emit_just_candidate_rows_for_file "Justfile" "${root}/Justfile"
    emit_just_candidate_rows_for_file "justfile" "${root}/justfile"
}

emit_taskfile_candidate_rows_for_file() {
    local source_id="$1"
    local taskfile_path="$2"
    local runnable="no"
    local availability="missing-task"

    exact_case_file_exists "${taskfile_path}" || return 0
    if command -v task >/dev/null 2>&1; then
        runnable="yes"
        availability="available"
    fi

    python3 - "${source_id}" "${taskfile_path}" "${runnable}" "${availability}" <<'PY'
import pathlib
import re
import shlex
import sys

source_id = sys.argv[1]
path = pathlib.Path(sys.argv[2]).resolve()
runnable = sys.argv[3]
availability = sys.argv[4]
lines = path.read_text(encoding="utf-8").splitlines()

tasks = []
current_name = None
current_block = []
in_tasks = False
tasks_indent = None
task_indent = None

def indent_of(line):
    stripped = line.lstrip(" ")
    return len(line) - len(stripped)

def clean(value):
    return str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ")

def clean_scalar(value):
    text = value.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in ("'", '"'):
        text = text[1:-1]
    return clean(text)

def flush():
    global current_name, current_block
    if not current_name:
        current_block = []
        return

    cmds = []
    deps = []
    single_cmd = ""
    section = ""
    section_indent = -1
    for raw in current_block:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = indent_of(raw)
        if section and indent <= section_indent and not stripped.startswith("- "):
            section = ""
            section_indent = -1

        if stripped == "cmds:":
            section = "cmds"
            section_indent = indent
            continue
        if stripped == "deps:":
            section = "deps"
            section_indent = indent
            continue
        if section == "cmds" and stripped.startswith("- "):
            cmds.append(clean_scalar(stripped[2:]))
            continue
        if section == "deps" and stripped.startswith("- "):
            deps.append(clean_scalar(stripped[2:]))
            continue

        match = re.match(r"^cmd:\s*(.+)$", stripped)
        if match:
            single_cmd = clean_scalar(match.group(1))

    definition = " ; ".join(cmds)
    if not definition and single_cmd:
        definition = single_cmd
    if not definition and deps:
        definition = "deps: " + ", ".join(deps)
    tasks.append((current_name, clean(definition)))
    current_name = None
    current_block = []

for raw in lines:
    line = raw.rstrip("\n")
    stripped = line.strip()
    indent = indent_of(line)

    if not in_tasks:
        if stripped == "tasks:":
            in_tasks = True
            tasks_indent = indent
            task_indent = None
        continue

    if stripped and indent <= tasks_indent and not stripped.startswith("#"):
        flush()
        in_tasks = False
        tasks_indent = None
        task_indent = None
        if stripped == "tasks:":
            in_tasks = True
            tasks_indent = indent
        continue

    if stripped.endswith(":") and not stripped.startswith("- ") and indent > tasks_indent:
        if task_indent is None:
            task_indent = indent
        if indent == task_indent:
            flush()
            name = clean_scalar(stripped[:-1])
            if re.match(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$", name):
                current_name = name
                current_block = []
                continue
            current_name = None
            current_block = []
            continue

    if current_name:
        current_block.append(line)

flush()

seen = set()
for name, definition in sorted(tasks, key=lambda item: item[0]):
    if name in seen:
        continue
    seen.add(name)
    print("\t".join([
        source_id,
        clean(name),
        str(path),
        definition,
        "task",
        runnable,
        availability,
        f"task --taskfile {shlex.quote(str(path))} {shlex.quote(name)}",
    ]))
PY
}

emit_taskfile_candidate_rows() {
    local root="$1"
    emit_taskfile_candidate_rows_for_file "Taskfile.yml" "${root}/Taskfile.yml"
    emit_taskfile_candidate_rows_for_file "Taskfile.yaml" "${root}/Taskfile.yaml"
}

workflow_native_discovery_json() {
    local root="$1"
    local candidates_file=""
    local tasks_file=""
    local allowlist_file=""
    local status=0

    candidates_file=$(mktemp) || return 1
    tasks_file=$(mktemp) || {
        rm -f "${candidates_file}"
        return 1
    }
    allowlist_file=$(gate_allowlist_file_for_root "${root}")

    if ! emit_package_script_candidate_rows "${root}" > "${candidates_file}"; then
        rm -f "${candidates_file}" "${tasks_file}"
        return 1
    fi
    if ! emit_makefile_candidate_rows "${root}" >> "${candidates_file}"; then
        rm -f "${candidates_file}" "${tasks_file}"
        return 1
    fi
    if ! emit_just_candidate_rows "${root}" >> "${candidates_file}"; then
        rm -f "${candidates_file}" "${tasks_file}"
        return 1
    fi
    if ! emit_taskfile_candidate_rows "${root}" >> "${candidates_file}"; then
        rm -f "${candidates_file}" "${tasks_file}"
        return 1
    fi

    : > "${tasks_file}"
    while IFS=$'\t' read -r source_id name path definition runner runnable availability command; do
        [[ -n "${source_id}" ]] || continue
        local category=""
        local risk_info=""
        local risk_target=""
        local risk_level=""
        local risk_score=""
        local risk_reason=""
        local workflow_path=""
        local workflow_conflict="no"

        category=$(native_task_category "${name}" "${command}" "${definition}")
        risk_target=$(native_task_risk_target "${definition}" "${command}")
        risk_info=$(classify_risk "${risk_target}" "${allowlist_file}")
        risk_level="${risk_info%%|*}"
        local risk_tail="${risk_info#*|}"
        risk_score="${risk_tail%%|*}"
        risk_reason="${risk_tail#*|}"
        workflow_path=$(workflow_file_for_name "${root}" "${name}" 2>/dev/null || true)
        if [[ -n "${workflow_path}" ]]; then
            workflow_conflict="yes"
        fi

        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "${source_id}:${name}" "${source_id}" "${name}" "${path}" "${definition}" "${runner}" "${runnable}" "${availability}" "${command}" "${category}" "${workflow_conflict}" "${workflow_path}" "${risk_level}" "${risk_score}" "${risk_reason}" >> "${tasks_file}"
    done < "${candidates_file}"

    python3 - "${root}" "${tasks_file}" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
task_file = pathlib.Path(sys.argv[2])
source_specs = [
    ("package.json", root / "package.json", "implemented"),
    ("Makefile", root / "Makefile", "implemented"),
    ("Justfile", root / "Justfile", "implemented"),
    ("justfile", root / "justfile", "implemented"),
    ("Taskfile.yml", root / "Taskfile.yml", "implemented"),
    ("Taskfile.yaml", root / "Taskfile.yaml", "implemented"),
]

tasks = []
source_counts = {}
runnable = 0
workflow_conflicts = 0

def present_exact(path):
    parent = path.parent
    if not parent.is_dir():
        return False
    return path.name in {child.name for child in parent.iterdir()}

if task_file.exists():
    for raw in task_file.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        parts = raw.split("\t")
        if len(parts) != 15:
            continue
        (
            task_id,
            source_id,
            name,
            path,
            definition,
            runner_name,
            runnable_flag,
            availability,
            command,
            category,
            workflow_conflict,
            workflow_path,
            risk_level,
            risk_score,
            risk_reason,
        ) = parts
        task = {
            "id": task_id,
            "source": source_id,
            "name": name,
            "origin": f"{source_id}:{name}" if source_id != "package.json" else f"package.json:scripts.{name}",
            "path": path,
            "definition": definition,
            "runner": runner_name,
            "runnable": runnable_flag == "yes",
            "availability": availability,
            "command": command,
            "category": category,
            "workflowConflict": workflow_conflict == "yes",
            "workflowPath": workflow_path,
            "risk": {
                "level": risk_level,
                "score": int(risk_score or "0"),
                "reason": risk_reason,
            },
        }
        tasks.append(task)
        source_counts[source_id] = source_counts.get(source_id, 0) + 1
        if task["runnable"]:
            runnable += 1
        if task["workflowConflict"]:
            workflow_conflicts += 1

sources = []
for source_id, path, support in source_specs:
    sources.append({
        "id": source_id,
        "path": str(path),
        "present": present_exact(path),
        "support": support,
        "taskCount": source_counts.get(source_id, 0),
    })

print(json.dumps({
    "schemaVersion": 1,
    "root": str(root),
    "sources": sources,
    "tasks": tasks,
    "summary": {
        "tasks": len(tasks),
        "runnable": runnable,
        "workflowConflicts": workflow_conflicts,
    },
}, indent=2, sort_keys=True))
PY
    status=$?
    rm -f "${candidates_file}" "${tasks_file}"
    return "${status}"
}

native_task_record_for_id() {
    local root="$1"
    local task_id="$2"
    local discovery=""

    discovery=$(workflow_native_discovery_json "${root}") || return 1
    python3 - "${task_id}" "${discovery}" <<'PY'
import json
import sys

task_id = sys.argv[1]
payload = json.loads(sys.argv[2] or "{}")

def clean(value):
    return str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ")

for task in payload.get("tasks") or []:
    if task.get("id") != task_id:
        continue
    risk = task.get("risk") or {}
    print("\t".join([
        clean(task.get("id")),
        clean(task.get("source")),
        clean(task.get("name")),
        clean(task.get("path")),
        clean(task.get("definition")),
        clean(task.get("runner")),
        "yes" if task.get("runnable") else "no",
        clean(task.get("availability")),
        clean(task.get("command")),
        clean(task.get("category")),
        "yes" if task.get("workflowConflict") else "no",
        clean(task.get("workflowPath")),
        clean(risk.get("level")),
        clean(risk.get("score")),
        clean(risk.get("reason")),
    ]))
    sys.exit(0)

sys.exit(2)
PY
}

native_task_record_shell_vars() {
    local record="$1"
    python3 - "${record}" <<'PY'
import shlex
import sys

keys = [
    "task_id",
    "source_id",
    "native_name",
    "native_path",
    "native_definition",
    "native_runner",
    "native_runnable",
    "native_availability",
    "native_command",
    "native_category",
    "native_conflict",
    "native_workflow_path",
    "native_risk_level",
    "native_risk_score",
    "native_risk_reason",
]
parts = (sys.argv[1].split("\t") + [""] * len(keys))[: len(keys)]
for key, value in zip(keys, parts):
    print(f"{key}={shlex.quote(value)}")
PY
}

workflow_remote_discovery_payload_json() {
    local discovery="$1"
    python3 - \
        "${discovery}" \
        "${WORKFLOW_TARGET_EXECUTION_LOCATION}" \
        "${WORKFLOW_TARGET_WORKSPACE_IDENTITY}" \
        "${WORKFLOW_TARGET_REQUESTED_PATH}" \
        "${WORKFLOW_TARGET_REMOTE_AUTHORITY}" \
        "${WORKFLOW_TARGET_REMOTE_PORT}" \
        "${WORKFLOW_TARGET_REMOTE_LABEL}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
port = sys.argv[6]
payload["executionLocation"] = sys.argv[2]
payload["workspaceIdentity"] = sys.argv[3]
payload["requestedPath"] = sys.argv[4]
payload["remoteAuthority"] = sys.argv[5]
payload["remotePort"] = int(port) if port else None
payload["remoteLabel"] = sys.argv[7]
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

workflow_remote_lookup_record() {
    local discovery="$1"
    local kind="$2"
    local name="$3"
    python3 - "${discovery}" "${kind}" "${name}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
kind = sys.argv[2]
name = sys.argv[3]
records = payload.get("workflows") if kind == "workflow" else payload.get("tasks")
for record in records or []:
    if kind == "workflow":
        if record.get("name") == name:
            print(json.dumps(record, indent=2, sort_keys=True))
            raise SystemExit(0)
    else:
        if record.get("id") == name:
            print(json.dumps(record, indent=2, sort_keys=True))
            raise SystemExit(0)
raise SystemExit(2)
PY
}

workflow_remote_policy_banner() {
    echo "Execution location: remote"
    if [[ -n "${WORKFLOW_TARGET_WORKSPACE_IDENTITY}" ]]; then
        echo "Workspace identity: ${WORKFLOW_TARGET_WORKSPACE_IDENTITY}"
    fi
    if [[ -n "${WORKFLOW_TARGET_REQUESTED_PATH}" ]]; then
        echo "Requested path:     ${WORKFLOW_TARGET_REQUESTED_PATH}"
    fi
    if [[ -n "${WORKFLOW_TARGET_REMOTE_AUTHORITY}" ]]; then
        if [[ -n "${WORKFLOW_TARGET_REMOTE_PORT}" ]]; then
            echo "Remote authority:   ${WORKFLOW_TARGET_REMOTE_AUTHORITY}:${WORKFLOW_TARGET_REMOTE_PORT}"
        else
            echo "Remote authority:   ${WORKFLOW_TARGET_REMOTE_AUTHORITY}"
        fi
    fi
    if [[ -n "${WORKFLOW_TARGET_REMOTE_LABEL}" ]]; then
        echo "Remote label:       ${WORKFLOW_TARGET_REMOTE_LABEL}"
    fi
}

workflow_remote_workflow_metadata_row() {
    local workflow_record="$1"
    python3 - "${workflow_record}" <<'PY'
import json
import sys

workflow = json.loads(sys.argv[1] or "{}")
print("\t".join([
    str(workflow.get("name") or ""),
    str(workflow.get("description") or "").replace("\t", " ").replace("\r", " ").replace("\n", " "),
    str(workflow.get("schema") or ""),
    "true" if workflow.get("trustRequired") else "false",
    str(workflow.get("path") or ""),
    str(len(workflow.get("steps") or [])),
]))
PY
}

workflow_remote_workflow_step_rows_file() {
    local workflow_record="$1"
    local rows_file="$2"
    python3 - "${workflow_record}" > "${rows_file}" <<'PY'
import json
import sys

workflow = json.loads(sys.argv[1] or "{}")
for step in workflow.get("steps") or []:
    risk = step.get("risk") or {}
    print("\t".join([
        str(step.get("index") or ""),
        str(step.get("mode") or ""),
        str(risk.get("level") or ""),
        str(risk.get("score") or 0),
        str(risk.get("reason") or "").replace("\t", " ").replace("\r", " ").replace("\n", " "),
        str(step.get("command") or "").replace("\t", " ").replace("\r", " ").replace("\n", " "),
    ]))
PY
}

workflow_remote_native_task_shell_vars() {
    local task_record="$1"
    python3 - "${task_record}" <<'PY'
import json
import shlex
import sys

task = json.loads(sys.argv[1] or "{}")
risk = task.get("risk") or {}
fields = {
    "task_id": task.get("id") or "",
    "source_id": task.get("source") or "",
    "native_name": task.get("name") or "",
    "native_path": task.get("path") or "",
    "native_definition": task.get("definition") or "",
    "native_runner": task.get("runner") or "",
    "native_runnable": "yes" if task.get("runnable") else "no",
    "native_availability": task.get("availability") or "",
    "native_command": task.get("command") or "",
    "native_category": task.get("category") or "",
    "native_conflict": "yes" if task.get("workflowConflict") else "no",
    "native_workflow_path": task.get("workflowPath") or "",
    "native_risk_level": risk.get("level") or "",
    "native_risk_score": risk.get("score") or 0,
    "native_risk_reason": risk.get("reason") or "",
}
for key, value in fields.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
}

workflow_remote_execute_command_capture() {
    local root="$1"
    local command_text="$2"
    local remote_command=""

    remote_command="cd $(shell_quote_single "${root}") && bash -lc $(shell_quote_single "${command_text}")"
    ide_remote_shell_command \
        "${WORKFLOW_TARGET_REMOTE_AUTHORITY}" \
        "${WORKFLOW_TARGET_REMOTE_PORT}" \
        "${remote_command}" \
        "sh"
}

WORKFLOW_NATIVE_LAST_OUTCOME=""
WORKFLOW_NATIVE_LAST_SUMMARY=""
WORKFLOW_NATIVE_LAST_DETAILS=""
WORKFLOW_NATIVE_LAST_SEMANTIC=""
WORKFLOW_NATIVE_LAST_STATUS_CODE="0"

workflow_write_watch_state() {
    local root="$1"
    local session="$2"
    local active="$3"
    local state="$4"
    local iteration="$5"
    local interval="$6"
    local max_runs="$7"
    local scope="$8"
    local branch="$9"
    local label="${10}"
    local stop_reason="${11}"
    local started_at="${12}"

    watch_state_write "${root}" "workflow-native-build" \
        "kind=workflow-native-build" \
        "root=$(watch_state_clean_value "${root}")" \
        "session=$(watch_state_clean_value "${session}")" \
        "label=$(watch_state_clean_value "${label}")" \
        "branch=$(watch_state_clean_value "${branch}")" \
        "active=$(watch_state_clean_value "${active}")" \
        "state=$(watch_state_clean_value "${state}")" \
        "iteration=$(watch_state_clean_value "${iteration}")" \
        "interval_seconds=$(watch_state_clean_value "${interval}")" \
        "max_runs=$(watch_state_clean_value "${max_runs}")" \
        "scope=$(watch_state_clean_value "${scope}")" \
        "started_at=$(watch_state_clean_value "${started_at}")" \
        "updated_at=$(iso_now)" \
        "stop_reason=$(watch_state_clean_value "${stop_reason}")" \
        "last_outcome=$(watch_state_clean_value "${WORKFLOW_NATIVE_LAST_OUTCOME}")" \
        "last_exit_code=$(watch_state_clean_value "${WORKFLOW_NATIVE_LAST_STATUS_CODE}")" \
        "summary=$(watch_state_clean_value "${WORKFLOW_NATIVE_LAST_SUMMARY}")" \
        "details=$(watch_state_clean_value "${WORKFLOW_NATIVE_LAST_DETAILS}")" \
        "semantic=$(watch_state_clean_value "${WORKFLOW_NATIVE_LAST_SEMANTIC}")"
}

workflow_run_native_task_iteration() {
    local root="$1"
    local native_task_id="$2"
    local allow_untrusted="$3"
    local assume_yes="$4"
    local risk_override="$5"
    local allowlist_file_override="$6"
    local watch_session="${7:-}"
    local watch_iteration="${8:-0}"
    local watch_scope="${9:-}"
    local native_record=""
    local native_lookup_status=0
    local task_id=""
    local source_id=""
    local native_name=""
    local native_path=""
    local native_definition=""
    local native_runner=""
    local native_runnable=""
    local native_availability=""
    local native_command=""
    local native_category=""
    local native_conflict=""
    local native_workflow_path=""
    local native_risk_level=""
    local native_risk_score=""
    local native_risk_reason=""
    local native_trust_required="true"
    local native_schema="native-task-v1"
    local native_description=""
    local policy_mode=""
    local risk_info=""
    local rest=""
    local needs_prompt="0"
    local approved="yes"
    local trusted_state="no"
    local allowlist_file=""
    local rows_file=""
    local timestamp=""
    local stamp_ms=""
    local hash=""
    local task_slug=""
    local report_base=""
    local report_summary=""
    local report_details=""
    local report_semantic=""
    local step_start_ms=""
    local step_end_ms=""
    local step_duration_ms=""
    local step_status=""
    local step_output=""
    local watch_detail=""

    WORKFLOW_NATIVE_LAST_OUTCOME=""
    WORKFLOW_NATIVE_LAST_SUMMARY=""
    WORKFLOW_NATIVE_LAST_DETAILS=""
    WORKFLOW_NATIVE_LAST_SEMANTIC=""
    WORKFLOW_NATIVE_LAST_STATUS_CODE="0"

    set +e
    native_record=$(native_task_record_for_id "${root}" "${native_task_id}")
    native_lookup_status=$?
    set -e
    if [[ "${native_lookup_status}" -ne 0 ]]; then
        if [[ "${native_lookup_status}" == "2" ]]; then
            WORKFLOW_NATIVE_LAST_OUTCOME="missing"
            WORKFLOW_NATIVE_LAST_STATUS_CODE="1"
            yen_error "Native task '${native_task_id}' not found."
            yen_info "Run: yen ide workflow discover --project ${root}"
            return 1
        fi
        WORKFLOW_NATIVE_LAST_OUTCOME="missing"
        WORKFLOW_NATIVE_LAST_STATUS_CODE="${native_lookup_status}"
        return "${native_lookup_status}"
    fi

    eval "$(native_task_record_shell_vars "${native_record}")"

    allowlist_file=$(gate_allowlist_file_for_root "${root}")
    if [[ -n "${allowlist_file_override}" ]]; then
        allowlist_file="${allowlist_file_override}"
    fi
    risk_info=$(classify_risk "$(native_task_risk_target "${native_definition}" "${native_command}")" "${allowlist_file}")
    native_risk_level="${risk_info%%|*}"
    rest="${risk_info#*|}"
    native_risk_score="${rest%%|*}"
    native_risk_reason="${rest#*|}"

    if [[ -n "${risk_override}" ]]; then
        risk_override=$(printf "%s" "${risk_override}" | tr '[:upper:]' '[:lower:]')
        case "${risk_override}" in
            low|medium|high|critical)
                native_risk_level="${risk_override}"
                native_risk_reason="${native_risk_reason},override=${risk_override}"
                ;;
            *)
                WORKFLOW_NATIVE_LAST_OUTCOME="blocked"
                WORKFLOW_NATIVE_LAST_STATUS_CODE="1"
                yen_error "Invalid --risk-override '${risk_override}'. Use low|medium|high|critical."
                return 1
                ;;
        esac
    fi

    native_description="Repo-native task from ${source_id} (${native_category})"
    rows_file=$(mktemp)
    printf "1\trequired\t%s\t%s\t%s\t%s\n" "${native_risk_level}" "${native_risk_score}" "${native_risk_reason}" "${native_command}" > "${rows_file}"

    if is_workflow_trusted_project "${root}"; then
        trusted_state="yes"
    fi

    if [[ -n "${watch_session}" ]]; then
        watch_detail=";watchSession=${watch_session};watchIteration=${watch_iteration};watchScope=${watch_scope}"
        echo "Watch iteration:  ${watch_iteration}"
    fi

    echo ""
    yen_header "Native Task Plan"
    echo "Project:          ${root}"
    echo "Native task:      ${task_id}"
    echo "Source:           ${source_id}"
    echo "Path:             ${native_path}"
    echo "Runner:           ${native_runner}"
    echo "Availability:     ${native_availability}"
    echo "Category:         ${native_category}"
    echo "Schema:           ${native_schema}"
    echo "Trust required:   ${native_trust_required}"
    echo "Project trusted:  ${trusted_state}"
    echo "Workflow conflict:${native_conflict}"
    if [[ -n "${native_workflow_path}" ]]; then
        echo "Workflow path:    ${native_workflow_path}"
    fi
    echo "Description:      ${native_description}"
    echo ""
    printf "%-5s %-9s %-9s %-6s %s\n" "STEP" "MODE" "RISK" "SCORE" "COMMAND"
    while IFS=$'\t' read -r idx mode risk_level risk_score _risk_reason command; do
        [[ -n "${idx}" ]] || continue
        printf "%-5s %-9s %-9s %-6s %s\n" "${idx}" "${mode}" "${risk_level}" "${risk_score}" "${command}"
    done < "${rows_file}"
    echo ""

    if [[ "${native_runnable}" != "yes" ]]; then
        WORKFLOW_NATIVE_LAST_OUTCOME="blocked"
        WORKFLOW_NATIVE_LAST_STATUS_CODE="1"
        timeline_log "workflow" "${root}" "blocked" "name=${task_id};kind=native;reason=${native_availability}${watch_detail}"
        yen_error "Native task '${task_id}' is not runnable: ${native_availability}."
        yen_info "Install '${native_runner}' or choose a different discovered task."
        rm -f "${rows_file}"
        return 1
    fi

    if [[ "${trusted_state}" != "yes" && "${allow_untrusted}" != "1" ]]; then
        WORKFLOW_NATIVE_LAST_OUTCOME="blocked"
        WORKFLOW_NATIVE_LAST_STATUS_CODE="1"
        timeline_log "workflow" "${root}" "blocked" "name=${task_id};kind=native;reason=untrusted-project${watch_detail}"
        yen_error "Native task execution blocked: project is untrusted."
        yen_info "Run: yen ide workflow trust ${root}"
        yen_info "Or bypass once with --allow-untrusted."
        rm -f "${rows_file}"
        return 1
    fi

    if [[ "${allow_untrusted}" == "1" && "${trusted_state}" != "yes" ]]; then
        yen_warn "Running native task in untrusted mode due to --allow-untrusted."
    fi

    policy_mode=$(policy_mode_for_root "${root}")
    if needs_approval_for "${policy_mode}" "${native_risk_level}"; then
        needs_prompt="1"
    fi

    if [[ "${needs_prompt}" == "1" && "${assume_yes}" != "1" ]]; then
        if [[ -t 0 ]]; then
            echo ""
            yen_header "IDE Approval Gate"
            echo "Policy:      ${policy_mode}"
            echo "Risk:        ${native_risk_level} (score=${native_risk_score}; ${native_risk_reason})"
            echo "Project:     ${root}"
            echo "Native task: ${task_id}"
            echo "Command:"
            echo "  ${native_command}"
            echo ""
            read -r -p "Approve command? [y/N] " gate_answer
            case "${gate_answer}" in
                y|Y|yes|YES)
                    approved="yes"
                    ;;
                *)
                    approved="no"
                    ;;
            esac
        else
            approved="no"
        fi
    fi

    if [[ "${approved}" != "yes" ]]; then
        WORKFLOW_NATIVE_LAST_OUTCOME="blocked"
        WORKFLOW_NATIVE_LAST_STATUS_CODE="1"
        timeline_log "gate" "${root}" "denied" "policy=${policy_mode};risk=${native_risk_level};score=${native_risk_score};reason=${native_risk_reason};cmd=${native_command}${watch_detail}"
        timeline_log "workflow" "${root}" "blocked" "name=${task_id};kind=native;reason=approval-denied${watch_detail}"
        yen_error "Native task denied by approval gate."
        yen_info "If this is a false positive: use --risk-override low (or configure .yen/gate-allowlist)."
        rm -f "${rows_file}"
        return 1
    fi

    timeline_log "gate" "${root}" "approved" "policy=${policy_mode};risk=${native_risk_level};score=${native_risk_score};reason=${native_risk_reason};cmd=${native_command}${watch_detail}"

    timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
    stamp_ms=$(now_ms)
    hash=$(project_short_hash_for_root "${root}")
    task_slug=$(printf "%s" "${task_id}" | tr -cs 'A-Za-z0-9._-' '-')
    report_base="${IDE_WORKFLOW_DIR}/native-task-${timestamp}-${stamp_ms}-${hash}-${task_slug}"
    report_summary="${report_base}.tsv"
    report_details="${report_base}.log"
    report_semantic="${report_base}.semantic.tsv"
    : > "${report_summary}"
    : > "${report_details}"
    : > "${report_semantic}"

    timeline_log "workflow" "${root}" "start" "name=${task_id};kind=native;source=${source_id};steps=1;trust_required=${native_trust_required};trusted=${trusted_state}${watch_detail}"
    timeline_log "workflow-step" "${root}" "start" "name=${task_id};kind=native;source=${source_id};step=1;mode=required;risk=${native_risk_level};score=${native_risk_score};cmd=${native_command}${watch_detail}"

    step_start_ms=$(now_ms)
    set +e
    step_output=$(cd "${root}" && bash -lc "${native_command}" 2>&1)
    step_status=$?
    set -e
    step_end_ms=$(now_ms)
    step_duration_ms=$((step_end_ms - step_start_ms))

    {
        echo "=== step 1 (required) ==="
        echo "native_task: ${task_id}"
        echo "source: ${source_id}"
        echo "runner: ${native_runner}"
        echo "category: ${native_category}"
        echo "command: ${native_command}"
        echo "risk: ${native_risk_level} (score=${native_risk_score}; reason=${native_risk_reason})"
        echo "status: ${step_status}"
        echo "duration_ms: ${step_duration_ms}"
        echo "--- output ---"
        printf "%s\n" "${step_output}"
        echo ""
    } >> "${report_details}"
    append_semantic_reference_report "${report_semantic}" "${root}" "${root}" "$(printf "%s\t%s\t%s\t%s" "$(iso_now)" "1" "required" "${step_status}")" "${step_output}"
    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$(iso_now)" "1" "required" "${step_status}" "${step_duration_ms}" "${native_risk_level}" "${native_risk_score}" "${native_command}" >> "${report_summary}"
    timeline_log "workflow-step" "${root}" "status=${step_status}" "name=${task_id};kind=native;source=${source_id};step=1;mode=required;risk=${native_risk_level};score=${native_risk_score};cmd=${native_command}${watch_detail}"

    echo "Summary file: ${report_summary}"
    echo "Details file: ${report_details}"
    echo "Semantic file: ${report_semantic}"
    WORKFLOW_NATIVE_LAST_SUMMARY="${report_summary}"
    WORKFLOW_NATIVE_LAST_DETAILS="${report_details}"
    WORKFLOW_NATIVE_LAST_SEMANTIC="${report_semantic}"

    if [[ "${step_status}" -ne 0 ]]; then
        WORKFLOW_NATIVE_LAST_OUTCOME="command-failed"
        WORKFLOW_NATIVE_LAST_STATUS_CODE="${step_status}"
        timeline_log "workflow" "${root}" "failed" "name=${task_id};kind=native;source=${source_id};status=${step_status};summary=${report_summary};semantic=${report_semantic}${watch_detail}"
        yen_error "Native task failed (status=${step_status})."
        rm -f "${rows_file}"
        return "${step_status}"
    fi

    WORKFLOW_NATIVE_LAST_OUTCOME="success"
    WORKFLOW_NATIVE_LAST_STATUS_CODE="0"
    timeline_log "workflow" "${root}" "success" "name=${task_id};kind=native;source=${source_id};summary=${report_summary};semantic=${report_semantic}${watch_detail}"
    if [[ "${native_conflict}" == "yes" && -n "${native_workflow_path}" ]]; then
        yen_info "Authored workflow remains available at: ${native_workflow_path}"
    fi
    yen_success "Native task completed successfully."
    rm -f "${rows_file}"
    return 0
}

cmd_workflow() {
    local subcommand="${1:-list}"
    local workflow_name=""
    local project_target=""
    local root=""
    local workflow_path=""
    local parsed=""
    local wf_name=""
    local wf_description=""
    local wf_schema=""
    local wf_trust_required=""
    local steps_file=""
    local rows_file=""
    local allowlist_file=""
    local dry_run="0"
    local trust_override="0"
    local allow_untrusted="0"
    local native_requested="0"
    local native_task_id=""
    local assume_yes="0"
    local risk_override=""
    local allowlist_file_override=""
    local watch="0"
    local watch_interval="1"
    local watch_max_runs=""
    local watch_session=""
    local watch_scope_label=""
    local watch_scope_key=""
    local watch_snapshot=""
    local watch_fingerprint=""
    local watch_runs_completed="0"
    local watch_progress_enabled="0"
    local watch_progress_branch=""
    local watch_started_at=""
    local run_status="0"
    local row=""

    if [[ $# -gt 0 ]]; then
        shift
    fi

    case "${subcommand}" in
        list|ls)
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --project|--path)
                        shift
                        project_target="${1:-}"
                        ;;
                    *)
                        yen_error "Unknown workflow list option: $1"
                        exit 1
                        ;;
                esac
                shift
            done

            workflow_target_resolve "${project_target}" || exit 1
            root="${WORKFLOW_TARGET_ROOT}"
            if workflow_target_is_remote; then
                local remote_discovery=""
                remote_discovery=$(workflow_remote_probe_json) || exit 1
                python3 - "${remote_discovery}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
workflows = payload.get("workflows") or []
if not workflows:
    print(f"No workflows found at {payload.get('root', '')}/.yen/workflows")
    raise SystemExit(0)

print("")
print("IDE Workflows")
print(f"Project: {payload.get('root', '')}")
print("")
print(f"{'NAME':<18} {'SCHEMA':<8} {'TRUST':<8} {'STEPS':<6} DESCRIPTION")
for workflow in workflows:
    print(
        f"{workflow.get('name', ''):<18} "
        f"{workflow.get('schema', ''):<8} "
        f"{('true' if workflow.get('trustRequired') else 'false'):<8} "
        f"{workflow.get('stepCount', 0):<6} "
        f"{workflow.get('description', '')}"
    )
print("")
PY
                workflow_remote_policy_banner
                echo "Execution mode:    remote-exec"
                echo "Trust model:       local-record"
                echo "Limitations:       --watch stays local-only; risk metadata comes from remote-probe heuristics."
                echo ""
                return 0
            fi
            if [[ ! -d "$(workflow_dir_for_root "${root}")" ]]; then
                yen_info "No workflows found at $(workflow_dir_for_root "${root}")"
                return 0
            fi

            echo ""
            yen_header "IDE Workflows"
            echo "Project: ${root}"
            echo ""
            printf "%-18s %-8s %-8s %-6s %s\n" "NAME" "SCHEMA" "TRUST" "STEPS" "DESCRIPTION"

            while IFS= read -r workflow_path; do
                [[ -n "${workflow_path}" ]] || continue
                parsed=$(parse_workflow_metadata_file "${workflow_path}" "$(basename "${workflow_path}" .toml)")
                IFS=$'\t' read -r wf_name wf_description wf_schema wf_trust_required << EOF
${parsed}
EOF
                steps_file=$(mktemp)
                parse_workflow_steps_file "${workflow_path}" "${steps_file}"
                local step_count
                step_count=$(wc -l < "${steps_file}" | tr -d '[:space:]')
                printf "%-18s %-8s %-8s %-6s %s\n" "${wf_name}" "${wf_schema}" "${wf_trust_required}" "${step_count}" "${wf_description}"
                rm -f "${steps_file}"
            done < <(find "$(workflow_dir_for_root "${root}")" -maxdepth 1 -type f -name '*.toml' 2>/dev/null | sort)
            echo ""
            ;;
        show)
            if [[ $# -lt 1 ]]; then
                yen_error "workflow show requires a workflow name."
                exit 1
            fi
            workflow_name="$1"
            shift

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --project|--path)
                        shift
                        project_target="${1:-}"
                        ;;
                    *)
                        yen_error "Unknown workflow show option: $1"
                        exit 1
                        ;;
                esac
                shift
            done

            workflow_target_resolve "${project_target}" || exit 1
            root="${WORKFLOW_TARGET_ROOT}"
            if workflow_target_is_remote; then
                local remote_discovery=""
                local workflow_record=""
                local lookup_status=0
                remote_discovery=$(workflow_remote_probe_json) || exit 1
                set +e
                workflow_record=$(workflow_remote_lookup_record "${remote_discovery}" "workflow" "${workflow_name}")
                lookup_status=$?
                set -e
                if [[ "${lookup_status}" -ne 0 ]]; then
                    yen_error "Workflow '${workflow_name}' not found in $(workflow_dir_for_root "${root}")."
                    exit 1
                fi
                python3 - "${workflow_record}" <<'PY'
import json
import sys

workflow = json.loads(sys.argv[1] or "{}")
print("")
print("IDE Workflow")
print(f"Project:        {workflow.get('path', '').rsplit('/.yen/workflows/', 1)[0]}")
print(f"Workflow:       {workflow.get('name', '')}")
print(f"Path:           {workflow.get('path', '')}")
print(f"Schema:         {workflow.get('schema', '')}")
print(f"Trust required: {'true' if workflow.get('trustRequired') else 'false'}")
print(f"Description:    {workflow.get('description', '')}")
print("")
print(f"{'STEP':<5} {'MODE':<9} {'RISK':<9} {'SCORE':<6} COMMAND")
for step in workflow.get("steps") or []:
    risk = step.get("risk") or {}
    print(
        f"{step.get('index', ''):<5} "
        f"{step.get('mode', ''):<9} "
        f"{risk.get('level', ''):<9} "
        f"{risk.get('score', 0):<6} "
        f"{step.get('command', '')}"
    )
print("")
PY
                workflow_remote_policy_banner
                echo "Execution mode:    remote-exec"
                echo "Risk source:       heuristic-remote-probe"
                echo "Trust model:       local-record"
                echo "Limitations:       --watch stays local-only; risk metadata comes from remote-probe heuristics."
                echo ""
                return 0
            fi
            workflow_path=$(workflow_file_for_name "${root}" "${workflow_name}" || true)
            if [[ -z "${workflow_path}" ]]; then
                yen_error "Workflow '${workflow_name}' not found in $(workflow_dir_for_root "${root}")."
                exit 1
            fi

            parsed=$(parse_workflow_metadata_file "${workflow_path}" "${workflow_name}")
            IFS=$'\t' read -r wf_name wf_description wf_schema wf_trust_required << EOF
${parsed}
EOF
            steps_file=$(mktemp)
            parse_workflow_steps_file "${workflow_path}" "${steps_file}"
            rows_file=$(mktemp)
            allowlist_file=$(gate_allowlist_file_for_root "${root}")
            workflow_step_rows_with_risk "${steps_file}" "${allowlist_file}" "${rows_file}"

            echo ""
            yen_header "IDE Workflow"
            echo "Project:        ${root}"
            echo "Workflow:       ${wf_name}"
            echo "Path:           ${workflow_path}"
            echo "Schema:         ${wf_schema}"
            echo "Trust required: ${wf_trust_required}"
            echo "Description:    ${wf_description}"
            echo ""
            printf "%-5s %-9s %-9s %-6s %s\n" "STEP" "MODE" "RISK" "SCORE" "COMMAND"
            while IFS=$'\t' read -r idx mode risk_level risk_score _risk_reason command; do
                [[ -n "${idx}" ]] || continue
                printf "%-5s %-9s %-9s %-6s %s\n" "${idx}" "${mode}" "${risk_level}" "${risk_score}" "${command}"
            done < "${rows_file}"
            echo ""

            rm -f "${rows_file}" "${steps_file}"
            ;;
        discover|native)
            local format="text"
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --project|--path)
                        shift
                        project_target="${1:-}"
                        ;;
                    --format=*)
                        format="${1#*=}"
                        ;;
                    --format)
                        shift
                        format="${1:-text}"
                        ;;
                    *)
                        yen_error "Unknown workflow discover option: $1"
                        exit 1
                        ;;
                esac
                shift
            done

            workflow_target_resolve "${project_target}" || exit 1
            root="${WORKFLOW_TARGET_ROOT}"
            local discovery=""
            if workflow_target_is_remote; then
                discovery=$(workflow_remote_probe_json) || exit 1
            else
                discovery=$(workflow_native_discovery_json "${root}")
            fi

            case "${format}" in
                json)
                    if workflow_target_is_remote; then
                        workflow_remote_discovery_payload_json "${discovery}"
                    else
                        printf "%s\n" "${discovery}"
                    fi
                    ;;
                text)
                    python3 - "${discovery}" "${WORKFLOW_TARGET_EXECUTION_LOCATION}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
execution_location = sys.argv[2]
print("")
print("IDE Native Task Discovery")
print(f"Project: {payload.get('root', '')}")
if execution_location == "remote":
    print("Execution mode: remote-exec")
print(f"Tasks:   {(payload.get('summary') or {}).get('tasks', 0)}")
print(f"Runnable: {(payload.get('summary') or {}).get('runnable', 0)}")
print(f"Workflow conflicts: {(payload.get('summary') or {}).get('workflowConflicts', 0)}")
print("")
print(f"{'SOURCE':<14} {'PRESENT':<8} {'SUPPORT':<9} {'TASKS':<5} PATH")
for source in payload.get("sources") or []:
    print(
        f"{source.get('id', ''):<14} "
        f"{('yes' if source.get('present') else 'no'):<8} "
        f"{source.get('support', ''):<9} "
        f"{source.get('taskCount', 0):<5} "
        f"{source.get('path', '')}"
    )
print("")
if not payload.get("tasks"):
    print("No native tasks discovered yet; this command currently establishes the shared source/report contract.")
    print("")
else:
    print(f"{'ID':<22} {'CATEGORY':<8} {'RUN':<8} {'CONFLICT':<9} {'RISK':<8} COMMAND")
    for task in payload.get("tasks") or []:
        print(
            f"{task.get('id', ''):<22} "
            f"{task.get('category', ''):<8} "
            f"{('yes' if task.get('runnable') else 'no'):<8} "
            f"{('yes' if task.get('workflowConflict') else 'no'):<9} "
            f"{((task.get('risk') or {}).get('level', '')):<8} "
            f"{task.get('command', '')}"
        )
    print("")
PY
                    if workflow_target_is_remote; then
                        workflow_remote_policy_banner
                        echo "Execution mode:    remote-exec"
                        echo "Risk source:       heuristic-remote-probe"
                        echo "Trust model:       local-record"
                        echo "Limitations:       --watch stays local-only; risk metadata comes from remote-probe heuristics."
                        echo ""
                    fi
                    ;;
                *)
                    yen_error "Unknown workflow discover format: ${format} (expected text|json)"
                    exit 1
                    ;;
            esac
            ;;
        run|exec|start)
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --project|--path)
                        shift
                        project_target="${1:-}"
                        ;;
                    --dry-run)
                        dry_run="1"
                        ;;
                    --trust)
                        trust_override="1"
                        ;;
                    --allow-untrusted)
                        allow_untrusted="1"
                        ;;
                    --native=*)
                        native_requested="1"
                        native_task_id="${1#*=}"
                        if ! validate_option_value "workflow run --native" "${native_task_id}"; then
                            exit 1
                        fi
                        ;;
                    --native)
                        native_requested="1"
                        shift
                        native_task_id="${1:-}"
                        if ! validate_option_value "workflow run --native" "${native_task_id}"; then
                            exit 1
                        fi
                        ;;
                    --yes|-y)
                        assume_yes="1"
                        ;;
                    --watch)
                        watch="1"
                        ;;
                    --watch-interval)
                        shift
                        watch_interval="${1:-}"
                        if ! validate_option_value "workflow run --watch-interval" "${watch_interval}"; then
                            exit 1
                        fi
                        ;;
                    --watch-interval=*)
                        watch_interval="${1#*=}"
                        if ! validate_option_value "workflow run --watch-interval" "${watch_interval}"; then
                            exit 1
                        fi
                        ;;
                    --max-runs)
                        shift
                        watch_max_runs="${1:-}"
                        if ! validate_option_value "workflow run --max-runs" "${watch_max_runs}"; then
                            exit 1
                        fi
                        ;;
                    --max-runs=*)
                        watch_max_runs="${1#*=}"
                        if ! validate_option_value "workflow run --max-runs" "${watch_max_runs}"; then
                            exit 1
                        fi
                        ;;
                    --risk-override)
                        shift
                        risk_override="${1:-}"
                        if ! validate_option_value "workflow run --risk-override" "${risk_override}"; then
                            exit 1
                        fi
                        ;;
                    --allowlist)
                        shift
                        allowlist_file_override="${1:-}"
                        if ! validate_option_value "workflow run --allowlist" "${allowlist_file_override}"; then
                            exit 1
                        fi
                        ;;
                    --*)
                        yen_error "Unknown workflow run option: $1"
                        exit 1
                        ;;
                    *)
                        if [[ -n "${workflow_name}" ]]; then
                            yen_error "workflow run accepts either one workflow name or --native <task-id>."
                            exit 1
                        fi
                        workflow_name="$1"
                        ;;
                esac
                shift
            done

            workflow_target_resolve "${project_target}" || exit 1
            root="${WORKFLOW_TARGET_ROOT}"

            if [[ -n "${native_task_id}" && -n "${workflow_name}" ]]; then
                yen_error "workflow run accepts either <name> or --native <task-id>, not both."
                exit 1
            fi

            if [[ "${native_requested}" == "1" && -z "${native_task_id}" ]]; then
                yen_error "workflow run --native requires a discovered task id."
                exit 1
            fi
            if ! ide_watch_validate_interval "${watch_interval}"; then
                exit 1
            fi
            if [[ -n "${watch_max_runs}" ]] && ! ide_watch_validate_max_runs "${watch_max_runs}"; then
                exit 1
            fi
            if [[ "${watch}" != "1" && -n "${watch_max_runs}" ]]; then
                yen_error "--max-runs requires --watch."
                exit 1
            fi
            if [[ "${watch}" == "1" && "${native_requested}" != "1" ]]; then
                yen_error "--watch is only supported with workflow run --native <task-id>."
                exit 1
            fi
            if [[ "${watch}" == "1" && "${dry_run}" == "1" ]]; then
                yen_error "--watch is not supported with --dry-run."
                exit 1
            fi

            if workflow_target_is_remote; then
                local remote_discovery=""
                remote_discovery=$(workflow_remote_probe_json) || exit 1
                if [[ "${watch}" == "1" ]]; then
                    yen_error "Remote workflow execution keeps watch-mode blocked for now; --watch is only available for local native-task execution."
                    exit 1
                fi

                if [[ -n "${native_task_id}" ]]; then
                    local remote_task=""
                    local remote_lookup_status=0
                    local task_id=""
                    local source_id=""
                    local native_name=""
                    local native_path=""
                    local native_definition=""
                    local native_runner=""
                    local native_runnable=""
                    local native_availability=""
                    local native_command=""
                    local native_category=""
                    local native_conflict=""
                    local native_workflow_path=""
                    local native_risk_level=""
                    local native_risk_score=""
                    local native_risk_reason=""
                    local native_description=""
                    local trusted_state="no"
                    local allowlist_file=""
                    local policy_mode=""
                    local needs_prompt="0"
                    local approved="yes"
                    local timestamp=""
                    local stamp_ms=""
                    local hash=""
                    local task_slug=""
                    local report_base=""
                    local report_summary=""
                    local report_details=""
                    local report_semantic=""
                    local step_start_ms=""
                    local step_end_ms=""
                    local step_duration_ms=""
                    local step_status=""
                    local step_output=""
                    local failure_label=""

                    set +e
                    remote_task=$(workflow_remote_lookup_record "${remote_discovery}" "task" "${native_task_id}")
                    remote_lookup_status=$?
                    set -e
                    if [[ "${remote_lookup_status}" -ne 0 ]]; then
                        yen_error "Native task '${native_task_id}' not found."
                        yen_info "Run: yen ide workflow discover --project ${WORKFLOW_TARGET_WORKSPACE_IDENTITY:-${root}}"
                        exit 1
                    fi
                    eval "$(workflow_remote_native_task_shell_vars "${remote_task}")"
                    native_description="Repo-native task from ${source_id} (${native_category})"
                    if is_workflow_trusted_project "${root}"; then
                        trusted_state="yes"
                    fi
                    if [[ "${trust_override}" == "1" ]]; then
                        trust_workflow_project "${root}"
                        trusted_state="yes"
                        timeline_log "workflow-trust" "${root}" "trusted" "source=run-native-remote;task=${task_id}"
                    fi

                    echo ""
                    yen_header "Native Task Plan"
                    workflow_remote_policy_banner
                    echo "Project:          ${root}"
                    echo "Native task:      ${task_id}"
                    echo "Source:           ${source_id}"
                    echo "Path:             ${native_path}"
                    echo "Runner:           ${native_runner}"
                    echo "Availability:     ${native_availability}"
                    echo "Category:         ${native_category}"
                    echo "Schema:           native-task-v1"
                    echo "Trust required:   local-record"
                    echo "Project trusted:  ${trusted_state}"
                    echo "Workflow conflict:${native_conflict}"
                    if [[ -n "${native_workflow_path}" ]]; then
                        echo "Workflow path:    ${native_workflow_path}"
                    fi
                    echo "Description:      ${native_description}"
                    echo "Execution mode:   $([[ "${dry_run}" == "1" ]] && printf "dry-run" || printf "remote-exec")"
                    echo "Risk source:      heuristic-remote-probe"
                    echo ""
                    printf "%-5s %-9s %-9s %-6s %s\n" "STEP" "MODE" "RISK" "SCORE" "COMMAND"
                    printf "%-5s %-9s %-9s %-6s %s\n" "1" "required" "${native_risk_level}" "${native_risk_score}" "${native_command}"
                    echo ""

                    if [[ "${dry_run}" == "1" ]]; then
                        timeline_log "workflow" "${root}" "dry-run" "name=${native_task_id};kind=native;location=remote;mode=dry-run;trusted=${trusted_state}"
                        if [[ "${trusted_state}" != "yes" ]]; then
                            yen_warn "Execution would require local workflow trust approval before the remote task runs."
                            yen_info "Run: yen ide workflow trust ${WORKFLOW_TARGET_WORKSPACE_IDENTITY:-${root}}"
                            yen_info "Or run once with: yen ide workflow run --native ${task_id} --allow-untrusted --project ${WORKFLOW_TARGET_WORKSPACE_IDENTITY:-${root}}"
                        fi
                        if [[ "${native_runnable}" != "yes" ]]; then
                            yen_warn "Execution would currently fail because runtime '${native_runner}' is unavailable (${native_availability})."
                        fi
                        yen_info "Dry run: remote native task plan rendered with zero side effects."
                        exit 0
                    fi

                    if [[ "${native_runnable}" != "yes" ]]; then
                        timeline_log "workflow" "${root}" "blocked" "name=${task_id};kind=native;location=remote;reason=${native_availability}"
                        yen_error "Remote native task '${task_id}' is not runnable: ${native_availability}."
                        exit 1
                    fi
                    if [[ "${trusted_state}" != "yes" && "${allow_untrusted}" != "1" ]]; then
                        timeline_log "workflow" "${root}" "blocked" "name=${task_id};kind=native;location=remote;reason=untrusted-project"
                        yen_error "Remote native task execution blocked: workspace is untrusted locally."
                        yen_info "Run: yen ide workflow trust ${WORKFLOW_TARGET_WORKSPACE_IDENTITY:-${root}}"
                        yen_info "Or bypass once with --allow-untrusted."
                        exit 1
                    fi
                    if [[ "${allow_untrusted}" == "1" && "${trusted_state}" != "yes" ]]; then
                        yen_warn "Running remote native task in untrusted mode due to --allow-untrusted."
                    fi

                    allowlist_file=$(gate_allowlist_file_for_root "${root}")
                    if [[ -n "${allowlist_file_override}" ]]; then
                        allowlist_file="${allowlist_file_override}"
                    fi
                    local risk_info=""
                    local rest=""
                    risk_info=$(classify_risk "$(native_task_risk_target "${native_definition}" "${native_command}")" "${allowlist_file}")
                    native_risk_level="${risk_info%%|*}"
                    rest="${risk_info#*|}"
                    native_risk_score="${rest%%|*}"
                    native_risk_reason="${rest#*|}"
                    if [[ -n "${risk_override}" ]]; then
                        risk_override=$(printf "%s" "${risk_override}" | tr '[:upper:]' '[:lower:]')
                        case "${risk_override}" in
                            low|medium|high|critical)
                                native_risk_level="${risk_override}"
                                native_risk_reason="${native_risk_reason},override=${risk_override}"
                                ;;
                            *)
                                yen_error "Invalid --risk-override '${risk_override}'. Use low|medium|high|critical."
                                exit 1
                                ;;
                        esac
                    fi

                    policy_mode=$(policy_mode_for_root "${root}")
                    if needs_approval_for "${policy_mode}" "${native_risk_level}"; then
                        needs_prompt="1"
                    fi
                    if [[ "${needs_prompt}" == "1" && "${assume_yes}" != "1" ]]; then
                        if [[ -t 0 ]]; then
                            echo ""
                            yen_header "IDE Approval Gate"
                            echo "Policy:      ${policy_mode}"
                            echo "Risk:        ${native_risk_level} (score=${native_risk_score}; ${native_risk_reason})"
                            echo "Project:     ${WORKFLOW_TARGET_WORKSPACE_IDENTITY:-${root}}"
                            echo "Native task: ${task_id}"
                            echo "Location:    remote"
                            echo "Command:"
                            echo "  ${native_command}"
                            echo ""
                            read -r -p "Approve command? [y/N] " gate_answer
                            case "${gate_answer}" in
                                y|Y|yes|YES)
                                    approved="yes"
                                    ;;
                                *)
                                    approved="no"
                                    ;;
                            esac
                        else
                            approved="no"
                        fi
                    fi
                    if [[ "${approved}" != "yes" ]]; then
                        timeline_log "gate" "${root}" "denied" "policy=${policy_mode};risk=${native_risk_level};score=${native_risk_score};reason=${native_risk_reason};location=remote;cmd=${native_command}"
                        timeline_log "workflow" "${root}" "blocked" "name=${task_id};kind=native;location=remote;reason=approval-denied"
                        yen_error "Remote native task denied by approval gate."
                        exit 1
                    fi
                    timeline_log "gate" "${root}" "approved" "policy=${policy_mode};risk=${native_risk_level};score=${native_risk_score};reason=${native_risk_reason};location=remote;cmd=${native_command}"

                    timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
                    stamp_ms=$(now_ms)
                    hash=$(project_short_hash_for_root "${root}")
                    task_slug=$(printf "%s" "${task_id}" | tr -cs 'A-Za-z0-9._-' '-')
                    report_base="${IDE_WORKFLOW_DIR}/native-task-${timestamp}-${stamp_ms}-${hash}-${task_slug}"
                    report_summary="${report_base}.tsv"
                    report_details="${report_base}.log"
                    report_semantic="${report_base}.semantic.tsv"
                    : > "${report_summary}"
                    : > "${report_details}"
                    : > "${report_semantic}"

                    timeline_log "workflow" "${root}" "start" "name=${task_id};kind=native;source=${source_id};location=remote;steps=1;trusted=${trusted_state}"
                    timeline_log "workflow-step" "${root}" "start" "name=${task_id};kind=native;source=${source_id};location=remote;step=1;mode=required;risk=${native_risk_level};score=${native_risk_score};cmd=${native_command}"
                    step_start_ms=$(now_ms)
                    set +e
                    step_output=$(workflow_remote_execute_command_capture "${root}" "${native_command}" 2>&1)
                    step_status=$?
                    set -e
                    step_end_ms=$(now_ms)
                    step_duration_ms=$((step_end_ms - step_start_ms))
                    if [[ "${step_status}" -ne 0 ]]; then
                        failure_label=$(ide_remote_command_failure_label "${step_status}")
                    else
                        failure_label=""
                    fi
                    {
                        echo "=== step 1 (required) ==="
                        echo "location: remote"
                        echo "command: ${native_command}"
                        echo "risk: ${native_risk_level} (score=${native_risk_score}; reason=${native_risk_reason})"
                        if [[ -n "${failure_label}" ]]; then
                            echo "failure: ${failure_label}"
                        fi
                        echo "status: ${step_status}"
                        echo "duration_ms: ${step_duration_ms}"
                        echo "--- output ---"
                        printf "%s\n" "${step_output}"
                        echo ""
                    } >> "${report_details}"
                    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                        "$(iso_now)" "1" "required" "${step_status}" "${step_duration_ms}" "${native_risk_level}" "${native_risk_score}" "${native_command}" >> "${report_summary}"
                    timeline_log "workflow-step" "${root}" "status=${step_status}" "name=${task_id};kind=native;source=${source_id};location=remote;step=1;mode=required;risk=${native_risk_level};score=${native_risk_score};failure=${failure_label:-none};cmd=${native_command}"
                    echo "Summary file: ${report_summary}"
                    echo "Details file: ${report_details}"
                    echo "Semantic file: ${report_semantic}"
                    if [[ "${step_status}" -ne 0 ]]; then
                        timeline_log "workflow" "${root}" "failed" "name=${task_id};kind=native;source=${source_id};location=remote;status=${step_status};reason=${failure_label:-command-failed};summary=${report_summary};semantic=${report_semantic}"
                        if [[ "${failure_label}" == "transport-failed" ]]; then
                            yen_error "Remote native task failed because the SSH transport could not reach ${WORKFLOW_TARGET_REMOTE_AUTHORITY}."
                        else
                            yen_error "Remote native task failed (status=${step_status})."
                        fi
                        exit "${step_status}"
                    fi
                    timeline_log "workflow" "${root}" "success" "name=${task_id};kind=native;source=${source_id};location=remote;summary=${report_summary};semantic=${report_semantic}"
                    yen_success "Remote native task completed successfully."
                    exit 0
                fi

                if [[ -z "${workflow_name}" ]]; then
                    yen_error "workflow run requires a workflow name."
                    exit 1
                fi

                local remote_workflow=""
                local remote_lookup_status=0
                set +e
                remote_workflow=$(workflow_remote_lookup_record "${remote_discovery}" "workflow" "${workflow_name}")
                remote_lookup_status=$?
                set -e
                if [[ "${remote_lookup_status}" -ne 0 ]]; then
                    yen_error "Workflow '${workflow_name}' not found in $(workflow_dir_for_root "${root}")."
                    exit 1
                fi
                parsed=$(workflow_remote_workflow_metadata_row "${remote_workflow}")
                IFS=$'\t' read -r wf_name wf_description wf_schema wf_trust_required workflow_path step_count << EOF
${parsed}
EOF
                rows_file=$(mktemp)
                workflow_remote_workflow_step_rows_file "${remote_workflow}" "${rows_file}"

                local trusted_state="no"
                if is_workflow_trusted_project "${root}"; then
                    trusted_state="yes"
                fi
                if [[ "${trust_override}" == "1" ]]; then
                    trust_workflow_project "${root}"
                    trusted_state="yes"
                    timeline_log "workflow-trust" "${root}" "trusted" "source=run-remote;workflow=${wf_name}"
                fi

                echo ""
                yen_header "Workflow Plan"
                workflow_remote_policy_banner
                echo "Project:        ${root}"
                echo "Workflow:       ${wf_name}"
                echo "Path:           ${workflow_path}"
                echo "Schema:         ${wf_schema}"
                echo "Trust required: local-record"
                echo "Project trusted:${trusted_state}"
                echo "Description:    ${wf_description}"
                echo "Execution mode: $([[ "${dry_run}" == "1" ]] && printf "dry-run" || printf "remote-exec")"
                echo "Risk source:    heuristic-remote-probe"
                echo ""
                printf "%-5s %-9s %-9s %-6s %s\n" "STEP" "MODE" "RISK" "SCORE" "COMMAND"
                while IFS=$'\t' read -r idx mode risk_level risk_score _risk_reason command; do
                    [[ -n "${idx}" ]] || continue
                    printf "%-5s %-9s %-9s %-6s %s\n" "${idx}" "${mode}" "${risk_level}" "${risk_score}" "${command}"
                done < "${rows_file}"
                echo ""

                if [[ "${dry_run}" == "1" ]]; then
                    timeline_log "workflow" "${root}" "dry-run" "name=${wf_name};location=remote;mode=dry-run;trusted=${trusted_state}"
                    if [[ "${trusted_state}" != "yes" ]]; then
                        yen_warn "Execution would require local workflow trust approval before remote steps run."
                        yen_info "Run: yen ide workflow trust ${WORKFLOW_TARGET_WORKSPACE_IDENTITY:-${root}}"
                        yen_info "Or run once with: yen ide workflow run ${wf_name} --allow-untrusted --project ${WORKFLOW_TARGET_WORKSPACE_IDENTITY:-${root}}"
                    fi
                    yen_info "Dry run: remote workflow plan rendered with zero side effects."
                    rm -f "${rows_file}"
                    exit 0
                fi

                if [[ "${trusted_state}" != "yes" && "${allow_untrusted}" != "1" ]]; then
                    timeline_log "workflow" "${root}" "blocked" "name=${wf_name};location=remote;reason=untrusted-project"
                    yen_error "Remote workflow execution blocked: workspace is untrusted locally."
                    yen_info "Run: yen ide workflow trust ${WORKFLOW_TARGET_WORKSPACE_IDENTITY:-${root}}"
                    yen_info "Or bypass once with --allow-untrusted."
                    rm -f "${rows_file}"
                    exit 1
                fi
                if [[ "${allow_untrusted}" == "1" && "${trusted_state}" != "yes" ]]; then
                    yen_warn "Running remote workflow in untrusted mode due to --allow-untrusted."
                fi

                local timestamp=""
                local hash=""
                local workflow_slug=""
                local report_base=""
                local report_summary=""
                local report_details=""
                local report_semantic=""
                timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
                hash=$(project_short_hash_for_root "${root}")
                workflow_slug=$(printf "%s" "${wf_name}" | tr -cs 'A-Za-z0-9._-' '-')
                report_base="${IDE_WORKFLOW_DIR}/workflow-${timestamp}-${hash}-${workflow_slug}"
                report_summary="${report_base}.tsv"
                report_details="${report_base}.log"
                report_semantic="${report_base}.semantic.tsv"
                : > "${report_summary}"
                : > "${report_details}"
                : > "${report_semantic}"

                timeline_log "workflow" "${root}" "start" "name=${wf_name};steps=${step_count};location=remote;trusted=${trusted_state}"
                local failed_required_status=0
                local failed_required_reason=""
                local optional_failures=0
                while IFS=$'\t' read -r idx mode risk_level risk_score risk_reason command; do
                    [[ -n "${idx}" ]] || continue
                    local step_start_ms=""
                    local step_end_ms=""
                    local step_duration_ms=""
                    local step_status=""
                    local step_output=""
                    local failure_label=""

                    timeline_log "workflow-step" "${root}" "start" "name=${wf_name};location=remote;step=${idx};mode=${mode};risk=${risk_level};score=${risk_score};cmd=${command}"
                    step_start_ms=$(now_ms)
                    set +e
                    step_output=$(workflow_remote_execute_command_capture "${root}" "${command}" 2>&1)
                    step_status=$?
                    set -e
                    step_end_ms=$(now_ms)
                    step_duration_ms=$((step_end_ms - step_start_ms))
                    if [[ "${step_status}" -ne 0 ]]; then
                        failure_label=$(ide_remote_command_failure_label "${step_status}")
                    else
                        failure_label=""
                    fi
                    {
                        echo "=== step ${idx} (${mode}) ==="
                        echo "location: remote"
                        echo "command: ${command}"
                        echo "risk: ${risk_level} (score=${risk_score}; reason=${risk_reason})"
                        if [[ -n "${failure_label}" ]]; then
                            echo "failure: ${failure_label}"
                        fi
                        echo "status: ${step_status}"
                        echo "duration_ms: ${step_duration_ms}"
                        echo "--- output ---"
                        printf "%s\n" "${step_output}"
                        echo ""
                    } >> "${report_details}"
                    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                        "$(iso_now)" "${idx}" "${mode}" "${step_status}" "${step_duration_ms}" "${risk_level}" "${risk_score}" "${command}" >> "${report_summary}"
                    timeline_log "workflow-step" "${root}" "status=${step_status}" "name=${wf_name};location=remote;step=${idx};mode=${mode};risk=${risk_level};score=${risk_score};failure=${failure_label:-none};cmd=${command}"

                    if [[ "${step_status}" -ne 0 ]]; then
                        if [[ "${failure_label}" == "transport-failed" || "${failure_label}" == "missing-remote-shell" ]]; then
                            failed_required_status="${step_status}"
                            failed_required_reason="${failure_label}"
                            yen_error "Remote workflow transport failed at step ${idx} (status=${step_status})."
                            break
                        fi
                        if [[ "${mode}" == "optional" ]]; then
                            optional_failures=$((optional_failures + 1))
                            yen_warn "Optional remote step ${idx} failed (status=${step_status}); continuing."
                        else
                            failed_required_status="${step_status}"
                            failed_required_reason="${failure_label:-command-failed}"
                            yen_error "Remote workflow failed at step ${idx} (status=${step_status})."
                            break
                        fi
                    fi
                done < "${rows_file}"

                echo "Summary file: ${report_summary}"
                echo "Details file: ${report_details}"
                echo "Semantic file: ${report_semantic}"

                if [[ "${failed_required_status}" -ne 0 ]]; then
                    timeline_log "workflow" "${root}" "failed" "name=${wf_name};location=remote;status=${failed_required_status};reason=${failed_required_reason:-command-failed};summary=${report_summary};semantic=${report_semantic}"
                    rm -f "${rows_file}"
                    return "${failed_required_status}"
                fi

                timeline_log "workflow" "${root}" "success" "name=${wf_name};location=remote;optional_failures=${optional_failures};summary=${report_summary};semantic=${report_semantic}"
                if [[ "${optional_failures}" -gt 0 ]]; then
                    yen_warn "Remote workflow completed with ${optional_failures} optional step failure(s)."
                else
                    yen_success "Remote workflow completed successfully."
                fi
                rm -f "${rows_file}"
                return 0
            fi

            if [[ -n "${native_task_id}" ]]; then
                if [[ "${trust_override}" == "1" ]]; then
                    trust_workflow_project "${root}"
                    timeline_log "workflow-trust" "${root}" "trusted" "source=run-native;task=${native_task_id}"
                fi

                if [[ "${dry_run}" == "1" ]]; then
                    local native_record=""
                    local native_lookup_status=0
                    local task_id=""
                    local source_id=""
                    local native_name=""
                    local native_path=""
                    local native_definition=""
                    local native_runner=""
                    local native_runnable=""
                    local native_availability=""
                    local native_command=""
                    local native_category=""
                    local native_conflict=""
                    local native_workflow_path=""
                    local native_risk_level=""
                    local native_risk_score=""
                    local native_risk_reason=""
                    local native_trust_required="true"
                    local native_schema="native-task-v1"
                    local native_description=""
                    local trusted_state="no"
                    local risk_info=""
                    local rest=""

                    set +e
                    native_record=$(native_task_record_for_id "${root}" "${native_task_id}")
                    native_lookup_status=$?
                    set -e
                    if [[ "${native_lookup_status}" -ne 0 ]]; then
                        if [[ "${native_lookup_status}" == "2" ]]; then
                            yen_error "Native task '${native_task_id}' not found."
                            yen_info "Run: yen ide workflow discover --project ${root}"
                            exit 1
                        fi
                        exit "${native_lookup_status}"
                    fi

                    eval "$(native_task_record_shell_vars "${native_record}")"

                    allowlist_file=$(gate_allowlist_file_for_root "${root}")
                    if [[ -n "${allowlist_file_override}" ]]; then
                        allowlist_file="${allowlist_file_override}"
                    fi
                    risk_info=$(classify_risk "$(native_task_risk_target "${native_definition}" "${native_command}")" "${allowlist_file}")
                    native_risk_level="${risk_info%%|*}"
                    rest="${risk_info#*|}"
                    native_risk_score="${rest%%|*}"
                    native_risk_reason="${rest#*|}"

                    if [[ -n "${risk_override}" ]]; then
                        risk_override=$(printf "%s" "${risk_override}" | tr '[:upper:]' '[:lower:]')
                        case "${risk_override}" in
                            low|medium|high|critical)
                                native_risk_level="${risk_override}"
                                native_risk_reason="${native_risk_reason},override=${risk_override}"
                                ;;
                            *)
                                yen_error "Invalid --risk-override '${risk_override}'. Use low|medium|high|critical."
                                exit 1
                                ;;
                        esac
                    fi

                    native_description="Repo-native task from ${source_id} (${native_category})"
                    rows_file=$(mktemp)
                    printf "1\trequired\t%s\t%s\t%s\t%s\n" "${native_risk_level}" "${native_risk_score}" "${native_risk_reason}" "${native_command}" > "${rows_file}"

                    if is_workflow_trusted_project "${root}"; then
                        trusted_state="yes"
                    fi

                    echo ""
                    yen_header "Native Task Plan"
                    echo "Project:          ${root}"
                    echo "Native task:      ${task_id}"
                    echo "Source:           ${source_id}"
                    echo "Path:             ${native_path}"
                    echo "Runner:           ${native_runner}"
                    echo "Availability:     ${native_availability}"
                    echo "Category:         ${native_category}"
                    echo "Schema:           ${native_schema}"
                    echo "Trust required:   ${native_trust_required}"
                    echo "Project trusted:  ${trusted_state}"
                    echo "Workflow conflict:${native_conflict}"
                    if [[ -n "${native_workflow_path}" ]]; then
                        echo "Workflow path:    ${native_workflow_path}"
                    fi
                    echo "Description:      ${native_description}"
                    echo ""
                    printf "%-5s %-9s %-9s %-6s %s\n" "STEP" "MODE" "RISK" "SCORE" "COMMAND"
                    while IFS=$'\t' read -r idx mode risk_level risk_score _risk_reason command; do
                        [[ -n "${idx}" ]] || continue
                        printf "%-5s %-9s %-9s %-6s %s\n" "${idx}" "${mode}" "${risk_level}" "${risk_score}" "${command}"
                    done < "${rows_file}"
                    echo ""

                    timeline_log "workflow" "${root}" "dry-run" "name=${task_id};kind=native;source=${source_id};steps=1;trust_required=${native_trust_required};trusted=${trusted_state}"
                    if [[ "${trusted_state}" != "yes" ]]; then
                        yen_warn "Execution would require explicit trust approval before the native task runs."
                        yen_info "Run: yen ide workflow trust ${root}"
                        yen_info "Or run once with: yen ide workflow run --native ${task_id} --allow-untrusted --project ${root}"
                    fi
                    if [[ "${native_runnable}" != "yes" ]]; then
                        yen_warn "Execution would currently fail because runtime '${native_runner}' is unavailable (${native_availability})."
                    fi
                    if [[ "${native_conflict}" == "yes" && -n "${native_workflow_path}" ]]; then
                        yen_info "Explicit native execution leaves the authored workflow untouched: ${native_workflow_path}"
                    fi
                    yen_info "Dry run: native task plan rendered with zero side effects."
                    rm -f "${rows_file}"
                    return 0
                fi

                if [[ "${watch}" == "1" ]]; then
                    local initial_native_record=""
                    local initial_native_lookup_status=0
                    local initial_native_category=""

                    set +e
                    initial_native_record=$(native_task_record_for_id "${root}" "${native_task_id}")
                    initial_native_lookup_status=$?
                    set -e
                    if [[ "${initial_native_lookup_status}" -eq 0 ]]; then
                        initial_native_category=$(printf "%s\n" "${initial_native_record}" | awk -F'\t' '{print $10}')
                        if [[ "${initial_native_category}" == "build" ]]; then
                            watch_progress_enabled="1"
                            watch_progress_branch=$(watch_state_branch_for_root "${root}")
                            watch_started_at=$(iso_now)
                        fi
                    fi
                    watch_session="workflow-watch-$(date -u +"%Y%m%dT%H%M%SZ")-$(project_short_hash_for_root "${root}")"
                    watch_scope_label="native task snapshot (${native_task_id})"
                    watch_scope_key="native-task-snapshot"
                    echo ""
                    echo "Watch:            enabled"
                    echo "Watch interval:   ${watch_interval}s"
                    echo "Max runs:         ${watch_max_runs:-unbounded}"
                    echo "Rerun scope:      ${watch_scope_label}"
                    echo ""
                    timeline_log "workflow-watch" "${root}" "start" "session=${watch_session};scope=${watch_scope_key};interval=${watch_interval};maxRuns=${watch_max_runs:-unbounded};task=${native_task_id}"
                    if [[ "${watch_progress_enabled}" == "1" ]]; then
                        workflow_write_watch_state "${root}" "${watch_session}" "yes" "starting" "0" "${watch_interval}" "${watch_max_runs:-unbounded}" "${watch_scope_key}" "${watch_progress_branch}" "${native_task_id}" "" "${watch_started_at}"
                    fi
                fi

                while true; do
                    run_status=0
                    workflow_run_native_task_iteration "${root}" "${native_task_id}" "${allow_untrusted}" "${assume_yes}" "${risk_override}" "${allowlist_file_override}" "${watch_session}" "$((watch_runs_completed + 1))" "${watch_scope_key}" || run_status=$?
                    watch_runs_completed=$((watch_runs_completed + 1))

                    if [[ "${watch}" != "1" ]]; then
                        return "${run_status}"
                    fi

                    if [[ "${watch_progress_enabled}" == "1" ]]; then
                        workflow_write_watch_state "${root}" "${watch_session}" "yes" "waiting" "${watch_runs_completed}" "${watch_interval}" "${watch_max_runs:-unbounded}" "${watch_scope_key}" "${watch_progress_branch}" "${native_task_id}" "" "${watch_started_at}"
                    fi

                    if [[ "${WORKFLOW_NATIVE_LAST_OUTCOME}" == "missing" || "${WORKFLOW_NATIVE_LAST_OUTCOME}" == "blocked" ]]; then
                        if [[ "${watch_progress_enabled}" == "1" ]]; then
                            workflow_write_watch_state "${root}" "${watch_session}" "no" "${WORKFLOW_NATIVE_LAST_OUTCOME}" "${watch_runs_completed}" "${watch_interval}" "${watch_max_runs:-unbounded}" "${watch_scope_key}" "${watch_progress_branch}" "${native_task_id}" "${WORKFLOW_NATIVE_LAST_OUTCOME}" "${watch_started_at}"
                        fi
                        timeline_log "workflow-watch" "${root}" "stop" "session=${watch_session};reason=${WORKFLOW_NATIVE_LAST_OUTCOME};runs=${watch_runs_completed};status=${run_status};task=${native_task_id}"
                        return "${run_status}"
                    fi

                    watch_snapshot=$(ide_watch_snapshot_for_root "${root}")
                    watch_fingerprint="${watch_snapshot%%$'\t'*}"

                    if [[ -n "${watch_max_runs}" && "${watch_runs_completed}" -ge "${watch_max_runs}" ]]; then
                        if [[ "${watch_progress_enabled}" == "1" ]]; then
                            workflow_write_watch_state "${root}" "${watch_session}" "no" "max-runs" "${watch_runs_completed}" "${watch_interval}" "${watch_max_runs}" "${watch_scope_key}" "${watch_progress_branch}" "${native_task_id}" "max-runs" "${watch_started_at}"
                        fi
                        timeline_log "workflow-watch" "${root}" "stop" "session=${watch_session};reason=max-runs;runs=${watch_runs_completed};status=${run_status};task=${native_task_id}"
                        return "${run_status}"
                    fi

                    yen_info "Watch: waiting for project changes to rerun ${watch_scope_label}. Press Ctrl+C to stop."
                    local next_snapshot=""
                    local next_fingerprint=""
                    local changed_path=""
                    local _watch_count=""
                    local _watch_mtime=""
                    next_snapshot=$(ide_watch_wait_for_change "${root}" "${watch_fingerprint}" "${watch_interval}")
                    IFS=$'\t' read -r next_fingerprint _watch_count changed_path _watch_mtime << EOF
${next_snapshot}
EOF
                    if [[ "${next_fingerprint}" == "missing" ]]; then
                        if [[ "${watch_progress_enabled}" == "1" ]]; then
                            workflow_write_watch_state "${root}" "${watch_session}" "no" "missing-root" "${watch_runs_completed}" "${watch_interval}" "${watch_max_runs:-unbounded}" "${watch_scope_key}" "${watch_progress_branch}" "${native_task_id}" "missing-root" "${watch_started_at}"
                        fi
                        timeline_log "workflow-watch" "${root}" "stop" "session=${watch_session};reason=missing-root;runs=${watch_runs_completed};task=${native_task_id}"
                        yen_error "Watch stopped because the project root is no longer available: ${root}"
                        return 1
                    fi
                    watch_fingerprint="${next_fingerprint}"
                    timeline_log "workflow-watch" "${root}" "rerun" "session=${watch_session};iteration=$((watch_runs_completed + 1));scope=${watch_scope_key};path=${changed_path};task=${native_task_id}"
                    yen_info "Watch: change detected (${changed_path:-project update}); rerunning ${watch_scope_label}."
                    echo ""
                done
            fi

            if [[ -z "${workflow_name}" ]]; then
                yen_error "workflow run requires a workflow name."
                exit 1
            fi
            if [[ "${assume_yes}" == "1" || -n "${risk_override}" || -n "${allowlist_file_override}" ]]; then
                yen_error "--yes, --risk-override, and --allowlist are only valid with workflow run --native <task-id>."
                exit 1
            fi

            workflow_path=$(workflow_file_for_name "${root}" "${workflow_name}" || true)
            if [[ -z "${workflow_path}" ]]; then
                yen_error "Workflow '${workflow_name}' not found in $(workflow_dir_for_root "${root}")."
                exit 1
            fi

            parsed=$(parse_workflow_metadata_file "${workflow_path}" "${workflow_name}")
            IFS=$'\t' read -r wf_name wf_description wf_schema wf_trust_required << EOF
${parsed}
EOF
            steps_file=$(mktemp)
            parse_workflow_steps_file "${workflow_path}" "${steps_file}"
            rows_file=$(mktemp)
            allowlist_file=$(gate_allowlist_file_for_root "${root}")
            workflow_step_rows_with_risk "${steps_file}" "${allowlist_file}" "${rows_file}"

            local trusted_state="no"
            if is_workflow_trusted_project "${root}"; then
                trusted_state="yes"
            fi
            if [[ "${trust_override}" == "1" ]]; then
                trust_workflow_project "${root}"
                trusted_state="yes"
                timeline_log "workflow-trust" "${root}" "trusted" "source=run;workflow=${wf_name}"
            fi

            local step_count
            step_count=$(wc -l < "${steps_file}" | tr -d '[:space:]')
            echo ""
            yen_header "Workflow Plan"
            echo "Project:        ${root}"
            echo "Workflow:       ${wf_name}"
            echo "Path:           ${workflow_path}"
            echo "Schema:         ${wf_schema}"
            echo "Trust required: ${wf_trust_required}"
            echo "Project trusted:${trusted_state}"
            echo "Description:    ${wf_description}"
            echo ""
            printf "%-5s %-9s %-9s %-6s %s\n" "STEP" "MODE" "RISK" "SCORE" "COMMAND"
            while IFS=$'\t' read -r idx mode risk_level risk_score _risk_reason command; do
                [[ -n "${idx}" ]] || continue
                printf "%-5s %-9s %-9s %-6s %s\n" "${idx}" "${mode}" "${risk_level}" "${risk_score}" "${command}"
            done < "${rows_file}"
            echo ""

            if [[ "${dry_run}" == "1" ]]; then
                timeline_log "workflow" "${root}" "dry-run" "name=${wf_name};steps=${step_count};trust_required=${wf_trust_required};trusted=${trusted_state}"
                if [[ "${wf_trust_required}" == "true" && "${trusted_state}" != "yes" ]]; then
                    yen_warn "Execution would require explicit trust approval before steps run."
                    yen_info "Run: yen ide workflow trust ${root}"
                    yen_info "Or run once with: yen ide workflow run ${wf_name} --allow-untrusted --project ${root}"
                fi
                yen_info "Dry run: workflow plan rendered with zero side effects."
                rm -f "${rows_file}" "${steps_file}"
                return 0
            fi

            if [[ "${wf_trust_required}" == "true" && "${trusted_state}" != "yes" && "${allow_untrusted}" != "1" ]]; then
                timeline_log "workflow" "${root}" "blocked" "name=${wf_name};reason=untrusted-project"
                yen_error "Workflow execution blocked: project is untrusted."
                yen_info "Run: yen ide workflow trust ${root}"
                yen_info "Or bypass once with --allow-untrusted."
                rm -f "${rows_file}" "${steps_file}"
                exit 1
            fi

            if [[ "${allow_untrusted}" == "1" && "${trusted_state}" != "yes" ]]; then
                yen_warn "Running workflow in untrusted mode due to --allow-untrusted."
            fi

            local timestamp
            local hash
            local workflow_slug
            local report_base
            local report_summary
            local report_details
            local report_semantic
            timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
            hash=$(project_short_hash_for_root "${root}")
            workflow_slug=$(printf "%s" "${wf_name}" | tr -cs 'A-Za-z0-9._-' '-')
            report_base="${IDE_WORKFLOW_DIR}/workflow-${timestamp}-${hash}-${workflow_slug}"
            report_summary="${report_base}.tsv"
            report_details="${report_base}.log"
            report_semantic="${report_base}.semantic.tsv"
            : > "${report_summary}"
            : > "${report_details}"
            : > "${report_semantic}"

            timeline_log "workflow" "${root}" "start" "name=${wf_name};steps=${step_count};trust_required=${wf_trust_required};trusted=${trusted_state}"

            local failed_required_status=0
            local optional_failures=0
            while IFS=$'\t' read -r idx mode risk_level risk_score risk_reason command; do
                [[ -n "${idx}" ]] || continue

                local step_start_ms
                local step_end_ms
                local step_duration_ms
                local step_status
                local step_output=""

                timeline_log "workflow-step" "${root}" "start" "name=${wf_name};step=${idx};mode=${mode};risk=${risk_level};score=${risk_score};cmd=${command}"
                step_start_ms=$(now_ms)
                set +e
                step_output=$(cd "${root}" && bash -lc "${command}" 2>&1)
                step_status=$?
                set -e
                step_end_ms=$(now_ms)
                step_duration_ms=$((step_end_ms - step_start_ms))

                {
                    echo "=== step ${idx} (${mode}) ==="
                    echo "command: ${command}"
                    echo "risk: ${risk_level} (score=${risk_score}; reason=${risk_reason})"
                    echo "status: ${step_status}"
                    echo "duration_ms: ${step_duration_ms}"
                    echo "--- output ---"
                    printf "%s\n" "${step_output}"
                    echo ""
                } >> "${report_details}"
                append_semantic_reference_report "${report_semantic}" "${root}" "${root}" "$(printf "%s\t%s\t%s\t%s" "$(iso_now)" "${idx}" "${mode}" "${step_status}")" "${step_output}"

                printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                    "$(iso_now)" "${idx}" "${mode}" "${step_status}" "${step_duration_ms}" "${risk_level}" "${risk_score}" "${command}" >> "${report_summary}"
                timeline_log "workflow-step" "${root}" "status=${step_status}" "name=${wf_name};step=${idx};mode=${mode};risk=${risk_level};score=${risk_score};cmd=${command}"

                if [[ "${step_status}" -ne 0 ]]; then
                    if [[ "${mode}" == "optional" ]]; then
                        optional_failures=$((optional_failures + 1))
                        yen_warn "Optional step ${idx} failed (status=${step_status}); continuing."
                    else
                        failed_required_status="${step_status}"
                        yen_error "Workflow failed at step ${idx} (status=${step_status})."
                        break
                    fi
                fi
            done < "${rows_file}"

            echo "Summary file: ${report_summary}"
            echo "Details file: ${report_details}"
            echo "Semantic file: ${report_semantic}"

            if [[ "${failed_required_status}" -ne 0 ]]; then
                timeline_log "workflow" "${root}" "failed" "name=${wf_name};status=${failed_required_status};summary=${report_summary};semantic=${report_semantic}"
                rm -f "${rows_file}" "${steps_file}"
                return "${failed_required_status}"
            fi

            timeline_log "workflow" "${root}" "success" "name=${wf_name};optional_failures=${optional_failures};summary=${report_summary};semantic=${report_semantic}"
            if [[ "${optional_failures}" -gt 0 ]]; then
                yen_warn "Workflow completed with ${optional_failures} optional step failure(s)."
            else
                yen_success "Workflow completed successfully."
            fi

            rm -f "${rows_file}" "${steps_file}"
            ;;
        trust)
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --project|--path)
                        shift
                        project_target="${1:-}"
                        ;;
                    *)
                        if [[ -n "${project_target}" ]]; then
                            yen_error "Unknown workflow trust option: $1"
                            exit 1
                        fi
                        project_target="$1"
                        ;;
                esac
                shift
            done
            workflow_target_resolve "${project_target}" || exit 1
            root="${WORKFLOW_TARGET_ROOT}"
            trust_workflow_project "${root}"
            timeline_log "workflow-trust" "${root}" "trusted" "source=manual;location=${WORKFLOW_TARGET_EXECUTION_LOCATION:-local}"
            if workflow_target_is_remote; then
                yen_success "Workflow trust enabled for remote workspace ${WORKFLOW_TARGET_WORKSPACE_IDENTITY:-${root}}"
            else
                yen_success "Workflow trust enabled for ${root}"
            fi
            ;;
        untrust)
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --project|--path)
                        shift
                        project_target="${1:-}"
                        ;;
                    *)
                        if [[ -n "${project_target}" ]]; then
                            yen_error "Unknown workflow untrust option: $1"
                            exit 1
                        fi
                        project_target="$1"
                        ;;
                esac
                shift
            done
            workflow_target_resolve "${project_target}" || exit 1
            root="${WORKFLOW_TARGET_ROOT}"
            untrust_workflow_project "${root}"
            timeline_log "workflow-trust" "${root}" "untrusted" "source=manual;location=${WORKFLOW_TARGET_EXECUTION_LOCATION:-local}"
            if workflow_target_is_remote; then
                yen_info "Workflow trust removed for remote workspace ${WORKFLOW_TARGET_WORKSPACE_IDENTITY:-${root}}"
            else
                yen_info "Workflow trust removed for ${root}"
            fi
            ;;
        trusted|list-trusted)
            if [[ $# -gt 0 ]]; then
                yen_error "Unknown workflow trusted option: $1"
                exit 1
            fi
            ensure_state_dirs
            if [[ ! -s "${IDE_WORKFLOW_TRUST_FILE}" ]]; then
                yen_info "No workflow-trusted projects."
                return 0
            fi
            echo ""
            yen_header "Workflow-Trusted Projects"
            nl -ba "${IDE_WORKFLOW_TRUST_FILE}"
            echo ""
            ;;
        *)
            yen_error "Unknown workflow command: ${subcommand}"
            exit 1
            ;;
    esac
}
