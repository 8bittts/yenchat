#!/bin/bash
# verify-audit-layers.sh — Verify the agent actually completed every required
# audit layer for a vendor bump.
#
# Usage: verify-audit-layers.sh <vendor> <audit_log_file>
# Bash 3.2 compatible.
#
# For Ghostty (source vendor): layers 1-6.
# For binary and source-built vendors: layers 3-6 (no overlay health, no
# structural-change review — there are no overlays over a prebuilt binary).
#
# WHAT CHANGED AND WHY
# This script used to check only that six static repo files existed. It
# reported all six [PASS] and exited 0 against a completely un-audited tree,
# while eval check VA-04 presented it as "all audit layers complete".
# The audit_log argument was accepted by the signature and never read. That is
# a placebo gate: it cannot fail for the reason it claims to exist.
#
# It now requires the audit log the signature always advertised, and each
# required layer must carry its own marker line with a non-empty finding:
#
#   LAYER 1: overlays applied clean, 0 patched / 50 idempotent skips
#   LAYER 2: no upstream structural moves affecting overlay anchors
#   ...
#
# The tool-availability checks are kept as a preflight — if the branding or
# component verifier is missing, the audit could not have been performed — but
# they are no longer the whole gate.
#
# Layers 2, 4 and 6 remain human-judgment layers. This gate cannot check that
# the judgment was *good*; it enforces that it was recorded, which is the part
# a script can honestly assert.

set -euo pipefail

# Resolve this script's own directory PHYSICALLY before walking up. The skill
# dirs are symlinked into ~/.claude and ~/.codex, and a logical `cd` applies
# ".." to the symlink path, so invoking by skill path resolved REPO_ROOT to
# the home directory instead of the repo.
SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
REPO_ROOT="$(cd -P "$SCRIPT_DIR/../../../.." && pwd -P)"

vendor="${1:-}"
audit_log="${2:-}"

if [ -z "$vendor" ]; then
    echo "Usage: verify-audit-layers.sh <vendor> <audit_log_file>" >&2
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

echo "=== Audit Layer Verification: ${vendor} ==="

# Vendor type. The accepted list must stay in step with the targets
# 14-vendor.sh accepts; tests/119 asserts that parity, because a vendor missing
# here fails with "Unknown vendor" and looks like a tooling bug rather than the
# missing-coverage it actually is (delta was absent for exactly that reason).
case "$vendor" in
    ghostty)
        vendor_type="source"
        required_layer_ids="1 2 3 4 5 6"
        ;;
    btop|fd|delta)
        vendor_type="source-built"
        required_layer_ids="3 4 5 6"
        ;;
    yazi|ripgrep|fzf|zoxide|bat|jq|lazygit|resvg|fastfetch)
        vendor_type="binary"
        required_layer_ids="3 4 5 6"
        ;;
    *)
        echo "Unknown vendor: ${vendor}" >&2
        exit 2
        ;;
esac

required_layers=0
for _layer_id in $required_layer_ids; do
    required_layers=$((required_layers + 1))
done

echo "Vendor type: ${vendor_type}"
echo "Required layers: ${required_layers} (${required_layer_ids})"
echo ""

# --- Preflight: the audit log itself -----------------------------------------
# Fail closed on a missing, unreadable, or empty log. "Nothing to check" is the
# failure this gate exists to catch, not a pass.
echo "Preflight: audit log"
if [ -z "$audit_log" ]; then
    note_error "no audit log supplied — pass the log this run appended layer markers to"
elif [ ! -f "$audit_log" ]; then
    note_error "audit log not found: ${audit_log}"
elif [ ! -s "$audit_log" ]; then
    note_error "audit log is empty: ${audit_log}"
else
    note_pass "audit log present: ${audit_log}"
fi

# --- Preflight: tools the audit depends on ------------------------------------
echo "Preflight: audit tooling"
for tool_path in \
    "yen-terminal/apply-overlays.sh" \
    "scripts/04-verify-branding.sh" \
    "scripts/03-verify-components.sh" \
    "_docs/04-security.md"
do
    # apply-overlays.sh only matters for the source vendor.
    if [ "$tool_path" = "yen-terminal/apply-overlays.sh" ] && [ "$vendor_type" != "source" ]; then
        continue
    fi
    if [ -f "${REPO_ROOT}/${tool_path}" ]; then
        note_pass "${tool_path}"
    else
        note_error "${tool_path} missing — the audit could not have been performed"
    fi
done

baseline_file="${REPO_ROOT}/yen-terminal/.${vendor}-baseline"
if [ -f "$baseline_file" ] && [ -s "$baseline_file" ]; then
    note_pass "yen-terminal/.${vendor}-baseline"
else
    note_error "baseline missing or empty: yen-terminal/.${vendor}-baseline"
fi

# --- The actual gate: one recorded finding per required layer ------------------
echo ""
echo "Recorded layer findings"
if [ -n "$audit_log" ] && [ -s "$audit_log" ]; then
    for layer_id in $required_layer_ids; do
        finding=$(grep -E "^[[:space:]]*LAYER[[:space:]]+${layer_id}[[:space:]]*:" "$audit_log" 2>/dev/null | head -1 || true)
        if [ -z "$finding" ]; then
            note_error "Layer ${layer_id}: no 'LAYER ${layer_id}: <finding>' line in the audit log"
            continue
        fi
        # Everything after the first colon, trimmed.
        detail="${finding#*:}"
        detail="$(printf '%s' "$detail" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        if [ ${#detail} -lt 8 ]; then
            note_error "Layer ${layer_id}: finding is empty or too short to be a real record"
        else
            note_pass "Layer ${layer_id}: ${detail}"
        fi
    done
else
    for layer_id in $required_layer_ids; do
        note_error "Layer ${layer_id}: not verifiable without a readable audit log"
    done
fi

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "Audit layer verification: ${ERRORS} issue(s) found"
    echo "Required layers: ${required_layers} | Checks failed: ${ERRORS}"
    exit 1
fi

echo "Audit layer verification: all checks passed"
echo "Required layers: ${required_layers} | All recorded"
exit 0
