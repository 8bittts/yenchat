#!/bin/bash
# Check recent crash reports for currently shipped YEN runtime binaries before shipping.
#
# Two sources: macOS `.ips` reports in DiagnosticReports, and the bundled crash
# reporter's `.yencrash` files in ~/.local/state/yen/crash. An abort inside a
# framework (an AttributeGraph precondition, for one) writes only the second, so
# a scan of `.ips` alone passes over it. A `.yencrash` counts only when its main
# executable is the installed /Applications/YEN.app; test hosts and Debug builds
# write the same directory and are not shipped binaries.
#
# Usage:
#   ./scripts/manual/12-check-recent-crashes.sh
#   ./scripts/manual/12-check-recent-crashes.sh --days 3
#   ./scripts/manual/12-check-recent-crashes.sh --days 7 --allow
#   ./scripts/manual/12-check-recent-crashes.sh --triage <report.ips>  # mark as triaged
#   ./scripts/manual/12-check-recent-crashes.sh --triage-all           # mark all current as triaged
#   ./scripts/manual/12-check-recent-crashes.sh --list-triaged         # show triaged list
#   ./scripts/manual/12-check-recent-crashes.sh --clear-triaged        # reset triaged list
#
# Triaged crashes are recorded in .triaged-crashes at the repo root.
# Future runs skip reports that have already been triaged.
#
# Exits non-zero when NEW (untriaged) matching crash reports are found
# unless --allow (or YEN_ALLOW_RECENT_CRASHES=1) is provided.

set -euo pipefail

DAYS=3
ALLOW=false
DIAG_DIR="${YEN_DIAGNOSTIC_REPORTS_DIR:-${HOME}/Library/Logs/DiagnosticReports}"
CRASH_DIR="${YEN_CRASH_DIR:-${HOME}/.local/state/yen/crash}"
SHIPPED_EXECUTABLE='"code_file":"/Applications/YEN.app/Contents/MacOS/yen"'

# Resolve repo root (script lives at scripts/manual/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TRIAGED_FILE="${YEN_TRIAGED_CRASHES_FILE:-${REPO_ROOT}/.triaged-crashes}"

# Ensure triaged file exists
[ -f "$TRIAGED_FILE" ] || touch "$TRIAGED_FILE"

# Check if a filename is in the triaged list
is_triaged() {
    grep -Fxq "$1" "$TRIAGED_FILE" 2>/dev/null
}

ACTION=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --days)
            shift
            if [ "$#" -eq 0 ] || ! echo "$1" | grep -Eq '^[0-9]+$' || [ "$1" -le 0 ]; then
                echo "ERROR: --days requires a positive integer"
                exit 2
            fi
            DAYS="$1"
            ;;
        --allow)
            ALLOW=true
            ;;
        --triage)
            shift
            if [ "$#" -eq 0 ]; then
                echo "ERROR: --triage requires a filename argument"
                exit 2
            fi
            TRIAGE_TARGET="$1"
            # Accept full path or just filename
            TRIAGE_BASE="$(basename "$TRIAGE_TARGET")"
            if is_triaged "$TRIAGE_BASE"; then
                echo "  Already triaged: $TRIAGE_BASE"
            else
                echo "$TRIAGE_BASE" >> "$TRIAGED_FILE"
                echo "  Triaged: $TRIAGE_BASE"
            fi
            exit 0
            ;;
        --triage-all)
            ACTION="triage-all"
            ;;
        --list-triaged)
            if [ -s "$TRIAGED_FILE" ]; then
                echo "  Triaged crashes:"
                while IFS= read -r line; do
                    [ -n "$line" ] || continue
                    echo "    $line"
                done < "$TRIAGED_FILE"
            else
                echo "  No triaged crashes"
            fi
            exit 0
            ;;
        --clear-triaged)
            : > "$TRIAGED_FILE"
            echo "  Triaged list cleared"
            exit 0
            ;;
        -h|--help)
            sed -n '2,23p' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            exit 2
            ;;
    esac
    shift
done

if [ "${YEN_ALLOW_RECENT_CRASHES:-0}" = "1" ]; then
    ALLOW=true
fi

if [ ! -d "$DIAG_DIR" ]; then
    echo "ERROR: DiagnosticReports directory not found: $DIAG_DIR"
    exit 1
