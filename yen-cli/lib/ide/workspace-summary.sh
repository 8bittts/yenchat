# shellcheck shell=bash
# Source-time pure workspace-capability helpers and command handlers for yen ide.

remote_detect_ssh_binary() {
    command -v ssh 2>/dev/null
}

remote_detect_snapshot() {
    local authority="$1"
    local port="$2"
    local requested_path="$3"
    local ssh_bin=""
    local stderr_file=""
    local output=""
    local status=0
    local stderr_text=""
    local -a ssh_cmd=()

    ssh_bin=$(remote_detect_ssh_binary) || {
        yen_error "ssh is required for remote workspace detection."
        return 1
    }
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/yen-remote-detect.XXXXXX" 2>/dev/null) || {
        yen_error "Unable to allocate a temp file for remote workspace detection."
        return 1
    }

    ssh_cmd=("${ssh_bin}")
    if [[ -n "${port}" ]]; then
        ssh_cmd+=("-p" "${port}")
    fi
    ssh_cmd+=("${authority}" "python3" "-" "${requested_path}")

    output=$(
        "${ssh_cmd[@]}" 2>"${stderr_file}" <<'PY'
import json
import os
import pathlib
import sys

requested = pathlib.Path(sys.argv[1]).expanduser()
requested_abs = requested if requested.is_absolute() else pathlib.Path.cwd() / requested
requested_abs = requested_abs.resolve()

ignored_names = {
    ".git",
    ".hg",
    ".svn",
    ".yarn",
    ".next",
    ".turbo",
    ".venv",
    ".tmp",
    ".temp",
    ".scratch",
    "DerivedData",
    "__pycache__",
    "build",
    "dist",
    "ghostty",
    "node_modules",
    "scratch",
    "temp",
    "tmp",
    "vendor",
    "venv",
    "zig-out",
}
ignored_prefixes = ("tmp-", "temp-", "scratch-")
marker_files = {
    "package.json",
    "go.mod",
    "Cargo.toml",
    "pyproject.toml",
    "requirements.txt",
    "setup.py",
    "Package.swift",
    "build.zig",
    ".devcontainer.json",
    "Makefile",
}


def error(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def has_markers(path: pathlib.Path) -> bool:
    return (
        (path / ".git").exists()
        or (path / "package.json").is_file()
        or (path / "go.mod").is_file()
        or (path / "Cargo.toml").is_file()
        or (path / "pyproject.toml").is_file()
        or (path / "requirements.txt").is_file()
        or (path / "setup.py").is_file()
        or (path / "Package.swift").is_file()
        or (path / "build.zig").is_file()
        or (path / ".devcontainer.json").is_file()
        or (path / ".devcontainer" / "devcontainer.json").is_file()
        or (path / "Makefile").is_file()
    )


def ignored(name: str) -> bool:
    return name in ignored_names or any(name.startswith(prefix) for prefix in ignored_prefixes)


def find_descendant_matches(root):
    matches = []
    max_depth = 5
    for current_root, dirnames, filenames in os.walk(str(root)):
        current = pathlib.Path(current_root).resolve()
        try:
            depth = len(current.relative_to(root).parts)
        except Exception:
            continue
        dirnames[:] = [name for name in dirnames if not ignored(name)]
        if depth == 0:
            continue
        if depth > max_depth:
            dirnames[:] = []
            continue
        has_marker = ".git" in dirnames or any(name in marker_files for name in filenames)
        if not has_marker and ".devcontainer" in dirnames:
            has_marker = (current / ".devcontainer" / "devcontainer.json").is_file()
        if has_marker:
            matches.append(str(current))
            dirnames[:] = []
    return list(dict.fromkeys(matches))


def find_project_root(start: pathlib.Path) -> pathlib.Path:
    path = start if start.is_dir() else start.parent
    if not path.exists():
        error(f"Remote target does not exist: {start}", 2)

    if not has_markers(path):
        descendants = find_descendant_matches(path)
        if len(descendants) == 1:
            return pathlib.Path(descendants[0])
        if len(descendants) > 1:
            error(f"Remote target resolves to multiple nested workspaces: {path}", 3)

    current = path
    while True:
        if has_markers(current):
            return current
        if current == current.parent:
            return path
        current = current.parent


def append_unique(tokens, value):
    if value and value not in tokens:
        tokens.append(value)


root = find_project_root(requested_abs).resolve()
types = []
runtime = []
tooling = []

if (root / "package.json").is_file():
    append_unique(types, "node")
if (root / "go.mod").is_file():
    append_unique(types, "go")
if (root / "Cargo.toml").is_file():
    append_unique(types, "rust")
if (root / "pyproject.toml").is_file() or (root / "requirements.txt").is_file() or (root / "setup.py").is_file():
    append_unique(types, "python")
if (root / "Package.swift").is_file():
    append_unique(types, "swift")
if (root / "build.zig").is_file():
    append_unique(types, "zig")
if (root / "Makefile").is_file():
    append_unique(types, "make")
if not types:
    types.append("generic")

if (root / "package.json").is_file():
    if (root / "bun.lockb").is_file() or (root / "bun.lock").is_file():
        append_unique(runtime, "bun")
    append_unique(runtime, "node")
if (root / "go.mod").is_file():
    append_unique(runtime, "go")
if (root / "Cargo.toml").is_file():
    append_unique(runtime, "rust")
if (root / "pyproject.toml").is_file() or (root / "requirements.txt").is_file():
    append_unique(runtime, "python")
if (root / "Package.swift").is_file():
    append_unique(runtime, "swift")
if (root / "build.zig").is_file():
    append_unique(runtime, "zig")
if not runtime:
    runtime.append("unknown")

if (root / ".git").exists():
    append_unique(tooling, "git")
if (root / "biome.json").is_file():
    append_unique(tooling, "biome")
if (root / "tsconfig.json").is_file():
    append_unique(tooling, "typescript")
if (root / "next.config.ts").is_file() or (root / "next.config.js").is_file():
    append_unique(tooling, "nextjs")
if (root / "Dockerfile").is_file() or (root / ".devcontainer").is_dir() or (root / ".devcontainer.json").is_file():
    append_unique(tooling, "container")
if (root / "Makefile").is_file():
    append_unique(tooling, "make")
if (root / "package-lock.json").is_file():
    append_unique(tooling, "npm")
if (root / "pnpm-lock.yaml").is_file():
    append_unique(tooling, "pnpm")
if (root / "yarn.lock").is_file():
    append_unique(tooling, "yarn")
if (root / "bun.lock").is_file() or (root / "bun.lockb").is_file():
    append_unique(tooling, "bun")
if (root / "go.mod").is_file():
    append_unique(tooling, "go-mod")
if (root / "Cargo.toml").is_file():
    append_unique(tooling, "cargo")
if (root / "pyproject.toml").is_file():
    append_unique(tooling, "pyproject")
if not tooling:
    tooling.append("minimal")

env_files = []
for candidate in (root / ".env", root / ".env.local"):
    if candidate.is_file():
        env_files.append(str(candidate))

package_manager_requirement = ""
package_json = root / "package.json"
if package_json.is_file():
    try:
        package_payload = json.loads(package_json.read_text(encoding="utf-8"))
        package_manager_requirement = str(package_payload.get("packageManager") or "")
    except Exception:
        package_manager_requirement = ""

lockfiles = []
for candidate in ("bun.lock", "bun.lockb", "pnpm-lock.yaml", "yarn.lock", "package-lock.json"):
    if (root / candidate).is_file():
        lockfiles.append(candidate)

go_requirements = []
for candidate in sorted(root.rglob("go.mod")):
    try:
        depth = len(candidate.relative_to(root).parts)
    except Exception:
        continue
    if depth > 4:
        continue
    try:
        for raw in candidate.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if line.startswith("go "):
                version = line[3:].strip()
                if version and version not in go_requirements:
                    go_requirements.append(version)
                break
    except Exception:
        continue

swift_tools_version = ""
package_swift = root / "Package.swift"
if package_swift.is_file():
    try:
        for raw in package_swift.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if line.startswith("//") and "swift-tools-version:" in line:
                swift_tools_version = line.split("swift-tools-version:", 1)[1].strip()
                break
    except Exception:
        swift_tools_version = ""

python_requirement = ""
pyproject = root / "pyproject.toml"
if pyproject.is_file():
    try:
        for raw in pyproject.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line.startswith("requires-python"):
                continue
            _, _, remainder = line.partition("=")
            python_requirement = remainder.strip().strip("'\"")
            break
    except Exception:
        python_requirement = ""

workflow_count = 0
workflow_dir = root / ".yen" / "workflows"
if workflow_dir.is_dir():
    workflow_count = len([entry for entry in workflow_dir.iterdir() if entry.is_file() and entry.suffix == ".toml"])

devcontainer_supported = (
    (root / ".devcontainer.json").is_file()
    or (root / ".devcontainer" / "devcontainer.json").is_file()
)

print(json.dumps(
    {
        "root": str(root),
        "types": ",".join(types),
        "runtime": ",".join(runtime),
        "tooling": ",".join(tooling),
        "envFiles": env_files,
        "envCount": len(env_files),
        "devcontainerSupported": devcontainer_supported,
        "workflowCount": workflow_count,
        "packageManagerRequirement": package_manager_requirement,
        "lockfiles": lockfiles,
        "goRequirements": go_requirements,
        "swiftToolsVersion": swift_tools_version,
        "pythonRequirement": python_requirement,
    },
    sort_keys=True,
))
PY
    )
    status=$?

    stderr_text=$(tr '\n' ' ' < "${stderr_file}" | sed 's/[[:space:]]*$//')
    rm -f "${stderr_file}"

    if [[ "${status}" -ne 0 ]]; then
        if [[ -z "${stderr_text}" ]]; then
            stderr_text="remote workspace detection failed"
        fi
        yen_error "Unable to inspect remote workspace ${authority}: ${stderr_text}"
        return 1
    fi

    printf "%s\n" "${output}"
}

