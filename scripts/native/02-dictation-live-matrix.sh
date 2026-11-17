#!/bin/bash
# Dictation live-matrix capture + report harness for YEN.
#
# Closes the last manual-only validation on _docs/11-speech-to-text.md's
# "macOS 26 Verification Matrix": speaking into a live local YEN.app and
# capturing the per-session structured logs (stop_cause, fallback_used,
# insertion_outcome, transcript_source, key_up_to_insert_ms, state
# transitions) that the headless coordinator/controller harness cannot prove.
#
# The dictation subsystem logs via Swift print() to STDOUT (not os_log), so the
# only way to capture it is to launch the built binary from a terminal and tee
# its stdout. `log stream` will NOT see these lines. This harness does the
# launch + capture; the operator drives the physical hold-to-talk matrix from
# _docs/09-quality.md.
#
# Usage:
#   bash scripts/native/02-dictation-live-matrix.sh [capture] [--force]
#   bash scripts/native/02-dictation-live-matrix.sh report [<logfile>]
#   bash scripts/native/02-dictation-live-matrix.sh --help
#
# capture (default): preflight, launch zig-out/YEN.app as the SOLE instance,
#   stream the filtered Dictation* lines live while writing the full stdout to a
#   persistent log. Ctrl-C to stop; then run `report` on the saved log.
# report: parse a captured log into the per-session evidence table with
#   PASS/FAIL heuristics. With no <logfile>, uses the newest capture log.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOCAL_APP="$REPO_ROOT/yen-terminal/ghostty/zig-out/YEN.app"
LOCAL_APP_BIN="$LOCAL_APP/Contents/MacOS/yen"
LOG_DIR="$HOME/.yen-dictation-matrix"
DICTATION_FILTER='(DictationController|DictationHotKey|DictationRecognizer|SpeechAnalyzerRecognizer):'

usage() {
    cat <<EOF
Dictation live-matrix capture + report harness.

Usage:
  bash scripts/native/02-dictation-live-matrix.sh [capture] [--force]
  bash scripts/native/02-dictation-live-matrix.sh report [<logfile>]
  bash scripts/native/02-dictation-live-matrix.sh --help

capture (default):
  Preflight, then launch zig-out/YEN.app as the sole instance and stream the
  filtered Dictation* stdout live while saving the full log under $LOG_DIR.
  Ctrl-C to stop capture (kills the launched test instance).

  --force   Launch even when another YEN.app is already running. NOT
            recommended: two Option+Space CGEventTaps fight for the global
            hotkey and the result is non-deterministic. Prefer quitting the
            other instance first (see the runbook).

report [<logfile>]:
  Parse a captured log into the per-session structured-evidence table. With no
  argument, uses the newest log in $LOG_DIR.

  Exit codes (structural only — operator CHECK still needs human phrase review):
    0  sessions present, no FAIL verdicts, at least one terminal outcome
    1  incomplete session(s) or zero terminal outcomes
    2  zero sessions in the log

Runbook + fillable evidence template:
  $REPO_ROOT/_docs/09-quality.md
EOF
}

# ---- report ---------------------------------------------------------------

