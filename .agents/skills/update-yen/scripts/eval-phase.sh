#!/bin/bash
# eval-phase.sh — Machine-evaluable pass/fail per phase
# Usage:
#   eval-phase.sh check <skill> <check_id> <description> <command...>
#   eval-phase.sh summary <skill>
#
# Output: tmp/skill-telemetry/<skill>-eval-<date>.jsonl
# Each check produces a JSONL line: {"check_id":"PF-01","desc":"...","pass":true}
# Live progress:
#   - Prints [RUN] at check start
#   - Prints [RUNNING] heartbeat every N seconds for long checks
#   - Prints trailing command output on failures
# Env:
#   YEN_SKILL_EVAL_HEARTBEAT_SECONDS (default: 20, set 0 to disable heartbeat)
# Bash 3.2 compatible.

set -euo pipefail

# Resolve this script's own directory PHYSICALLY before walking up. The skill
# dirs are symlinked into ~/.claude and ~/.codex, and a logical `cd` applies
# ".." to the symlink path, so invoking by skill path resolved REPO_ROOT to
# the home directory instead of the repo.
SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd -P "$SCRIPT_DIR/../../../.." && pwd -P)"
TELEMETRY_DIR="${REPO_ROOT}/tmp/skill-telemetry"
mkdir -p "$TELEMETRY_DIR"

# JSON string escaping. Backslash MUST be escaped before the quote pass, or the
# backslash this pass introduces gets escaped again. The old form handled only
# `"`, so any command carrying a regex escape (\., \[, \d) emitted a line that
# is not valid JSON — measured: 3 of 165 records written on 2026-09-01 failed a
# strict parser, in files this skill advertises as machine-evaluable JSONL. The
# summary's awk never noticed, so the corruption was invisible to the only
# reader that ever looked.
json_escape() {
    printf '%s' "$1" \
        | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' \
        | awk 'BEGIN { ORS = "" } NR > 1 { print "\\n" } { print }'
}

action="${1:-}"
skill="${2:-}"

if [ -z "$action" ] || [ -z "$skill" ]; then
    echo "Usage: eval-phase.sh <begin|check|summary> <skill> [args...]" >&2
    exit 2
fi

DATE_TAG="$(date +%Y%m%d)"
EVAL_FILE="${TELEMETRY_DIR}/${skill}-eval-${DATE_TAG}.jsonl"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# The eval file is keyed to the LOCAL date, so a run that crosses local
# midnight writes into two files. `summary` reads today's, so a FAIL recorded
# before midnight would otherwise vanish and the post-midnight subset would
# read green. Resolve the previous day's file so `summary` can carry unresolved
# failures forward. BSD date first (macOS), GNU as the fallback.
PREV_DATE_TAG="$(date -v-1d +%Y%m%d 2>/dev/null || date -d 'yesterday' +%Y%m%d 2>/dev/null || echo '')"
PREV_EVAL_FILE=""
if [ -n "$PREV_DATE_TAG" ]; then
    PREV_EVAL_FILE="${TELEMETRY_DIR}/${skill}-eval-${PREV_DATE_TAG}.jsonl"
fi

# The eval file is keyed to the DAY, but a verdict is about ONE RUN. Without a
# run id, `summary` reported the latest result per check ID across every run of
# that skill that day, so a check from an earlier run counted as this run's
# evidence. Measured on 2026-09-01: a vendor run that built nothing still
# reported 14/14 because VB-02 (compile gate) carried over from a release run
# five hours earlier, whose smoke log had already been deleted. That is the
# borrowed-evidence form of the empty-scan-set false green.
RUN_ID_FILE="${TELEMETRY_DIR}/${skill}-eval-run.id"
current_run_id() {
    if [ -f "$RUN_ID_FILE" ]; then
        cat "$RUN_ID_FILE"
    else
        echo ""
    fi
}