IDE_WORKSPACE_SUMMARY_ROOT=""
IDE_WORKSPACE_SUMMARY_TYPES=""
IDE_WORKSPACE_SUMMARY_RUNTIME=""
IDE_WORKSPACE_SUMMARY_TOOLING=""
IDE_WORKSPACE_SUMMARY_ENV_FILES=""
IDE_WORKSPACE_SUMMARY_ENV_COUNT="0"
IDE_WORKSPACE_SUMMARY_DEVCONTAINER_SUPPORTED="no"
IDE_WORKSPACE_SUMMARY_WORKFLOW_COUNT="0"
IDE_WORKSPACE_SUMMARY_PACKAGE_MANAGER_REQUIREMENT=""
IDE_WORKSPACE_SUMMARY_LOCKFILES=""
IDE_WORKSPACE_SUMMARY_GO_REQUIREMENTS=""
IDE_WORKSPACE_SUMMARY_SWIFT_TOOLS_VERSION=""
IDE_WORKSPACE_SUMMARY_PYTHON_REQUIREMENT=""

workspace_summary_reset() {
    IDE_WORKSPACE_SUMMARY_ROOT=""
    IDE_WORKSPACE_SUMMARY_TYPES=""
    IDE_WORKSPACE_SUMMARY_RUNTIME=""
    IDE_WORKSPACE_SUMMARY_TOOLING=""
    IDE_WORKSPACE_SUMMARY_ENV_FILES=""
    IDE_WORKSPACE_SUMMARY_ENV_COUNT="0"
    IDE_WORKSPACE_SUMMARY_DEVCONTAINER_SUPPORTED="no"
    IDE_WORKSPACE_SUMMARY_WORKFLOW_COUNT="0"
    IDE_WORKSPACE_SUMMARY_PACKAGE_MANAGER_REQUIREMENT=""
    IDE_WORKSPACE_SUMMARY_LOCKFILES=""
    IDE_WORKSPACE_SUMMARY_GO_REQUIREMENTS=""
    IDE_WORKSPACE_SUMMARY_SWIFT_TOOLS_VERSION=""
    IDE_WORKSPACE_SUMMARY_PYTHON_REQUIREMENT=""
}

