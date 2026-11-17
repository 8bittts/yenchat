# shellcheck shell=bash
# Source-time pure workspace-capability helpers and command handlers for yen ide.

vscode_import_lock_dir() {
    local root="$1"
    printf "%s/vscode-locks/%s.lock\n" "${IDE_STATE_DIR}" "$(project_hash_for_root "${root}")"
}

vscode_inventory_json() {
    local root="$1"
    python3 - "${root}" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]).resolve()
workspace = root / ".vscode"
import_dir = root / ".yen" / "vscode-import"
workflow_dir = root / ".yen" / "workflows"

def load_jsonc(path):
    raw = path.read_text(encoding="utf-8")
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
    return json.loads("".join(result))

fixed_shortcuts = {
    "cmd+shift+p": "yen.command_palette",
    "cmd+shift+o": "yen.file_browser",
    "cmd+,": "yen.settings",
    "cmd+shift+b": "yen.toggle_tab_sidebar",
}
keybinding_map = {
    "workbench.action.showCommands": "yen.command_palette",
    "workbench.action.quickOpen": "yen.file_browser",
    "workbench.action.terminal.focus": "yen.focus_terminal",
    "workbench.action.toggleSidebarVisibility": "yen.toggle_tab_sidebar",
}
supported_settings = {
    "editor.insertSpaces",
    "editor.tabSize",
    "editor.wordWrap",
    "files.exclude",
    "search.exclude",
}
extension_exact = {
    "github.vscode-pull-request-github": {
        "bucket": "partial",
        "reason": "yen-pr-review-baseline",
        "detail": "YEN ships a PR review baseline, but not the full GitHub extension surface.",
        "migrationTarget": "yen ide pr-review",
        "manualAction": "Review any GitHub-only review panes or browser integrations that still depend on the VS Code extension.",
    },
    "ms-vscode-remote.remote-containers": {
        "bucket": "supported",
        "reason": "yen-devcontainer-built-in",
        "detail": "YEN ships a built-in devcontainer control plane for local workspaces.",
        "migrationTarget": "yen ide devcontainer",
        "manualAction": "",
    },
    "ms-vscode.js-debug": {
        "bucket": "partial",
        "reason": "node-debugger-baseline",
        "detail": "YEN ships a local node inspect debugger baseline, but not the full VS Code JavaScript debugger surface.",
        "migrationTarget": "yen ide debug",
        "manualAction": "Run yen ide debug status to confirm local JavaScript entry-file readiness; keep VS Code for richer browser, attach, or TypeScript debugger workflows.",
    },
    "ms-vscode.js-debug-nightly": {
        "bucket": "partial",
        "reason": "node-debugger-baseline",
        "detail": "YEN ships a local node inspect debugger baseline, but not the full VS Code JavaScript debugger surface.",
        "migrationTarget": "yen ide debug",
        "manualAction": "Run yen ide debug status to confirm local JavaScript entry-file readiness; keep VS Code for richer browser, attach, or TypeScript debugger workflows.",
    },
}
extension_prefixes = [
    (
        "ms-python.",
        {
            "bucket": "partial",
            "reason": "python-language-baseline",
            "detail": "YEN ships Python LSP/AST baselines, but not full VS Code Python extension parity.",
            "migrationTarget": "yen ide lsp",
            "manualAction": "Run yen ide debug status to confirm local Python debugger readiness; keep VS Code for richer debugger, test, or editor-only Python workflows.",
        },
    ),
    (
        "golang.",
        {
            "bucket": "partial",
            "reason": "go-language-baseline",
            "detail": "YEN ships Go LSP support, but not the full VS Code Go extension surface.",
            "migrationTarget": "yen ide lsp",
            "manualAction": "Run yen ide debug status to confirm the executable-only baseline; keep VS Code or Delve for package, test, or editor-only Go debugger workflows.",
        },
    ),
    (
        "rust-lang.",
        {
            "bucket": "partial",
            "reason": "rust-language-baseline",
            "detail": "YEN ships Rust LSP support, but not the full VS Code Rust extension surface.",
            "migrationTarget": "yen ide lsp",
            "manualAction": "Run yen ide debug status to confirm the executable-only baseline; keep VS Code or CodeLLDB for package, test, or editor-only Rust debugger workflows.",
        },
    ),
    (
        "redhat.",
        {
            "bucket": "partial",
            "reason": "schema-language-baseline",
            "detail": "YEN ships baseline YAML/JSON language tooling, but not the full VS Code extension surface.",
            "migrationTarget": "yen ide lsp",
            "manualAction": "Review editor-specific validation or schema helpers that still rely on VS Code.",
        },
    ),
    (
        "tamasfe.",
        {
            "bucket": "partial",
            "reason": "schema-language-baseline",
            "detail": "YEN ships baseline TOML tooling, but not the full VS Code extension surface.",
            "migrationTarget": "yen ide lsp",
            "manualAction": "Review editor-specific validation or schema helpers that still rely on VS Code.",
        },
    ),
]