fi

MATCHED_COUNT=0
MATCHED_REPORTS=""
TRIAGED_COUNT=0
TRIAGED_REPORTS=""
ALL_BASES=""
IPS_SCANNED=0
YENCRASH_SCANNED=0

record_report() {
    local report="$1"
    local base
    base="$(basename "$report")"
    if is_triaged "$base"; then
        TRIAGED_COUNT=$((TRIAGED_COUNT + 1))
        TRIAGED_REPORTS="${TRIAGED_REPORTS}\n  (triaged) ${report}"
    else
        MATCHED_COUNT=$((MATCHED_COUNT + 1))
        MATCHED_REPORTS="${MATCHED_REPORTS}\n${report}"
        ALL_BASES="${ALL_BASES}${base}\n"
    fi
}

while IFS= read -r report; do
    [ -n "$report" ] || continue
    IPS_SCANNED=$((IPS_SCANNED + 1))
    base="$(basename "$report")"
    if echo "$base" | grep -Eq '^(yen|YEN)-[0-9]{4}-[0-9]{2}-[0-9]{2}.*\.ips$'; then
        record_report "$report"
    fi
done <<EOF
$(find "$DIAG_DIR" -maxdepth 1 -type f -name "*.ips" -mtime "-${DAYS}" 2>/dev/null || true)
EOF

# Grep the file itself: under pipefail, `head | grep -q` reads as a miss whenever
# grep exits early and head takes SIGPIPE.
if [ -d "$CRASH_DIR" ]; then
    while IFS= read -r report; do
        [ -n "$report" ] || continue
        YENCRASH_SCANNED=$((YENCRASH_SCANNED + 1))
        if LC_ALL=C grep -aFq "$SHIPPED_EXECUTABLE" "$report"; then
            record_report "$report"
        fi
    done <<EOF
$(find "$CRASH_DIR" -maxdepth 1 -type f -name "*.yencrash" -mtime "-${DAYS}" 2>/dev/null || true)
EOF
fi

# --triage-all: mark all currently-matched (untriaged) reports as triaged
if [ "$ACTION" = "triage-all" ]; then
    if [ "$MATCHED_COUNT" -eq 0 ]; then
        echo "  No untriaged crash reports to mark"
        exit 0
    fi
    printf '%b' "$ALL_BASES" | while IFS= read -r b; do
        [ -n "$b" ] || continue
        if ! is_triaged "$b"; then
            echo "$b" >> "$TRIAGED_FILE"
            echo "  Triaged: $b"
        fi
    done
    exit 0
fi

if [ "$TRIAGED_COUNT" -gt 0 ]; then
    echo "  Skipped ${TRIAGED_COUNT} previously triaged crash report(s)"
fi

echo "  Scanned ${IPS_SCANNED} .ips and ${YENCRASH_SCANNED} .yencrash file(s) from the last ${DAYS} days"

if [ "$MATCHED_COUNT" -eq 0 ]; then
    echo "  ✓ No new YEN crash reports found (last ${DAYS} days)"
    exit 0
fi

if [ "$ALLOW" = true ]; then
    echo "  ! New YEN crash reports found (${MATCHED_COUNT}) — continuing due to override"
    echo -e "$MATCHED_REPORTS"
    exit 0
fi

echo "  X New YEN crash reports found (${MATCHED_COUNT})"
echo -e "$MATCHED_REPORTS"
echo ""
echo "  Triage each report before /yen-zip:"
echo "    sed -n '1,220p' ~/Library/Logs/DiagnosticReports/<report>.ips"
echo "    head -c 4000 ~/.local/state/yen/crash/<report>.yencrash   # JSON header; read the unified log near its timestamp for the cause"
echo ""
echo "  After triage, mark as triaged so future /yen-zip runs skip it:"
echo "    bash $HOME/Documents/yenchat/scripts/manual/12-check-recent-crashes.sh --triage <report>.ips|<report>.yencrash"
echo "    bash $HOME/Documents/yenchat/scripts/manual/12-check-recent-crashes.sh --triage-all"
echo ""
echo "  Emergency override: YEN_ALLOW_RECENT_CRASHES=1"
exit 1
