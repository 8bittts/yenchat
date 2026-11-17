# shellcheck shell=bash
# Repo-native quality baseline helpers and command handlers.

quality_action_title() {
    case "$1" in
        format)
            printf "Format\n"
            ;;
        lint)
            printf "Lint\n"
            ;;
        fix)
            printf "Fix\n"
            ;;
        *)
            printf "%s\n" "$1"
            ;;
    esac
}

quality_action_status_json() {
    local action="$1"
    local root="$2"
    local discovery=""

    discovery=$(workflow_native_discovery_json "${root}") || return 1

    QUALITY_ACTION="${action}" QUALITY_ROOT="${root}" QUALITY_DISCOVERY="${discovery}" python3 - <<'PY'
import json
import os
import pathlib
import re
import shutil

action = os.environ.get("QUALITY_ACTION", "")
root = pathlib.Path(os.environ.get("QUALITY_ROOT", ".")).resolve()
payload = json.loads(os.environ.get("QUALITY_DISCOVERY", "{}") or "{}")

source_rank_map = {
    "package.json": 0,
    "Makefile": 1,
    "Justfile": 2,
    "justfile": 3,
    "Taskfile.yml": 4,
    "Taskfile.yaml": 5,
}


def normalize(value):
    return str(value or "").strip()


def lower(value):
    return normalize(value).lower()


def relpath(value):
    raw = normalize(value)
    if not raw:
        return ""
    path = pathlib.Path(raw)
    try:
        resolved = path.resolve()
        return str(resolved.relative_to(root))
    except Exception:
        return raw


def clean_slug(value):
    slug = re.sub(r"[^a-z0-9_.-]+", "-", lower(value)).strip("-")
    return slug or "root"


def explanation_for(availability):
    availability = lower(availability)
    if availability in {"", "available"}:
        return ""
    if availability.startswith("missing-"):
        tool = availability[len("missing-") :]
        return f"Install {tool} or choose a different repo-native candidate."
    return availability


def task_matches(candidate):
    name = lower(candidate.get("name"))
    command = lower(candidate.get("command"))
    definition = lower(candidate.get("definition"))
    category = lower(candidate.get("category"))
    blob = " ".join(
        entry for entry in [candidate.get("id"), name, command, definition, category] if entry
    ).lower()

    if action == "format":
        if category == "format" or name in {"format", "fmt", "format-check", "fmt-check"}:
            return True
        return any(
            needle in blob
            for needle in (
                "prettier",
                "biome format",
                "cargo fmt",
                "gofmt",
                "zig fmt",
                "swift format",
                "clang-format",
            )
        )

    if action == "lint":
        if category == "lint" or name in {"lint", "lint:check", "check:lint"}:
            return True
        return any(
            needle in blob
            for needle in (
                "eslint",
                "ruff",
                "clippy",
                "checkstyle",
                "golangci-lint",
                "biome check",
            )
        )

    if action == "fix":
        if "fix" in name or name in {"format:write", "fmt:write"}:
            return True
        return any(
            needle in blob
            for needle in (
                "--fix",
                "--write",
                "cargo fix",
                "cargo fmt",
                "gofmt -w",
                "zig fmt",
                "ruff format",
                "ruff check --fix",
                "eslint --fix",
                "prettier --write",
                "biome check --write",
                "biome format --write",
                "swift format -i",
            )
        )

    return False


def native_selection_reason(candidate):
    source = candidate.get("source") or ""
    if source == "package.json":
        return "repo-native package script"
    if source in {"Makefile", "Justfile", "justfile", "Taskfile.yml", "Taskfile.yaml"}:
        return "repo-native task source"
    return "repo-native candidate"


def builtin_candidate(source_path, workdir, command, executable, label, builtin_id):
    available = shutil.which(executable) is not None
    return {
        "id": builtin_id,
        "name": label,
        "originType": "toolchain-default",
        "source": pathlib.Path(source_path).name,
        "sourcePath": relpath(source_path),
        "path": normalize(source_path),
        "workdir": normalize(workdir),
        "definition": command,
        "command": command,
        "runnable": available,
        "availability": "available" if available else f"missing-{executable}",
        "explanation": "" if available else f"Install {executable} to use the toolchain-default {action} fallback.",
        "category": action,
        "workflowConflict": False,
        "workflowPath": "",
        "selectionReason": "toolchain-default fallback",
    }


def builtin_candidates():
    out = []
    ignored_parts = {
        ".git",
        ".hg",
        ".next",
        ".svn",
        ".temp",
        ".tmp",
        ".turbo",
        ".venv",
        ".yarn",
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

    def ignored_part(part):
        return part in ignored_parts or part.startswith(ignored_prefixes)

    if action not in {"format", "fix"}:
        return out

    cargo_toml = root / "Cargo.toml"
    if cargo_toml.is_file():
        out.append(
            builtin_candidate(
                str(cargo_toml),
                str(root),
                "cargo fmt --all --check" if action == "format" else "cargo fmt --all",
                "cargo",
                "cargo fmt",
                "toolchain:cargo-fmt-check" if action == "format" else "toolchain:cargo-fmt-write",
            )
        )

    for go_mod in sorted(root.glob("**/go.mod")):
        try:
            relative_parts = go_mod.relative_to(root).parts
            if len(relative_parts) > 4:
                continue
            if any(ignored_part(part) for part in relative_parts[:-1]):
                continue
        except Exception:
            continue
        workdir = go_mod.parent
        rel = relpath(str(go_mod))
        slug = clean_slug(rel or "go-root")
        out.append(
            builtin_candidate(
                str(go_mod),
                str(workdir),
                "gofmt -l ." if action == "format" else "gofmt -w .",
                "gofmt",
                "gofmt",
                f"toolchain:gofmt-check-{slug}" if action == "format" else f"toolchain:gofmt-write-{slug}",
            )
        )

    build_zig = root / "build.zig"
    if build_zig.is_file():
        out.append(
            builtin_candidate(
                str(build_zig),
                str(root),
                "zig fmt --check ." if action == "format" else "zig fmt .",
                "zig",
                "zig fmt",
                "toolchain:zig-fmt-check" if action == "format" else "toolchain:zig-fmt-write",
            )
        )

    return out


def candidate_priority(candidate):
    runnable_penalty = 0 if candidate.get("runnable") else 1000
    origin_penalty = 0 if candidate.get("originType") == "native-task" else 100
    source_penalty = source_rank_map.get(candidate.get("source"), 50)
    name = lower(candidate.get("name"))

    if action == "format":
        preferred_names = ["format", "fmt", "format-check", "fmt-check"]
    elif action == "lint":
        preferred_names = ["lint:check", "lint", "check:lint"]
    else:
        preferred_names = ["fix", "lint:fix", "format:write", "fmt:write", "fix:lint", "fix:format"]

    try:
        name_penalty = preferred_names.index(name)
    except ValueError:
        name_penalty = len(preferred_names) + 10

    return (
        runnable_penalty + origin_penalty + source_penalty + name_penalty,
        candidate.get("id") or "",
    )


candidates = []
for task in payload.get("tasks") or []:
    if not task_matches(task):
        continue
    availability = normalize(task.get("availability") or "")
    runnable = bool(task.get("runnable"))
    candidates.append(
        {
            "id": normalize(task.get("id")),
            "name": normalize(task.get("name")),
            "originType": "native-task",
            "source": normalize(task.get("source")),
            "sourcePath": relpath(task.get("path")),
            "path": normalize(task.get("path")),
            "workdir": str(root),
            "definition": normalize(task.get("definition")),
            "command": normalize(task.get("command")),
            "runnable": runnable,
            "availability": availability,
            "explanation": explanation_for(availability),
            "category": action,
            "workflowConflict": bool(task.get("workflowConflict")),
            "workflowPath": normalize(task.get("workflowPath")),
            "selectionReason": native_selection_reason(task),
        }
    )

candidates.extend(builtin_candidates())
candidates.sort(key=candidate_priority)

recommended = candidates[0] if candidates else None
if recommended:
    recommended["recommended"] = True

present_sources = [source.get("id") for source in payload.get("sources") or [] if source.get("present")]
guidance = ""
if not candidates:
    guidance = (
        f"No {action} candidates were detected from repo-native task discovery or built-in toolchain defaults. "
        "Inspect `yen ide workflow discover` and add a native task/target if you want an explicit baseline."
    )
elif recommended and not recommended.get("runnable"):
    guidance = recommended.get("explanation") or "Install the missing tool or use another available candidate."

result = {
    "schemaVersion": 1,
    "root": str(root),
    "action": action,
    "summary": {
        "candidateCount": len(candidates),
        "runnableCount": sum(1 for candidate in candidates if candidate.get("runnable")),
        "unavailableCount": sum(1 for candidate in candidates if not candidate.get("runnable")),
        "recommendedId": recommended.get("id", "") if recommended else "",
        "recommendedRunnable": bool(recommended and recommended.get("runnable")),
        "presentSources": present_sources,
    },
    "recommended": recommended or {},
    "guidance": guidance,
    "candidates": candidates,
}

print(json.dumps(result, indent=2, sort_keys=True))
PY
}

git_changed_files_for_root() {
    local root="$1"
    (
        cd "${root}" || exit 1
        {
            git diff --name-only --diff-filter=ACMR HEAD -- 2>/dev/null || true
            git diff --name-only --cached --diff-filter=ACMR -- 2>/dev/null || true
            git ls-files --others --exclude-standard -- 2>/dev/null || true
        } | awk 'NF { gsub(/\r/, "", $0); if (!seen[$0]++) print $0 }'
    )
}

quality_action_preview_json() {
    local action="$1"
    local root="$2"
    local status_payload="$3"
    local scope_mode="$4"
    local changed_status="$5"
    local changed_files="$6"

    QUALITY_ACTION="${action}" \
    QUALITY_ROOT="${root}" \
    QUALITY_STATUS_PAYLOAD="${status_payload}" \
    QUALITY_SCOPE_MODE="${scope_mode}" \
    QUALITY_CHANGED_STATUS="${changed_status}" \
    QUALITY_CHANGED_FILES="${changed_files}" \
    python3 - <<'PY'
import json
import os
import pathlib
import shlex

action = os.environ.get("QUALITY_ACTION", "")
root = pathlib.Path(os.environ.get("QUALITY_ROOT", ".")).resolve()
payload = json.loads(os.environ.get("QUALITY_STATUS_PAYLOAD", "{}") or "{}")
scope_mode = os.environ.get("QUALITY_SCOPE_MODE", "workspace")
changed_status = os.environ.get("QUALITY_CHANGED_STATUS", "not-requested")
changed_files = [line.strip() for line in (os.environ.get("QUALITY_CHANGED_FILES", "") or "").splitlines() if line.strip()]
candidate = payload.get("recommended") or {}


def normalize(value):
    return str(value or "").strip()


def lower(value):
    return normalize(value).lower()


def changed_status_guidance(status):
    if status == "git-missing":
        return "Changed-files preview requires git on PATH."
    if status == "not-git-worktree":
        return "Changed-files preview requires running inside a git worktree."
    if status == "no-changes":
        return "No changed files are available for preview."
    return ""


def path_matches(path_obj, suffixes=None, names=None):
    suffixes = suffixes or []
    names = names or []
    if path_obj.name in names:
        return True
    full_name = path_obj.name.lower()
    for suffix in suffixes:
        if full_name.endswith(suffix):
            return True
    return False


def files_for_candidate(workdir_value, suffixes=None, names=None):
    workdir = pathlib.Path(normalize(workdir_value) or str(root)).resolve()
    eligible = []
    for rel in changed_files:
        file_path = (root / rel).resolve()
        try:
            local_path = file_path.relative_to(workdir)
        except Exception:
            continue
        if not path_matches(file_path, suffixes=suffixes, names=names):
            continue
        eligible.append(str(local_path))
    return eligible


def append_step(steps, label, command, files, derivation):
    if not files:
        return
    quoted = " ".join(shlex.quote(item) for item in files)
    steps.append(
        {
            "label": label,
            "command": f"{command} {quoted}".strip(),
            "eligibleFiles": files,
            "derivation": derivation,
        }
    )


def derive_changed_steps(candidate_obj):
    blob = " ".join(
        [
            normalize(candidate_obj.get("definition")),
            normalize(candidate_obj.get("command")),
            normalize(candidate_obj.get("name")),
        ]
    ).lower()
    steps = []
    workdir = candidate_obj.get("workdir") or str(root)
    js_like_suffixes = [
        ".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".mts", ".cts",
        ".json", ".jsonc", ".css", ".scss", ".md", ".mdx", ".html",
        ".yaml", ".yml",
    ]
    py_suffixes = [".py", ".pyi"]
    go_suffixes = [".go"]
    zig_suffixes = [".zig", ".zig.zon", ".zon"]

    if "biome check" in blob and action in {"lint", "fix"}:
        command = "biome check --write" if action == "fix" or "--write" in blob else "biome check"
        append_step(
            steps,
            "biome-check",
            command,
            files_for_candidate(workdir, suffixes=js_like_suffixes),
            "derived from repo-native biome check definition",
        )
    if "biome format" in blob and action in {"format", "fix"}:
        append_step(
            steps,
            "biome-format",
            "biome format --write",
            files_for_candidate(workdir, suffixes=js_like_suffixes),
            "derived from repo-native biome format definition",
        )
    if "prettier" in blob and action in {"format", "fix"}:
        append_step(
            steps,
            "prettier",
            "prettier --write",
            files_for_candidate(workdir, suffixes=js_like_suffixes),
            "derived from repo-native prettier definition",
        )
    if "eslint" in blob and action in {"lint", "fix"}:
        command = "eslint --fix" if action == "fix" or "--fix" in blob else "eslint"
        append_step(
            steps,
            "eslint",
            command,
            files_for_candidate(workdir, suffixes=[".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".mts", ".cts"]),
            "derived from repo-native eslint definition",
        )
    if "ruff check" in blob and action in {"lint", "fix"}:
        command = "ruff check --fix" if action == "fix" or "--fix" in blob else "ruff check"
        append_step(
            steps,
            "ruff-check",
            command,
            files_for_candidate(workdir, suffixes=py_suffixes),
            "derived from repo-native ruff check definition",
        )
    if "ruff format" in blob and action in {"format", "fix"}:
        append_step(
            steps,
            "ruff-format",
            "ruff format",
            files_for_candidate(workdir, suffixes=py_suffixes),
            "derived from repo-native ruff format definition",
        )
    if "gofmt" in blob and action in {"format", "fix"}:
        append_step(
            steps,
            "gofmt",
            "gofmt -l" if action == "format" else "gofmt -w",
            files_for_candidate(workdir, suffixes=go_suffixes),
            "derived from gofmt-compatible definition",
        )
    if "zig fmt" in blob and action in {"format", "fix"}:
        append_step(
            steps,
            "zig-fmt",
            "zig fmt --check" if action == "format" else "zig fmt",
            files_for_candidate(workdir, suffixes=zig_suffixes, names=["build.zig", "build.zig.zon"]),
            "derived from zig fmt-compatible definition",
        )
    return steps


def append_preview_command(commands, candidate_obj, label, command, derivation, eligible_files=None):
    commands.append(
        {
            "label": label,
            "candidateId": normalize(candidate_obj.get("id")),
            "workdir": normalize(candidate_obj.get("workdir")) or str(root),
            "command": normalize(command),
            "eligibleFiles": list(eligible_files or []),
            "derivation": derivation,
        }
    )


def build_execution_candidates(primary_candidate, candidates):
    selected = []
    seen = set()

    def add(candidate_obj):
        if not candidate_obj:
            return
        candidate_id = normalize(candidate_obj.get("id"))
        if not candidate_id or candidate_id in seen:
            return
        seen.add(candidate_id)
        selected.append(candidate_obj)

    add(primary_candidate)
    if action in {"format", "fix"}:
        for candidate_obj in candidates:
            if lower(candidate_obj.get("originType")) != "toolchain-default":
                continue
            add(candidate_obj)
    return selected


def missing_execution_candidates(candidates):
    return [candidate_obj for candidate_obj in candidates if not candidate_obj.get("runnable")]


def execution_candidate_note(candidates):
    if len(candidates) <= 1:
        return ""
    companion_ids = [normalize(candidate_obj.get("id")) for candidate_obj in candidates[1:] if normalize(candidate_obj.get("id"))]
    if not companion_ids:
        return ""
    return "Execution set also includes repository-implied companion candidates: " + ", ".join(companion_ids) + "."


def missing_execution_guidance(candidates):
    for candidate_obj in candidates:
        explanation = normalize(candidate_obj.get("explanation"))
        if explanation:
            return explanation
    return ""


execution_candidates = build_execution_candidates(candidate, payload.get("candidates") or [])
base_guidance = normalize(payload.get("guidance"))
companion_note = execution_candidate_note(execution_candidates)
if companion_note:
    base_guidance = f"{base_guidance} {companion_note}".strip()

preview = {
    "schemaVersion": 1,
    "root": str(root),
    "action": action,
    "dryRun": True,
    "scope": {
        "mode": scope_mode,
        "status": changed_status if scope_mode == "changed" else "workspace",
        "changedFiles": changed_files if scope_mode == "changed" else [],
        "eligibleFiles": [],
        "eligibleCount": 0,
        "supported": scope_mode == "workspace",
    },
    "selection": {
        "recommendedId": (payload.get("summary") or {}).get("recommendedId", ""),
        "selectedId": normalize(candidate.get("id")),
        "selectedIds": [normalize(candidate_obj.get("id")) for candidate_obj in execution_candidates if normalize(candidate_obj.get("id"))],
    },
    "candidate": candidate,
    "executionCandidates": execution_candidates,
    "planStatus": "ready",
    "commands": [],
    "guidance": base_guidance,
}

if not execution_candidates:
    preview["planStatus"] = "no-candidate"
elif scope_mode == "workspace":
    for index, execution_candidate in enumerate(execution_candidates):
        append_preview_command(
            preview["commands"],
            execution_candidate,
            normalize(execution_candidate.get("id")) or "workspace",
            normalize(execution_candidate.get("command")),
            "workspace preview uses the selected baseline command"
            if index == 0
            else "workspace preview includes repository-implied companion coverage",
            [],
        )
    missing_candidates = missing_execution_candidates(execution_candidates)
    if missing_candidates:
        preview["planStatus"] = "blocked-missing-tool"
        preview["guidance"] = f"{missing_execution_guidance(missing_candidates)} {companion_note}".strip() or preview["guidance"]
else:
    preview["scope"]["supported"] = False
    if changed_status != "ok":
        preview["planStatus"] = changed_status
        preview["guidance"] = changed_status_guidance(changed_status)
    else:
        steps = []
        eligible_files = []
        scope_supported = True
        missing_candidates = []
        for execution_candidate in execution_candidates:
            derived_steps = derive_changed_steps(execution_candidate)
            if not derived_steps:
                scope_supported = False
                break
            for step in derived_steps:
                append_preview_command(
                    steps,
                    execution_candidate,
                    normalize(step.get("label")),
                    normalize(step.get("command")),
                    normalize(step.get("derivation")),
                    step.get("eligibleFiles") or [],
                )
                for item in step.get("eligibleFiles") or []:
                    if item not in eligible_files:
                        eligible_files.append(item)
            if not execution_candidate.get("runnable"):
                missing_candidates.append(execution_candidate)
        if not scope_supported:
            preview["planStatus"] = "scope-unavailable"
            preview["guidance"] = "Changed-files scoping is not derivable for the recommended candidate yet, so the dry run stays informational."
        else:
            preview["scope"]["supported"] = True
            preview["scope"]["eligibleFiles"] = eligible_files
            preview["scope"]["eligibleCount"] = len(eligible_files)
            preview["commands"] = steps
            if not eligible_files:
                preview["planStatus"] = "no-matching-changed-files"
                preview["guidance"] = "Changed files exist, but none match the selected candidate's scoped file types."
            elif missing_candidates:
                preview["planStatus"] = "blocked-missing-tool"
                preview["guidance"] = f"{missing_execution_guidance(missing_candidates)} {companion_note}".strip() or preview["guidance"]

if candidate.get("workflowConflict"):
    conflict_note = f"Authored workflow also exists at {candidate.get('workflowPath', '')}."
    preview["guidance"] = f"{preview['guidance']} {conflict_note}".strip()

print(json.dumps(preview, indent=2, sort_keys=True))
PY
}

quality_preview_record() {
    local payload="$1"
    python3 - "${payload}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
candidate = payload.get("candidate") or {}
selection = payload.get("selection") or {}
scope = payload.get("scope") or {}

print("\t".join([
    str(payload.get("planStatus") or ""),
    str(selection.get("selectedId") or ""),
    ",".join(selection.get("selectedIds") or []),
    str(candidate.get("workdir") or ""),
    str(candidate.get("originType") or ""),
    "yes" if candidate.get("runnable") else "no",
    "yes" if candidate.get("workflowConflict") else "no",
    str(candidate.get("workflowPath") or ""),
    str(candidate.get("explanation") or ""),
    str(scope.get("mode") or ""),
    str(payload.get("guidance") or ""),
]))
PY
}

quality_preview_record_shell_vars() {
    local record="$1"
    python3 - "${record}" <<'PY'
import shlex
import sys

keys = [
    "plan_status",
    "selected_id",
    "selected_ids_csv",
    "candidate_workdir",
    "candidate_kind",
    "candidate_runnable",
    "candidate_conflict",
    "candidate_workflow_path",
    "candidate_explanation",
    "scope_mode",
    "preview_guidance",
]
parts = (sys.argv[1].split("\t") + [""] * len(keys))[: len(keys)]
for key, value in zip(keys, parts):
    print(f"{key}={shlex.quote(value)}")
PY
}

quality_preview_command_rows() {
    local payload="$1"
    python3 - "${payload}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
for entry in payload.get("commands") or []:
    print("\t".join([
        str(entry.get("label") or ""),
        str(entry.get("command") or "").replace("\t", " ").replace("\r", " ").replace("\n", " "),
        str(entry.get("derivation") or "").replace("\t", " ").replace("\r", " ").replace("\n", " "),
        str(entry.get("workdir") or "").replace("\t", " ").replace("\r", " ").replace("\n", " "),
        str(entry.get("candidateId") or "").replace("\t", " ").replace("\r", " ").replace("\n", " "),
    ]))
PY
}

quality_execution_result_json() {
    local preview_payload="$1"
    local execution_status="$2"
    local exit_code="$3"
    local trusted_state="$4"
    local allow_untrusted="$5"
    local report_summary="$6"
    local report_details="$7"
    local report_semantic="$8"
    local steps_file="$9"

    python3 - "${preview_payload}" "${steps_file}" "${execution_status}" "${exit_code}" "${trusted_state}" "${allow_untrusted}" "${report_summary}" "${report_details}" "${report_semantic}" <<'PY'
import json
import pathlib
import sys

preview = json.loads(sys.argv[1] or "{}")
steps_path = pathlib.Path(sys.argv[2])
execution_status = sys.argv[3]
exit_code = int(sys.argv[4] or "0")
trusted_state = sys.argv[5]
allow_untrusted = sys.argv[6]
report_summary = sys.argv[7]
report_details = sys.argv[8]
report_semantic = sys.argv[9]

steps = []
if steps_path.exists():
    for raw in steps_path.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        label, command, derivation, workdir, candidate_id, status, duration_ms = (raw.split("\t") + ["", "", "", "", "", "", ""])[:7]
        steps.append(
            {
                "label": label,
                "command": command,
                "derivation": derivation,
                "workdir": workdir,
                "candidateId": candidate_id,
                "status": int(status or "0"),
                "durationMs": int(duration_ms or "0"),
            }
        )

payload = dict(preview)
payload["dryRun"] = False
payload["execution"] = {
    "status": execution_status,
    "exitCode": exit_code,
    "trusted": trusted_state == "yes",
    "allowUntrusted": allow_untrusted == "1",
}
payload["reports"] = {
    "summary": report_summary,
    "details": report_details,
    "semantic": report_semantic,
}
payload["commands"] = steps
print(json.dumps(payload, indent=2, sort_keys=True))
PY
}

validate_option_value() {
    local option_name="$1"
    local option_value="$2"
    if [[ -z "${option_value}" || "${option_value}" == --* ]]; then
        yen_error "${option_name} requires a value."
        return 1
    fi
}

workflow_file_for_name() {
    local root="$1"
    local workflow_name="$2"
    local direct_path=""
    local row=""
    local parsed_name=""

    direct_path="$(workflow_dir_for_root "${root}")/${workflow_name}.toml"
    if [[ -f "${direct_path}" ]]; then
        printf "%s\n" "${direct_path}"
        return 0
    fi

    while IFS= read -r row; do
        [[ -z "${row}" ]] && continue
        parsed_name=$(sed -nE 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "${row}" | head -n 1)
        if [[ "${parsed_name}" == "${workflow_name}" ]]; then
            printf "%s\n" "${row}"
            return 0
        fi
    done < <(find "$(workflow_dir_for_root "${root}")" -maxdepth 1 -type f -name '*.toml' 2>/dev/null | sort)

    return 1
}

parse_workflow_metadata_file() {
    local path="$1"
    local fallback_name="$2"
    local name=""
    local description=""
    local schema_version=""
    local trust_required=""

    if [[ ! -f "${path}" ]]; then
        yen_error "Workflow file not found: ${path}"
        return 1
    fi

    name=$(sed -nE 's/^[[:space:]]*name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "${path}" | head -n 1)
    description=$(sed -nE 's/^[[:space:]]*description[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "${path}" | head -n 1)
    schema_version=$(sed -nE 's/^[[:space:]]*schema_version[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' "${path}" | head -n 1)
    trust_required=$(sed -nE 's/^[[:space:]]*trust_required[[:space:]]*=[[:space:]]*(true|false).*/\1/p' "${path}" | head -n 1)

    if [[ -z "${schema_version}" ]]; then
        yen_error "Workflow '${path}' is missing required 'schema_version'."
        return 2
    fi
    if [[ "${schema_version}" != "1" ]]; then
        yen_error "Workflow '${path}' has unsupported schema_version='${schema_version}'. Expected '1'."
        return 2
    fi

    if [[ -z "${trust_required}" ]]; then
        trust_required="true"
    fi
    trust_required=$(printf "%s" "${trust_required}" | tr '[:upper:]' '[:lower:]')
    case "${trust_required}" in
        true|false)
            ;;
        *)
            yen_error "Workflow '${path}' has invalid trust_required='${trust_required}'. Use true|false."
            return 2
            ;;
    esac

    if [[ -z "${name}" ]]; then
        name="${fallback_name}"
    fi
    if [[ -z "${name}" ]]; then
        name="$(basename "${path}" .toml)"
    fi
    if [[ -z "${description}" ]]; then
        description="Workflow from ${path}"
    fi

    name=$(printf "%s" "${name}" | tr '\t\r\n' '   ')
    description=$(printf "%s" "${description}" | tr '\t\r\n' '   ')
    printf "%s\t%s\t%s\t%s\n" "${name}" "${description}" "${schema_version}" "${trust_required}"
}

parse_workflow_steps_file() {
    local path="$1"
    local out_file="$2"
    local raw=""
    local line=""
    local mode=""
    local command=""
    local index=0

    : > "${out_file}"
    while IFS= read -r raw || [[ -n "${raw}" ]]; do
        line=$(trim "${raw}")
        [[ -z "${line}" ]] && continue
        [[ "${line#\#}" != "${line}" ]] && continue

        mode=""
        command=""
        if [[ "${line}" =~ ^step[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
            mode="required"
            command="${BASH_REMATCH[1]}"
        elif [[ "${line}" =~ ^optional_step[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
            mode="optional"
            command="${BASH_REMATCH[1]}"
        fi

        [[ -n "${mode}" ]] || continue
        command=$(printf "%s" "${command}" | sed 's/\\"/"/g')
        command=$(printf "%s" "${command}" | tr '\t\r\n' '   ')
        index=$((index + 1))
        printf "%s\t%s\t%s\n" "${index}" "${mode}" "${command}" >> "${out_file}"
    done < "${path}"

    if [[ "${index}" -lt 1 ]]; then
        yen_error "Workflow '${path}' must define at least one step via step=\"...\"."
        return 2
    fi
}

workflow_step_rows_with_risk() {
    local steps_file="$1"
    local allowlist_file="$2"
    local out_file="$3"
    local idx=""
    local mode=""
    local command=""
    local risk_info=""
    local risk_level=""
    local risk_score=""
    local risk_reason=""
    local rest=""

    : > "${out_file}"
    while IFS=$'\t' read -r idx mode command; do
        [[ -n "${idx}" ]] || continue
        risk_info=$(classify_risk "${command}" "${allowlist_file}")
        risk_level="${risk_info%%|*}"
        rest="${risk_info#*|}"
        risk_score="${rest%%|*}"
        risk_reason="${rest#*|}"
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${idx}" "${mode}" "${risk_level}" "${risk_score}" "${risk_reason}" "${command}" >> "${out_file}"
    done < "${steps_file}"
}

cmd_quality_status() {
    local action="$1"
    shift || true
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
                if [[ -n "${target}" ]]; then
                    yen_error "${action} status accepts at most one project path."
                    return 1
                fi
                target="$1"
                ;;
        esac
        shift
    done

    root=$(find_project_root "${target}")
    payload=$(quality_action_status_json "${action}" "${root}") || return 1

    case "${format}" in
        json)
            printf "%s\n" "${payload}"
            ;;
        text)
            QUALITY_STATUS_JSON="${payload}" QUALITY_STATUS_TITLE="$(quality_action_title "${action}")" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("QUALITY_STATUS_JSON", "{}") or "{}")
title = os.environ.get("QUALITY_STATUS_TITLE", "Quality")
summary = payload.get("summary") or {}
recommended = payload.get("recommended") or {}
candidates = payload.get("candidates") or []

print("")
print(f"IDE {title} Status")
print(f"Project root:       {payload.get('root', '')}")
print(f"Candidates:         {summary.get('candidateCount', 0)} total / {summary.get('runnableCount', 0)} runnable")
print(f"Recommended:        {summary.get('recommendedId', '') or 'none'}")
if recommended:
    print(f"Recommended kind:   {recommended.get('originType', '')}")
    print(f"Recommended cmd:    {recommended.get('command', '') or 'missing'}")
if payload.get("guidance"):
    print(f"Guidance:           {payload.get('guidance', '')}")
print("")

if not candidates:
    print("No candidates detected yet.")
    print("")
    raise SystemExit(0)

print(f"{'ID':<26} {'KIND':<17} {'RUN':<5} {'SOURCE':<20} COMMAND")
for candidate in candidates:
    source = candidate.get("sourcePath") or candidate.get("source") or ""
    print(
        f"{candidate.get('id', ''):<26} "
        f"{candidate.get('originType', ''):<17} "
        f"{('yes' if candidate.get('runnable') else 'no'):<5} "
        f"{source:<20} "
        f"{candidate.get('command', '')}"
    )
    if candidate.get("explanation"):
        print(f"  note: {candidate.get('explanation')}")
    if candidate.get("workflowConflict"):
        print(f"  conflict: authored workflow also exists at {candidate.get('workflowPath', '')}")
print("")
PY
            ;;
        *)
            yen_error "Unknown ${action} status format: ${format} (expected text|json)"
            return 1
            ;;
    esac
}

cmd_quality_run() {
    local action="$1"
    shift || true
    local target=""
    local format="text"
    local dry_run="0"
    local changed="0"
    local trust_override="0"
    local allow_untrusted="0"
    local assume_yes="0"
    local risk_override=""
    local allowlist_file_override=""
    local root=""
    local payload=""
    local changed_status="not-requested"
    local changed_files=""
    local preview_record=""
    local plan_status=""
    local selected_id=""
    local selected_ids_csv=""
    local candidate_workdir=""
    local candidate_kind=""
    local candidate_runnable=""
    local candidate_conflict=""
    local candidate_workflow_path=""
    local candidate_explanation=""
    local scope_mode=""
    local preview_guidance=""
    local trusted_state="no"
    local rows_file=""
    local command_rows=""
    local combined_command=""
    local allowlist_file=""
    local risk_info=""
    local risk_level=""
    local risk_score=""
    local risk_reason=""
    local policy_mode=""
    local needs_prompt="0"
    local approved="yes"
    local result_payload=""
    local report_summary=""
    local report_details=""
    local report_semantic=""
    local execution_status="success"
    local execution_exit_code="0"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --dry-run)
                dry_run="1"
                ;;
            --changed)
                changed="1"
                ;;
            --trust)
                trust_override="1"
                ;;
            --allow-untrusted)
                allow_untrusted="1"
                ;;
            --yes|-y)
                assume_yes="1"
                ;;
            --risk-override)
                shift
                risk_override="${1:-}"
                if ! validate_option_value "${action} run --risk-override" "${risk_override}"; then
                    return 1
                fi
                ;;
            --allowlist)
                shift
                allowlist_file_override="${1:-}"
                if ! validate_option_value "${action} run --allowlist" "${allowlist_file_override}"; then
                    return 1
                fi
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
                    yen_error "${action} run accepts at most one project path."
                    return 1
                fi
                target="$1"
                ;;
        esac
        shift
    done

    root=$(find_project_root "${target}")
    payload=$(quality_action_status_json "${action}" "${root}") || return 1

    if [[ "${changed}" == "1" ]]; then
        if ! command -v git >/dev/null 2>&1; then
            changed_status="git-missing"
        elif ! git -C "${root}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            changed_status="not-git-worktree"
        else
            changed_status="ok"
            changed_files=$(git_changed_files_for_root "${root}")
            if [[ -z "${changed_files}" ]]; then
                changed_status="no-changes"
            fi
        fi
    fi

    payload=$(quality_action_preview_json "${action}" "${root}" "${payload}" "$([[ "${changed}" == "1" ]] && printf "changed" || printf "workspace")" "${changed_status}" "${changed_files}") || return 1
    preview_record=$(quality_preview_record "${payload}")
    eval "$(quality_preview_record_shell_vars "${preview_record}")"
    rows_file=$(mktemp)

    if is_workflow_trusted_project "${root}"; then
        trusted_state="yes"
    fi
    if [[ "${trust_override}" == "1" && "${trusted_state}" != "yes" && "${dry_run}" != "1" ]]; then
        trust_workflow_project "${root}"
        trusted_state="yes"
        timeline_log "workflow-trust" "${root}" "trusted" "source=quality-run;action=${action}"
    fi

    if [[ "${dry_run}" == "1" ]]; then
        case "${format}" in
            json)
                printf "%s\n" "${payload}"
                ;;
            text)
                QUALITY_PREVIEW_JSON="${payload}" QUALITY_PREVIEW_TITLE="$(quality_action_title "${action}")" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("QUALITY_PREVIEW_JSON", "{}") or "{}")