def classify_extension(extension_id):
    if extension_id in extension_exact:
        return extension_exact[extension_id]
    for prefix, guidance in extension_prefixes:
        if extension_id.startswith(prefix):
            return guidance
    if ".theme-" in extension_id or extension_id.endswith("-theme") or ".icons-" in extension_id:
        return {
            "bucket": "unsupported",
            "reason": "editor-theme-extension",
            "detail": "YEN does not import editor theme or icon-pack extensions.",
            "migrationTarget": "",
            "manualAction": "Keep this recommendation in VS Code or configure your editor separately.",
        }
    return {
        "bucket": "unsupported",
        "reason": "no-yen-migration-target",
        "detail": "YEN does not have a shipped migration target for this extension recommendation yet.",
        "migrationTarget": "",
        "manualAction": "Keep this recommendation in VS Code or review whether a repo-native CLI already covers the workflow.",
    }

def slugify(value):
    return re.sub(r"[^a-z0-9]+", "-", str(value or "").lower()).strip("-") or "task"

def load_package_scripts(root):
    package_path = root / "package.json"
    if not package_path.exists():
        return {}
    try:
        payload = json.loads(package_path.read_text(encoding="utf-8"))
    except Exception:
        return {}
    scripts = payload.get("scripts")
    return scripts if isinstance(scripts, dict) else {}

def load_make_targets(root):
    makefile_path = root / "Makefile"
    if not makefile_path.exists():
        return set()
    targets = set()
    try:
        lines = makefile_path.read_text(encoding="utf-8").splitlines()
    except Exception:
        return targets
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("."):
            continue
        match = re.match(r"^([A-Za-z0-9_.-]+)\s*:", stripped)
        if match:
            targets.add(match.group(1))
    return targets

def repo_signal_for_command(command, package_scripts, make_targets):
    command_text = str(command or "").strip()
    script_match = re.match(r"^(?:bun|npm|pnpm|yarn)\s+(?:run\s+)?([A-Za-z0-9:_-]+)$", command_text)
    if script_match:
        script_name = script_match.group(1)
        if script_name in package_scripts:
            return f"package.json:scripts.{script_name}"
    make_match = re.match(r"^make\s+([A-Za-z0-9_.-]+)$", command_text)
    if make_match:
        target = make_match.group(1)
        if target in make_targets:
            return f"Makefile:{target}"
    return ""

def repo_test_signals(root, package_scripts, make_targets):
    signals = []
    for script_name in sorted(package_scripts.keys()):
        if script_name == "test" or script_name.startswith("test:"):
            signals.append(f"package.json:scripts.{script_name}")
    if "test" in make_targets:
        signals.append("Makefile:test")
    if (root / "go.mod").exists():
        signals.append("go.mod:go test ./...")
    if (root / "Cargo.toml").exists():
        signals.append("Cargo.toml:cargo test --all-targets")
    if (root / "pyproject.toml").exists():
        signals.append("pyproject.toml:pytest")
    if (root / "Package.swift").exists():
        signals.append("Package.swift:swift test")
    if (root / "build.zig").exists():
        signals.append("build.zig:zig build test")
    return signals