workspace_summary_apply_minimal_snapshot() {
    local root="$1"
    local env_files=""
    local env_count="0"

    IDE_WORKSPACE_SUMMARY_ROOT="${root}"
    IDE_WORKSPACE_SUMMARY_TYPES=$(detect_project_types "${root}")
    IDE_WORKSPACE_SUMMARY_RUNTIME=$(detect_runtime_context "${root}")
    IDE_WORKSPACE_SUMMARY_TOOLING=$(detect_tooling_context "${root}")
    env_files=$(collect_env_files "${root}" || true)
    IDE_WORKSPACE_SUMMARY_ENV_FILES="${env_files}"
    if [[ -n "${env_files}" ]]; then
        env_count=$(printf "%s\n" "${env_files}" | wc -l | tr -d '[:space:]')
    fi
    IDE_WORKSPACE_SUMMARY_ENV_COUNT="${env_count}"
}

workspace_summary_snapshot_value() {
    local snapshot="$1"
    local key="$2"
    python3 - "${snapshot}" "${key}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
value = payload.get(sys.argv[2], "")
if value is None:
    value = ""
if isinstance(value, bool):
    print("yes" if value else "no")
elif isinstance(value, list):
    print(",".join(str(item) for item in value if str(item)))
else:
    print(value)
PY
}