run_report() {
    local logfile="${1:-}"
    if [ -z "$logfile" ]; then
        if [ ! -d "$LOG_DIR" ]; then
            echo "ERROR: no log dir $LOG_DIR; run a capture first." >&2
            exit 1
        fi
        # Newest capture log (BSD ls -t; Bash 3.2 safe).
        logfile="$(cd "$LOG_DIR" && ls -t session-*.log 2>/dev/null | head -1 || true)"
        if [ -z "$logfile" ]; then
            echo "ERROR: no session-*.log in $LOG_DIR; run a capture first." >&2
            exit 1
        fi
        logfile="$LOG_DIR/$logfile"
    fi
    if [ ! -r "$logfile" ]; then
        echo "ERROR: cannot read log: $logfile" >&2
        exit 1
    fi

    echo "Dictation structured-log report"
    echo "Log: $logfile"
    echo

    awk '
    # Pull "key=value" tokens out of a DictationController: line.
    function kv(line, key,   re, seg, val) {
        re = "(^| )" key "=[^ ]+"
        if (match(line, re)) {
            seg = substr(line, RSTART, RLENGTH)
            sub("^ ?" key "=", "", seg)
            return seg
        }
        return ""
    }
    /DictationController: / {
        line = $0
        sub(/^.*DictationController: /, "", line)

        # State-transition lines: session_state_transition ... from=X to=Y
        if (line ~ /^session_state_transition/) {
            s = kv(line, "session")
            if (s == "" || s == "none") next
            to = kv(line, "to")
            if (to != "") {
                if (transitions[s] == "") transitions[s] = to
                else transitions[s] = transitions[s] " -> " to
            }
            if (!(s in seen)) { seen[s] = 1; order[++n] = s }
            next
        }

        ev = kv(line, "event")
        if (ev == "") next
        s = kv(line, "session")
        if (s == "" || s == "none") {
            noSession++
            next
        }
        if (!(s in seen)) { seen[s] = 1; order[++n] = s }

        if (events[s] == "") events[s] = ev
        else events[s] = events[s] ", " ev

        rec = kv(line, "recognizer"); if (rec != "") recognizer[s] = rec
        sc  = kv(line, "stop_cause"); if (sc != "") stopcause[s] = sc
        fb  = kv(line, "fallback_used"); if (fb != "") fallback[s] = fb
        ms  = kv(line, "key_up_to_insert_ms"); if (ms != "") latency[s] = ms
        io  = kv(line, "insertion_outcome"); if (io != "") outcome[s] = io
        ts  = kv(line, "transcript_source"); if (ts != "") source[s] = ts
    }
    END {
        ok_count = 0
        check_count = 0
        fail_count = 0
        terminal_count = 0

        if (n == 0) {
            print "No dictation sessions found in log."
            print "(Expected lines like: DictationController: event=... session=<uuid> ...)"
            # Structural FAIL for empty captures so automation can fail closed.
            print "STRUCTURAL: FAIL (zero sessions)"
            exit 2
        }
        for (i = 1; i <= n; i++) {
            s = order[i]
            printf "Session %d: %s\n", i, s
            printf "  recognizer      : %s\n", (recognizer[s] == "" ? "-" : recognizer[s])
            printf "  states          : %s\n", (transitions[s] == "" ? "-" : transitions[s])
            printf "  stop_cause      : %s\n", (stopcause[s] == "" ? "-" : stopcause[s])
            printf "  fallback_used   : %s\n", (fallback[s] == "" ? "-" : fallback[s])
            printf "  transcript_src  : %s\n", (source[s] == "" ? "-" : source[s])
            printf "  insertion       : %s\n", (outcome[s] == "" ? "-" : outcome[s])
            printf "  key_up_to_ins_ms: %s\n", (latency[s] == "" ? "-" : latency[s])
            printf "  events          : %s\n", events[s]

            # Verdict heuristics grounded in DictationController insertion policy.
            # NOTE: a normal (hotkeyRelease/legacyTimeout/paused) stop MAY carry
            # fallback legitimately when SpeechAnalyzer finalization genuinely
            # fails: transcriptForInsertion() allows fallback on
            # stopResult.stopMarkedAsFailure, which is NOT in the log. So this is
            # CHECK (operator confirms against the spoken phrase), never a hard
            # FAIL the log cannot prove.
            verdict = "OK"; note = ""
            sc = stopcause[s]; fb = fallback[s]; src = source[s]
            normalStop = (sc == "hotkeyRelease" || sc == "legacyTimeout" || sc == "paused")
            failStop   = (sc == "recognizerError" || sc == "watchdog" || sc == "forcedReset")
            hasTerminal = (outcome[s] != "" || events[s] ~ /insert_completed|insert_manual_recovery_required|start_blocked|start_cancelled|stop_completion_without_insert|stop_completion_ignored/)
            if (hasTerminal) terminal_count++

            if (normalStop && (fb == "true" || src == "fallback")) {
                verdict = "CHECK"; note = "fallback on a NORMAL stop — legitimate only if finalization genuinely failed (stopMarkedAsFailure, not logged); a policy violation if the phrase finalized cleanly"
            } else if (failStop && fb == "true") {
                verdict = "OK"; note = "fallback allowed (explicit failure stop)"
            } else if (sc == "" && outcome[s] == "" && events[s] !~ /blocked|cancelled|ignored/) {
                verdict = "CHECK"; note = "no stop_cause/insertion captured; confirm session completed"
            }

            # Structural incompleteness: started listening but never stopped/inserted.
            if (events[s] ~ /listening_started/ && events[s] !~ /stop_|insert_|force_stop|recognizer_error/) {
                verdict = "FAIL"
                note = "listening_started without stop/insert/error terminal event"
            }

            if (verdict == "OK") ok_count++
            else if (verdict == "CHECK") check_count++
            else if (verdict == "FAIL") fail_count++

            printf "  VERDICT         : %s%s\n", verdict, (note == "" ? "" : "  (" note ")")
            print ""
        }
        printf "Sessions: %d\n", n
        printf "Summary: OK=%d CHECK=%d FAIL=%d terminal_outcomes=%d\n", ok_count, check_count, fail_count, terminal_count
        if (noSession > 0) printf "Note: %d event line(s) had session=none (pre-listening blocks/cancels).\n", noSession

        if (fail_count > 0) {
            print "STRUCTURAL: FAIL (session incomplete)"
            exit 1
        }
        if (terminal_count == 0) {
            print "STRUCTURAL: FAIL (no terminal insert/stop/block outcomes in any session)"
            exit 1
        }
        print "STRUCTURAL: OK"
        exit 0
    }
    ' "$logfile"
}

