#!/bin/bash
# Gate receipt contract — shared by every script on scripts/lib/gate-roster.txt.
#
# WHY THIS EXISTS
#
# Every gate in this repo used to answer exactly one question — "did anything
# fail?" — via its exit code. `exit 0` is unfalsifiable: it is produced
# identically by "ran everything, found nothing" and by "ran nothing". No gate
# could answer "what did I run?".
#
# That made every hardening fix an ENUMERATION fix: find one route by which a
# gate can skip its own work, add a NEGATIVE marker for that one route. The
# enumeration is open-ended (a new `if [ -f ]`, a new optional flag, a new empty
# scan set, a new absent toolchain, a new git-diff window), so it never closes —
# 33 distinct shell files were patched this way between 2025-12 and 2026-08, and
# the discovery rate was still rising.
#
# Worse, each negative marker leaves the POSITIVE claim unstated, which
# manufactures the next inference-from-absence. That is literally what happened:
# `1da77f08f` added a `— xcodebuild regression SKIPPED (...)` suffix to
# 03-verify-components.sh, and the next day a reader took the ABSENCE of that
# suffix as proof the native slice had executed. It had, but nothing in the
# output said so.
#
# THE CONTRACT
#
# A gate declares its units of work up front in scripts/lib/units/<gate>.units,
# records each one as RAN (with a measured quantity) or SKIP (with a reason), and
# CANNOT print a passing receipt unless every declared unit is accounted for.
# Any path that reaches the summary without recording work fails — without
# anyone having had to anticipate that particular route.
#
# That is the difference from the 22 prior fixes: "mark every skip" requires
# enumerating an infinite set; "account for every declared unit" enumerates a
# finite one that is checked into git.
#
# Output shape (digest LAST, so a truncated transcript is detectable — no
# RECEIPT line means no pass):
#
#   RAN|shell-compat|scanned=118
#   RAN|xcode-regression|suites=12 executed=418
#   SKIP|yazi-flavor-assets|flavor directory absent
#   RECEIPT gate=03-verify-components ran=16 skipped=1 declared=17 result=PASS
#
# Bash 3.2 only: no associative arrays, no `mapfile`, no bash-4 declare flags.

GATE_NAME=""
GATE_RECEIPT_FILE=""
GATE_UNITS_FILE=""
GATE_COMPLETED=0
GATE_CLEANUP_FN=""

# Declared-unit ids, newline separated. A plain string rather than an array so
# membership tests stay bash 3.2 friendly.
GATE_DECLARED_UNITS=""

gate_receipt_lib_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

# gate_begin <gate-name> [cleanup-fn]
#
# Loads the declared unit roster and installs the abort trap. Fails closed when
# the units file is missing or empty — a gate that cannot say what it intends to
# verify has nothing to report.
gate_begin() {
    GATE_NAME="$1"
    GATE_CLEANUP_FN="${2:-}"

    local lib_dir
    lib_dir="$(gate_receipt_lib_dir)"
    GATE_UNITS_FILE="$lib_dir/units/${GATE_NAME}.units"

    if [ ! -f "$GATE_UNITS_FILE" ]; then
        echo "  X gate-receipt: no unit declaration at scripts/lib/units/${GATE_NAME}.units" >&2
        echo "    Every gate must declare the work it intends to perform. Create the file." >&2
        exit 1
    fi

    GATE_DECLARED_UNITS="$(grep -v '^[[:space:]]*#' "$GATE_UNITS_FILE" 2>/dev/null | grep -v '^[[:space:]]*$' || true)"
    if [ -z "$GATE_DECLARED_UNITS" ]; then
        echo "  X gate-receipt: ${GATE_NAME}.units declares zero units — an empty roster is a false green" >&2
        exit 1
    fi

    GATE_RECEIPT_FILE="$(mktemp -t "yen-gate-${GATE_NAME}")"
    GATE_COMPLETED=0

    # Single-slot traps in bash 3.2, so callers hand their cleanup to gate_begin
    # rather than installing a second EXIT trap that would silently replace this
    # one. This subsumes the three hand-copied completion sentinels.
    trap 'gate_receipt_abort' EXIT
    trap 'gate_receipt_abort' INT
    trap 'gate_receipt_abort' TERM
}

