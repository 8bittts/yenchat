#!/bin/bash
# Conditionally run the built-app AppleScript verifier when the current worktree
# touches AppleScript or workspace-shortcut contract surfaces.
#
# Usage:
#   ./scripts/manual/16-verify-applescript-if-needed.sh
#   ./scripts/manual/16-verify-applescript-if-needed.sh --keep-open
#   ./scripts/manual/16-verify-applescript-if-needed.sh --app /abs/path/to/YEN.app
#
# Trigger logic has two tiers of PATH, and three sources of CHANGE.
#
# [CRITICAL] The change sources must include committed history. This gate
# originally read only the working tree -- `git diff HEAD`, `--cached`, and
# untracked files -- so committing a change to a tripwire path disarmed the
# tripwire that exists to catch it. The gate then printed a checkmark and exited
# 0, and because it emitted no receipt, both callers' evals (vendor VB-04,
# /yen-zip VF-01) recorded that skip as a pass. `zip-verify.md` mandates committing a
# vendor bump BEFORE starting /yen-zip, so in the documented order this gate could
# never fire for a vendor-introduced change. Measured on 2c3a40580: the same
# TerminalViewContainer.swift edit triggered the gate while dirty and reported
# "no AppleScript/workspace contract changes detected" once committed.
#
# The third source is the committed range since the last VERIFIED commit, which
# is stamped in yen-terminal/.applescript-verified by a successful run on a clean
# tree. A missing, empty, or unresolvable stamp triggers the verifier rather than
# skipping it -- an unknown baseline is not evidence of a verified one.
#
# Path tiers:
#
# 1. UNCONDITIONAL_PATHS — any change to these files triggers the verifier.
#    These files exist solely to implement AppleScript or workspace-shortcut
#    contract surfaces, so any edit is relevant by definition.
#
# 2. SCOPED_PATHS — files with AppleScript-adjacent checks mixed in with
#    unrelated checks (e.g. scripts/04-verify-branding.sh). For these, the
#    wrapper scans the diff for AppleScript keywords and only triggers the
#    verifier when an added or removed line contains one. This avoids the
#    false-positive where editing an unrelated check in the same file (for
#    example check #38 for DockTilePlugin) would pull in the full AppleScript
#    verification run.

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERIFIER="$SCRIPT_DIR/15-verify-applescript.sh"

# shellcheck source=../lib/gate-receipt.sh
. "$REPO_ROOT/scripts/lib/gate-receipt.sh"
gate_begin "16-verify-applescript-if-needed"

# The stamp naming the last commit at which the verifier passed on a clean tree.
VERIFIED_STAMP="$REPO_ROOT/yen-terminal/.applescript-verified"

if [ ! -x "$VERIFIER" ]; then
    echo "ERROR: AppleScript verifier missing or not executable: $VERIFIER"
    exit 1
fi

# [CRITICAL] Every path here must EXIST and be TRACKED, or it is a dead
# tripwire that reads as coverage. `yen-terminal/overlays/macos/Sources/Features/AppleScript`
# sat in this list and is not on disk at all: YEN does not carry whole-file
# AppleScript overlays, so nothing could ever match it.
#
# Do not add a `yen-terminal/ghostty/...` path to compensate. That tree is
# gitignored, so `git diff` can never report it either — an upstream vendor
# change to AppleScript sources is invisible to this wrapper by construction,
# and the native slice in scripts/03-verify-components.sh is what covers it.
UNCONDITIONAL_PATHS=(
    "scripts/manual/15-verify-applescript.sh"
    "scripts/lib/overlay-phases/01-branding.sh"
    "scripts/lib/overlay-phases/02-renames.sh"
    "scripts/lib/overlay-phases/06-copy.sh"
    "scripts/lib/overlay-rename-preflight.sh"
    "scripts/lib/overlay-verification.sh"
    "yen-terminal/overlays/macos/YEN.sdef"
    "yen-terminal/overlays/macos/Sources/Features/Settings/KeybindRegistry.swift"
    "yen-terminal/overlays/macos/Sources/Features/Terminal/TerminalViewContainer.swift"
)

# The extracted phases and guards above own AppleScript branding, renames,
# copying, and validation. Watch them without a keyword filter so a helper call
# or path-only edit cannot bypass verification. Keep the broad entry points
# below scoped to AppleScript-related changes.
SCOPED_PATHS=(
    "scripts/04-verify-branding.sh"
    "yen-terminal/apply-overlays.sh"
)

# Keywords that indicate an AppleScript-related change when present in a diff
# line. Case-insensitive extended regex. Keep in sync with the AppleScript
# checks in scripts/04-verify-branding.sh (checks 12e and 24b at time of writing).
APPLESCRIPT_KEYWORDS='applescript|\.sdef|YENScript|macos-applescript|isAppleScriptActionAllowed|logAutomationAudit|AppDelegate\+AppleScript'

unconditional_changes() {
    git -C "$REPO_ROOT" diff --name-only HEAD -- "${UNCONDITIONAL_PATHS[@]}" 2>/dev/null || true
    git -C "$REPO_ROOT" diff --cached --name-only -- "${UNCONDITIONAL_PATHS[@]}" 2>/dev/null || true
    git -C "$REPO_ROOT" ls-files --others --exclude-standard -- "${UNCONDITIONAL_PATHS[@]}" 2>/dev/null || true
}