# The per-skill check-ID contract. `check` rejects an ID that does not match and
# `summary` counts only matching IDs, so the two can never disagree about which
# checks exist. An unknown skill keeps the permissive default.
CHECK_ID_PATTERN='.*'
case "$skill" in
    update-yen)
        CHECK_ID_PATTERN='^(PF|BD|VF|RL)-[0-9][0-9]$'
        ;;
    yen-vendor)
        CHECK_ID_PATTERN='^(VC|VU|VA|VB|VK)-[0-9][0-9]$'
        ;;
    yen-deps)
        CHECK_ID_PATTERN='^DP-[0-9][0-9]$'
        ;;
esac

case "$action" in
    begin)
        # Start a new run. Every later `check` stamps this id and `summary`
        # counts only records carrying it, so two runs on one day cannot borrow
        # each other's results.
        new_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
        printf '%s' "$new_id" > "$RUN_ID_FILE"
        echo "{\"ts\":\"${TIMESTAMP}\",\"skill\":\"${skill}\",\"event\":\"run_start\",\"run_id\":\"${new_id}\"}" >> "$EVAL_FILE"
        echo "[RUN-ID] ${skill} run ${new_id}"
        exit 0
        ;;
    check)
        check_id="${3:-}"
        description="${4:-}"
        shift 4
        command_to_run="$*"

        if [ -z "$check_id" ] || [ -z "$description" ]; then
            echo "Usage: eval-phase.sh check <skill> <check_id> <description> <command...>" >&2
            exit 2
        fi

        # A check with no command is the emptiest possible scan set: `eval ""`
        # exits 0, so the check would be recorded as a PASS having verified
        # nothing at all. Refuse it rather than mint a green from silence.
        if [ -z "$(printf '%s' "$command_to_run" | tr -d '[:space:]')" ]; then
            echo "ERROR: check '${check_id}' was given no command to run." >&2
            echo "  An empty command exits 0 and would be recorded as a PASS that verified nothing." >&2
            exit 2
        fi

        # Reject a malformed ID here rather than letting it be written and then
        # silently dropped by the summary's filter. A check that vanishes from
        # the summary is indistinguishable from one that was never run.
        if ! printf '%s' "$check_id" | grep -Eq "$CHECK_ID_PATTERN"; then
            echo "ERROR: check_id '${check_id}' does not match the ${skill} contract ${CHECK_ID_PATTERN}" >&2
            echo "  A non-conforming ID would be written but excluded from the summary count." >&2
            exit 2
        fi

        heartbeat_seconds="${YEN_SKILL_EVAL_HEARTBEAT_SECONDS:-20}"
        case "$heartbeat_seconds" in
            ""|*[!0-9]*)
                heartbeat_seconds=20
                ;;
        esac

        echo "[RUN] ${check_id}: ${description}"
        cmd_log="${TELEMETRY_DIR}/${skill}-${check_id}-$$.log"
        start_epoch="$(date +%s)"

        # Run command in background so we can emit heartbeats while waiting.
        # The explicit subshell is load-bearing: under bash 3.2 a bare
        # `eval "$cmd" &` lets `command <external>` exec in place of the
        # background job, which skips every later step and records that one
        # tool's exit code as the verdict.
        set +e
        ( eval "$command_to_run" ) >"$cmd_log" 2>&1 &
        cmd_pid=$!

        # Poll for the command's end every 0.2 s and print a heartbeat once per
        # interval. Sleeping the whole interval before looking again made every
        # check last a multiple of it: a `test` that returned in 40 ms was
        # recorded 20 s later, on each of the roughly 45 checks in a full run.
        if [ "$heartbeat_seconds" -gt 0 ]; then
            next_heartbeat=$((start_epoch + heartbeat_seconds))
            while kill -0 "$cmd_pid" 2>/dev/null; do
                sleep 0.2
                now_epoch="$(date +%s)"
                if [ "$now_epoch" -ge "$next_heartbeat" ] && kill -0 "$cmd_pid" 2>/dev/null; then
                    elapsed=$((now_epoch - start_epoch))
                    mins=$((elapsed / 60))
                    secs=$((elapsed % 60))
                    printf '[RUNNING] %s: %s (%dm%02ds)\n' "$check_id" "$description" "$mins" "$secs"
                    next_heartbeat=$((now_epoch + heartbeat_seconds))
                fi
            done
        fi

        wait "$cmd_pid"
        cmd_exit=$?
        set -e

        if [ $cmd_exit -eq 0 ]; then
            pass="true"
            status="PASS"
        else
            pass="false"
            status="FAIL"
        fi

        # Escape description
        desc_escaped="$(json_escape "$description")"
        cmd_escaped="$(json_escape "$command_to_run")"

        # Auto-open a run when the caller did not, so `check` never blocks; the
        # id still separates this run from earlier ones in the same file.
        run_id="$(current_run_id)"
        if [ -z "$run_id" ]; then
            run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
            printf '%s' "$run_id" > "$RUN_ID_FILE"
        fi
        echo "{\"ts\":\"${TIMESTAMP}\",\"run_id\":\"${run_id}\",\"check_id\":\"${check_id}\",\"desc\":\"${desc_escaped}\",\"pass\":${pass},\"exit_code\":${cmd_exit},\"cmd\":\"${cmd_escaped}\"}" >> "$EVAL_FILE"

        if [ "$cmd_exit" -ne 0 ] && [ -s "$cmd_log" ]; then
            echo "  Last command output (tail):"
            tail -n 20 "$cmd_log" | sed 's/^/    /'
        fi
        rm -f "$cmd_log"

        echo "[${status}] ${check_id}: ${description}"
        exit "$cmd_exit"
        ;;
    summary)
        # No eval file means nothing was verified. That is a failure, not a pass:
        # an absent record is not evidence that the phases ran.
        if [ ! -f "$EVAL_FILE" ]; then
            echo "=== Eval Summary: ${skill} (${DATE_TAG}) ==="
            echo "No eval data for ${skill} on ${DATE_TAG} — nothing was verified."
            echo ""
            echo "Result: FAIL"
            exit 1
        fi

        SUMMARY_TMP="$(mktemp)"
        CARRY_TMP="$(mktemp)"
        : > "$CARRY_TMP"

        # Latest result per check ID, pattern-filtered, as "<id>\t<pass>\t<desc>".
        # `want_run` scopes to one run: empty means "any run" (used for the
        # previous day's carry-forward, where the run is by definition a
        # different one).
        latest_per_id() {
            awk -v want_run="${2:-}" '
            {
                if (match($0, /"check_id":"[^"]+"/) == 0) next
                cid = substr($0, RSTART + 12, RLENGTH - 13)

                rid = ""
                if (match($0, /"run_id":"[^"]*"/) != 0) {
                    rid = substr($0, RSTART + 10, RLENGTH - 11)
                }
                if (want_run != "" && rid != want_run) next

                pass = "false"
                if (match($0, /"pass":(true|false)/) != 0) {
                    pass = substr($0, RSTART + 7, RLENGTH - 7)
                }

                desc = ""
                if (match($0, /"desc":"[^"]*"/) != 0) {
                    desc = substr($0, RSTART + 8, RLENGTH - 9)
                }

                last_pass[cid] = pass
                last_desc[cid] = desc
            }
            END {
                for (cid in last_pass) {
                    printf "%s\t%s\t%s\n", cid, last_pass[cid], last_desc[cid]
                }
            }
            ' "$1" | awk -F '\t' -v pat="$CHECK_ID_PATTERN" '$1 ~ pat { print $0 }'
        }

        ACTIVE_RUN_ID="$(current_run_id)"
        latest_per_id "$EVAL_FILE" "$ACTIVE_RUN_ID" > "$SUMMARY_TMP"

        # Say plainly how many of today's checks belong to earlier runs and are
        # therefore excluded. Silence here is what made the borrowed evidence
        # invisible in the first place.
        OTHER_RUN_COUNT=0
        if [ -n "$ACTIVE_RUN_ID" ]; then
            ALL_TODAY_TMP="$(mktemp)"
            latest_per_id "$EVAL_FILE" "" > "$ALL_TODAY_TMP"
            OTHER_RUN_COUNT=$(( $(wc -l < "$ALL_TODAY_TMP" | tr -d ' ') - $(wc -l < "$SUMMARY_TMP" | tr -d ' ') ))
            rm -f "$ALL_TODAY_TMP"
        fi

        # Carry forward ONLY unresolved failures from the previous local day,
        # and only for check IDs today did not re-run. Passes are deliberately
        # never carried: importing yesterday's greens would let a run that
        # verified almost nothing today report a full, healthy total -- the
        # same false green this gate exists to prevent, one day displaced.
        if [ -n "$PREV_EVAL_FILE" ] && [ -f "$PREV_EVAL_FILE" ]; then
            latest_per_id "$PREV_EVAL_FILE" \
                | awk -F '\t' 'NR==FNR { seen[$1]=1; next } $2=="false" && !($1 in seen)' \
                    "$SUMMARY_TMP" - > "$CARRY_TMP"
        fi

        carried="$(wc -l < "$CARRY_TMP" | tr -d ' ')"
        today_total="$(wc -l < "$SUMMARY_TMP" | tr -d ' ')"
        passed="$(awk -F '\t' '$2=="true" { c++ } END { print c+0 }' "$SUMMARY_TMP")"
        failed="$(awk -F '\t' '$2=="false" { c++ } END { print c+0 }' "$SUMMARY_TMP")"
        failed=$((failed + carried))
        total=$((today_total + carried))

        echo "=== Eval Summary: ${skill} (${DATE_TAG}) ==="
        echo "Total checks (latest result per check ID): ${total}"
        echo "Passed (latest): ${passed}"
        echo "Failed (latest): ${failed}"
        if [ "$carried" -gt 0 ]; then
            echo "Carried forward from ${PREV_DATE_TAG}: ${carried} unresolved failure(s) -- a run that crossed local midnight."
        fi
        if [ -z "$ACTIVE_RUN_ID" ]; then
            echo "Run scope: UNSCOPED -- no run id recorded, so this counts every check today regardless of which run produced it."
        elif [ "$OTHER_RUN_COUNT" -gt 0 ]; then
            echo "Run scope: ${ACTIVE_RUN_ID} (${OTHER_RUN_COUNT} check(s) from earlier runs today excluded)."
        else
            echo "Run scope: ${ACTIVE_RUN_ID}."
        fi
        echo ""

        # An empty set is the worst outcome to report as green: it is what a run
        # with zero recorded checks looks like. Fail closed before the pass path.
        if [ "$today_total" -eq 0 ]; then
            echo "No checks matched the ${skill} contract ${CHECK_ID_PATTERN} — nothing was verified."
            echo ""
            rm -f "$SUMMARY_TMP" "$CARRY_TMP"
            echo "Result: FAIL"
            exit 1
        fi

        if [ "$failed" -gt 0 ]; then
            echo "--- Failed Checks ---"
            awk -F '\t' '$2=="false" { print $1 "\t" $3 }' "$SUMMARY_TMP" | while IFS=$'\t' read -r cid desc; do
                echo "  [FAIL] ${cid}: ${desc}"
            done
            awk -F '\t' '{ print $1 "\t" $3 }' "$CARRY_TMP" | while IFS=$'\t' read -r cid desc; do
                echo "  [FAIL] ${cid}: ${desc} (unresolved from ${PREV_DATE_TAG}; re-run it to clear)"
            done
            echo ""
            rm -f "$SUMMARY_TMP" "$CARRY_TMP"
            echo "Result: FAIL"
            exit 1
        else
            rm -f "$SUMMARY_TMP" "$CARRY_TMP"
            echo "Result: PASS"
            exit 0
        fi
        ;;
    *)
        echo "Unknown action: ${action}" >&2
        exit 2
        ;;
esac