gate_unit_is_declared() {
    local id="$1"
    local declared
    while IFS= read -r declared; do
        [ "$declared" = "$id" ] && return 0
    done <<EOF
$GATE_DECLARED_UNITS
EOF
    return 1
}

# gate_unit_ran <id> <evidence>
#
# `evidence` must be a MEASUREMENT, not a label. A unit that examined nothing is
# a failure, not a pass — that is the empty-scan-set false green, which has been
# the single most common shape in this repo's history.
gate_unit_ran() {
    local id="$1"
    local evidence="${2:-}"

    if ! gate_unit_is_declared "$id"; then
        echo "  X gate-receipt: '$id' is not declared in ${GATE_NAME}.units" >&2
        exit 1
    fi
    if [ -z "$evidence" ]; then
        echo "  X gate-receipt: unit '$id' recorded RAN with no evidence — a bare claim is not a receipt" >&2
        exit 1
    fi
    # Only a SOLE zero measurement is rejected. Multi-field evidence such as
    # "entries=3 findings=0" is a legitimate clean result — three things were
    # examined and none were bad. Rejecting any zero-valued field would ban the
    # normal shape of a passing scan.
    case "$evidence" in
        *[[:space:]]*)
            : # multi-field evidence carries at least one other measurement
            ;;
        0|*=0)
            echo "  X gate-receipt: unit '$id' recorded RAN with a zero quantity ('$evidence')" >&2
            echo "    A gate that examined nothing has not passed. Use gate_unit_skipped with a reason." >&2
            exit 1
            ;;
    esac

    echo "RAN|$id|$evidence" >> "$GATE_RECEIPT_FILE"
}

# gate_unit_skipped <id> <reason>
#
# A skip is legitimate and is reported on BOTH the pass and fail branch. What is
# never legitimate is a skip that leaves no trace.
gate_unit_skipped() {
    local id="$1"
    local reason="${2:-}"

    if ! gate_unit_is_declared "$id"; then
        echo "  X gate-receipt: '$id' is not declared in ${GATE_NAME}.units" >&2
        exit 1
    fi
    if [ -z "$reason" ]; then
        echo "  X gate-receipt: unit '$id' recorded SKIP with no reason" >&2
        exit 1
    fi

    echo "SKIP|$id|$reason" >> "$GATE_RECEIPT_FILE"
}

# gate_subgate <id> <command...>
#
# Runs a child gate, capturing its output. On success the child's own receipt or
# summary line becomes this unit's evidence, so sub-gate measurements survive the
# caller instead of dying in a `>/dev/null`. On failure the full body is printed.
gate_subgate() {
    local id="$1"
    shift

    local body="" rc=0
    body="$("$@" 2>&1)" || rc=$?

    if [ "$rc" -ne 0 ]; then
        echo "$body"
        return "$rc"
    fi

    local evidence
    evidence="$(printf '%s\n' "$body" | grep -E '^(RECEIPT |[[:space:]]*(OK|✓) )' | tail -1 | sed 's/^[[:space:]]*//')"
    [ -n "$evidence" ] || evidence="exit=0 lines=$(printf '%s\n' "$body" | grep -c . || true)"
    gate_unit_ran "$id" "$evidence"
    return 0
}

