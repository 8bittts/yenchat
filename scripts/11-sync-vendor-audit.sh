#!/bin/bash
# Sync vendor audit snapshot metadata from tracked baseline files.
#
# Updates _docs/04-security.md keys:
#   snapshot_date
#   ghostty_commit
#   ghostty_version
#   ghostty_upstream_repo
#   <key>_version for every other vendor in scripts/lib/vendor-manifest.sh
#
# Usage:
#   ./scripts/11-sync-vendor-audit.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/vendor-manifest.sh"
DOC_PATH="$REPO_ROOT/_docs/04-security.md"

source "$REPO_ROOT/scripts/lib/python-utils.sh"
require_python3 "for vendor audit metadata sync" || exit 1

fail() {
	echo "ERROR: $1"
	exit 1
}


# Derived from scripts/lib/vendor-manifest.sh so a new vendor cannot be missed
# here — a baseline absent from this list is simply never verified, which is a
# silent gap rather than a failure.
BASELINES=()
for _vendor_key in $(vendor_manifest_keys); do
    BASELINES+=("$(vendor_baseline_path "$REPO_ROOT" "$_vendor_key")")
done

for baseline in "${BASELINES[@]}"; do
	[ -f "$baseline" ] || fail "Missing baseline file: ${baseline#$REPO_ROOT/}"
done

[ -f "$DOC_PATH" ] || fail "Canonical vendor audit doc missing: _docs/04-security.md"

LATEST_SYNC=""
for baseline in "${BASELINES[@]}"; do
	sync_value=$(baseline_value "last_sync" "$baseline")
	echo "$sync_value" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || \
		fail "Invalid last_sync in ${baseline#$REPO_ROOT/}: $sync_value"
	if [ -z "$LATEST_SYNC" ] || [ "$sync_value" \> "$LATEST_SYNC" ]; then
		LATEST_SYNC="$sync_value"
	fi
done

GHOSTTY_COMMIT=$(baseline_value "upstream_commit" "$REPO_ROOT/yen-terminal/.ghostty-baseline")
GHOSTTY_VERSION=$(baseline_value "upstream_version" "$REPO_ROOT/yen-terminal/.ghostty-baseline")
GHOSTTY_UPSTREAM_REPO=$(baseline_value "upstream_repo" "$REPO_ROOT/yen-terminal/.ghostty-baseline")
for required_value in \
	"$LATEST_SYNC" \
	"$GHOSTTY_COMMIT" \
	"$GHOSTTY_VERSION" \
	"$GHOSTTY_UPSTREAM_REPO"; do
	[ -n "$required_value" ] || fail "Baseline metadata contains empty required value"
done

# One "<key>_version=<value>" pair per binary vendor, in manifest order, so the
# snapshot keys cannot drift from the roster.
VERSION_UPDATES=()
for _vendor_key in $(vendor_manifest_keys); do
	[ "$_vendor_key" = "ghostty" ] && continue
	_vendor_version=$(baseline_value "upstream_version" "$(vendor_baseline_path "$REPO_ROOT" "$_vendor_key")")
	[ -n "$_vendor_version" ] || fail "Baseline metadata contains empty upstream_version: $_vendor_key"
	VERSION_UPDATES+=("${_vendor_key}_version=${_vendor_version}")
done
[ "${#VERSION_UPDATES[@]}" -gt 0 ] || fail "Vendor manifest lists no binary vendors"

python3 - <<'PY' "$DOC_PATH" "$LATEST_SYNC" "$GHOSTTY_COMMIT" "$GHOSTTY_VERSION" "$GHOSTTY_UPSTREAM_REPO" "${VERSION_UPDATES[@]}"
import re
import sys
from pathlib import Path

doc_path = Path(sys.argv[1])
updates = [
    ("snapshot_date", sys.argv[2]),
    ("ghostty_commit", sys.argv[3]),
    ("ghostty_version", sys.argv[4]),
    ("ghostty_upstream_repo", sys.argv[5]),
]
updates += [tuple(pair.split("=", 1)) for pair in sys.argv[6:]]

text = doc_path.read_text()
for key, value in updates:
    pattern = rf"(?m)^{re.escape(key)}=.*$"
    if not re.search(pattern, text):
        raise SystemExit(f"ERROR: Missing {key}= in {doc_path}")
    text = re.sub(pattern, f"{key}={value}", text, count=1)

doc_path.write_text(text)

# Also sync all other ghostty_commit references in the doc
# so verify_overlap_commit_references() never finds stale hashes.
ghostty_commit = sys.argv[3]
ghostty_short = ghostty_commit[:8]

# 1. Overlap assessment header: (commit `XXXXXXXX`)
text = doc_path.read_text()
text = re.sub(
    r'(?m)(Audit of YEN customizations against upstream Ghostty \(commit `)([0-9a-f]{7,40})(`\))',
    rf'\g<1>{ghostty_short}\g<3>',
    text,
)

# 2. All ghostty_commit=HASH references outside the snapshot block
#    Replace every occurrence with the current full hash.
text = re.sub(
    r'ghostty_commit=[0-9a-f]{7,40}',
    f'ghostty_commit={ghostty_commit}',
    text,
)

doc_path.write_text(text)

print("  ✓ Synced vendor audit snapshot metadata")
for key, value in updates:
    print(f"    {key}={value}")
PY