def task_looks_like_test(task):
    haystack = " ".join([str(task.get("label") or ""), str(task.get("command") or "")]).lower()
    test_markers = (
        " test",
        "test ",
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
    return any(marker in haystack for marker in test_markers) or haystack.startswith("test")

def append_manual_cleanup(checklist, key, detail):
    if key in checklist["seen"]:
        return
    checklist["seen"].add(key)
    checklist["items"].append({
        "id": key,
        "detail": detail,
    })

report = {
    "schemaVersion": 1,
    "root": str(root),
    "workspace": str(workspace),
    "present": workspace.exists(),
    "artifacts": {
        "importDir": str(import_dir),
        "workflowDir": str(workflow_dir),
    },
    "categories": {
        "keybindings": {"supported": [], "partial": [], "unsupported": []},
        "tasks": {"supported": [], "partial": [], "unsupported": []},
        "settings": {"supported": [], "partial": [], "unsupported": []},
        "snippets": {"supported": [], "partial": [], "unsupported": []},
        "extensions": {"supported": [], "partial": [], "unsupported": []},
    },
    "summary": {"supported": 0, "partial": 0, "unsupported": 0},
    "migration": {
        "coverage": {
            "extensions": "classified",
            "taskParity": "derived",
            "testParity": "derived",
            "manualCleanupChecklist": "derived",
        },
        "unsupportedInventory": [],
        "extensionRecommendations": {
            "recommended": 0,
            "unwanted": 0,
            "unwantedRecommendations": [],
        },
        "taskParityNotes": [],
        "testParityNotes": [],
        "manualCleanupChecklist": [],
    },
}

def record(category, bucket, item):
    report["categories"][category][bucket].append(item)
    report["summary"][bucket] += 1
    if bucket in {"partial", "unsupported"}:
        report["migration"]["unsupportedInventory"].append({
            "category": category,
            "status": bucket,
            "item": item,
        })

if not workspace.exists():
    print(json.dumps(report, indent=2, sort_keys=True))
    raise SystemExit(0)

keybindings_path = workspace / "keybindings.json"
if keybindings_path.exists():
    for entry in load_jsonc(keybindings_path):
        key = str(entry.get("key") or "").lower()
        command = entry.get("command") or ""
        mapped = keybinding_map.get(command)
        item = {
            "key": key,
            "command": command,
            "mappedCommand": mapped or "",
            "when": entry.get("when") or "",
            "conflict": fixed_shortcuts.get(key) or "",
            "reason": "",
            "migrationTarget": mapped or "",
            "manualAction": "",
        }
        if mapped and not item["when"]:
            item["reason"] = "direct-command-mapping"
            if item["conflict"]:
                item["manualAction"] = "Review this binding because the key overlaps with a fixed YEN shortcut."
            record("keybindings", "supported", item)
        elif mapped:
            item["reason"] = "conditional-when-clause"
            item["manualAction"] = "YEN does not preserve VS Code when-clause context; review this binding manually."
            record("keybindings", "partial", item)
        else:
            item["reason"] = "unsupported-vscode-command"
            item["manualAction"] = "Keep this binding in VS Code or map it manually in your editor."
            record("keybindings", "unsupported", item)

tasks_path = workspace / "tasks.json"
if tasks_path.exists():
    for task in (load_jsonc(tasks_path).get("tasks") or []):
        item = {
            "label": task.get("label") or "",
            "type": task.get("type") or "shell",
            "command": task.get("command") or "",
            "detail": task.get("detail") or "",
            "dependsOn": task.get("dependsOn") or [],
            "problemMatcher": task.get("problemMatcher") or [],
            "presentation": task.get("presentation") or {},
            "reason": "",
            "migrationTarget": "yen ide workflow",
            "manualAction": "",
        }
        if item["type"] in {"shell", "process"} and item["command"] and not item["dependsOn"] and not item["problemMatcher"] and not item["presentation"]:
            item["reason"] = "simple-command-task"
            record("tasks", "supported", item)
        elif item["command"]:
            item["reason"] = "composite-or-editor-managed-task"
            item["manualAction"] = "Split dependencies/problem matchers into separate YEN workflows or keep the VS Code task as reference."
            record("tasks", "partial", item)
        else:
            item["reason"] = "missing-command"
            item["manualAction"] = "Add a runnable command before trying to import this task into YEN."
            record("tasks", "unsupported", item)

settings_path = workspace / "settings.json"
if settings_path.exists():
    settings = load_jsonc(settings_path)
    for key, value in sorted(settings.items()):
        item = {
            "key": key,
            "value": value,
            "reason": "",
            "migrationTarget": "",
            "manualAction": "",
        }
        if key in supported_settings:
            item["reason"] = "direct-setting-import"
            item["migrationTarget"] = ".yen/vscode-import/settings.json"
            record("settings", "supported", item)
        elif key.startswith("terminal.integrated."):
            item["reason"] = "terminal-preference-manual-review"
            item["manualAction"] = "Recreate terminal preferences manually in YEN or the target editor."
            record("settings", "partial", item)
        else:
            item["reason"] = "editor-or-workbench-setting"
            item["manualAction"] = "Keep this setting in VS Code or migrate it manually in the target editor."
            record("settings", "unsupported", item)

for snippet_path in sorted(workspace.glob("*.code-snippets")):
    snippets = load_jsonc(snippet_path)
    for name, definition in sorted(snippets.items()):
        prefix_value = definition.get("prefix")
        prefixes = []
        if isinstance(prefix_value, list):
            prefixes = [str(value) for value in prefix_value if value]
        elif prefix_value:
            prefixes = [str(prefix_value)]
        item = {
            "file": snippet_path.name,
            "name": name,
            "prefix": prefixes[0] if prefixes else "",
            "prefixes": prefixes,
            "scope": definition.get("scope") or "",
            "description": definition.get("description") or "",
            "body": definition.get("body"),
            "reason": "",
            "migrationTarget": "",
            "manualAction": "",
        }
        body = item["body"]
        if item["prefix"] and isinstance(body, (list, str)) and not item["scope"] and len(item["prefixes"]) == 1:
            item["reason"] = "direct-snippet-copy"
            item["migrationTarget"] = ".yen/vscode-import/snippets/*.json"
            record("snippets", "supported", item)
        elif item["prefix"] and isinstance(body, (list, str)):
            item["reason"] = "scoped-or-multi-prefix-snippet"
            item["manualAction"] = "Review snippet scope/prefix behavior manually after import."
            record("snippets", "partial", item)
        else:
            item["reason"] = "invalid-snippet-definition"
            item["manualAction"] = "Fix the snippet prefix/body before importing it into YEN."
            record("snippets", "unsupported", item)

extensions_path = workspace / "extensions.json"
if extensions_path.exists():
    extensions = load_jsonc(extensions_path)
    recommendations = [str(value) for value in (extensions.get("recommendations") or []) if value]
    unwanted = [str(value) for value in (extensions.get("unwantedRecommendations") or []) if value]
    report["migration"]["extensionRecommendations"]["recommended"] = len(recommendations)
    report["migration"]["extensionRecommendations"]["unwanted"] = len(unwanted)
    report["migration"]["extensionRecommendations"]["unwantedRecommendations"] = unwanted
    for extension_id in recommendations:
        guidance = classify_extension(extension_id)
        item = {
            "id": extension_id,
            "kind": "recommendation",
            "reason": guidance["reason"],
            "detail": guidance["detail"],
            "migrationTarget": guidance["migrationTarget"],
            "manualAction": guidance["manualAction"],
        }
        record("extensions", guidance["bucket"], item)

package_scripts = load_package_scripts(root)
make_targets = load_make_targets(root)
for bucket, parity_status in (("supported", "mapped"), ("partial", "partial"), ("unsupported", "manual")):
    for task in report["categories"]["tasks"][bucket]:
        label = task.get("label") or "(unnamed task)"
        target = ""
        detail = ""
        repo_signal = repo_signal_for_command(task.get("command"), package_scripts, make_targets)
        if parity_status == "mapped":
            target = f".yen/workflows/vscode-task-{slugify(label)}.toml"
            detail = "Imports cleanly as a deterministic YEN workflow shim."
        elif parity_status == "partial":
            target = "yen ide workflow"
            detail = "Needs manual cleanup before it behaves like a YEN workflow."
        else:
            target = "yen ide workflow"
            detail = "Does not map to a runnable YEN workflow without manual repair."
        if repo_signal:
            detail = f"{detail} Command matches {repo_signal}."
        report["migration"]["taskParityNotes"].append({
            "source": f"task:{label}",
            "status": parity_status,
            "reason": task.get("reason") or "",
            "detail": detail,
            "migrationTarget": target,
            "repoSignal": repo_signal,
            "manualAction": task.get("manualAction") or "",
        })

test_tasks = []
for bucket in ("supported", "partial", "unsupported"):
    for task in report["categories"]["tasks"][bucket]:
        if task_looks_like_test(task):
            test_tasks.append((bucket, task))

for bucket, task in test_tasks:
    label = task.get("label") or "(unnamed task)"
    repo_signal = repo_signal_for_command(task.get("command"), package_scripts, make_targets)
    status = "mapped" if bucket == "supported" else "partial" if bucket == "partial" else "manual"
    detail = "This VS Code test task can move into YEN with the same baseline as other imported tasks."
    if status == "partial":
        detail = "This VS Code test task needs manual cleanup before it fits the YEN workflow/test baseline."
    elif status == "manual":
        detail = "This VS Code test task does not map cleanly into the YEN workflow/test baseline."
    if repo_signal:
        detail = f"{detail} Command matches {repo_signal}."
    report["migration"]["testParityNotes"].append({
        "source": f"task:{label}",
        "status": status,
        "reason": task.get("reason") or "",
        "detail": detail,
        "migrationTarget": "yen ide verify --quick" if repo_signal else "yen ide workflow",
        "repoSignal": repo_signal,
        "manualAction": task.get("manualAction") or "",
        })

if not report["migration"]["testParityNotes"]:
    signals = repo_test_signals(root, package_scripts, make_targets)
    if signals:
        report["migration"]["testParityNotes"].append({
            "source": signals[0],
            "status": "native",
            "reason": "repo-native-test-signal",
            "detail": "The repo already exposes a native test command, so YEN can rely on verify/workflow without a VS Code test task.",
            "migrationTarget": "yen ide verify --quick",
            "repoSignal": signals[0],
            "manualAction": "",
        })
    else:
        report["migration"]["testParityNotes"].append({
            "source": "workspace",
            "status": "manual",
            "reason": "no-test-signal-detected",
            "detail": "No repo-native test command or VS Code test task was detected; add a test script or workflow manually.",
            "migrationTarget": "yen ide workflow",
            "repoSignal": "",
            "manualAction": "Add a repo-native test command before depending on YEN test workflows.",
        })

manual_cleanup = {"seen": set(), "items": []}
keybinding_manual = len(report["categories"]["keybindings"]["partial"]) + len(report["categories"]["keybindings"]["unsupported"])
if keybinding_manual:
    append_manual_cleanup(
        manual_cleanup,
        "keybindings-manual-review",
        f"Review {keybinding_manual} keybinding(s) with VS Code-only context or unsupported commands before dropping the old editor setup.",
    )
task_manual = len(report["categories"]["tasks"]["partial"]) + len(report["categories"]["tasks"]["unsupported"])
if task_manual:
    append_manual_cleanup(
        manual_cleanup,
        "tasks-manual-review",
        f"Split or rewrite {task_manual} VS Code task(s) before relying on them as YEN workflows.",
    )
settings_manual = len(report["categories"]["settings"]["partial"]) + len(report["categories"]["settings"]["unsupported"])
if settings_manual:
    append_manual_cleanup(
        manual_cleanup,
        "settings-manual-review",
        f"Recreate {settings_manual} VS Code setting(s) manually in YEN or the target editor.",
    )
snippet_manual = len(report["categories"]["snippets"]["partial"]) + len(report["categories"]["snippets"]["unsupported"])
if snippet_manual:
    append_manual_cleanup(
        manual_cleanup,
        "snippets-manual-review",
        f"Review {snippet_manual} snippet definition(s) for scope, prefix, or body differences after import.",
    )
extension_manual = (
    len(report["categories"]["extensions"]["partial"])
    + len(report["categories"]["extensions"]["unsupported"])
    + int(report["migration"]["extensionRecommendations"]["unwanted"] or 0)
)
if extension_manual:
    append_manual_cleanup(
        manual_cleanup,
        "extensions-manual-review",
        f"Keep, replace, or drop {extension_manual} VS Code extension recommendation(s) manually; YEN does not fully cover them yet.",
    )
test_manual = sum(1 for note in report["migration"]["testParityNotes"] if note.get("status") in {"partial", "manual"})
if test_manual:
    append_manual_cleanup(
        manual_cleanup,
        "tests-manual-review",
        f"Decide how to run {test_manual} partial/manual test path(s) inside YEN before removing VS Code-specific setup.",
    )
report["migration"]["manualCleanupChecklist"] = manual_cleanup["items"]

print(json.dumps(report, indent=2, sort_keys=True))
PY
}