# ---- capture --------------------------------------------------------------

detect_hosted_in_yen() {
    # Walk the process ancestry from this shell; return 0 if an ancestor is the
    # installed /Applications/YEN.app binary (this shell would die if it quits).
    local pid parent args
    pid="$PPID"
    local hops=0
    while [ "$hops" -lt 12 ]; do
        args="$(ps -o args= -p "$pid" 2>/dev/null || true)"
        case "$args" in
            *"/Applications/YEN.app/Contents/MacOS/yen"*) return 0 ;;
        esac
        parent="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
        [ -z "$parent" ] && break
        [ "$parent" = "0" ] || [ "$parent" = "1" ] && break
        pid="$parent"
        hops=$((hops + 1))
    done
    return 1
}

run_capture() {
    local force="$1"

    if [ ! -x "$LOCAL_APP_BIN" ]; then
        echo "ERROR: missing built test app: $LOCAL_APP_BIN" >&2
        echo "Build it first: bash scripts/native/01-macos-smoke.sh --build-only" >&2
        exit 1
    fi
    local local_bin_canonical
    local_bin_canonical="$(cd "$(dirname "$LOCAL_APP_BIN")" && pwd -P)/$(basename "$LOCAL_APP_BIN")"

    # macOS version -> recognizer path.
    local osver major
    osver="$(sw_vers -productVersion 2>/dev/null || echo "unknown")"
    major="${osver%%.*}"
    echo "macOS $osver"
    if [ "$major" != "unknown" ] && [ "$major" -ge 26 ] 2>/dev/null; then
        echo "Recognizer path: SpeechAnalyzer + DictationTranscriber (no 60s limit; Translate-on-Dictate available)"
    else
        echo "Recognizer path: SFSpeechRecognizer legacy (60s cap; no translation)"
    fi

    # Detect other running YEN instances (session-host conflict / tap fight).
    local nonlocal_running=false existing_local_running=false
    while IFS= read -r line; do
        case "$line" in
            *"/YEN.app/Contents/MacOS/yen"*)
                case "$line" in
                    *"$local_bin_canonical"*) existing_local_running=true ;;
                    *) nonlocal_running=true ;;
                esac
                ;;
        esac
    done <<EOF
