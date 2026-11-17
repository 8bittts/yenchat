#!/usr/bin/env python3
"""Read-only remote planning probe for yen ide workflow/devcontainer parity."""

from __future__ import annotations

import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
from typing import Iterable


IGNORED_NAMES = {
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
IGNORED_PREFIXES = ("tmp-", "temp-", "scratch-")
MARKER_FILES = {
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
SOURCE_SPECS = [
    ("package.json", "package.json", "implemented"),
    ("Makefile", "Makefile", "implemented"),
    ("Justfile", "Justfile", "implemented"),
    ("justfile", "justfile", "implemented"),
    ("Taskfile.yml", "Taskfile.yml", "implemented"),
    ("Taskfile.yaml", "Taskfile.yaml", "implemented"),
]


def error(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def clean(value: object) -> str:
    return str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ")


def clean_scalar(value: object) -> str:
    text = str(value or "").strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in ("'", '"'):
        text = text[1:-1]
    return clean(text)


def append_unique(items: list[str], value: str) -> None:
    if value and value not in items:
        items.append(value)


def ignored(name: str) -> bool:
    return name in IGNORED_NAMES or any(name.startswith(prefix) for prefix in IGNORED_PREFIXES)


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


def find_descendant_matches(root: pathlib.Path) -> list[str]:
    matches: list[str] = []
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
        has_marker = ".git" in dirnames or any(name in MARKER_FILES for name in filenames)
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
            return pathlib.Path(descendants[0]).resolve()
        if len(descendants) > 1:
            error(f"Remote target resolves to multiple nested workspaces: {path}", 3)

    current = path
    while True:
        if has_markers(current):
            return current.resolve()
        if current == current.parent:
            return path.resolve()
        current = current.parent


def present_exact(path: pathlib.Path) -> bool:
    parent = path.parent
    if not parent.is_dir():
        return False
    return path.name in {child.name for child in parent.iterdir()}


def strip_jsonc(raw: str) -> str:
    result: list[str] = []
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
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
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
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
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


def load_json_file(path: pathlib.Path) -> dict:
    return json.loads(strip_jsonc(path.read_text(encoding="utf-8")))


def declared_node_package_manager(root: pathlib.Path) -> str:
    if (root / "bun.lockb").is_file() or (root / "bun.lock").is_file():
        return "bun"
    if (root / "pnpm-lock.yaml").is_file():
        return "pnpm"
    if (root / "yarn.lock").is_file():
        return "yarn"
    if (root / "package.json").is_file():
        return "npm"
    return "none"


def command_available(name: str) -> bool:
    return bool(name and shutil.which(name))


def native_task_category(name: str, command: str, definition: str) -> str:
    blob = f"{name} {command} {definition}".lower()
    if any(token in blob for token in ("lint", "eslint", "ruff", "clippy", "checkstyle")):
        return "lint"
    if any(
        token in blob
        for token in (
            "test",
            "pytest",
            "go test",
            "cargo test",
            "swift test",
            "zig build test",
            "bun test",
            "npm test",
            "pnpm test",
            "yarn test",
        )
    ):
        return "test"
    if any(token in blob for token in ("format", "fmt", "prettier", "rustfmt", "gofmt", "biome format")):
        return "format"
    if any(token in blob for token in ("build", "compile", "bundle", "tsc")):
        return "build"
    if any(token in blob for token in ("dev", "start", "serve", "watch")):
        return "dev"
    return "custom"


def classify_risk(command_text: str) -> dict:
    lower = command_text.lower()
    score = 0
    reasons = ["baseline"]
    if any(token in lower for token in ("rm -rf", "rm -fr", "mkfs", "diskutil erase", ":(){ :|:& };:")):
        score += 95
        reasons.append("destructive-or-disk-command")
    if any(token in lower for token in ("git reset --hard", "git clean -fdx", "git push --force", "chmod -r ", "chown -r ")):
        score += 70
        reasons.append("history-or-permission-rewrite")
    if lower.startswith("sudo") or " sudo " in lower:
        score += 60
        reasons.append("elevated-privilege")
    if any(token in lower for token in ("curl ") ) and ("| sh" in lower or "| bash" in lower):
        score += 75
        reasons.append("remote-script-execution")
    if any(token in lower for token in ("wget ")) and ("| sh" in lower or "| bash" in lower):
        score += 75
        reasons.append("remote-script-execution")
    if any(token in lower for token in ("git rebase", "git cherry-pick", "docker system prune", "npm publish", "bun publish", "pnpm publish", "yarn publish")):
        score += 35
        reasons.append("state-mutating-command")
    if any(token in lower for token in ("git push", "terraform apply", "kubectl delete")):
        score += 30
        reasons.append("remote-or-cluster-impact")

    if score >= 85:
        level = "critical"
    elif score >= 55:
        level = "high"
    elif score >= 25:
        level = "medium"
    else:
        level = "low"
    return {"level": level, "score": score, "reason": ",".join(reasons)}


def read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def iter_workflow_files(root: pathlib.Path) -> Iterable[pathlib.Path]:
    workflow_dir = root / ".yen" / "workflows"
    if not workflow_dir.is_dir():
        return []
    return sorted(
        entry.resolve()
        for entry in workflow_dir.iterdir()
        if entry.is_file() and entry.suffix == ".toml"
    )


def parse_workflow_metadata(path: pathlib.Path, fallback_name: str) -> dict:
    if not path.is_file():
        error(f"Workflow file not found: {path}", 4)

    name = ""
    description = ""
    schema_version = ""
    trust_required = ""
    for raw in read_text(path).splitlines():
        if not name:
            match = re.match(r'^[ \t]*name[ \t]*=[ \t]*"([^"]+)".*$', raw)
            if match:
                name = match.group(1)
        if not description:
            match = re.match(r'^[ \t]*description[ \t]*=[ \t]*"([^"]+)".*$', raw)
            if match:
                description = match.group(1)
        if not schema_version:
            match = re.match(r"^[ \t]*schema_version[ \t]*=[ \t]*([0-9]+).*$", raw)
            if match:
                schema_version = match.group(1)
        if not trust_required:
            match = re.match(r"^[ \t]*trust_required[ \t]*=[ \t]*(true|false).*$", raw)
            if match:
                trust_required = match.group(1)

    if schema_version != "1":
        if not schema_version:
            error(f"Workflow '{path}' is missing required 'schema_version'.", 4)
        error(f"Workflow '{path}' has unsupported schema_version='{schema_version}'. Expected '1'.", 4)

    if not trust_required:
        trust_required = "true"
    trust_required = trust_required.lower()
    if trust_required not in {"true", "false"}:
        error(f"Workflow '{path}' has invalid trust_required='{trust_required}'. Use true|false.", 4)

    if not name:
        name = fallback_name or path.stem
    if not description:
        description = f"Workflow from {path}"

    return {
        "name": clean(name),
        "description": clean(description),
        "schema": schema_version,
        "trustRequired": trust_required == "true",
        "path": str(path.resolve()),
    }


def parse_workflow_steps(path: pathlib.Path) -> list[dict]:
    steps: list[dict] = []
    for raw in read_text(path).splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = re.match(r'^step[ \t]*=[ \t]*"(.*)"[ \t]*$', line)
        mode = "required"
        if not match:
            match = re.match(r'^optional_step[ \t]*=[ \t]*"(.*)"[ \t]*$', line)
            mode = "optional"
        if not match:
            continue
        command = clean(match.group(1).replace('\\"', '"'))
        steps.append(
            {
                "index": len(steps) + 1,
                "mode": mode,
                "command": command,
                "risk": classify_risk(command),
            }
        )
    if not steps:
        error(f"Workflow '{path}' must define at least one step via step=\"...\".", 4)
    return steps


def workflow_records(root: pathlib.Path) -> list[dict]:
    records: list[dict] = []
    for workflow_path in iter_workflow_files(root):
        metadata = parse_workflow_metadata(workflow_path, workflow_path.stem)
        metadata["steps"] = parse_workflow_steps(workflow_path)
        metadata["stepCount"] = len(metadata["steps"])
        records.append(metadata)
    return records


def emit_package_tasks(root: pathlib.Path) -> list[tuple]:
    package_path = root / "package.json"
    if not package_path.is_file():
        return []
    try:
        payload = json.loads(package_path.read_text(encoding="utf-8"))
    except Exception:
        payload = {}
    scripts = payload.get("scripts")
    if not isinstance(scripts, dict):
        scripts = {}
    manager = declared_node_package_manager(root)
    runnable = manager in {"bun", "pnpm", "yarn", "npm"} and command_available(manager)
    availability = "available" if runnable else f"missing-{manager}"

    def command_for(name: str) -> str:
        if manager == "bun":
            return f"bun run {name}"
        if manager == "pnpm":
            return f"pnpm run {name}"
        if manager == "yarn":
            return f"yarn run {name}"
        return f"npm run {name}"

    rows = []
    for name in sorted(scripts.keys()):
        rows.append(
            (
                "package.json",
                clean(name),
                str(package_path.resolve()),
                clean(scripts.get(name)),
                manager,
                runnable,
                availability,
                command_for(name),
            )
        )
    return rows


def emit_makefile_tasks(root: pathlib.Path) -> list[tuple]:
    makefile_path = root / "Makefile"
    if not makefile_path.is_file():
        return []
    runnable = command_available("make")
    availability = "available" if runnable else "missing-make"
    lines = makefile_path.read_text(encoding="utf-8").splitlines()
    targets: list[tuple[str, str]] = []
    current_name = ""
    current_recipe: list[str] = []

    def flush() -> None:
        nonlocal current_name, current_recipe
        if not current_name:
            return
        recipe = " ; ".join(current_recipe)
        targets.append((current_name, clean(recipe)))
        current_name = ""
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

    seen: set[str] = set()
    rows = []
    for name, definition in targets:
        if name in seen:
            continue
        seen.add(name)
        rows.append(
            (
                "Makefile",
                clean(name),
                str(makefile_path.resolve()),
                clean(definition),
                "make",
                runnable,
                availability,
                f"make {name}",
            )
        )
    return rows


def emit_just_tasks_for_file(source_id: str, path: pathlib.Path) -> list[tuple]:
    if not present_exact(path):
        return []
    runnable = command_available("just")
    availability = "available" if runnable else "missing-just"
    lines = path.read_text(encoding="utf-8").splitlines()
    recipes: list[tuple[str, str]] = []
    current_name = ""
    current_header = ""
    current_body: list[str] = []

    def flush() -> None:
        nonlocal current_name, current_header, current_body
        if not current_name:
            current_header = ""
            current_body = []
            return
        definition = " ; ".join(line for line in current_body if line)
        if not definition:
            definition = current_header
        recipes.append((current_name, clean(definition)))
        current_name = ""
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
        if stripped.startswith(("set ", "alias ", "export ", "import ", "mod ")):
            continue
        if ":=" in stripped or ":" not in stripped:
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

    seen: set[str] = set()
    rows = []
    for name, definition in sorted(recipes, key=lambda item: item[0]):
        if name in seen:
            continue
        seen.add(name)
        rows.append(
            (
                source_id,
                clean(name),
                str(path.resolve()),
                clean(definition),
                "just",
                runnable,
                availability,
                f"just --justfile {shlex.quote(str(path.resolve()))} {shlex.quote(name)}",
            )
        )
    return rows


def emit_taskfile_tasks_for_file(source_id: str, path: pathlib.Path) -> list[tuple]:
    if not present_exact(path):
        return []
    runnable = command_available("task")
    availability = "available" if runnable else "missing-task"
    lines = path.read_text(encoding="utf-8").splitlines()
    tasks: list[tuple[str, str]] = []
    current_name = ""
    current_block: list[str] = []
    in_tasks = False
    tasks_indent: int | None = None
    task_indent: int | None = None

    def indent_of(line: str) -> int:
        stripped = line.lstrip(" ")
        return len(line) - len(stripped)

    def flush() -> None:
        nonlocal current_name, current_block
        if not current_name:
            current_block = []
            return
        cmds: list[str] = []
        deps: list[str] = []
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
        current_name = ""
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
        if stripped and tasks_indent is not None and indent <= tasks_indent and not stripped.startswith("#"):
            flush()
            in_tasks = False
            tasks_indent = None
            task_indent = None
            if stripped == "tasks:":
                in_tasks = True
                tasks_indent = indent
            continue
        if stripped.endswith(":") and not stripped.startswith("- ") and tasks_indent is not None and indent > tasks_indent:
            if task_indent is None:
                task_indent = indent
            if indent == task_indent:
                flush()
                name = clean_scalar(stripped[:-1])
                if re.match(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$", name):
                    current_name = name
                    current_block = []
                    continue
                current_name = ""
                current_block = []
                continue
        if current_name:
            current_block.append(line)
    flush()

    seen: set[str] = set()
    rows = []
    for name, definition in sorted(tasks, key=lambda item: item[0]):
        if name in seen:
            continue
        seen.add(name)
        rows.append(
            (
                source_id,
                clean(name),
                str(path.resolve()),
                clean(definition),
                "task",
                runnable,
                availability,
                f"task --taskfile {shlex.quote(str(path.resolve()))} {shlex.quote(name)}",
            )
        )
    return rows


def build_native_discovery(root: pathlib.Path, workflows: list[dict]) -> dict:
    workflow_names = {entry.get("name", ""): entry.get("path", "") for entry in workflows}
    candidate_rows = []
    candidate_rows.extend(emit_package_tasks(root))
    candidate_rows.extend(emit_makefile_tasks(root))
    candidate_rows.extend(emit_just_tasks_for_file("Justfile", root / "Justfile"))
    candidate_rows.extend(emit_just_tasks_for_file("justfile", root / "justfile"))
    candidate_rows.extend(emit_taskfile_tasks_for_file("Taskfile.yml", root / "Taskfile.yml"))
    candidate_rows.extend(emit_taskfile_tasks_for_file("Taskfile.yaml", root / "Taskfile.yaml"))

    tasks = []
    runnable = 0
    workflow_conflicts = 0
    source_counts: dict[str, int] = {}
    for source_id, name, path, definition, runner_name, runnable_flag, availability, command in candidate_rows:
        category = native_task_category(name, command, definition)
        risk = classify_risk(f"{definition} {command}".strip())
        workflow_path = workflow_names.get(name, "")
        workflow_conflict = bool(workflow_path)
        task = {
            "id": f"{source_id}:{name}",
            "source": source_id,
            "name": name,
            "origin": f"{source_id}:{name}" if source_id != "package.json" else f"package.json:scripts.{name}",
            "path": path,
            "definition": definition,
            "runner": runner_name,
            "runnable": bool(runnable_flag),
            "availability": availability,
            "command": command,
            "category": category,
            "workflowConflict": workflow_conflict,
            "workflowPath": workflow_path,
            "risk": risk,
        }
        tasks.append(task)
        source_counts[source_id] = source_counts.get(source_id, 0) + 1
        if task["runnable"]:
            runnable += 1
        if task["workflowConflict"]:
            workflow_conflicts += 1

    sources = []
    for source_id, filename, support in SOURCE_SPECS:
        path = root / filename
        sources.append(
            {
                "id": source_id,
                "path": str(path.resolve()),
                "present": present_exact(path),
                "support": support,
                "taskCount": source_counts.get(source_id, 0),
            }
        )

    return {
        "schemaVersion": 1,
        "root": str(root.resolve()),
        "metadataSource": "remote-probe",
        "executionMode": "remote-exec",
        "policyMode": "remote-explicit",
        "limitations": [
            "Remote workflow trust is local-record-only and remote watch-mode is still blocked.",
            "Risk metadata for remote workflow plans comes from read-only probe heuristics instead of local allowlist state.",
        ],
        "sources": sources,
        "tasks": tasks,
        "summary": {
            "tasks": len(tasks),
            "runnable": runnable,
            "workflowConflicts": workflow_conflicts,
            "workflows": len(workflows),
        },
        "workflows": workflows,
    }


def devcontainer_spec_file(root: pathlib.Path) -> pathlib.Path | None:
    legacy = root / ".devcontainer.json"
    modern = root / ".devcontainer" / "devcontainer.json"
    if legacy.is_file():
        return legacy.resolve()
    if modern.is_file():
        return modern.resolve()
    return None


def devcontainer_cli_path(override: str) -> str:
    if override:
        return override
    resolved = shutil.which("devcontainer")
    return resolved or ""


def command_version(command_text: str) -> str:
    if not command_text:
        return ""
    try:
        output = subprocess.check_output(
            shlex.split(command_text) + ["--version"],
            stderr=subprocess.STDOUT,
            text=True,
        )
    except Exception:
        return ""
    return clean(output.splitlines()[0] if output else "")


def devcontainer_summary(spec_path: pathlib.Path) -> dict:
    data = load_json_file(spec_path)
    run_args = data.get("runArgs") or []
    mounts = data.get("mounts") or []
    workspace_mount = data.get("workspaceMount") or ""
    features = data.get("features") or {}
    unsafe: list[str] = []
    for arg in run_args:
        arg_text = str(arg)
        if arg_text == "--privileged":
            unsafe.append("runArgs:--privileged")
        if arg_text.startswith("--cap-add"):
            unsafe.append(f"runArgs:{arg_text}")
        if arg_text.startswith("--mount") and ("source=/" in arg_text or "src=/" in arg_text):
            unsafe.append(f"runArgs:{arg_text}")
    for mount in mounts:
        mount_text = str(mount)
        if "source=/" in mount_text or "src=/" in mount_text:
            unsafe.append(f"mount:{mount_text}")
    if isinstance(workspace_mount, str) and ("source=/" in workspace_mount or "src=/" in workspace_mount):
        unsafe.append(f"workspaceMount:{workspace_mount}")
    return {
        "name": clean(data.get("name") or spec_path.parent.parent.name),
        "workspaceFolder": clean(data.get("workspaceFolder") or ""),
        "remoteUser": clean(data.get("remoteUser") or ""),
        "containerUser": clean(data.get("containerUser") or ""),
        "dockerFile": clean(data.get("dockerFile") or ""),
        "image": clean(data.get("image") or ""),
        "dockerComposeFile": clean(data.get("dockerComposeFile") or ""),
        "service": clean(data.get("service") or ""),
        "mountsCount": len(mounts),
        "runArgsCount": len(run_args),
        "featuresCount": len(features.keys() if isinstance(features, dict) else []),
        "forwardPorts": [clean(item) for item in (data.get("forwardPorts") or []) if clean(item)],
        "unsafe": unsafe,
    }


def workflow_payload(requested_path: pathlib.Path) -> dict:
    root = find_project_root(requested_path)
    workflows = workflow_records(root)
    payload = build_native_discovery(root, workflows)
    payload["requestedPath"] = str(requested_path.resolve())
    return payload


def devcontainer_payload(requested_path: pathlib.Path, override_cli: str) -> dict:
    root = find_project_root(requested_path)
    spec = devcontainer_spec_file(root)
    cli = devcontainer_cli_path(override_cli)
    payload = {
        "root": str(root.resolve()),
        "requestedPath": str(requested_path.resolve()),
        "metadataSource": "remote-probe",
        "stateSource": "local-ide-state",
        "executionMode": "remote-lifecycle",
        "limitations": [
            "Remote devcontainer trust is local-record-only and tracked runtime state is still stored in local IDE state keyed by workspace identity.",
            "Status reports remote spec/CLI metadata plus local tracked state keyed by workspace identity.",
        ],
        "supported": spec is not None,
        "spec": str(spec) if spec else "",
        "cli": cli,
        "cliVersion": command_version(cli),
        "summary": {
            "workspaceFolder": "",
            "forwardPorts": [],
            "unsafe": [],
        },
    }
    if spec is not None:
        payload["summary"] = devcontainer_summary(spec)
    return payload


def detect_project_types(root: pathlib.Path) -> str:
    out: list[str] = []
    if (root / "package.json").is_file():
        append_unique(out, "node")
    if (root / "go.mod").is_file():
        append_unique(out, "go")
    if (root / "Cargo.toml").is_file():
        append_unique(out, "rust")
    if (root / "pyproject.toml").is_file() or (root / "requirements.txt").is_file() or (root / "setup.py").is_file():
        append_unique(out, "python")
    if (root / "Package.swift").is_file():
        append_unique(out, "swift")
    if (root / "build.zig").is_file():
        append_unique(out, "zig")
    if (root / "Makefile").is_file():
        append_unique(out, "make")
    return ",".join(out) if out else "generic"


def parse_semantic_target(raw_target: str) -> dict[str, str]:
    text = clean_scalar(raw_target)
    if not text:
        error("Remote debug target is empty.", 2)
    match = re.match(r"^(.*?)(?::([0-9]+)(?::([0-9]+))?)?$", text)
    if not match:
        error(f"Unable to resolve remote debug target: {raw_target}", 2)
    path_text = clean_scalar(match.group(1) or "")
    if not path_text:
        error(f"Unable to resolve remote debug target: {raw_target}", 2)
    line = clean_scalar(match.group(2) or "")
    column = clean_scalar(match.group(3) or "")
    return {
        "raw": text,
        "path": path_text,
        "line": line,
        "column": column,
    }


def location_display(path_text: str, line: str, column: str) -> str:
    if not line:
        return path_text
    if not column:
        column = "1"
    return f"{path_text}:{line}:{column}"


def debug_payload(requested_path: pathlib.Path, raw_target: str = "") -> dict:
    root = find_project_root(requested_path)
    payload = {
        "root": str(root.resolve()),
        "requestedPath": str(requested_path.resolve()),
        "metadataSource": "remote-probe",
        "projectTypes": detect_project_types(root),
        "available": {
            "python-pdb": command_available("python3"),
            "node-inspect": command_available("node"),
            "lldb": command_available("lldb"),
        },
        "target": None,
    }

    if not raw_target:
        return payload

    parsed = parse_semantic_target(raw_target)
    target_path = pathlib.Path(parsed["path"]).expanduser()
    absolute = target_path if target_path.is_absolute() else (root / target_path)
    try:
        absolute = absolute.resolve()
    except Exception:
        absolute = absolute
    if not absolute.exists():
        error(f"Remote debug target does not exist: {parsed['path']}", 2)
    relative = os.path.relpath(str(absolute), str(root))
    if relative == ".":
        relative = absolute.name
    if relative.startswith(".."):
        relative = str(absolute)

    payload["target"] = {
        "absolutePath": str(absolute),
        "entryPath": relative,
        "displayTarget": location_display(relative, parsed["line"], parsed["column"]),
        "line": int(parsed["line"]) if parsed["line"] else None,
        "column": int(parsed["column"]) if parsed["column"] else (1 if parsed["line"] else None),
        "extension": absolute.suffix.lower().lstrip("."),
        "isFile": absolute.is_file(),
        "isExecutable": os.access(str(absolute), os.X_OK),
    }
    return payload


def main() -> None:
    if len(sys.argv) < 3:
        error("Usage: remote-planning-probe.py <workflow|devcontainer|debug> <path> [extra...]", 64)
    action = sys.argv[1]
    requested = pathlib.Path(sys.argv[2]).expanduser()
    requested_abs = requested if requested.is_absolute() else pathlib.Path.cwd() / requested
    requested_abs = requested_abs.resolve()
    override_cli = sys.argv[3] if len(sys.argv) > 3 else ""

    if action == "workflow":
        print(json.dumps(workflow_payload(requested_abs), indent=2, sort_keys=True))
        return
    if action == "devcontainer":
        print(json.dumps(devcontainer_payload(requested_abs, override_cli), indent=2, sort_keys=True))
        return
    if action == "debug":
        raw_target = sys.argv[3] if len(sys.argv) > 3 else ""
        print(json.dumps(debug_payload(requested_abs, raw_target), indent=2, sort_keys=True))
        return
    error(f"Unknown action: {action}", 64)


if __name__ == "__main__":
    main()