vscode_import_plan_json() {
    local root="$1"
    local inventory=""
    if ! inventory=$(vscode_inventory_json "${root}" 2>&1); then
        printf "%s\n" "${inventory}"
        return 1
    fi
    python3 - "${inventory}" <<'PY'
import json
import pathlib
import re
import sys

report = json.loads(sys.argv[1] or "{}")
root = pathlib.Path(report.get("root") or ".").resolve()
artifacts = report.get("artifacts") or {}
import_dir = pathlib.Path(artifacts.get("importDir") or (root / ".yen" / "vscode-import"))
workflow_dir = pathlib.Path(artifacts.get("workflowDir") or (root / ".yen" / "workflows"))
categories = report.get("categories") or {}

def slugify(value):
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-") or "task"

def toml_string(value):
    text = str(value or "")
    text = text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
    return f"\"{text}\""

plan = {
    "schemaVersion": report.get("schemaVersion", 1),
    "report": report,
    "summary": report.get("summary") or {"supported": 0, "partial": 0, "unsupported": 0},
    "writes": [],
}
if not report.get("present"):
    print(json.dumps(plan, indent=2, sort_keys=True))
    raise SystemExit(0)

keybinding_entries = []
for bucket in ("supported", "partial"):
    for entry in (categories.get("keybindings") or {}).get(bucket, []):
        keybinding_entries.append({
            "sourceCommand": entry.get("command") or "",
            "yenCommand": entry.get("mappedCommand") or "",
            "key": entry.get("key") or "",
            "when": entry.get("when") or "",
            "conflict": entry.get("conflict") or "",
        })
if keybinding_entries:
    plan["writes"].append({
        "path": str(import_dir / "keybindings.json"),
        "content": json.dumps(keybinding_entries, indent=2, sort_keys=True) + "\n",
        "category": "keybindings",
    })

for task in (categories.get("tasks") or {}).get("supported", []):
    label = task.get("label") or ""
    command = task.get("command") or ""
    body = "\n".join([
        'schema_version = 1',
        f"name = {toml_string(label)}",
        f"step = {toml_string(command)}",
        "",
    ])
    plan["writes"].append({
        "path": str(workflow_dir / f"vscode-task-{slugify(label)}.toml"),
        "content": body,
        "category": "tasks",
    })

settings_payload = {}
for entry in (categories.get("settings") or {}).get("supported", []):
    settings_payload[entry.get("key") or ""] = entry.get("value")
if settings_payload:
    plan["writes"].append({
        "path": str(import_dir / "settings.json"),
        "content": json.dumps(settings_payload, indent=2, sort_keys=True) + "\n",
        "category": "settings",
    })

snippets_by_target = {}
for entry in (categories.get("snippets") or {}).get("supported", []):
    target = entry.get("file") or "snippets.json"
    payload = snippets_by_target.setdefault(target, {})
    payload[entry.get("name") or "snippet"] = {
        "prefix": entry.get("prefix") or "",
        "body": entry.get("body"),
        "description": entry.get("description") or "",
    }
for target, payload in sorted(snippets_by_target.items()):
    plan["writes"].append({
        "path": str(import_dir / "snippets" / target.replace(".code-snippets", ".json")),
        "content": json.dumps(payload, indent=2, sort_keys=True) + "\n",
        "category": "snippets",
    })

plan["writes"].append({
    "path": str(import_dir / "migration-report.json"),
    "content": json.dumps(report, indent=2, sort_keys=True) + "\n",
    "category": "migration-report",
})

checklist_items = ((report.get("migration") or {}).get("manualCleanupChecklist") or [])
checklist_lines = ["Manual cleanup still required", ""]
if checklist_items:
    for item in checklist_items:
        checklist_lines.append(f"- {item.get('detail') or ''}")
else:
    checklist_lines.append("- No manual cleanup required.")
plan["writes"].append({
    "path": str(import_dir / "manual-cleanup.txt"),
    "content": "\n".join(checklist_lines) + "\n",
    "category": "migration-checklist",
})

plan["writes"].sort(key=lambda item: item["path"])
print(json.dumps(plan, indent=2, sort_keys=True))
PY
}

