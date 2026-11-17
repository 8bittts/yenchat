#!/bin/bash
# Overlay recurrence gates for YEN-on-Ghostty Swift overlays and apply-overlays.sh.
#
# These are narrow guards for sweep follow-up work:
# - new non-DEBUG Swift print(...) call sites require baseline review
# - new Timer.scheduledTimer call sites either set .tolerance or require baseline review
# - large overlay files warn only, so decomposition remains visible but non-blocking
#   (the apply-overlays.sh applicator is line-counted under the same god-file
#   threshold here too, warn only)
# - controller lookups derived from a SURFACE's window are held at baseline zero:
#   a surface's window is nil or stale while AppKit attaches or moves a native tab,
#   so such a lookup silently resolves to no controller. Use
#   BaseTerminalController.controller(owning:), which resolves through split-tree
#   ownership. Window-derived lookups are legitimate and are not matched.
# - apply-overlays.sh inline python heredocs are held at baseline zero: the inventory
#   is intentionally empty (all patch payloads live in scripts/lib helpers), so this scan
#   is a regression tripwire that fails closed if any inline heredoc is reintroduced
#
# Usage: ./scripts/42-lint-overlay-recurrence-gates.sh
#        [--sources-dir DIR] [--apply-overlays PATH] [--phase-dir DIR] [--allowlist-dir DIR]
#        [--god-file-threshold N]
#
# Exit: 0 when failing gates are clean, 1 on print/timer/heredoc drift.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCES_DIR="$REPO_ROOT/yen-terminal/overlays/macos/Sources"
APPLY_OVERLAYS="$REPO_ROOT/yen-terminal/apply-overlays.sh"
PHASE_DIR="$REPO_ROOT/scripts/lib/overlay-phases"
ALLOWLIST_DIR="$REPO_ROOT/scripts/lib/overlay-recurrence-allowlist"
CUSTOM_ALLOWLIST_DIR=0
GOD_FILE_THRESHOLD=1500

usage() {
    echo "Usage: $0 [--sources-dir DIR] [--apply-overlays PATH] [--phase-dir DIR] [--allowlist-dir DIR] [--god-file-threshold N]" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --sources-dir)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            SOURCES_DIR="$2"
            shift 2
            ;;
        --apply-overlays)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            APPLY_OVERLAYS="$2"
            shift 2
            ;;
        --phase-dir)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            PHASE_DIR="$2"
            shift 2
            ;;
        --allowlist-dir)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            ALLOWLIST_DIR="$2"
            CUSTOM_ALLOWLIST_DIR=1
            shift 2
            ;;
        --god-file-threshold)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            GOD_FILE_THRESHOLD="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

PRINT_ALLOWLIST="$ALLOWLIST_DIR/non-debug-print-sites.txt"
TIMER_ALLOWLIST="$ALLOWLIST_DIR/timer-without-tolerance-sites.txt"
HEREDOC_INVENTORY="$ALLOWLIST_DIR/apply-overlays-python-heredocs.txt"

python3 - "$REPO_ROOT" "$SOURCES_DIR" "$APPLY_OVERLAYS" "$PRINT_ALLOWLIST" "$TIMER_ALLOWLIST" "$HEREDOC_INVENTORY" "$GOD_FILE_THRESHOLD" "$CUSTOM_ALLOWLIST_DIR" "$PHASE_DIR" <<'PYEOF'
from __future__ import annotations

import bisect
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

repo_root = Path(sys.argv[1]).resolve()
sources_dir = Path(sys.argv[2]).resolve()
apply_overlays = Path(sys.argv[3]).resolve()
print_allowlist_path = Path(sys.argv[4]).resolve()
timer_allowlist_path = Path(sys.argv[5]).resolve()
heredoc_inventory_path = Path(sys.argv[6]).resolve()
god_file_threshold = int(sys.argv[7])
custom_allowlist_dir = sys.argv[8] == "1"
phase_dir = Path(sys.argv[9]).resolve()
default_sources_dir = (repo_root / "yen-terminal/overlays/macos/Sources").resolve()
strict_allowlist = sources_dir == default_sources_dir or custom_allowlist_dir