title = os.environ.get("QUALITY_PREVIEW_TITLE", "Quality")
candidate = payload.get("candidate") or {}
scope = payload.get("scope") or {}
commands = payload.get("commands") or []

print("")
print(f"IDE {title} Dry Run")
print(f"Project root:       {payload.get('root', '')}")
print(f"Plan status:        {payload.get('planStatus', '')}")
print(f"Scope:              {scope.get('mode', 'workspace')}")
print(f"Selected candidate: {((payload.get('selection') or {}).get('selectedId') or 'none')}")
selected_ids = (payload.get("selection") or {}).get("selectedIds") or []
print(f"Execution set:      {', '.join(selected_ids) if selected_ids else 'none'}")
if candidate:
    print(f"Candidate kind:     {candidate.get('originType', '')}")
    print(f"Base command:       {candidate.get('command', '') or 'missing'}")
if scope.get("mode") == "changed":
    print(f"Changed status:     {scope.get('status', '')}")
    print(f"Changed files:      {len(scope.get('changedFiles') or [])}")
    print(f"Eligible files:     {scope.get('eligibleCount', 0)}")
    print(f"Scope supported:    {'yes' if scope.get('supported') else 'no'}")
if payload.get("guidance"):
    print(f"Guidance:           {payload.get('guidance', '')}")