workspace_summary_snapshot_lines() {
    local snapshot="$1"
    local key="$2"
    python3 - "${snapshot}" "${key}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
for item in payload.get(sys.argv[2]) or []:
    print(item)
PY
}

workspace_summary_project_metadata_source() {
    if workspace_identity_is_remote; then
        printf "remote-probe\n"
        return 0
    fi
    printf "local-filesystem\n"
}

workspace_summary_state_source() {
    printf "local-ide-state\n"
}

workspace_summary_timeline_source() {
    printf "local-ide-state\n"
}

workspace_summary_note() {
    if workspace_identity_is_remote; then
        printf "Remote project metadata comes from a read-only SSH probe; trust, timeline, verify, and runtime state come from local IDE state keyed by workspace identity.\n"
        return 0
    fi
    printf "Project metadata and runtime evidence come from the local workspace and local IDE state.\n"
}

workspace_summary_resolve_target() {
    local target="$1"
    local detail_level="${2:-full}"
    local remote_snapshot=""
    local env_files=""
    local env_count="0"
    local workflow_dir=""

    workspace_summary_reset
    if ! workspace_identity_parse_target "${target}"; then
        yen_error "Invalid project target: ${target}"
        return 1
    fi

    if workspace_identity_is_remote; then
        remote_snapshot=$(
            remote_detect_snapshot \
                "${IDE_WORKSPACE_AUTHORITY}" \
                "${IDE_WORKSPACE_PORT}" \
                "${IDE_WORKSPACE_REQUESTED_PATH}"
        ) || return 1
        IDE_WORKSPACE_SUMMARY_ROOT=$(workspace_summary_snapshot_value "${remote_snapshot}" "root")
        IDE_WORKSPACE_SUMMARY_TYPES=$(workspace_summary_snapshot_value "${remote_snapshot}" "types")
        IDE_WORKSPACE_SUMMARY_RUNTIME=$(workspace_summary_snapshot_value "${remote_snapshot}" "runtime")
        IDE_WORKSPACE_SUMMARY_TOOLING=$(workspace_summary_snapshot_value "${remote_snapshot}" "tooling")
        IDE_WORKSPACE_SUMMARY_ENV_FILES=$(workspace_summary_snapshot_lines "${remote_snapshot}" "envFiles")
        IDE_WORKSPACE_SUMMARY_ENV_COUNT=$(workspace_summary_snapshot_value "${remote_snapshot}" "envCount")
        IDE_WORKSPACE_SUMMARY_DEVCONTAINER_SUPPORTED=$(workspace_summary_snapshot_value "${remote_snapshot}" "devcontainerSupported")
        IDE_WORKSPACE_SUMMARY_WORKFLOW_COUNT=$(workspace_summary_snapshot_value "${remote_snapshot}" "workflowCount")
        IDE_WORKSPACE_SUMMARY_PACKAGE_MANAGER_REQUIREMENT=$(workspace_summary_snapshot_value "${remote_snapshot}" "packageManagerRequirement")
        IDE_WORKSPACE_SUMMARY_LOCKFILES=$(workspace_summary_snapshot_value "${remote_snapshot}" "lockfiles")
        IDE_WORKSPACE_SUMMARY_GO_REQUIREMENTS=$(workspace_summary_snapshot_value "${remote_snapshot}" "goRequirements")
        IDE_WORKSPACE_SUMMARY_SWIFT_TOOLS_VERSION=$(workspace_summary_snapshot_value "${remote_snapshot}" "swiftToolsVersion")
        IDE_WORKSPACE_SUMMARY_PYTHON_REQUIREMENT=$(workspace_summary_snapshot_value "${remote_snapshot}" "pythonRequirement")
        workspace_identity_set_resolved_root "${IDE_WORKSPACE_SUMMARY_ROOT}"
        return 0
    fi

    IDE_WORKSPACE_SUMMARY_ROOT=$(find_project_root "${target}")
    workspace_summary_apply_minimal_snapshot "${IDE_WORKSPACE_SUMMARY_ROOT}"
    if [[ "${detail_level}" == "minimal" ]]; then
        workspace_identity_set_resolved_root "${IDE_WORKSPACE_SUMMARY_ROOT}"
        return 0
    fi
    if [[ -n "$(devcontainer_spec_file "${IDE_WORKSPACE_SUMMARY_ROOT}")" ]]; then
        IDE_WORKSPACE_SUMMARY_DEVCONTAINER_SUPPORTED="yes"
    fi
    workflow_dir="${IDE_WORKSPACE_SUMMARY_ROOT}/.yen/workflows"
    if declare -F workflow_dir_for_root >/dev/null 2>&1; then
        workflow_dir=$(workflow_dir_for_root "${IDE_WORKSPACE_SUMMARY_ROOT}")
    fi
    if [[ -d "${workflow_dir}" ]]; then
        IDE_WORKSPACE_SUMMARY_WORKFLOW_COUNT=$(find "${workflow_dir}" -maxdepth 1 -type f -name '*.toml' 2>/dev/null | wc -l | tr -d '[:space:]')
    fi
    IDE_WORKSPACE_SUMMARY_PACKAGE_MANAGER_REQUIREMENT=$(doctor_package_manager_requirement "${IDE_WORKSPACE_SUMMARY_ROOT}")
    IDE_WORKSPACE_SUMMARY_LOCKFILES=$(doctor_lockfile_inventory "${IDE_WORKSPACE_SUMMARY_ROOT}")
    IDE_WORKSPACE_SUMMARY_GO_REQUIREMENTS=$(doctor_collect_go_requirements "${IDE_WORKSPACE_SUMMARY_ROOT}")
    IDE_WORKSPACE_SUMMARY_SWIFT_TOOLS_VERSION=$(doctor_swift_tools_version "${IDE_WORKSPACE_SUMMARY_ROOT}")
    IDE_WORKSPACE_SUMMARY_PYTHON_REQUIREMENT=$(doctor_python_requires_version "${IDE_WORKSPACE_SUMMARY_ROOT}")
    workspace_identity_set_resolved_root "${IDE_WORKSPACE_SUMMARY_ROOT}"
}