$(ps -axo args= 2>/dev/null)
EOF

    if detect_hosted_in_yen; then
        echo
        echo "[WARNING] This shell is hosted INSIDE /Applications/YEN.app."
        echo "          Quitting that app to clear the hotkey conflict will kill this session."
        echo "          Run the live matrix from a plain Terminal.app / iTerm2 window instead."
    fi

    if [ "$nonlocal_running" = true ]; then
        echo
        echo "[CRITICAL] Another (non-test) YEN.app is already running."
        echo "           It owns a global Option+Space CGEventTap. Launching a second"
        echo "           instance makes two taps fight for the hotkey (non-deterministic),"
        echo "           and pausing dictation does NOT release the tap."
        echo "           Quit /Applications/YEN.app and rerun so the test build is the sole instance."
        if [ "$force" != true ]; then
            echo "           (Use --force to override and accept the tap conflict.)"
            exit 1
        fi
        echo "           --force set: continuing despite the conflict."
    fi

    if [ "$existing_local_running" = true ]; then
        echo
        echo "[NOTE] The test build is already running; attaching a fresh instance is skipped."
        echo "       Its earlier stdout was not captured here. Quit it and rerun to capture from launch."
        if [ "$force" != true ]; then
            exit 1
        fi
    fi

    mkdir -p "$LOG_DIR"
    # Script-scoped so the EXIT trap can always see them (Bash 3.2: locals would
    # be out of scope by the time an INT-driven EXIT trap runs).
    CAPTURE_LOG="$LOG_DIR/session-$(date +%Y%m%d-%H%M%S).log"
    APP_PID=""
    TAIL_PID=""

    echo
    echo "Launching test build (sole instance):"
    echo "  $LOCAL_APP_BIN"
    echo "Full stdout log: $CAPTURE_LOG"
    echo "Streaming Dictation* events below. Drive the matrix in _docs/09-quality.md."
    echo "Press Ctrl-C when the matrix is done, then run:"
    echo "  bash scripts/native/02-dictation-live-matrix.sh report \"$CAPTURE_LOG\""
    echo "--------------------------------------------------------------------------"

    "$LOCAL_APP_BIN" >"$CAPTURE_LOG" 2>&1 &
    APP_PID=$!
    trap cleanup_capture EXIT

    # Confirm the launch actually started before streaming.
    local attempts=0
    while [ "$attempts" -lt 20 ]; do
        ps -p "$APP_PID" >/dev/null 2>&1 && break
        attempts=$((attempts + 1))
        sleep 0.25
    done
    if ! ps -p "$APP_PID" >/dev/null 2>&1; then
        echo "ERROR: test build exited before capture started." >&2
        tail -n 40 "$CAPTURE_LOG" >&2 || true
        exit 1
    fi

    # Live-filter the dictation lines; full stdout stays in $CAPTURE_LOG.
    tail -n +1 -f "$CAPTURE_LOG" | grep --line-buffered -E "$DICTATION_FILTER" &
    TAIL_PID=$!
    wait "$APP_PID"
}

cleanup_capture() {
    [ -n "${TAIL_PID:-}" ] && kill "$TAIL_PID" >/dev/null 2>&1 || true
    if [ -n "${APP_PID:-}" ] && ps -p "$APP_PID" >/dev/null 2>&1; then
        kill "$APP_PID" >/dev/null 2>&1 || true
        wait "$APP_PID" >/dev/null 2>&1 || true
    fi
    echo
    echo "--------------------------------------------------------------------------"
    echo "Capture stopped. Saved log: ${CAPTURE_LOG:-<none>}"
    [ -n "${CAPTURE_LOG:-}" ] && echo "Report: bash scripts/native/02-dictation-live-matrix.sh report \"$CAPTURE_LOG\""
}

# ---- dispatch -------------------------------------------------------------

CMD="capture"
FORCE=false
ARG=""
for a in "$@"; do
    case "$a" in
        -h|--help) usage; exit 0 ;;
        capture|report) CMD="$a" ;;
        --force) FORCE=true ;;
        *) ARG="$a" ;;
    esac
done

case "$CMD" in
    report) run_report "$ARG" ;;
    capture) run_capture "$FORCE" ;;
esac
