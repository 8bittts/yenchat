# shellcheck shell=bash
# Source-time pure review-routing helpers shared by search, merge-readiness, and PR review.

review_context_json_for_targets() {
    local root="$1"
    shift || true
    local payload=""
    local debug_targets=""
    local debug_target=""
    local debug_row=""
    local debug_rows=""

    payload=$(REVIEW_CONTEXT_ROOT="${root}" python3 - "$@" <<'PY'
import json
import os
import pathlib
import shlex
import subprocess
import sys
from fnmatch import fnmatchcase


def run_command(args, cwd):
    try:
        completed = subprocess.run(
            args,
            cwd=cwd or None,
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return 127, "", ""
    return completed.returncode, completed.stdout, completed.stderr


def clean(value):
    return str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()


def parse_target(target):
    raw = target or ""
    parts = raw.rsplit(":", 2)
    if len(parts) == 3 and parts[1].isdigit() and parts[2].isdigit():
        return parts[0], int(parts[1]), int(parts[2])
    parts = raw.rsplit(":", 1)
    if len(parts) == 2 and parts[1].isdigit():
        return parts[0], int(parts[1]), None
    return raw, None, None


def resolve_target(root, target):
    raw_path, line, column = parse_target(target)
    raw_path = raw_path.strip()
    root_path = pathlib.Path(root).expanduser().resolve()
    if raw_path.startswith("/"):
        absolute = pathlib.Path(raw_path).expanduser()
    else:
        absolute = root_path / raw_path
    try:
        absolute = absolute.resolve()
    except Exception:
        absolute = absolute

    relative = clean(raw_path)
    try:
        relative = absolute.relative_to(root_path).as_posix()
    except Exception:
        if raw_path:
            relative = clean(raw_path).replace("\\", "/")
        else:
            relative = absolute.as_posix()

    normalized = relative
    if line is not None:
        normalized = f"{normalized}:{line}"
        if column is not None:
            normalized = f"{normalized}:{column}"

    return {
        "target": clean(target),
        "path": relative or ".",
        "absolutePath": absolute.as_posix(),
        "line": line,
        "column": column,
        "normalizedTarget": normalized,
    }


def codeowners_candidates(root_path):
    return [
        root_path / ".github" / "CODEOWNERS",
        root_path / "CODEOWNERS",
        root_path / "docs" / "CODEOWNERS",
    ]


def load_codeowners(root_path):
    codeowners_path = None
    for candidate in codeowners_candidates(root_path):
        if candidate.is_file():
            codeowners_path = candidate.resolve()
            break

    rules = []
    if not codeowners_path:
        return None, rules

    for raw in codeowners_path.read_text(encoding="utf-8").splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        try:
            parts = shlex.split(raw, comments=True)
        except Exception:
            parts = stripped.split()
        if len(parts) < 2:
            continue
        pattern = parts[0].strip()
        owners = [clean(owner) for owner in parts[1:] if clean(owner)]
        if not pattern or not owners or pattern.startswith("!"):
            continue
        rules.append({"pattern": pattern, "owners": owners})

    return codeowners_path, rules


def match_codeowners(pattern, rel_path):
    candidate = rel_path.lstrip("/")
    if not candidate:
        return False

    normalized = pattern.strip()
    if not normalized:
        return False

    anchored = normalized.startswith("/")
    if anchored:
        normalized = normalized[1:]
    normalized = normalized.replace("\\ ", " ")
    if normalized.endswith("/"):
        normalized = f"{normalized}**"

    path_obj = pathlib.PurePosixPath(candidate)
    path_text = path_obj.as_posix()
    base_name = path_obj.name

    patterns = [normalized]
    if not anchored and "/" not in normalized:
        patterns.append(f"**/{normalized}")
    for candidate_pattern in patterns:
        if fnmatchcase(base_name, candidate_pattern):
            return True
        try:
            if path_obj.match(candidate_pattern):
                return True
        except Exception:
            pass
        if fnmatchcase(path_text, candidate_pattern):
            return True
    return False


def owners_for_path(rel_path, rules):
    owners = []
    for rule in rules:
        if match_codeowners(rule["pattern"], rel_path):
            owners = list(rule["owners"])
    return owners


def history_for_path(root, rel_path):
    code, out, _ = run_command(
        [
            "git",
            "log",
            "--max-count",
            "3",
            "--date=short",
            "--format=%H%x09%an%x09%ad%x09%s",
            "--",
            rel_path,
        ],
        cwd=root,
    )
    if code != 0:
        return []

    history = []
    for raw in out.splitlines():
        parts = raw.split("\t", 3)
        if len(parts) != 4:
            continue
        sha, author, date_text, subject = parts
        history.append(
            {
                "sha": clean(sha),
                "shortSha": clean(sha)[:8],
                "author": clean(author),
                "date": clean(date_text),
                "subject": clean(subject),
            }
        )
    return history


def blame_for_target(root, rel_path, line):
    if line is None:
        return {}
    code, out, _ = run_command(
        [
            "git",
            "blame",
            "-L",
            f"{line},{line}",
            "--porcelain",
            "--",
            rel_path,
        ],
        cwd=root,
    )
    if code != 0 or not out:
        return {}

    result = {"line": line}
    first_line = out.splitlines()[0] if out.splitlines() else ""
    if first_line:
        sha = first_line.split(" ", 1)[0]
        result["sha"] = clean(sha)
        result["shortSha"] = clean(sha)[:8]

    for raw in out.splitlines()[1:]:
        if raw.startswith("\t"):
            break
        if raw.startswith("author "):
            result["author"] = clean(raw[len("author ") :])
        elif raw.startswith("author-time "):
            result["authorTime"] = clean(raw[len("author-time ") :])
        elif raw.startswith("summary "):
            result["subject"] = clean(raw[len("summary ") :])

    author_time = result.get("authorTime")
    if author_time and author_time.isdigit():
        import datetime as _dt

        result["date"] = _dt.datetime.utcfromtimestamp(int(author_time)).strftime("%Y-%m-%d")
    return result


root = os.environ.get("REVIEW_CONTEXT_ROOT", "").strip()
targets = []
seen_targets = set()
for arg in sys.argv[1:]:
    cleaned = clean(arg)
    if not cleaned or cleaned in seen_targets:
        continue
    seen_targets.add(cleaned)
    targets.append(cleaned)
root_path = pathlib.Path(root).expanduser().resolve() if root else pathlib.Path.cwd().resolve()

git_available = run_command(["git", "rev-parse", "--is-inside-work-tree"], cwd=root_path.as_posix())[0] == 0
codeowners_path, codeowners_rules = load_codeowners(root_path)

entries = []
for target in targets:
    resolved = resolve_target(root_path.as_posix(), target)
    rel_path = resolved["path"]
    owners = owners_for_path(rel_path, codeowners_rules)
    history = history_for_path(root_path.as_posix(), rel_path) if git_available else []
    blame = blame_for_target(root_path.as_posix(), rel_path, resolved["line"]) if git_available else {}
    entries.append(
        {
            **resolved,
            "owners": owners,
            "history": history,
            "blame": blame,
        }
    )

payload = {
    "root": root_path.as_posix(),
    "available": bool(entries),
    "gitAvailable": git_available,
    "codeownersFile": codeowners_path.as_posix() if codeowners_path else "",
    "entries": entries,
}

print(json.dumps(payload, indent=2, sort_keys=True))
PY
)

    if [[ -n "${payload}" ]] && declare -F debug_handoff_row_for_target >/dev/null 2>&1; then
        debug_targets=$(REVIEW_CONTEXT_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os

try:
    payload = json.loads(os.environ.get("REVIEW_CONTEXT_PAYLOAD") or "{}")
except Exception:
    payload = {}

seen = []
for entry in payload.get("entries") or []:
    target = (entry.get("normalizedTarget") or entry.get("target") or "").strip()
    if target and target not in seen:
        seen.append(target)

for target in seen:
    print(target)
PY
)
        while IFS= read -r debug_target; do
            [[ -n "${debug_target}" ]] || continue
            debug_row=$(debug_handoff_row_for_target "${root}" "${debug_target}" || true)
            if [[ -n "${debug_row}" ]]; then
                debug_rows="${debug_rows}${debug_target}"$'\t'"${debug_row}"$'\n'
            fi
        done << EOF
${debug_targets}
EOF
        payload=$(REVIEW_CONTEXT_PAYLOAD="${payload}" REVIEW_CONTEXT_DEBUG_HANDOFFS="${debug_rows}" python3 - <<'PY'
import json
import os


def parse_debug_handoffs(text: str) -> dict:
    rows = {}
    for raw in (text or "").splitlines():
        if not raw.strip():
            continue
        parts = raw.split("\t")
        while len(parts) < 10:
            parts.append("")
        key, target, command, tool, tool_title, line_applied, trusted, trust_required, trust_command, notes = parts[:10]
        rows[key] = {
            "target": target,
            "command": command,
            "tool": tool,
            "toolTitle": tool_title,
            "lineApplied": line_applied == "yes",
            "trusted": trusted == "yes",
            "trustRequired": trust_required == "yes",
            "trustCommand": trust_command,
            "notes": [note for note in notes.split("|") if note],
        }
    return rows


try:
    payload = json.loads(os.environ.get("REVIEW_CONTEXT_PAYLOAD") or "{}")
except Exception:
    payload = {}

debug_handoffs = parse_debug_handoffs(os.environ.get("REVIEW_CONTEXT_DEBUG_HANDOFFS", ""))
entries = payload.get("entries") or []
for entry in entries:
    key = (entry.get("normalizedTarget") or entry.get("target") or "").strip()
    entry["debugHandoff"] = debug_handoffs.get(key)

summary = payload.get("summary") or {}
summary["debuggableEntries"] = sum(1 for entry in entries if entry.get("debugHandoff"))
payload["summary"] = summary

print(json.dumps(payload, indent=2, sort_keys=True))
PY
)
    fi

    printf "%s\n" "${payload}"
}

review_context_summary_rows_from_json() {
    local payload="$1"
    REVIEW_CONTEXT_PAYLOAD="${payload}" python3 - <<'PY'
import json
import os


def clean(value):
    return str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()


def describe_history(entry):
    history = entry.get("history") or []
    if not history:
        return ""
    latest = history[0]
    return "last={} {} {}".format(
        clean(latest.get("author")),
        clean(latest.get("date")),
        clean(latest.get("subject")),
    ).strip()


def describe_blame(entry):
    blame = entry.get("blame") or {}
    if not blame:
        return ""
    return "blame={} {} {}".format(
        clean(blame.get("author")),
        clean(blame.get("date")),
        clean(blame.get("subject")),
    ).strip()


def describe_debug(entry):
    handoff = entry.get("debugHandoff") or {}
    if not handoff:
        return ""
    parts = ["debug={}".format(clean(handoff.get("command")))]
    if handoff.get("trustRequired"):
        parts.append("trust={}".format(clean(handoff.get("trustCommand"))))
    return " | ".join(part for part in parts if part)


try:
    payload = json.loads(os.environ.get("REVIEW_CONTEXT_PAYLOAD") or "{}")
except Exception:
    payload = {}

for entry in payload.get("entries") or []:
    parts = []
    owners = [clean(owner) for owner in entry.get("owners") or [] if clean(owner)]
    if owners:
        parts.append("owners={}".format(",".join(owners)))
    history = describe_history(entry)
    if history:
        parts.append(history)
    blame = describe_blame(entry)
    if blame:
        parts.append(blame)
    debug = describe_debug(entry)
    if debug:
        parts.append(debug)
    print("{}\t{}".format(clean(entry.get("normalizedTarget") or entry.get("target")), " | ".join(parts)))
PY
}

review_context_text_block_from_json() {
    local payload="$1"
    local limit="${2:-8}"
    local indent="${3:-  }"
    REVIEW_CONTEXT_PAYLOAD="${payload}" python3 - "${limit}" "${indent}" <<'PY'
import json
import os
import sys


def clean(value):
    return str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()


def history_summary(entry):
    history = entry.get("history") or []
    if not history:
        return ""
    latest = history[0]
    return "{} {} {}".format(
        clean(latest.get("author")),
        clean(latest.get("date")),
        clean(latest.get("subject")),
    ).strip()


try:
    payload = json.loads(os.environ.get("REVIEW_CONTEXT_PAYLOAD") or "{}")
except Exception:
    payload = {}

limit = int(sys.argv[1] or "8")
indent = sys.argv[2]
entries = payload.get("entries") or []
for entry in entries[:limit]:
    owners = ", ".join(clean(owner) for owner in entry.get("owners") or [] if clean(owner)) or "unowned"
    history = history_summary(entry) or "no recent git history"
    line = clean(entry.get("line"))
    blame = entry.get("blame") or {}
    blame_text = ""
    if blame:
        blame_text = "focus line {}: {} {} {}".format(
            line or "?",
            clean(blame.get("author")),
            clean(blame.get("date")),
            clean(blame.get("subject")),
        ).strip()
    handoff = entry.get("debugHandoff") or {}
    print("{}- {} owners={} last={}".format(indent, clean(entry.get("path")), owners, history))
    if blame_text:
        print("{}  {}".format(indent, blame_text))
    if handoff:
        print("{}  debug: {}".format(indent, clean(handoff.get("command"))))
        if handoff.get("trustRequired"):
            print("{}  trust: {}".format(indent, clean(handoff.get("trustCommand"))))
PY
}

review_context_markdown_section_from_json() {
    local payload="$1"
    local heading="${2:-Review Routing}"
    local limit="${3:-8}"
    REVIEW_CONTEXT_PAYLOAD="${payload}" python3 - "${heading}" "${limit}" <<'PY'
import json
import os
import sys


def clean(value):
    return str(value or "").replace("\t", " ").replace("\r", " ").replace("\n", " ").strip()


def history_summary(entry):
    history = entry.get("history") or []
    if not history:
        return ""
    latest = history[0]
    return "{} on {} (`{}`) {}".format(
        clean(latest.get("author")),
        clean(latest.get("date")),
        clean(latest.get("shortSha")),
        clean(latest.get("subject")),
    ).strip()


try:
    payload = json.loads(os.environ.get("REVIEW_CONTEXT_PAYLOAD") or "{}")
except Exception:
    payload = {}

heading = sys.argv[1]
limit = int(sys.argv[2] or "8")
entries = payload.get("entries") or []
if not entries:
    raise SystemExit(0)

print(f"## {heading}")
print("")
for entry in entries[:limit]:
    owners = ", ".join(clean(owner) for owner in entry.get("owners") or [] if clean(owner)) or "unowned"
    history = history_summary(entry) or "no recent git history"
    blame = entry.get("blame") or {}
    blame_text = ""
    if blame:
        blame_text = " focus line {}: {} on {} (`{}`) {}.".format(
            clean(blame.get("line")),
            clean(blame.get("author")),
            clean(blame.get("date")),
            clean(blame.get("shortSha")),
            clean(blame.get("subject")),
        )
    handoff = entry.get("debugHandoff") or {}
    debug_text = ""
    if handoff:
        debug_text = " Debug here: `{}`.".format(clean(handoff.get("command")))
        if handoff.get("trustRequired"):
            debug_text += " Trust first: `{}`.".format(clean(handoff.get("trustCommand")))
    print(f"- `{clean(entry.get('path'))}` — owners: {owners}; last change: {history}.{blame_text}{debug_text}")
print("")
PY
}