def display_path(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(repo_root).as_posix()
    except ValueError:
        try:
            return resolved.relative_to(sources_dir).as_posix()
        except ValueError:
            return resolved.as_posix()


def read_count_allowlist(path: Path) -> dict[str, int]:
    counts: dict[str, int] = {}
    if not path.exists():
        return counts
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|", 2)
        if len(parts) < 2:
            raise SystemExit(f"{display_path(path)}:{line_number}: expected path|count|note")
        key = parts[0].strip()
        try:
            count = int(parts[1].strip())
        except ValueError as exc:
            raise SystemExit(f"{display_path(path)}:{line_number}: invalid count") from exc
        counts[key] = count
    return counts


def read_site_allowlist(path: Path, field_count: int) -> Counter[tuple[str, ...]]:
    sites: Counter[tuple[str, ...]] = Counter()
    if not path.exists():
        return sites
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        site_fields, separator, _note = line.rpartition("|")
        parts = [part.strip() for part in site_fields.split("|", field_count - 1)]
        if not separator or len(parts) != field_count or any(not part for part in parts):
            raise SystemExit(
                f"{display_path(path)}:{line_number}: expected {field_count} pipe-delimited site fields plus note"
            )
        sites[tuple(parts)] += 1
    return sites


def line_starts(text: str) -> list[int]:
    starts = [0]
    for match in re.finditer("\n", text):
        starts.append(match.end())
    return starts


def line_number_for(starts: list[int], index: int) -> int:
    return bisect.bisect_right(starts, index)


def line_start_for(starts: list[int], index: int) -> int:
    return starts[bisect.bisect_right(starts, index) - 1]


def mask_comments_and_strings(text: str) -> str:
    chars = list(text)
    i = 0
    n = len(chars)
    while i < n:
        ch = chars[i]
        nxt = chars[i + 1] if i + 1 < n else ""
        if ch == "/" and nxt == "/":
            chars[i] = " "
            chars[i + 1] = " "
            i += 2
            while i < n and chars[i] != "\n":
                chars[i] = " "
                i += 1
            continue
        if ch == "/" and nxt == "*":
            chars[i] = " "
            chars[i + 1] = " "
            i += 2
            depth = 1
            while i < n and depth > 0:
                if chars[i] == "\n":
                    i += 1
                    continue
                if chars[i] == "/" and i + 1 < n and chars[i + 1] == "*":
                    chars[i] = " "
                    chars[i + 1] = " "
                    depth += 1
                    i += 2
                    continue
                if chars[i] == "*" and i + 1 < n and chars[i + 1] == "/":
                    chars[i] = " "
                    chars[i + 1] = " "
                    depth -= 1
                    i += 2
                    continue
                chars[i] = " "
                i += 1
            continue
        if ch == "#":
            raw_start = i
            while i < n and chars[i] == "#":
                i += 1
            raw_hashes = i - raw_start
            if i < n and chars[i] == '"':
                raw_end = '"' + ("#" * raw_hashes)
                if text.startswith('"""', i):
                    raw_end = '"""' + ("#" * raw_hashes)
                    for offset in range(raw_hashes + 3):
                        chars[raw_start + offset] = " "
                    i = raw_start + raw_hashes + 3
                else:
                    for offset in range(raw_hashes + 1):
                        chars[raw_start + offset] = " "
                    i = raw_start + raw_hashes + 1
                while i < n:
                    if text.startswith(raw_end, i):
                        for offset in range(len(raw_end)):
                            chars[i + offset] = " "
                        i += len(raw_end)
                        break
                    if chars[i] != "\n":
                        chars[i] = " "
                    i += 1
                continue
            i = raw_start
        if text.startswith('"""', i):
            for offset in range(3):
                chars[i + offset] = " "
            i += 3
            while i < n:
                if text.startswith('"""', i):
                    for offset in range(3):
                        chars[i + offset] = " "
                    i += 3
                    break
                if chars[i] != "\n":
                    chars[i] = " "
                i += 1
            continue
        if ch == '"':
            chars[i] = " "
            i += 1
            escaped = False
            while i < n:
                current = chars[i]
                if current == "\n":
                    i += 1
                    escaped = False
                    continue
                chars[i] = " "
                if current == '"' and not escaped:
                    i += 1
                    break
                escaped = current == "\\" and not escaped
                if current != "\\":
                    escaped = False
                i += 1
            continue
        i += 1
    return "".join(chars)


def debug_lines(text: str) -> list[bool]:
    stack: list[str] = []
    active: list[bool] = []
    for raw in text.splitlines():
        stripped = raw.strip()
        if stripped.startswith("#if "):
            expr = stripped[4:].strip()
            stack.append("debug" if re.search(r"\bDEBUG\b", expr) and "!DEBUG" not in expr else "other")
        elif stripped.startswith("#elseif "):
            if stack:
                expr = stripped[8:].strip()
                stack[-1] = "debug" if re.search(r"\bDEBUG\b", expr) and "!DEBUG" not in expr else "other"
        elif stripped.startswith("#else"):
            if stack and stack[-1] == "debug":
                stack[-1] = "other"
        elif stripped.startswith("#endif"):
            if stack:
                stack.pop()
        active.append(any(entry == "debug" for entry in stack))
    if text.endswith("\n"):
        active.append(any(entry == "debug" for entry in stack))
    return active


def extract_call(original: str, masked: str, start: int, open_paren: int) -> tuple[str, int]:
    depth = 0
    end = open_paren
    for index in range(open_paren, len(masked)):
        char = masked[index]
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                end = index + 1
                break
    else:
        line_end = original.find("\n", start)
        end = len(original) if line_end == -1 else line_end
    snippet = re.sub(r"\s+", " ", original[start:end]).strip()
    return snippet[:240], end


def swift_files() -> list[Path]:
    if not sources_dir.exists():
        return []
    return sorted(path for path in sources_dir.rglob("*.swift") if "/Tests/" not in path.as_posix())


# An empty scan set is a broken gate, not a clean tree. 41-lint-swift-view-modifiers.sh
# has carried this floor since it was written; 42 was added later and did not
# inherit it, because the rule lived only as prose. Verified before the fix:
# --sources-dir /tmp/nonexistent printed four "OK ... clean" lines and exited 0.
SWIFT_SOURCES = swift_files()

# A MISSING sources dir is a broken gate — that is the reproduction: pointing
# --sources-dir at a nonexistent path used to print four "OK ... clean" lines and
# exit 0. An EXISTING but empty dir is different: callers pass one deliberately to
# isolate the applicator-only gates, so it is allowed but announced, never silent.
if not sources_dir.exists():
    print(f"X Overlay recurrence gates: sources dir does not exist: {sources_dir}")
    print("  Refusing to report clean over an empty scan set.")
    sys.exit(1)
if not SWIFT_SOURCES:
    print(f"SKIP swift-scan: no .swift sources under {sources_dir} (applicator gates only)")

# Floor only against the REAL tree. `strict_allowlist` is also true for a custom
# --allowlist-dir, which the fixture-driven tests pair with a two-file
# --sources-dir; gating on that would fail every fixture run.
MIN_DEFAULT_SOURCES = 150
if sources_dir == default_sources_dir and len(SWIFT_SOURCES) < MIN_DEFAULT_SOURCES:
    print(f"X Overlay recurrence gates: only {len(SWIFT_SOURCES)} Swift source(s) scanned.")
    print(f"  Expected at least {MIN_DEFAULT_SOURCES}. The scan set collapsed --")
    print("  check the Sources path before trusting a clean run.")
    sys.exit(1)

if not apply_overlays.exists():
    print(f"X Overlay recurrence gates: applicator not found at {apply_overlays}")
    print("  The heredoc inventory gate cannot pass over a missing subject.")
    sys.exit(1)


phase_files = sorted(phase_dir.glob("*.sh"))
if not phase_files:
    print(f"X Overlay recurrence gates: phase scan matched zero scripts at {phase_dir}")
    sys.exit(1)
overlay_shell_files = [apply_overlays, *phase_files, *sorted((repo_root / "scripts/lib").glob("overlay-*.sh"))]


def scan_prints(path: Path) -> list[tuple[str, int, str]]:
    text = path.read_text(encoding="utf-8")
    masked = mask_comments_and_strings(text)
    starts = line_starts(text)
    debug_by_line = debug_lines(text)
    findings: list[tuple[str, int, str]] = []
    for match in re.finditer(r"(?:(?<![A-Za-z0-9_])Swift\s*\.\s*print|(?<![A-Za-z0-9_.])print)\s*\(", masked):
        line_number = line_number_for(starts, match.start())
        if line_number - 1 < len(debug_by_line) and debug_by_line[line_number - 1]:
            continue
        open_paren = masked.find("(", match.start(), match.end() + 1)
        snippet, _ = extract_call(text, masked, match.start(), open_paren)
        findings.append((display_path(path), line_number, snippet))
    return findings


def tolerance_target_before(text: str, starts: list[int], start: int) -> str:
    line_start = line_start_for(starts, start)
    prefix = text[line_start:start]
    match = re.search(
        r"(?:\blet\b|\bvar\b)?\s*((?:[A-Za-z_][A-Za-z0-9_]*\.)*[A-Za-z_][A-Za-z0-9_]*)\s*(?::[^=]+)?=\s*$",
        prefix,
    )
    return match.group(1) if match else ""


def has_tolerance_assignment(masked: str, starts: list[int], call_end: int, target: str) -> bool:
    if not target:
        return False
    start_line = line_number_for(starts, call_end)
    lines = masked.splitlines()
    window = "\n".join(lines[start_line : start_line + 12])
    return re.search(rf"\b{re.escape(target)}[?!]?\.tolerance\s*=", window) is not None


def scan_timers(path: Path) -> list[tuple[str, int, str, str]]:
    text = path.read_text(encoding="utf-8")
    masked = mask_comments_and_strings(text)
    starts = line_starts(text)
    findings: list[tuple[str, int, str, str]] = []
    for match in re.finditer(r"\bTimer\s*\.\s*scheduledTimer\s*\(", masked):
        line_number = line_number_for(starts, match.start())
        open_paren = masked.find("(", match.start(), match.end() + 1)
        snippet, call_end = extract_call(text, masked, match.start(), open_paren)
        target = tolerance_target_before(text, starts, match.start())
        if has_tolerance_assignment(masked, starts, call_end, target):
            continue
        findings.append((display_path(path), line_number, target or "Timer.scheduledTimer", snippet))
    return findings


def compare_counts(
    label: str,
    actual: Counter[str],
    allowed: dict[str, int],
    findings_by_path: dict[str, list[tuple]],
    extra_heading: str,
) -> list[str]:
    errors: list[str] = []
    for path in sorted(actual):
        expected = allowed.get(path, 0)
        if actual[path] <= expected:
            continue
        errors.append(f"{label}: {path} has {actual[path]} baseline count {expected}")
        for finding in findings_by_path.get(path, []):
            line_number = finding[1]
            subject = finding[2]
            snippet = finding[-1]
            errors.append(f"  {extra_heading}: {line_number}: {subject} {snippet}")
    if strict_allowlist:
        for path in sorted(set(allowed) - set(actual)):
            if allowed[path] != 0:
                errors.append(f"{label}: stale allowlist entry {path} count {allowed[path]} current 0")
        for path in sorted(set(actual) & set(allowed)):
            if actual[path] < allowed[path]:
                errors.append(f"{label}: stale allowlist entry {path} count {allowed[path]} current {actual[path]}")
    return errors


def compare_site_counts(
    label: str,
    actual: Counter[tuple[str, ...]],
    allowed: Counter[tuple[str, ...]],
    findings_by_site: dict[tuple[str, ...], list[tuple]],
    extra_heading: str,
) -> list[str]:
    errors: list[str] = []
    for site in sorted(set(actual) | set(allowed)):
        current = actual.get(site, 0)
        expected = allowed.get(site, 0)
        if current > expected:
            errors.append(f"{label}: {' | '.join(site)} count {current} baseline {expected}")
            for finding in findings_by_site.get(site, []):
                line_number = finding[1]
                subject = finding[2]
                snippet = finding[-1]
                errors.append(f"  {extra_heading}: {line_number}: {subject} {snippet}")
        elif strict_allowlist and current < expected:
            errors.append(f"{label}: stale allowlist site {' | '.join(site)} count {expected} current {current}")
    return errors


SURFACE_OWNER_LOOKUP_PATTERN = re.compile(
    r"(?<![A-Za-z0-9_])[A-Za-z0-9_]*[Ss]urface[A-Za-z0-9_]*"
    r"\s*\.\s*window\s*[?!]?\s*\.\s*windowController"
    r"\s+as\s*[?!]\s*BaseTerminalController"
)


def scan_surface_owner_lookups(path: Path) -> list[tuple[str, int, str]]:
    """Find controller lookups derived from a SURFACE's window.

    A surface's `window` is briefly nil, or still its previous window, while
    AppKit attaches or moves a native tab, so a lookup landing in that window
    silently resolves to no controller. `BaseTerminalController.controller(owning:)`
    resolves through split-tree ownership instead and falls back to the window.

    Window-derived lookups (`window.windowController as? BaseTerminalController`,
    `NSApp.keyWindow?...`) are legitimately window-based and are NOT matched --
    only receivers whose name contains "surface".
    """
    text = path.read_text(encoding="utf-8")
    masked = mask_comments_and_strings(text)
    starts = line_starts(text)
    findings: list[tuple[str, int, str]] = []
    for match in SURFACE_OWNER_LOOKUP_PATTERN.finditer(masked):
        line_number = line_number_for(starts, match.start())
        findings.append((display_path(path), line_number, match.group(0).strip()))
    return findings


def scan_heredocs(path: Path) -> Counter[str]:
    counts: Counter[str] = Counter()
    if not path.exists():
        return counts
    heredoc_pattern = re.compile(r"python3\s+-.*<<\s*'?([A-Za-z_][A-Za-z0-9_]*)'?")
    target_pattern = re.compile(r"python3\s+-\s+\"?\$([A-Za-z_][A-Za-z0-9_]*)\"?")
    for line in path.read_text(encoding="utf-8").splitlines():
        if not heredoc_pattern.search(line):
            continue
        target = target_pattern.search(line)
        counts[target.group(1) if target else "<no-target>"] += 1
    return counts


failures: list[str] = []
print_allowlist = read_site_allowlist(print_allowlist_path, 2)
timer_allowlist = read_site_allowlist(timer_allowlist_path, 3)
heredoc_inventory = read_count_allowlist(heredoc_inventory_path)

print_findings: list[tuple[str, int, str]] = []
timer_findings: list[tuple[str, int, str, str]] = []
surface_owner_findings: list[tuple[str, int, str]] = []
line_count_warnings: list[str] = []

for swift_path in SWIFT_SOURCES:
    rel = display_path(swift_path)
    line_count = len(swift_path.read_text(encoding="utf-8").splitlines())
    if line_count > god_file_threshold:
        line_count_warnings.append(
            f"WARN overlay god-file line-count: {rel} has {line_count} lines (threshold {god_file_threshold})"
        )
    print_findings.extend(scan_prints(swift_path))
    timer_findings.extend(scan_timers(swift_path))
    surface_owner_findings.extend(scan_surface_owner_lookups(swift_path))

# The overlay applicator is a shell script, not a Swift source, so swift_files()
# never covers it. Line-count it under the same god-file threshold so its growth
# stays visible after B2 DRY'd the ~45 patch call sites — warn only, never a hard
# failure, matching the Swift god-file gate above.
for shell_path in overlay_shell_files:
    shell_line_count = len(shell_path.read_text(encoding="utf-8").splitlines())
    if shell_line_count > god_file_threshold:
        line_count_warnings.append(
            f"WARN overlay god-file line-count: {display_path(shell_path)} has {shell_line_count} lines (threshold {god_file_threshold})"
        )

print_sites = Counter((path, snippet) for path, _, snippet in print_findings)
timer_sites = Counter((path, target, snippet) for path, _, target, snippet in timer_findings)

prints_by_site: dict[tuple[str, str], list[tuple]] = defaultdict(list)
for finding in print_findings:
    path, _, snippet = finding
    prints_by_site[(path, snippet)].append(finding)

timers_by_site: dict[tuple[str, str, str], list[tuple]] = defaultdict(list)
for finding in timer_findings:
    path, _, target, snippet = finding
    timers_by_site[(path, target, snippet)].append(finding)

print_errors = compare_site_counts(
    "unallowlisted non-DEBUG print",
    print_sites,
    print_allowlist,
    prints_by_site,
    "print",
)
timer_errors = compare_site_counts(
    "scheduled timers without tolerance",
    timer_sites,
    timer_allowlist,
    timers_by_site,
    "timer",
)

failures.extend(print_errors)
failures.extend(timer_errors)

# Baseline-zero tripwire: every surface-driven controller lookup was migrated to
# BaseTerminalController.controller(owning:), so any reintroduction is drift.
for finding in surface_owner_findings:
    failures.append(
        "surface-derived controller lookup: "
        f"{finding[0]}: {finding[1]}: {finding[2]}"
    )
    failures.append(
        "  use BaseTerminalController.controller(owning:) — a surface's window is "
        "nil or stale while AppKit attaches or moves a native tab"
    )

# Baseline-zero tripwire: the inventory is intentionally empty, so any inline
# python heredoc reintroduced into apply-overlays.sh trips this gate.
heredoc_counts: Counter[str] = Counter()
for shell_path in overlay_shell_files:
    heredoc_counts.update(scan_heredocs(shell_path))
for target in sorted(set(heredoc_counts) | set(heredoc_inventory)):
    actual = heredoc_counts.get(target, 0)
    expected = heredoc_inventory.get(target, 0)
    if actual != expected:
        failures.append(
            f"apply-overlays Python heredoc inventory drift: {target} count {actual} baseline {expected}"
        )

if print_errors:
    pass
else:
    print("OK Overlay print gate clean")

if timer_errors:
    pass
else:
    print("OK Timer tolerance gate clean")

if any(line.startswith("apply-overlays Python heredoc inventory drift") for line in failures):
    pass
else:
    print(f"OK apply-overlays Python heredoc inventory clean; scanned {len(overlay_shell_files)} shell files")

if surface_owner_findings:
    pass
else:
    print("OK surface owner lookup gate clean")

for warning in line_count_warnings:
    print(warning)

print(
    f"RECEIPT gate=42-lint-overlay-recurrence-gates swift_sources={len(SWIFT_SOURCES)} "
    f"print_findings={len(print_errors)} timer_findings={len(timer_errors)} "
    f"surface_owner_findings={len(surface_owner_findings)} warnings={len(line_count_warnings)} "
    f"result={'FAIL' if failures else 'PASS'}"
)

if failures:
    print("X Overlay recurrence gate failure")
    for failure in failures:
        print(failure)
    sys.exit(1)

sys.exit(0)
PYEOF