# gate_end <failed-count> [fail-exit-code]
#
# Prints every recorded unit on BOTH branches, then the digest. Refuses to
# report PASS if any declared unit recorded neither line, recorded both, or if
# nothing ran at all.
#
# `fail-exit-code` preserves a gate's existing exit contract. 13-scan-artifact-
# fingerprints.sh distinguishes 2 (findings remain / nothing scanned) from 1
# (internal abort), and callers switch on it -- collapsing them would silently
# change the release path's error handling.
gate_end() {
    local failed="${1:-0}"
    local fail_code="${2:-1}"

    local declared_count ran_count skipped_count
    declared_count="$(printf '%s\n' "$GATE_DECLARED_UNITS" | grep -c . || true)"
    ran_count="$(grep -c '^RAN|' "$GATE_RECEIPT_FILE" 2>/dev/null || true)"
    skipped_count="$(grep -c '^SKIP|' "$GATE_RECEIPT_FILE" 2>/dev/null || true)"
    [ -n "$ran_count" ] || ran_count=0
    [ -n "$skipped_count" ] || skipped_count=0

    # Unit accounting runs before the pass/fail decision so an unrecorded unit
    # cannot be masked by an otherwise-green run.
    local unaccounted="" duplicated="" id seen
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        seen="$(grep -c "^\(RAN\|SKIP\)|$id|" "$GATE_RECEIPT_FILE" 2>/dev/null || true)"
        [ -n "$seen" ] || seen=0
        if [ "$seen" -eq 0 ]; then
            unaccounted="$unaccounted $id"
        elif [ "$seen" -gt 1 ]; then
            duplicated="$duplicated $id"
        fi
    done <<EOF
$GATE_DECLARED_UNITS
EOF

    sort "$GATE_RECEIPT_FILE" 2>/dev/null || true

    GATE_COMPLETED=1

    if [ -n "$unaccounted" ]; then
        echo "  X $GATE_NAME reached its summary without accounting for:$unaccounted"
        echo "    Each declared unit must record gate_unit_ran or gate_unit_skipped."
        echo "RECEIPT gate=$GATE_NAME ran=$ran_count skipped=$skipped_count declared=$declared_count result=FAIL"
        gate_receipt_finish 1
    fi
    if [ -n "$duplicated" ]; then
        echo "  X $GATE_NAME recorded duplicate outcomes for:$duplicated"
        echo "RECEIPT gate=$GATE_NAME ran=$ran_count skipped=$skipped_count declared=$declared_count result=FAIL"
        gate_receipt_finish 1
    fi
    if [ "$ran_count" -eq 0 ]; then
        echo "  X $GATE_NAME ran zero units — an all-skipped gate is not a pass"
        echo "RECEIPT gate=$GATE_NAME ran=0 skipped=$skipped_count declared=$declared_count result=FAIL"
        gate_receipt_finish 1
    fi

    if [ "$failed" -eq 0 ]; then
        echo "RECEIPT gate=$GATE_NAME ran=$ran_count skipped=$skipped_count declared=$declared_count result=PASS"
        gate_receipt_finish 0
    fi

    echo "RECEIPT gate=$GATE_NAME ran=$ran_count skipped=$skipped_count declared=$declared_count result=FAIL"
    gate_receipt_finish "$fail_code"
}

# gate_end_disabled <reason>
#
# For a gate switched OFF by explicit operator choice (a *_GATE_MODE=off env).
# That is a legitimate all-skip, so it must not trip the "ran zero units" rule --
# but it must also never render as a pass. `result=DISABLED` is honest and stays
# distinguishable from `result=PASS` for anything grepping the digest.
gate_end_disabled() {
    local reason="${1:-unspecified}"
    local declared_count
    declared_count="$(printf '%s\n' "$GATE_DECLARED_UNITS" | grep -c . || true)"
    sort "$GATE_RECEIPT_FILE" 2>/dev/null || true
    GATE_COMPLETED=1
    echo "RECEIPT gate=$GATE_NAME ran=0 skipped=$declared_count declared=$declared_count result=DISABLED reason=$reason"
    gate_receipt_finish 0
}

gate_receipt_finish() {
    local rc="${1:-0}"
    [ -n "$GATE_CLEANUP_FN" ] && "$GATE_CLEANUP_FN"
    rm -f "$GATE_RECEIPT_FILE" 2>/dev/null || true
    trap - EXIT INT TERM
    exit "$rc"
}

# Abort handler. A gate that dies before gate_end — a `set -e` fatal, a swallowed
# subprocess error, an interrupt — must never leave its earlier "✓" lines reading
# as a verdict.
gate_receipt_abort() {
    local rc=$?
    trap - EXIT INT TERM
    if [ "$GATE_COMPLETED" != "1" ]; then
        echo "  X ${GATE_NAME:-gate} aborted before emitting a RECEIPT — nothing above was verified (exit=$rc)" >&2
        [ -n "$GATE_CLEANUP_FN" ] && "$GATE_CLEANUP_FN"
        rm -f "$GATE_RECEIPT_FILE" 2>/dev/null || true
        exit 1
    fi
    [ -n "$GATE_CLEANUP_FN" ] && "$GATE_CLEANUP_FN"
    rm -f "$GATE_RECEIPT_FILE" 2>/dev/null || true
    exit "$rc"
}