print("")

if commands:
    print("Preview Commands:")
    for entry in commands:
        print(f"  {entry.get('command', '')}")
        if entry.get("derivation"):
            print(f"    note: {entry.get('derivation', '')}")
else:
    print("No preview commands available.")
print("")
PY
                ;;
            *)
                yen_error "Unknown ${action} run format: ${format} (expected text|json)"
                rm -f "${rows_file}"
                return 1
                ;;
        esac
        rm -f "${rows_file}"
        return 0
    fi

    case "${plan_status}" in
        no-changes|no-matching-changed-files)
            timeline_log "quality" "${root}" "noop" "action=${action};candidate=${selected_id};scope=${scope_mode};reason=${plan_status}"
            result_payload=$(quality_execution_result_json "${payload}" "noop" "0" "${trusted_state}" "${allow_untrusted}" "" "" "" "${rows_file}")
            case "${format}" in
                json)
                    printf "%s\n" "${result_payload}"
                    ;;
                text)
                    echo ""
                    yen_header "IDE $(quality_action_title "${action}") Run"
                    echo "Project:           ${root}"
                    echo "Execution:         noop"
                    echo "Scope:             ${scope_mode}"
                    echo "Selected candidate:${selected_id:-none}"
                    echo "Execution set:     ${selected_ids_csv:-${selected_id:-none}}"
                    echo "Guidance:          ${preview_guidance}"
                    echo ""
                    ;;
                *)
                    yen_error "Unknown ${action} run format: ${format} (expected text|json)"
                    rm -f "${rows_file}"
                    return 1
                    ;;
            esac
            rm -f "${rows_file}"
            return 0
            ;;
        no-candidate|scope-unavailable|git-missing|not-git-worktree|blocked-missing-tool)
            timeline_log "quality" "${root}" "blocked" "action=${action};candidate=${selected_id};scope=${scope_mode};reason=${plan_status}"
            result_payload=$(quality_execution_result_json "${payload}" "blocked" "1" "${trusted_state}" "${allow_untrusted}" "" "" "" "${rows_file}")
            case "${format}" in
                json)
                    printf "%s\n" "${result_payload}"
                    ;;
                text)
                    echo ""
                    yen_header "IDE $(quality_action_title "${action}") Run"
                    echo "Project:           ${root}"
                    echo "Execution:         blocked"
                    echo "Plan status:       ${plan_status}"
                    echo "Scope:             ${scope_mode}"
                    echo "Selected candidate:${selected_id:-none}"
                    echo "Execution set:     ${selected_ids_csv:-${selected_id:-none}}"
                    if [[ -n "${preview_guidance}" ]]; then
                        echo "Guidance:          ${preview_guidance}"
                    fi
                    echo ""
                    ;;
                *)
                    yen_error "Unknown ${action} run format: ${format} (expected text|json)"
                    rm -f "${rows_file}"
                    return 1
                    ;;
            esac
            rm -f "${rows_file}"
            return 1
            ;;
    esac

    command_rows=$(quality_preview_command_rows "${payload}")
    if [[ -z "${command_rows}" ]]; then
        timeline_log "quality" "${root}" "blocked" "action=${action};candidate=${selected_id};scope=${scope_mode};reason=no-executable-commands"
        result_payload=$(quality_execution_result_json "${payload}" "blocked" "1" "${trusted_state}" "${allow_untrusted}" "" "" "" "${rows_file}")
        if [[ "${format}" == "json" ]]; then
            printf "%s\n" "${result_payload}"
        else
            yen_error "No executable quality commands were resolved."
        fi
        rm -f "${rows_file}"
        return 1
    fi

    if [[ "${trusted_state}" != "yes" && "${allow_untrusted}" != "1" ]]; then
        timeline_log "quality" "${root}" "blocked" "action=${action};candidate=${selected_id};scope=${scope_mode};reason=untrusted-project"
        result_payload=$(quality_execution_result_json "${payload}" "blocked" "1" "${trusted_state}" "${allow_untrusted}" "" "" "" "${rows_file}")
        if [[ "${format}" == "json" ]]; then
            printf "%s\n" "${result_payload}"
        else
            yen_error "$(quality_action_title "${action}") execution blocked: project is untrusted."
            yen_info "Run: yen ide workflow trust ${root}"
            yen_info "Or bypass once with --allow-untrusted."
        fi
        rm -f "${rows_file}"
        return 1
    fi

    if [[ "${allow_untrusted}" == "1" && "${trusted_state}" != "yes" ]]; then
        yen_warn "Running ${action} in untrusted mode due to --allow-untrusted."
    fi

    combined_command=$(printf "%s\n" "${command_rows}" | awk -F'\t' 'NF >= 2 { if (out != "") out = out " && " $2; else out = $2 } END { print out }')
    allowlist_file=$(gate_allowlist_file_for_root "${root}")
    if [[ -n "${allowlist_file_override}" ]]; then
        allowlist_file="${allowlist_file_override}"
    fi
    risk_info=$(classify_risk "${combined_command}" "${allowlist_file}")
    risk_level="${risk_info%%|*}"
    local risk_tail="${risk_info#*|}"
    risk_score="${risk_tail%%|*}"
    risk_reason="${risk_tail#*|}"

    if [[ -n "${risk_override}" ]]; then
        risk_override=$(printf "%s" "${risk_override}" | tr '[:upper:]' '[:lower:]')
        case "${risk_override}" in
            low|medium|high|critical)
                risk_level="${risk_override}"
                risk_reason="${risk_reason},override=${risk_override}"
                ;;
            *)
                yen_error "Invalid --risk-override '${risk_override}'. Use low|medium|high|critical."
                rm -f "${rows_file}"
                return 1
                ;;
        esac
    fi

    policy_mode=$(policy_mode_for_root "${root}")
    if needs_approval_for "${policy_mode}" "${risk_level}"; then
        needs_prompt="1"
    fi

    if [[ "${needs_prompt}" == "1" && "${assume_yes}" != "1" ]]; then
        if [[ -t 0 ]]; then
            echo ""
            yen_header "IDE Approval Gate"
            echo "Policy:      ${policy_mode}"
            echo "Risk:        ${risk_level} (score=${risk_score}; ${risk_reason})"
            echo "Project:     ${root}"
            echo "Action:      ${action}"
            echo "Command:"
            echo "  ${combined_command}"
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
        timeline_log "gate" "${root}" "denied" "policy=${policy_mode};risk=${risk_level};score=${risk_score};reason=${risk_reason};cmd=${combined_command}"
        timeline_log "quality" "${root}" "blocked" "action=${action};candidate=${selected_id};scope=${scope_mode};reason=approval-denied"
        result_payload=$(quality_execution_result_json "${payload}" "blocked" "1" "${trusted_state}" "${allow_untrusted}" "" "" "" "${rows_file}")
        if [[ "${format}" == "json" ]]; then
            printf "%s\n" "${result_payload}"
        else
            yen_error "${action} denied by approval gate."
            yen_info "If this is a false positive: use --risk-override low (or configure .yen/gate-allowlist)."
        fi
        rm -f "${rows_file}"
        return 1
    fi

    timeline_log "gate" "${root}" "approved" "policy=${policy_mode};risk=${risk_level};score=${risk_score};reason=${risk_reason};cmd=${combined_command}"

    local timestamp
    local hash
    local candidate_slug
    local report_base
    local command_count="0"
    timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
    hash=$(project_short_hash_for_root "${root}")
    candidate_slug=$(printf "%s" "${selected_id:-${action}}" | tr -cs 'A-Za-z0-9._-' '-')
    report_base="${IDE_QUALITY_DIR}/quality-${action}-${timestamp}-${hash}-${candidate_slug}"
    report_summary="${report_base}.tsv"
    report_details="${report_base}.log"
    report_semantic="${report_base}.semantic.tsv"
    : > "${report_summary}"
    : > "${report_details}"
    : > "${report_semantic}"
    : > "${rows_file}"

    command_count=$(printf "%s\n" "${command_rows}" | sed '/^$/d' | wc -l | tr -d '[:space:]')
    timeline_log "quality" "${root}" "start" "action=${action};candidate=${selected_id};scope=${scope_mode};steps=${command_count};trusted=${trusted_state};kind=${candidate_kind}"

    local idx="0"
    local label=""
    local command=""
    local derivation=""
    local step_workdir=""
    local step_candidate_id=""
    local step_start_ms
    local step_end_ms
    local step_duration_ms
    local step_status
    local step_output=""

    while IFS=$'\t' read -r label command derivation step_workdir step_candidate_id; do
        [[ -n "${command}" ]] || continue
        if [[ -z "${step_candidate_id}" ]]; then
            step_candidate_id="${selected_id}"
        fi
        idx=$((idx + 1))
        timeline_log "quality-step" "${root}" "start" "action=${action};candidate=${step_candidate_id};scope=${scope_mode};step=${idx};label=${label};cmd=${command}"
        step_start_ms=$(now_ms)
        set +e
        step_output=$(cd "${step_workdir:-${candidate_workdir:-${root}}}" && bash -lc "${command}" 2>&1)
        step_status=$?
        set -e
        step_end_ms=$(now_ms)
        step_duration_ms=$((step_end_ms - step_start_ms))

        {
            echo "=== ${action} step ${idx} (${label}) ==="
            echo "candidate: ${step_candidate_id}"
            echo "scope: ${scope_mode}"
            echo "workdir: ${step_workdir:-${candidate_workdir:-${root}}}"
            echo "command: ${command}"
            echo "derivation: ${derivation}"
            echo "status: ${step_status}"
            echo "duration_ms: ${step_duration_ms}"
            echo "--- output ---"
            printf "%s\n" "${step_output}"
            echo ""
        } >> "${report_details}"
        append_semantic_reference_report "${report_semantic}" "${root}" "${step_workdir:-${candidate_workdir:-${root}}}" "$(printf "%s\t%s\t%s\t%s\t%s\t%s" "$(iso_now)" "${action}" "${scope_mode}" "${step_candidate_id}" "${idx}" "${step_status}")" "${step_output}"
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$(iso_now)" "${idx}" "${scope_mode}" "${step_status}" "${step_duration_ms}" "${step_candidate_id}" "${label}" "${command}" >> "${report_summary}"
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "${label}" "${command}" "${derivation}" "${step_workdir:-${candidate_workdir:-${root}}}" "${step_candidate_id}" "${step_status}" "${step_duration_ms}" >> "${rows_file}"
        timeline_log "quality-step" "${root}" "status=${step_status}" "action=${action};candidate=${step_candidate_id};scope=${scope_mode};step=${idx};label=${label};cmd=${command}"

        if [[ "${step_status}" -ne 0 ]]; then
            execution_status="failed"
            execution_exit_code="${step_status}"
            break
        fi
    done << EOF
