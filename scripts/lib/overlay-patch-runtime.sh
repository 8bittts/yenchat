#!/bin/bash
# Shared patch execution and tally contract for overlay application and fixtures.

# Run patch-file.py against $1; every trailing arg passes through verbatim.
#
# FAIL-CLOSED ON A MISSING TARGET. A patch target that no longer exists means
# upstream moved, renamed, or deleted the file — the patch is silently lost and
# the build ships without it. That is the exact failure mode an upstream
# API-boundary refactor produces, so absence is an error, not a skip. Anchor
# drift (target present, marker gone) was already fail-closed: patch-file.py
# exits non-zero and `set -e` aborts the run.
#
# Pass --optional immediately after the path for a target that is genuinely
# allowed to be absent; the call site must say why. the patch-target manifest
# validates every non-optional target up front so an upstream restructure
# reports the complete list instead of one path per run.
# Authoritative overlay tallies. Before this, apply-overlays.sh printed only
# "Overlays applied" and build-release.sh reconstructed counts by grepping the
# prose it happened to emit. Two consumers grepping free text disagreed --
# measured 46 vs 44 on the same run -- and neither number came from the code
# that did the work, so a reported figure could not be trusted.
OVERLAY_APPLIED=0
OVERLAY_SKIPPED=0

patch_file() {
    local file="$1"
    shift
    local optional=0
    if [ "${1:-}" = "--optional" ]; then
        optional=1
        shift
    fi
    if [ ! -f "$file" ]; then
        if [ "$optional" -eq 1 ]; then
            return 0
        fi
        echo "  ERROR: patch target missing — $file"
        echo "         Upstream moved, renamed, or removed this file, so the patch"
        echo "         below cannot be applied and would be silently dropped."
        echo "         Re-anchor the patch, or mark the call --optional if the target"
        echo "         is legitimately absent."
        return 1
    fi
    # Capture so the tallies come from the util's own verdict lines rather than
    # from a downstream grep over the whole log.
    local patch_out patch_rc
    set +e
    patch_out="$(python3 "$PATCH_FILE_UTIL" --file "$file" "$@")"
    patch_rc=$?
    set -e
    [ -n "$patch_out" ] && printf '%s\n' "$patch_out"
    if [ "$patch_rc" -eq 0 ]; then
        local n_applied n_skipped
        n_applied=$(printf '%s\n' "$patch_out" | grep -c '^    Applied ' || true)
        n_skipped=$(printf '%s\n' "$patch_out" | grep -c '(idempotent skip)' || true)
        OVERLAY_APPLIED=$(( ${OVERLAY_APPLIED:-0} + n_applied ))
        OVERLAY_SKIPPED=$(( ${OVERLAY_SKIPPED:-0} + n_skipped ))
    fi
    return "$patch_rc"
}

# For the handful of overlay steps that patch in shell rather than through
# patch-file.py. Keeping them in the same tally is what makes the printed
# figure mean "every overlay step", not "the ones that happened to match".
overlay_note_applied() { OVERLAY_APPLIED=$(( ${OVERLAY_APPLIED:-0} + 1 )); }
overlay_note_skipped() { OVERLAY_SKIPPED=$(( ${OVERLAY_SKIPPED:-0} + 1 )); }

# Run any overlay util that prints its own verdict lines, echo them through, and
# fold them into the same tally. patch-file.py is not the only emitter --
# remove-wrapper-sendable.py and apple-script-action-policy.py print the same
# vocabulary, and counting only patch_file undercounted the run by 3.
run_overlay_util() {
    local util_out util_rc
    set +e
    util_out="$("$@")"
    util_rc=$?
    set -e
    [ -n "$util_out" ] && printf '%s\n' "$util_out"
    if [ "$util_rc" -eq 0 ]; then
        local n_applied n_skipped
        n_applied=$(printf '%s\n' "$util_out" | grep -cE '^    (Applied|Injected|Patched|Removed|Added) ' || true)
        n_skipped=$(printf '%s\n' "$util_out" | grep -c '(idempotent skip)' || true)
        OVERLAY_APPLIED=$(( ${OVERLAY_APPLIED:-0} + n_applied ))
        OVERLAY_SKIPPED=$(( ${OVERLAY_SKIPPED:-0} + n_skipped ))
    fi
    return "$util_rc"
}

# Keep the plan loader in the same process as patch-file.py.
OVERLAY_PATCH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
apply_overlay_patch() {
    run_overlay_util python3 "$OVERLAY_PATCH_LIB_DIR/overlay-patch-plan.py" \
        --plan "$OVERLAY_PATCH_LIB_DIR/overlay-patch-plan.json" \
        --patches-dir "$PATCHES_DIR" --patch-tool "$PATCH_FILE_UTIL" "$1"
}
