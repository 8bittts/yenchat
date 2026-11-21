#!/bin/bash
# verify-agent-work.sh — Verify agent decisions (not script output)
# Checks the two /update-yen outcomes no eval check covers on its own: the staged
# release set (after Step 7a) and the published, clean result (after Step 11).
# The former preflight and build phases only repeated PF-01, BD-01 and BD-03.
# Usage: verify-agent-work.sh <phase> [args...]
# Bash 3.2 compatible.

set -euo pipefail

# Resolve this script's own directory PHYSICALLY before walking up. The skill
# dirs are symlinked into ~/.claude and ~/.codex, and a logical `cd` applies
# ".." to the symlink path, so invoking by skill path resolved REPO_ROOT to
# the home directory instead of the repo.
SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd -P "$SCRIPT_DIR/../../../.." && pwd -P)"
RELEASE_COMMIT_REGEX='^v[0-9]+\.[0-9]{3}: .*\[deploy\]$'

phase="${1:-}"
if [ -z "$phase" ]; then
    echo "Usage: verify-agent-work.sh <verify|release|all>" >&2
    exit 2
fi

ERRORS=0
note_error() {
    echo "  [FAIL] $1"
    ERRORS=$((ERRORS + 1))
}
note_pass() {
    echo "  [PASS] $1"
}

check_verify() {
    echo "--- Verify Agent Checks ---"

    # This check used to pass on BOTH branches -- staged was a [PASS] and
    # "staging deferred" was also a [PASS] -- so the verify phase could not
    # fail for the reason it existed. The phase ends with 07-stage-release.sh,
    # which stages an enumerated set, so by the time this runs the set is
    # either present or the staging step did not happen.
    staged="$(cd "$REPO_ROOT" && git diff --cached --name-only 2>/dev/null || true)"
    if [ -z "$staged" ]; then
        note_error "nothing is staged -- 07-stage-release.sh did not run or staged nothing"
        return
    fi

    for want in \
        "public/stable/version.json" \
        "public/stable/version.sig" \
        "public/stable/appcast.xml" \
        "package.json"
    do
        if printf '%s\n' "$staged" | /usr/bin/grep -qx "$want"; then
            note_pass "staged: ${want}"
        else
            note_error "not staged: ${want} (07-stage-release.sh stages it)"
        fi
    done

    # The DMG checksum filename carries the version, so match the shape.
    if printf '%s\n' "$staged" | /usr/bin/grep -qE '^public/stable/.+\.dmg\.sha256$'; then
        note_pass "staged: public/stable/<release>.dmg.sha256"
    else
        note_error "not staged: public/stable/<release>.dmg.sha256"
    fi
}

check_release() {
    echo "--- Release Agent Checks ---"

    # Step 11 deliberately places the required release-notes commit after the
    # version commit, so validate the newest matching release commit in history.
    release_msg="$(cd "$REPO_ROOT" && git log --extended-regexp --grep="$RELEASE_COMMIT_REGEX" -1 --format=%s 2>/dev/null || true)"
    if [ -n "$release_msg" ]; then
        note_pass "Commit message format correct: ${release_msg}"
    else
        note_error "No release commit matches v<version>: ... [deploy]"
    fi

    # The newest matching commit exists in every repo that ever shipped, so on
    # its own that match cannot fail for THIS release. Bind it to the version
    # the release actually staged: the commit's v<version> must equal
    # public/stable/version.json, or the release was never committed.
    version_json="$REPO_ROOT/public/stable/version.json"
    shipped_version=""
    if [ -f "$version_json" ]; then
        shipped_version="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$version_json" | head -1)"
    fi
    if [ -z "$shipped_version" ]; then
        note_error "cannot read version from public/stable/version.json"
    elif [ -n "$release_msg" ]; then
        commit_version="${release_msg#v}"
        commit_version="${commit_version%%:*}"
        if [ "$commit_version" = "$shipped_version" ]; then
            note_pass "Release commit version matches version.json (${shipped_version})"
        else
            note_error "Newest release commit is v${commit_version} but version.json says ${shipped_version} -- this release was not committed"
        fi
    fi

    # The release can run from the required isolated worktree branch.
    # Verify publication state instead of requiring a literal branch name.
    head_sha="$(cd "$REPO_ROOT" && git rev-parse HEAD 2>/dev/null || echo "")"
    remote_main_sha="$(cd "$REPO_ROOT" && git ls-remote origin refs/heads/main 2>/dev/null | awk 'NR == 1 {print $1}')"
    if [ -n "$head_sha" ] && [ "$head_sha" = "$remote_main_sha" ]; then
        note_pass "Remote main matches HEAD"
    else
        note_error "Remote main does not match HEAD"
    fi

    # No unstaged changes after commit
    dirty="$(cd "$REPO_ROOT" && git status --porcelain 2>/dev/null | /usr/bin/grep -v '^??' | head -1 || echo "")"
    if [ -z "$dirty" ]; then
        note_pass "Working tree clean after commit"
    else
        note_error "Working tree dirty after commit"
    fi
}

case "$phase" in
    verify)    check_verify ;;
    release)   check_release ;;
    all)
        check_verify
        check_release
        ;;
    *)
        echo "Unknown phase: ${phase}" >&2
        exit 2
        ;;
esac

echo ""
if [ $ERRORS -gt 0 ]; then
    echo "Agent verification: ${ERRORS} issue(s) found"
    exit 1
else
    echo "Agent verification: all checks passed"
    exit 0
fi
