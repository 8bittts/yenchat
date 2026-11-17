# shellcheck shell=bash
# Source-time pure shared helpers for yen ide path/state/temp plumbing.

ensure_state_dirs() {
    mkdir -p "${IDE_HISTORY_DIR}" "${IDE_PROFILE_DIR}" "${IDE_BENCHMARK_DIR}" "${IDE_VERIFY_DIR}" "${IDE_TEST_DIR}" "${IDE_QUALITY_DIR}" "${IDE_EVIDENCE_DIR}" "${IDE_WORKFLOW_DIR}" "${IDE_LSP_DIR}" "${IDE_LSP_TOOLS_DIR}" "${IDE_LSP_SOCKET_DIR}" "${IDE_DEVCONTAINER_DIR}" "${IDE_VSCODE_IMPORT_DIR}" "${IDE_SHARE_DIR}" "${IDE_WATCH_DIR}" "${IDE_DEBUG_DIR}"
    if [[ ! -f "${IDE_TRUST_FILE}" ]]; then
        : > "${IDE_TRUST_FILE}"
    fi
    if [[ ! -f "${IDE_TIMELINE_FILE}" ]]; then
        : > "${IDE_TIMELINE_FILE}"
    fi
    if [[ ! -f "${IDE_VERIFY_FLAKY_FILE}" ]]; then
        : > "${IDE_VERIFY_FLAKY_FILE}"
    fi
    if [[ ! -f "${IDE_NON_INTERFERENCE_SLO_FILE}" ]]; then
        : > "${IDE_NON_INTERFERENCE_SLO_FILE}"
    fi
    if [[ ! -f "${IDE_WORKFLOW_TRUST_FILE}" ]]; then
        : > "${IDE_WORKFLOW_TRUST_FILE}"
    fi
    if [[ ! -f "${IDE_LSP_TRUST_FILE}" ]]; then
        : > "${IDE_LSP_TRUST_FILE}"
    fi
    if [[ ! -f "${IDE_DEVCONTAINER_TRUST_FILE}" ]]; then
        : > "${IDE_DEVCONTAINER_TRUST_FILE}"
    fi
    if [[ ! -f "${IDE_SHARE_TRUST_FILE}" ]]; then
        : > "${IDE_SHARE_TRUST_FILE}"
    fi
    if [[ ! -f "${IDE_DEBUG_TRUST_FILE}" ]]; then
        : > "${IDE_DEBUG_TRUST_FILE}"
    fi
}

shell_quote_single() {
    printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\"'\"'/g")"
}

