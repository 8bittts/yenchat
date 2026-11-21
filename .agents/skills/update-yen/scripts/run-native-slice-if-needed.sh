#!/bin/bash
# run-native-slice-if-needed.sh — run the native xcodebuild slice exactly once
# per run. /update-yen Step 6a (VF-04) and vendor Step V4 (VB-05) share this decision.
#
# Forces the slice after the build ONLY when the pre-build component gate
# (Step 4 and Step V4) did not run it. Step 4 tees the component gate output
# to <skill>-components.out, because eval-phase.sh deletes a passing check's
# own log; without that file the RAN receipt was gone, the decision could not
# see it, and every release re-ran all 17 component units in `always` mode to
# repeat a slice Step 4 had already run. A Ghostty vendor bump removes
# YENKit.xcframework, so Step 4 records SKIP there and the build is the first
# point at which the slice can run at all.
#
# Usage: run-native-slice-if-needed.sh [update-yen|yen-vendor]   (default: update-yen)
# The argument names the eval namespace: update-yen is the release, yen-vendor the vendor phase.
# Bash 3.2 compatible.

set -euo pipefail

# Resolve this script's own directory PHYSICALLY before walking up; the skill
# dirs are symlinked into ~/.claude and ~/.codex (see verify-agent-work.sh).
SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd -P "$SCRIPT_DIR/../../../.." && pwd -P)"

skill="${1:-update-yen}"
case "$skill" in
    update-yen) LABEL="native-slice-6a" ;;
    yen-vendor) LABEL="native-slice-vb05" ;;
    *)
        echo "Usage: run-native-slice-if-needed.sh [update-yen|yen-vendor]" >&2
        exit 2
        ;;
esac

STEP4_OUT="$REPO_ROOT/tmp/skill-telemetry/${skill}-components.out"
RUN_ID_FILE="$REPO_ROOT/tmp/skill-telemetry/${skill}-eval-run.id"
RAN_PATTERN='^RAN\|xcode-regression\|suites=[0-9]+ executed=[1-9][0-9]*$'

# Step 4 counts only when its receipt is from THIS run, passed, and shows the
# slice executing at least one test. Every other state forces the slice.
step4_ran=""
if [ -f "$STEP4_OUT" ] && [ -f "$RUN_ID_FILE" ] && [ "$STEP4_OUT" -nt "$RUN_ID_FILE" ] &&
    grep -Eq 'RECEIPT gate=03-verify-components .*result=PASS' "$STEP4_OUT"; then
    step4_ran="$(grep -E "$RAN_PATTERN" "$STEP4_OUT" | tail -n 1 || true)"
fi

if [ -n "$step4_ran" ]; then
    echo "SKIP|${LABEL}|Step 4 already ran it: $step4_ran"
    exit 0
fi

if [ ! -f "$STEP4_OUT" ]; then
    reason="no saved Step 4 output at $STEP4_OUT"
elif [ ! -f "$RUN_ID_FILE" ] || [ ! "$STEP4_OUT" -nt "$RUN_ID_FILE" ]; then
    reason="saved Step 4 output predates this run"
elif ! grep -Eq 'RECEIPT gate=03-verify-components .*result=PASS' "$STEP4_OUT"; then
    reason="saved Step 4 output has no passing RECEIPT"
else
    reason="$(grep -E '^SKIP\|xcode-regression\|' "$STEP4_OUT" | tail -n 1 || true)"
    reason="${reason:-no RAN|xcode-regression line in Step 4 output}"
fi
echo "RAN|${LABEL}|forcing the slice: $reason"
YEN_COMPONENT_XCODE_REGRESSION_MODE=always bash "$REPO_ROOT/scripts/03-verify-components.sh"