# For each scoped path, return the path only if its diff (working tree vs HEAD)
# contains added/removed lines matching any AppleScript keyword.
scoped_changes() {
    local path diff_output relevant_lines
    for path in "${SCOPED_PATHS[@]}"; do
        diff_output=$(git -C "$REPO_ROOT" diff HEAD -- "$path" 2>/dev/null || true)
        [ -z "$diff_output" ] && continue
        # Filter to added/removed content lines (leading + or -, but not diff
        # headers like +++ and ---). Drop empty output so grep doesn't match.
        relevant_lines=$(printf '%s\n' "$diff_output" | grep -E '^[+-][^+-]' || true)
        [ -z "$relevant_lines" ] && continue
        if printf '%s\n' "$relevant_lines" | grep -Eiq "$APPLESCRIPT_KEYWORDS"; then
            echo "$path"
        fi
    done
}

# The commit at which the verifier last passed on a clean tree. Prints nothing
# when the stamp is absent, empty, or names a commit this repo cannot resolve --
# every one of which is treated as "baseline unknown" by the caller below.
verified_baseline() {
    local sha=""
    [ -f "$VERIFIED_STAMP" ] || return 0
    sha=$(grep -E '^verified_commit=' "$VERIFIED_STAMP" 2>/dev/null | tail -1 | cut -d= -f2 | tr -d '[:space:]')
    [ -n "$sha" ] || return 0
    git -C "$REPO_ROOT" rev-parse --verify --quiet "${sha}^{commit}" >/dev/null 2>&1 || return 0
    echo "$sha"
}

# Changes to tripwire paths COMMITTED since the verified baseline. This is the
# source the gate originally lacked, and the only one that survives a commit.
committed_changes() {
    local base="$1"
    [ -n "$base" ] || return 0
    git -C "$REPO_ROOT" diff --name-only "$base..HEAD" -- "${UNCONDITIONAL_PATHS[@]}" 2>/dev/null || true

    local path diff_output relevant_lines
    for path in "${SCOPED_PATHS[@]}"; do
        diff_output=$(git -C "$REPO_ROOT" diff "$base..HEAD" -- "$path" 2>/dev/null || true)
        [ -z "$diff_output" ] && continue
        relevant_lines=$(printf '%s\n' "$diff_output" | grep -E '^[+-][^+-]' || true)
        [ -z "$relevant_lines" ] && continue
        if printf '%s\n' "$relevant_lines" | grep -Eiq "$APPLESCRIPT_KEYWORDS"; then
            echo "$path"
        fi
    done
}

BASELINE=$(verified_baseline)

CHANGED=$(
    {
        unconditional_changes
        scoped_changes
        committed_changes "$BASELINE"
    } | awk 'NF && !seen[$0]++ { print $0 }'
)

CHANGED_COUNT=$(printf '%s\n' "$CHANGED" | awk 'NF' | wc -l | tr -d ' ')
gate_unit_ran trigger-scan \
    "unconditional=${#UNCONDITIONAL_PATHS[@]} scoped=${#SCOPED_PATHS[@]} baseline=${BASELINE:-none} matches=$CHANGED_COUNT"

if [ -z "$CHANGED" ]; then
    if [ -z "$BASELINE" ]; then
        # No stamp means nothing has ever recorded a verified commit, so the
        # committed range could not be examined at all. That is an unexamined
        # gate, not a clean one -- run the verifier rather than reporting clean.
        echo "  No verified baseline in ${VERIFIED_STAMP#"$REPO_ROOT"/} — cannot prove committed history is clean."
        echo "  Running the verifier rather than reporting a skip."
        CHANGED="(no verified baseline)"
    else
        gate_unit_skipped verifier "no AppleScript/workspace contract changes since $BASELINE"
        gate_end 0
        exit 0
    fi
fi

echo "  Detected AppleScript/workspace contract changes:"
while IFS= read -r path; do
    [ -z "$path" ] && continue
    echo "    - $path"
done <<EOF
$CHANGED
EOF

VERIFIER_RC=0
bash "$VERIFIER" "$@" || VERIFIER_RC=$?

if [ "$VERIFIER_RC" -ne 0 ]; then
    gate_unit_ran verifier "delegated=15-verify-applescript exit=$VERIFIER_RC"
    gate_end 1 "$VERIFIER_RC"
    exit "$VERIFIER_RC"
fi

gate_unit_ran verifier "delegated=15-verify-applescript exit=0 triggers=$CHANGED_COUNT"

# Advance the stamp only when the tree carries no uncommitted tripwire change.
# A dirty verification cannot be named by a commit, so stamping HEAD would claim
# coverage for content that is not in HEAD.
DIRTY=$( { unconditional_changes; scoped_changes; } | awk 'NF' | head -1 )
if [ -n "$DIRTY" ]; then
    echo "  Stamp not advanced: verified a dirty worktree, which no commit names."
    echo "  Re-run after committing to record the verified commit."
else
    HEAD_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD)
    {
        echo "# AppleScript/workspace contract verification stamp."
        echo "# Written by scripts/manual/16-verify-applescript-if-needed.sh after a"
        echo "# passing scripts/manual/15-verify-applescript.sh run on a clean tree."
        echo "verified_commit=$HEAD_SHA"
        echo "verified_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$VERIFIED_STAMP"
    echo "  Verified baseline advanced to $HEAD_SHA"
fi

gate_end 0