${command_rows}
EOF

    if [[ "${execution_status}" == "failed" ]]; then
        timeline_log "quality" "${root}" "failed" "action=${action};candidate=${selected_id};scope=${scope_mode};status=${execution_exit_code};summary=${report_summary};semantic=${report_semantic}"
    else
        timeline_log "quality" "${root}" "success" "action=${action};candidate=${selected_id};scope=${scope_mode};summary=${report_summary};semantic=${report_semantic}"
    fi

    result_payload=$(quality_execution_result_json "${payload}" "${execution_status}" "${execution_exit_code}" "${trusted_state}" "${allow_untrusted}" "${report_summary}" "${report_details}" "${report_semantic}" "${rows_file}")

    case "${format}" in
        json)
            printf "%s\n" "${result_payload}"
            ;;
        text)
            echo ""
            yen_header "IDE $(quality_action_title "${action}") Run"
            echo "Project:           ${root}"
            echo "Execution:         ${execution_status}"
            echo "Scope:             ${scope_mode}"
            echo "Selected candidate:${selected_id}"
            echo "Execution set:     ${selected_ids_csv:-${selected_id}}"
            echo "Candidate kind:    ${candidate_kind}"
            echo "Trusted:           ${trusted_state}"
            echo "Commands:          ${command_count}"
            if [[ -n "${candidate_workflow_path}" ]]; then
                echo "Workflow path:     ${candidate_workflow_path}"
            fi
            echo "Summary file:      ${report_summary}"
            echo "Details file:      ${report_details}"
            echo "Semantic file:     ${report_semantic}"
            if [[ -n "${preview_guidance}" ]]; then
                echo "Guidance:          ${preview_guidance}"
            fi
            echo ""
            ;;
        *)
            yen_error "Unknown ${action} run format: ${format} (expected text|json)"
            rm -f "${rows_file}"
            return 1
            ;;
    esac

    rm -f "${rows_file}"
    if [[ "${execution_status}" == "failed" ]]; then
        return "${execution_exit_code}"
    fi
    return 0
}

cmd_quality_action() {
    local action="$1"
    shift || true
    local sub="${1:-status}"

    case "${sub}" in
        status)
            shift || true
            cmd_quality_status "${action}" "$@"
            ;;
        run)
            shift || true
            cmd_quality_run "${action}" "$@"
            ;;
        ""|--*)
            cmd_quality_status "${action}" "$@"
            ;;
        *)
            if [[ -d "${sub}" || -f "${sub}" ]]; then
                cmd_quality_status "${action}" "$@"
                return $?
            fi
            yen_error "Unknown ${action} command: ${sub}"
            return 1
            ;;
    esac
}