cmd_vscode_inventory() {
    local target=""
    local format="text"
    local root=""
    local inventory=""

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

    root=$(find_project_root "${target}")
    inventory=$(vscode_inventory_json "${root}")
    case "${format}" in
        json)
            printf "%s\n" "${inventory}"
            ;;
        text)
            python3 - "${inventory}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
categories = payload.get("categories") or {}
migration = payload.get("migration") or {}
extension_recommendations = migration.get("extensionRecommendations") or {}

def note_counts(notes):
    counts = {}
    for note in notes:
        status = note.get("status") or "unknown"
        counts[status] = counts.get(status, 0) + 1
    return counts

def format_note_counts(counts, order):
    parts = []
    for status in order:
        if status in counts:
            parts.append(f"{status}={counts[status]}")
    return " ".join(parts)

print("")
print("IDE VS Code Inventory")
print(f"Root:       {payload['root']}")
print(f"Workspace:  {payload['workspace']}")
print(f"Present:    {'yes' if payload['present'] else 'no'}")
if extension_recommendations.get("recommended") or extension_recommendations.get("unwanted"):
    print(
        f"Ext recs:   recommended={extension_recommendations.get('recommended', 0)} "
        f"unwanted={extension_recommendations.get('unwanted', 0)}"
    )
task_note_counts = note_counts(migration.get("taskParityNotes") or [])
test_note_counts = note_counts(migration.get("testParityNotes") or [])
if task_note_counts:
    print(f"Task parity: {format_note_counts(task_note_counts, ('mapped', 'partial', 'manual'))}")
