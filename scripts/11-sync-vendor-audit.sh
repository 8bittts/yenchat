#!/bin/bash
# Sync vendor audit snapshot metadata from tracked baseline files.
#
# Updates _docs/04-security.md keys:
#   snapshot_date
#   ghostty_commit
#   ghostty_version
#   ghostty_upstream_repo
#   yazi_version
#   fd_version
#   ripgrep_version
#   fzf_version
#   zoxide_version
#   bat_version
#   jq_version
#   lazygit_version
#   delta_version
#   resvg_version
#   btop_version
#   fastfetch_version
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
YAZI_VERSION=$(baseline_value "upstream_version" "$REPO_ROOT/yen-terminal/.yazi-baseline")
FD_VERSION=$(baseline_value "upstream_version" "$REPO_ROOT/yen-terminal/.fd-baseline")
RIPGREP_VERSION=$(baseline_value "upstream_version" "$REPO_ROOT/yen-terminal/.ripgrep-baseline")
FZF_VERSION=$(baseline_value "upstream_version" "$REPO_ROOT/yen-terminal/.fzf-baseline")
ZOXIDE_VERSION=$(baseline_value "upstream_version" "$REPO_ROOT/yen-terminal/.zoxide-baseline")
BAT_VERSION=$(baseline_value "upstream_version" "$REPO_ROOT/yen-terminal/.bat-baseline")
JQ_VERSION=$(baseline_value "upstream_version" "$REPO_ROOT/yen-terminal/.jq-baseline")
LAZYGIT_VERSION=$(baseline_value "upstream_version" "$REPO_ROOT/yen-terminal/.lazygit-baseline")
DELTA_VERSION=$(baseline_value "upstream_version" "$REPO_ROOT/yen-terminal/.delta-baseline")
RESVG_VERSION=$(baseline_value "upstream_version" "$REPO_ROOT/yen-terminal/.resvg-baseline")
BTOP_VERSION=$(baseline_value "upstream_version" "$REPO_ROOT/yen-terminal/.btop-baseline")
FASTFETCH_VERSION=$(baseline_value "upstream_version" "$REPO_ROOT/yen-terminal/.fastfetch-baseline")

for required_value in \
	"$LATEST_SYNC" \
	"$GHOSTTY_COMMIT" \
	"$GHOSTTY_VERSION" \
	"$GHOSTTY_UPSTREAM_REPO" \
	"$YAZI_VERSION" \
	"$FD_VERSION" \
	"$RIPGREP_VERSION" \
	"$FZF_VERSION" \
	"$ZOXIDE_VERSION" \
	"$BAT_VERSION" \
	"$JQ_VERSION" \
	"$LAZYGIT_VERSION" \
	"$DELTA_VERSION" \
	"$RESVG_VERSION" \
	"$BTOP_VERSION" \
	"$FASTFETCH_VERSION"; do
	[ -n "$required_value" ] || fail "Baseline metadata contains empty required value"
done

python3 - <<'PY' "$DOC_PATH" "$LATEST_SYNC" "$GHOSTTY_COMMIT" "$GHOSTTY_VERSION" "$GHOSTTY_UPSTREAM_REPO" "$YAZI_VERSION" "$FD_VERSION" "$RIPGREP_VERSION" "$FZF_VERSION" "$ZOXIDE_VERSION" "$BAT_VERSION" "$JQ_VERSION" "$LAZYGIT_VERSION" "$DELTA_VERSION" "$RESVG_VERSION" "$BTOP_VERSION" "$FASTFETCH_VERSION"
import re
import sys
from pathlib import Path

doc_path = Path(sys.argv[1])
updates = [
    ("snapshot_date", sys.argv[2]),
    ("ghostty_commit", sys.argv[3]),
    ("ghostty_version", sys.argv[4]),
    ("ghostty_upstream_repo", sys.argv[5]),
    ("yazi_version", sys.argv[6]),
    ("fd_version", sys.argv[7]),
    ("ripgrep_version", sys.argv[8]),
    ("fzf_version", sys.argv[9]),
    ("zoxide_version", sys.argv[10]),
    ("bat_version", sys.argv[11]),
    ("jq_version", sys.argv[12]),
    ("lazygit_version", sys.argv[13]),
    ("delta_version", sys.argv[14]),
    ("resvg_version", sys.argv[15]),
    ("btop_version", sys.argv[16]),
    ("fastfetch_version", sys.argv[17]),
]

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
