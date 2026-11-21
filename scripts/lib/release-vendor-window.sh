#!/bin/bash
# Release vendor window — may a shipping build proceed while Ghostty upstream
# is ahead of the committed baseline?
#
# /update-yen Step 1 asks `14-vendor.sh --check --release`. The vendor gate exists
# to block in-flight vendor mutations and unaudited engines; a Ghostty baseline
# that the /update-yen vendor phase audited, built and pushed satisfies that even when upstream
# `main` gained commits during the lap. Measured: 4 of 12 releases failed the
# plain check for that reason, each costing another full vendor run.
#
# Acceptance requires ALL of:
#   1. no in-flight vendor mutation: the baseline, VENDOR_INFO.txt, overlays,
#      the overlay pair manifest and _docs/04-security.md are clean in the tree
#   2. the newest commit touching yen-terminal/.ghostty-baseline has a
#      `vendor:` subject, which is how the vendor phase commits its audited run
#   3. that commit's committer time is within RELEASE_VENDOR_WINDOW_HOURS
#   4. that commit is reachable from origin/main after a fresh fetch, so the
#      audited baseline is published, not local
#
# Only Ghostty is covered: it tracks a moving branch. Binary vendors follow
# release tags and still block when behind. Unknown status, errors and missing
# binaries always block. The window is a constant on purpose: an env override
# would be a bypass, and this file is the one place the rule lives.
#
# Bash 3.2 compatible. Sourced, never executed.

RELEASE_VENDOR_WINDOW_HOURS=24
RELEASE_VENDOR_TRACKED_PATHS="yen-terminal/.ghostty-baseline yen-terminal/VENDOR_INFO.txt yen-terminal/.overlay-upstream-pairs.txt yen-terminal/overlays _docs/04-security.md"

# release_vendor_window_accepts_ghostty <repo_root>
# Sets RELEASE_VENDOR_WINDOW_REASON (why it was refused) or
# RELEASE_VENDOR_WINDOW_EVIDENCE (commit, age) and returns 0 on acceptance.
release_vendor_window_accepts_ghostty() {
    local repo_root="$1"
    local dirty baseline_commit subject committed_at now age_hours
    RELEASE_VENDOR_WINDOW_REASON=""
    RELEASE_VENDOR_WINDOW_EVIDENCE=""

    if ! git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        RELEASE_VENDOR_WINDOW_REASON="not a git checkout"
        return 1
    fi

    # shellcheck disable=SC2086
    dirty="$(git -C "$repo_root" status --porcelain -- $RELEASE_VENDOR_TRACKED_PATHS 2>/dev/null | head -1)"
    if [ -n "$dirty" ]; then
        RELEASE_VENDOR_WINDOW_REASON="vendor files are modified in the working tree (${dirty}); commit the vendor run first"
        return 1
    fi

    baseline_commit="$(git -C "$repo_root" log -1 --format=%H -- yen-terminal/.ghostty-baseline 2>/dev/null || true)"
    if [ -z "$baseline_commit" ]; then
        RELEASE_VENDOR_WINDOW_REASON="no commit touches yen-terminal/.ghostty-baseline"
        return 1
    fi

    subject="$(git -C "$repo_root" log -1 --format=%s "$baseline_commit" 2>/dev/null || true)"
    case "$subject" in
        vendor:*) ;;
        *)
            RELEASE_VENDOR_WINDOW_REASON="baseline commit ${baseline_commit:0:12} is not a vendor: commit (${subject})"
            return 1
            ;;
    esac

    committed_at="$(git -C "$repo_root" log -1 --format=%ct "$baseline_commit" 2>/dev/null || echo "")"
    now="$(date +%s)"
    case "$committed_at$now" in
        ''|*[!0-9]*)
            RELEASE_VENDOR_WINDOW_REASON="could not read the baseline commit time"
            return 1
            ;;
    esac
    age_hours=$(( (now - committed_at) / 3600 ))
    if [ "$age_hours" -ge "$RELEASE_VENDOR_WINDOW_HOURS" ]; then
        RELEASE_VENDOR_WINDOW_REASON="baseline commit ${baseline_commit:0:12} is ${age_hours}h old, outside the ${RELEASE_VENDOR_WINDOW_HOURS}h release window; run the /update-yen vendor phase"
        return 1
    fi

    if ! git -C "$repo_root" fetch -q origin main 2>/dev/null; then
        RELEASE_VENDOR_WINDOW_REASON="could not fetch origin/main to prove the baseline commit is published"
        return 1
    fi
    if ! git -C "$repo_root" merge-base --is-ancestor "$baseline_commit" FETCH_HEAD 2>/dev/null; then
        RELEASE_VENDOR_WINDOW_REASON="baseline commit ${baseline_commit:0:12} is not on origin/main; push the vendor run first"
        return 1
    fi

    RELEASE_VENDOR_WINDOW_EVIDENCE="baseline_commit=${baseline_commit:0:12} age_hours=${age_hours} window_hours=${RELEASE_VENDOR_WINDOW_HOURS}"
    return 0
}