detect_payload_json() {
    local root="$1"
    local types="$2"
    local runtime="$3"
    local tooling="$4"
    local trusted="$5"
    local env_count="$6"
    local env_files="$7"
    local hist_file="$8"
    local profile_file="$9"

    IDE_WORKSPACE_TRANSPORT="${IDE_WORKSPACE_TRANSPORT}" \
    IDE_WORKSPACE_EXECUTION_LOCATION="${IDE_WORKSPACE_EXECUTION_LOCATION}" \
    IDE_WORKSPACE_AUTHORITY="${IDE_WORKSPACE_AUTHORITY}" \
    IDE_WORKSPACE_PORT="${IDE_WORKSPACE_PORT}" \
    IDE_WORKSPACE_REQUESTED_TARGET="${IDE_WORKSPACE_REQUESTED_TARGET}" \
    IDE_WORKSPACE_REQUESTED_PATH="${IDE_WORKSPACE_REQUESTED_PATH}" \
    IDE_WORKSPACE_ROOT="${IDE_WORKSPACE_ROOT}" \
    IDE_WORKSPACE_LABEL="${IDE_WORKSPACE_LABEL}" \
    IDE_WORKSPACE_IDENTITY="${IDE_WORKSPACE_IDENTITY}" \
    DETECT_ROOT="${root}" \
    DETECT_TYPES="${types}" \
    DETECT_RUNTIME="${runtime}" \
    DETECT_TOOLING="${tooling}" \
    DETECT_TRUSTED="${trusted}" \
    DETECT_ENV_COUNT="${env_count}" \
    DETECT_ENV_FILES="${env_files}" \
    DETECT_HISTORY_LOG="${hist_file}" \
    DETECT_PROFILE_LOG="${profile_file}" \
    python3 - <<'PY'
import json
import os

env_files = [line for line in (os.environ.get("DETECT_ENV_FILES", "") or "").splitlines() if line]
port = os.environ.get("IDE_WORKSPACE_PORT", "")

payload = {
    "workspace": {
        "transport": os.environ.get("IDE_WORKSPACE_TRANSPORT", ""),
        "executionLocation": os.environ.get("IDE_WORKSPACE_EXECUTION_LOCATION", ""),
        "identity": os.environ.get("IDE_WORKSPACE_IDENTITY", ""),
        "requestedTarget": os.environ.get("IDE_WORKSPACE_REQUESTED_TARGET", ""),
        "requestedPath": os.environ.get("IDE_WORKSPACE_REQUESTED_PATH", ""),
        "root": os.environ.get("IDE_WORKSPACE_ROOT", ""),
        "authority": os.environ.get("IDE_WORKSPACE_AUTHORITY", ""),
        "port": int(port) if port else None,
        "label": os.environ.get("IDE_WORKSPACE_LABEL", ""),
    },
    "project": {
        "root": os.environ.get("DETECT_ROOT", ""),
        "types": os.environ.get("DETECT_TYPES", ""),
        "runtime": os.environ.get("DETECT_RUNTIME", ""),
        "tooling": os.environ.get("DETECT_TOOLING", ""),
        "envTrusted": os.environ.get("DETECT_TRUSTED", "no") == "yes",
        "envCount": int(os.environ.get("DETECT_ENV_COUNT", "0") or "0"),
        "envFiles": env_files,
        "historyLog": os.environ.get("DETECT_HISTORY_LOG", ""),
        "profileLog": os.environ.get("DETECT_PROFILE_LOG", ""),
    },
}
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

detect_cache_file() {
    printf "%s/yen-detect-%s.env\n" "${TMPDIR:-/tmp}" "${UID}"
}

detect_cache_schema_version() {
    printf "%s\n" "2"
}

detect_cache_value() {
    local cache_file="$1"
    local key="$2"
    sed -n "s/^${key}=//p" "${cache_file}" | head -n 1
}

detect_cache_try() {
    local target="$1"
    local cache_file=""
    local cached_schema=""
    local resolved=""
    local cached_root=""
    local cached_mtime=""
    local cached_requested_path=""
    local cached_trusted=""
    local current_mtime=""
    local current_trusted="no"

    case "${target}" in
        ssh://*)
            return 1
            ;;
    esac

    cache_file=$(detect_cache_file)
    [[ -f "${cache_file}" ]] || return 1

    cached_schema=$(detect_cache_value "${cache_file}" "schema_version")
    [[ "${cached_schema}" == "$(detect_cache_schema_version)" ]] || return 1

    cached_root=$(detect_cache_value "${cache_file}" "root")
    cached_mtime=$(detect_cache_value "${cache_file}" "root_mtime")
    cached_requested_path=$(detect_cache_value "${cache_file}" "requested_path")
    cached_trusted=$(detect_cache_value "${cache_file}" "env_trusted")
    [[ -n "${cached_root}" && -n "${cached_mtime}" && -n "${cached_requested_path}" && -n "${cached_trusted}" ]] || return 1
    [[ -d "${cached_root}" ]] || return 1

    resolved=$(resolve_start_path "${target}")
    [[ "${resolved}" == "${cached_requested_path}" ]] || return 1

    current_mtime=$(stat_mtime "${cached_root}")
    [[ "${current_mtime}" == "${cached_mtime}" ]] || return 1
    if is_trusted_project "${cached_root}"; then
        current_trusted="yes"
    fi
    [[ "${current_trusted}" == "${cached_trusted}" ]] || return 1

    sed -n '/^export /p' "${cache_file}"
}

detect_cache_write() {
    local root="$1"
    local requested_path="$2"
    local trusted="$3"
    local exports="$4"
    local cache_file=""
    local mtime=""
    local content=""

    cache_file=$(detect_cache_file)
    mtime=$(stat_mtime "${root}")
    content="schema_version=$(detect_cache_schema_version)
root=${root}
root_mtime=${mtime}
requested_path=${requested_path}
env_trusted=${trusted}
${exports}
"
    atomic_write_text "${cache_file}" "${content}"
}

cmd_detect() {
    local quiet="0"
    local cached="0"
    local target=""
    local format="text"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quiet|-q)
                quiet="1"
                ;;
            --cached)
                cached="1"
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

    if [[ "${cached}" == "1" && "${format}" == "env" && "${quiet}" == "0" ]]; then
        if detect_cache_try "${target}"; then
            return 0
        fi
    fi

    local root
    local types
    local runtime
    local tooling
    local trusted="no"
    local env_files
    local env_count="0"
    local hist_file
    local profile_file
    local detail_level="full"
    if [[ "${format}" == "env" ]]; then
        detail_level="minimal"
    fi
    if ! workspace_summary_resolve_target "${target}" "${detail_level}"; then
        return 1
    fi
    root="${IDE_WORKSPACE_SUMMARY_ROOT}"
    types="${IDE_WORKSPACE_SUMMARY_TYPES}"
    runtime="${IDE_WORKSPACE_SUMMARY_RUNTIME}"
    tooling="${IDE_WORKSPACE_SUMMARY_TOOLING}"
    env_files="${IDE_WORKSPACE_SUMMARY_ENV_FILES}"
    env_count="${IDE_WORKSPACE_SUMMARY_ENV_COUNT}"

    if is_trusted_project "${root}"; then
        trusted="yes"
    fi
    hist_file=$(project_history_file "${root}")
    profile_file=$(project_profile_file "${root}")

    if [[ "${quiet}" == "1" ]]; then
        return 0
    fi

    if [[ "${format}" == "env" ]]; then
        local env_output=""
        env_output="$(
            printf "export YEN_PROJECT_TRANSPORT=%s\n" "$(shell_quote_single "${IDE_WORKSPACE_TRANSPORT}")"
            printf "export YEN_PROJECT_EXECUTION_LOCATION=%s\n" "$(shell_quote_single "${IDE_WORKSPACE_EXECUTION_LOCATION}")"
            printf "export YEN_PROJECT_WORKSPACE_IDENTITY=%s\n" "$(shell_quote_single "${IDE_WORKSPACE_IDENTITY}")"
            printf "export YEN_PROJECT_REQUESTED_PATH=%s\n" "$(shell_quote_single "${IDE_WORKSPACE_REQUESTED_PATH}")"
            printf "export YEN_PROJECT_REMOTE_AUTHORITY=%s\n" "$(shell_quote_single "${IDE_WORKSPACE_AUTHORITY}")"
            printf "export YEN_PROJECT_REMOTE_PORT=%s\n" "$(shell_quote_single "${IDE_WORKSPACE_PORT}")"
            printf "export YEN_PROJECT_REMOTE_LABEL=%s\n" "$(shell_quote_single "${IDE_WORKSPACE_LABEL}")"
            printf "export YEN_PROJECT_ROOT=%s\n" "$(shell_quote_single "${root}")"
            printf "export YEN_PROJECT_TYPES=%s\n" "$(shell_quote_single "${types}")"
            printf "export YEN_PROJECT_RUNTIME=%s\n" "$(shell_quote_single "${runtime}")"
            printf "export YEN_PROJECT_TOOLING=%s\n" "$(shell_quote_single "${tooling}")"
            printf "export YEN_PROJECT_ENV_FILES=%s\n" "$(shell_quote_single "${env_count}")"
            printf "export YEN_PROJECT_ENV_TRUSTED=%s\n" "$(shell_quote_single "${trusted}")"
            printf "export YEN_PROJECT_HISTORY_LOG=%s\n" "$(shell_quote_single "${hist_file}")"
            printf "export YEN_PROJECT_PROFILE_LOG=%s\n" "$(shell_quote_single "${profile_file}")"
        )"
        printf "%s\n" "${env_output}"
        if [[ "${cached}" == "1" ]]; then
            detect_cache_write "${root}" "${IDE_WORKSPACE_REQUESTED_PATH}" "${trusted}" "${env_output}"
        fi
        return 0
    fi
    if [[ "${format}" == "json" ]]; then
        detect_payload_json \
            "${root}" \
            "${types}" \
            "${runtime}" \
            "${tooling}" \
            "${trusted}" \
            "${env_count}" \
            "${env_files}" \
            "${hist_file}" \
            "${profile_file}"
        return 0
    fi

    echo ""
    yen_header "IDE Project Detection"
    echo "Execution location: ${IDE_WORKSPACE_EXECUTION_LOCATION}"
    echo "Workspace identity: ${IDE_WORKSPACE_IDENTITY}"
    if workspace_identity_is_remote; then
        echo "Remote authority:   $(workspace_identity_remote_authority_with_port)"
        if [[ -n "${IDE_WORKSPACE_LABEL}" ]]; then
            echo "Remote label:       ${IDE_WORKSPACE_LABEL}"
        fi
        echo "Requested path:     ${IDE_WORKSPACE_REQUESTED_PATH}"
    fi
    echo "Root:               ${root}"
    echo "Project types:      ${types}"
    echo "Runtime context:    ${runtime}"
    echo "Tooling context:    ${tooling}"
    echo "Env files:          ${env_count}"
    echo "Env trust:          ${trusted}"
    echo "History log:        ${hist_file}"
    echo "Profile log:        ${profile_file}"
    if [[ -n "${env_files}" ]]; then
        echo ""
        echo "Detected env files:"
        printf "%s\n" "${env_files}" | sed 's/^/  - /'
    fi
    echo ""
}