if test_note_counts:
    print(f"Test parity: {format_note_counts(test_note_counts, ('mapped', 'partial', 'native', 'manual'))}")
for category in ("keybindings", "tasks", "settings", "snippets", "extensions"):
    info = categories.get(category) or {"supported": [], "partial": [], "unsupported": []}
    print(f"{category.capitalize():<11} supported={len(info['supported'])} partial={len(info['partial'])} unsupported={len(info['unsupported'])}")
print("")
for category in ("keybindings", "tasks", "settings", "snippets", "extensions"):
    info = categories.get(category) or {"supported": [], "partial": [], "unsupported": []}
    samples = info["supported"][:2] + info["partial"][:2] + info["unsupported"][:2]
    if not samples:
        continue
    print(category.capitalize())
    for item in samples:
        print(f"  - {json.dumps(item, sort_keys=True)}")
    print("")
PY
            ;;
        *)
            yen_error "Unknown vscode inventory format: ${format} (expected text|json)"
            return 1
            ;;
    esac
}

cmd_vscode_import() {
    local target=""
    local dry_run="0"
    local root=""
    local plan=""
    local report=""
    local lock_dir=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project|--path)
                shift
                target="${1:-}"
                ;;
            --dry-run)
                dry_run="1"
                ;;
            *)
                target="$1"
                ;;
        esac
        shift
    done

    root=$(find_project_root "${target}")
    lock_dir=$(vscode_import_lock_dir "${root}")
    if ! acquire_state_lock "${lock_dir}" "VS Code import"; then
        return 1
    fi
    if ! plan=$(vscode_import_plan_json "${root}" 2>&1); then
        release_state_lock "${lock_dir}"
        yen_error "VS Code import planning failed for ${root}: ${plan}"
        return 1
    fi
    if ! report=$(python3 - "${plan}" "${dry_run}" <<'PY'
import difflib
import json
import os
import pathlib
import sys
import tempfile

plan = json.loads(sys.argv[1] or "{}")
dry_run = sys.argv[2] == "1"
writes = plan.get("writes") or []
lines = []

def write_text_atomic(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".yen-vscode-import-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        pathlib.Path(tmp_path).replace(path)
    finally:
        try:
            pathlib.Path(tmp_path).unlink(missing_ok=True)
        except OSError:
            pass

for item in writes:
    path = pathlib.Path(item["path"])
    content = item["content"]
    if path.exists():
        existing = path.read_text(encoding="utf-8")
        status = "unchanged" if existing == content else "update"
    else:
        existing = ""
        status = "create"
    diff_text = "".join(
        difflib.unified_diff(
            existing.splitlines(keepends=True),
            content.splitlines(keepends=True),
            fromfile=f"{path} (before)",
            tofile=str(path),
            lineterm="",
        )
    )
    lines.append((status, item["category"], str(path), content, diff_text))
if not dry_run:
    for status, _category, path_text, content, _diff_text in lines:
        path = pathlib.Path(path_text)
        write_text_atomic(path, content)
print(json.dumps({
    "schemaVersion": plan.get("schemaVersion", 1),
    "report": plan.get("report") or {},
    "summary": plan.get("summary") or {},
    "writes": [
        {"status": status, "category": category, "path": path, "diff": diff_text}
        for status, category, path, _content, diff_text in lines
    ],
}, indent=2, sort_keys=True))
PY
); then
    release_state_lock "${lock_dir}"
        yen_error "VS Code import planning failed for ${root}."
        return 1
    fi
    release_state_lock "${lock_dir}"
    echo ""
    yen_header "IDE VS Code Import"
    echo "Root:      ${root}"
    echo "Dry run:   $( [[ "${dry_run}" == "1" ]] && printf "yes" || printf "no" )"
    printf "%s\n" "${report}"
    echo ""
    if [[ "${dry_run}" != "1" ]]; then
        timeline_log "vscode-import" "${root}" "applied" "writes=$(printf "%s\n" "${report}" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get(\"writes\", [])))')"
    fi
}

cmd_vscode() {
    local sub="${1:-inventory}"
    shift || true
    case "${sub}" in
        inventory)
            cmd_vscode_inventory "$@"
            ;;
        import)
            cmd_vscode_import "$@"
            ;;
        *)
            yen_error "Unknown vscode subcommand: ${sub}"
            return 1
            ;;
    esac
}