trim() {
    printf "%s" "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

atomic_write_text() {
    local target="$1"
    local content="$2"
    local parent=""
    local tmp=""

    parent=$(dirname "${target}")
    mkdir -p "${parent}"
    tmp=$(mktemp "${parent}/.yen-tmp.XXXXXX")
    printf "%s" "${content}" > "${tmp}"
    mv "${tmp}" "${target}"
}

watch_state_clean_value() {
    printf "%s" "$1" | tr '\t\r\n' '   '
}

watch_state_file_for_root_kind() {
    local root="$1"
    local kind="$2"
    local kind_slug=""

    kind_slug=$(printf "%s" "${kind}" | tr -cs 'A-Za-z0-9._-' '-')
    printf "%s/%s-%s.env\n" "${IDE_WATCH_DIR}" "$(project_hash_for_root "${root}")" "${kind_slug}"
}

watch_state_write() {
    local root="$1"
    local kind="$2"
    shift 2
    local file=""
    local line=""
    local content=""

    ensure_state_dirs
    file=$(watch_state_file_for_root_kind "${root}" "${kind}")
    content="schema_version=1"$'\n'
    while [[ $# -gt 0 ]]; do
        line="$1"
        content="${content}${line}"$'\n'
        shift
    done
    atomic_write_text "${file}" "${content}"
}

watch_state_latest_snapshot_for_root() {
    local root="$1"
    shift
    local kinds=("$@")
    local kind=""
    local candidate=""
    local latest=""

    if [[ ${#kinds[@]} -eq 0 ]]; then
        kinds=("verify" "workflow-native-build")
    fi

    for kind in "${kinds[@]}"; do
        candidate=$(watch_state_file_for_root_kind "${root}" "${kind}")
        if [[ ! -f "${candidate}" ]]; then
            continue
        fi
        if [[ -z "${latest}" || "${candidate}" -nt "${latest}" ]]; then
            latest="${candidate}"
        fi
    done

    if [[ -n "${latest}" ]]; then
        cat "${latest}"
    fi
}

watch_state_branch_for_root() {
    local root="$1"
    local branch=""

    branch=$(git -C "${root}" symbolic-ref --quiet --short HEAD 2>/dev/null | head -n 1 | tr -d '\r')
    if [[ -z "${branch}" ]]; then
        branch=$(git -C "${root}" branch --show-current 2>/dev/null | head -n 1 | tr -d '\r')
    fi
    if [[ -z "${branch}" || "${branch}" == "HEAD" ]]; then
        branch=$(git -C "${root}" rev-parse --abbrev-ref HEAD 2>/dev/null | head -n 1 | tr -d '\r')
    fi
    printf "%s" "${branch}"
}

ide_watch_validate_interval() {
    local interval="$1"
    if ! printf "%s" "${interval}" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then
        yen_error "Invalid watch interval '${interval}'. Use a positive number of seconds."
        return 1
    fi

    python3 - "${interval}" <<'PY'
import sys

try:
    value = float(sys.argv[1])
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if value > 0 else 1)
PY
    if [[ "$?" -ne 0 ]]; then
        yen_error "Invalid watch interval '${interval}'. Use a positive number of seconds."
        return 1
    fi
}

ide_watch_validate_max_runs() {
    local max_runs="$1"
    if ! printf "%s" "${max_runs}" | grep -Eq '^[0-9]+$'; then
        yen_error "Invalid --max-runs '${max_runs}'. Use a positive integer."
        return 1
    fi
    if [[ "${max_runs}" -lt 1 ]]; then
        yen_error "Invalid --max-runs '${max_runs}'. Use a positive integer."
        return 1
    fi
}

ide_watch_snapshot_for_root() {
    local root="$1"

    python3 - "${root}" <<'PY'
import hashlib
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).expanduser().resolve()
ignored_dir_names = {
    ".build",
    ".cache",
    ".direnv",
    ".git",
    ".gradle",
    ".idea",
    ".next",
    ".nuxt",
    ".parcel-cache",
    ".pytest_cache",
    ".ruff_cache",
    ".sass-cache",
    ".swiftpm",
    ".terraform",
    ".turbo",
    ".venv",
    ".vscode",
    ".vercel",
    ".yarn",
    "DerivedData",
    "__pycache__",
    "build",
    "coverage",
    "dist",
    "ghostty",
    "node_modules",
    "Pods",
    "target",
    "vendor",
    "venv",
    "zig-cache",
    "zig-out",
}
ignored_file_names = {
    ".DS_Store",
}
ignored_suffixes = (".swp", ".swo", ".swx", "~")

if not root.exists():
    print("missing\t0\t\t0")
    raise SystemExit(0)

digest = hashlib.sha256()
count = 0
latest_path = ""
latest_mtime_ns = 0

for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = sorted(name for name in dirnames if name not in ignored_dir_names)
    for filename in sorted(filenames):
        if filename in ignored_file_names or filename.endswith(ignored_suffixes):
            continue
        path = pathlib.Path(dirpath) / filename
        try:
            stat_result = path.stat()
            relative = path.resolve().relative_to(root).as_posix()
        except Exception:
            continue
        count += 1
        digest.update(relative.encode("utf-8", "ignore"))
        digest.update(b"\0")
        digest.update(str(stat_result.st_mtime_ns).encode("ascii", "ignore"))
        digest.update(b"\0")
        digest.update(str(stat_result.st_size).encode("ascii", "ignore"))
        digest.update(b"\0")
        if stat_result.st_mtime_ns >= latest_mtime_ns:
            latest_mtime_ns = stat_result.st_mtime_ns
            latest_path = relative

print(f"{digest.hexdigest()}\t{count}\t{latest_path}\t{latest_mtime_ns}")
PY
}

ide_watch_wait_for_change() {
    local root="$1"
    local baseline="$2"
    local interval="$3"
    local snapshot=""
    local fingerprint=""

    while true; do
        sleep "${interval}"
        snapshot=$(ide_watch_snapshot_for_root "${root}")
        fingerprint="${snapshot%%$'\t'*}"
        if [[ "${fingerprint}" != "${baseline}" ]]; then
            printf "%s\n" "${snapshot}"
            return 0
        fi
    done
}

is_pid_running() {
    local pid="$1"
    if [[ -z "${pid}" ]] || [[ ! "${pid}" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    kill -0 "${pid}" 2>/dev/null
}

canonicalize_path() {
    local input="$1"
    if [[ -z "${input}" ]]; then
        pwd -P
        return 0
    fi

    if [[ -d "${input}" ]]; then
        (cd "${input}" 2>/dev/null && pwd -P) && return 0
    fi

    local dir=""
    local base=""
    local cdir=""
    dir=$(dirname "${input}")
    base=$(basename "${input}")
    cdir=$(cd "${dir}" 2>/dev/null && pwd -P || true)
    if [[ -n "${cdir}" ]]; then
        printf "%s/%s\n" "${cdir}" "${base}"
    else
        printf "%s\n" "${input}"
    fi
}

resolve_start_path() {
    local arg="$1"
    if [[ -z "${arg}" ]]; then
        canonicalize_path "${PWD}"
        return 0
    fi

    if [[ "${arg}" == /* ]]; then
        canonicalize_path "${arg}"
    else
        canonicalize_path "${PWD}/${arg}"
    fi
}

stat_mtime() {
    local path="$1"
    stat -f %m "${path}" 2>/dev/null || stat -c %Y "${path}" 2>/dev/null || printf "0"
}

ide_remote_ssh_binary() {
    command -v ssh 2>/dev/null
}

ide_remote_python_helper_json() {
    local authority="$1"
    local port="$2"
    local helper_path="$3"
    shift 3
    local ssh_bin=""
    local stderr_file=""
    local output=""
    local status=0
    local stderr_text=""
    local -a ssh_cmd=()

    ssh_bin=$(ide_remote_ssh_binary) || {
        yen_error "ssh is required for remote workspace inspection."
        return 1
    }
    if [[ ! -f "${helper_path}" ]]; then
        yen_error "Remote helper not found: ${helper_path}"
        return 1
    fi
    stderr_file=$(mktemp "${TMPDIR:-/tmp}/yen-remote-helper.XXXXXX" 2>/dev/null) || {
        yen_error "Unable to allocate a temp file for remote workspace inspection."
        return 1
    }

    ssh_cmd=("${ssh_bin}")
    if [[ -n "${port}" ]]; then
        ssh_cmd+=("-p" "${port}")
    fi
    ssh_cmd+=("${authority}" "python3" "-")
    while [[ $# -gt 0 ]]; do
        ssh_cmd+=("$1")
        shift
    done

    output=$("${ssh_cmd[@]}" < "${helper_path}" 2>"${stderr_file}")
    status=$?
    stderr_text=$(tr '\n' ' ' < "${stderr_file}" | sed 's/[[:space:]]*$//')
    rm -f "${stderr_file}"

    if [[ "${status}" -ne 0 ]]; then
        if [[ -z "${stderr_text}" ]]; then
            stderr_text="remote workspace inspection failed"
        fi
        yen_error "Unable to inspect remote workspace ${authority}: ${stderr_text}"
        return 1
    fi

    printf "%s\n" "${output}"
}

ide_remote_shell_command() {
    local authority="$1"
    local port="$2"
    local command_text="$3"
    local shell_name="${4:-sh}"
    local ssh_bin=""
    local -a ssh_cmd=()

    ssh_bin=$(ide_remote_ssh_binary) || {
        yen_error "ssh is required for remote workspace execution."
        return 1
    }

    ssh_cmd=("${ssh_bin}")
    if [[ -n "${port}" ]]; then
        ssh_cmd+=("-p" "${port}")
    fi
    ssh_cmd+=("${authority}" "${shell_name}" "-lc" "${command_text}")
    "${ssh_cmd[@]}"
}

ide_remote_command_failure_label() {
    local status="$1"
    if [[ "${status}" -eq 255 ]]; then
        printf "transport-failed\n"
        return 0
    fi
    if [[ "${status}" -eq 127 ]]; then
        printf "missing-remote-shell\n"
        return 0
    fi
    printf "command-failed\n"
}

path_has_project_markers() {
    local path="$1"
    if [[ -e "${path}/.git" ]] || \
       [[ -f "${path}/package.json" ]] || \
       [[ -f "${path}/go.mod" ]] || \
       [[ -f "${path}/Cargo.toml" ]] || \
       [[ -f "${path}/pyproject.toml" ]] || \
       [[ -f "${path}/requirements.txt" ]] || \
       [[ -f "${path}/setup.py" ]] || \
       [[ -f "${path}/Package.swift" ]] || \
       [[ -f "${path}/build.zig" ]] || \
       [[ -f "${path}/.devcontainer.json" ]] || \
       [[ -f "${path}/.devcontainer/devcontainer.json" ]] || \
       [[ -f "${path}/Makefile" ]]; then
        return 0
    fi
    return 1
}

find_unique_descendant_project_root() {
    local start_dir="$1"
    [[ -d "${start_dir}" ]] || return 1

    python3 - "${start_dir}" <<'PY'
import os
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
max_depth = 5
# Bound the descendant scan so a cold detect in a huge or markerless directory
# (e.g. $HOME) cannot blow up into a multi-second os.walk on the prompt path.
# Once the budget is spent we treat the result as indeterminate and let the
# caller fall back to the cheap upward marker walk, rather than risk returning
# a non-unique match. Override via YEN_IDE_DETECT_MAX_DIRS (mainly for tests).
try:
    max_dirs = int(os.environ.get("YEN_IDE_DETECT_MAX_DIRS", "2000"))
except ValueError:
    max_dirs = 2000
if max_dirs < 1:
    max_dirs = 2000
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


def ignored(name: str) -> bool:
    return name in ignored_names or any(name.startswith(prefix) for prefix in ignored_prefixes)


matches = []
visited = 0
for current_root, dirnames, filenames in os.walk(str(root)):
    visited += 1
    if visited > max_dirs:
        # Budget exhausted: give up so find_project_root() falls through to
        # the upward marker walk instead of guessing a possibly-wrong root.
        raise SystemExit(1)
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

unique = list(dict.fromkeys(matches))
if len(unique) == 1:
    print(unique[0])
    raise SystemExit(0)

raise SystemExit(1)
PY
}

find_project_root() {
    local start=""
    local path=""
    local descendant=""
    start=$(resolve_start_path "$1")
    path="${start}"

    if [[ ! -d "${path}" ]]; then
        path=$(dirname "${path}")
    fi

    if ! path_has_project_markers "${path}"; then
        descendant=$(find_unique_descendant_project_root "${path}" || true)
        if [[ -n "${descendant}" ]]; then
            printf "%s\n" "${descendant}"
            return 0
        fi
    fi

    while true; do
        if path_has_project_markers "${path}"; then
            printf "%s\n" "${path}"
            return 0
        fi

        if [[ "${path}" == "/" ]]; then
            printf "%s\n" "${start}"
            return 0
        fi
        path=$(dirname "${path}")
    done
}

append_csv_unique() {
    local current="$1"
    local item="$2"
    if [[ -z "${item}" ]]; then
        printf "%s\n" "${current}"
        return 0
    fi
    case ",${current}," in
        *",${item},"*)
            printf "%s\n" "${current}"
            ;;
        *)
            if [[ -n "${current}" ]]; then
                printf "%s,%s\n" "${current}" "${item}"
            else
                printf "%s\n" "${item}"
            fi
            ;;
    esac
}

detect_project_types() {
    local root="$1"
    local out=""
    [[ -f "${root}/package.json" ]] && out="${out:+${out},}node"
    [[ -f "${root}/go.mod" ]] && out="${out:+${out},}go"
    [[ -f "${root}/Cargo.toml" ]] && out="${out:+${out},}rust"
    [[ -f "${root}/pyproject.toml" || -f "${root}/requirements.txt" || -f "${root}/setup.py" ]] && out="${out:+${out},}python"
    [[ -f "${root}/Package.swift" ]] && out="${out:+${out},}swift"
    [[ -f "${root}/build.zig" ]] && out="${out:+${out},}zig"
    [[ -f "${root}/Makefile" ]] && out="${out:+${out},}make"
    if [[ -z "${out}" ]]; then
        out="generic"
    fi
    printf "%s\n" "${out}"
}

detect_runtime_context() {
    local root="$1"
    local out=""
    if [[ -f "${root}/package.json" ]]; then
        if [[ -f "${root}/bun.lockb" || -f "${root}/bun.lock" ]]; then
            out="${out:+${out},}bun"
        fi
        out="${out:+${out},}node"
    fi
    [[ -f "${root}/go.mod" ]] && out="${out:+${out},}go"
    [[ -f "${root}/Cargo.toml" ]] && out="${out:+${out},}rust"
    [[ -f "${root}/pyproject.toml" || -f "${root}/requirements.txt" ]] && out="${out:+${out},}python"
    [[ -f "${root}/Package.swift" ]] && out="${out:+${out},}swift"
    [[ -f "${root}/build.zig" ]] && out="${out:+${out},}zig"
    if [[ -z "${out}" ]]; then
        out="unknown"
    fi
    printf "%s\n" "${out}"
}

detect_tooling_context() {
    local root="$1"
    local out=""
    [[ -e "${root}/.git" ]] && out="${out:+${out},}git"
    [[ -f "${root}/biome.json" ]] && out="${out:+${out},}biome"
    [[ -f "${root}/tsconfig.json" ]] && out="${out:+${out},}typescript"
    [[ -f "${root}/next.config.ts" || -f "${root}/next.config.js" ]] && out="${out:+${out},}nextjs"
    [[ -f "${root}/Dockerfile" || -d "${root}/.devcontainer" || -f "${root}/.devcontainer.json" ]] && out="${out:+${out},}container"
    [[ -f "${root}/Makefile" ]] && out="${out:+${out},}make"
    [[ -f "${root}/package-lock.json" ]] && out="${out:+${out},}npm"
    [[ -f "${root}/pnpm-lock.yaml" ]] && out="${out:+${out},}pnpm"
    [[ -f "${root}/yarn.lock" ]] && out="${out:+${out},}yarn"
    [[ -f "${root}/bun.lock" || -f "${root}/bun.lockb" ]] && out="${out:+${out},}bun"
    [[ -f "${root}/go.mod" ]] && out="${out:+${out},}go-mod"
    [[ -f "${root}/Cargo.toml" ]] && out="${out:+${out},}cargo"
    [[ -f "${root}/pyproject.toml" ]] && out="${out:+${out},}pyproject"
    if [[ -z "${out}" ]]; then
        out="minimal"
    fi
    printf "%s\n" "${out}"
}

csv_has_token() {
    local csv="$1"
    local token="$2"
    case ",${csv}," in
        *",${token},"*)
            return 0
            ;;
    esac
    return 1
}
