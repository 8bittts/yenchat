#!/bin/bash
# Check Upstream Script
# Manual utility for Ghostty upstream review (not invoked by 14-vendor.sh)
#
# Checks current baseline and fetches upstream changes.
#
# Usage: ./scripts/08-check-upstream.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/scripts/lib/python-utils.sh"
source "$REPO_ROOT/scripts/lib/upstream.sh"

require_python3 "for upstream JSON parsing" || exit 1

BASELINE_FILE="yen-terminal/.ghostty-baseline"

echo "Vendor Check"

# Current state
if [ -f "$BASELINE_FILE" ]; then
    CURRENT=$(grep "^upstream_commit=" "$BASELINE_FILE" | cut -d'=' -f2)
    VERSION=$(grep "^upstream_version=" "$BASELINE_FILE" | cut -d'=' -f2)
    SYNC_DATE=$(grep "^last_sync=" "$BASELINE_FILE" | cut -d'=' -f2)
    echo "  Baseline: ${CURRENT:0:8} ($VERSION, $SYNC_DATE)"
else
    echo "ERROR: .ghostty-baseline not found"
    exit 1
fi

# Check for uncommitted changes (warning only)
if [ -n "$(git status --porcelain)" ]; then
    echo "  ! Working directory has uncommitted changes"
fi

# Fetch upstream commits. Send the forge token when one is available —
# anonymous requests hit the rate limit quickly, and a rate-limited probe used
# to be indistinguishable from a genuine "up to date".
CURL_OPTS=(--max-time 30 --connect-timeout 10 -s -w "\n%{http_code}")
UPSTREAM_AUTH="$(upstream_auth_header)"
if [ -n "$UPSTREAM_AUTH" ]; then
    CURL_OPTS+=(-H "$UPSTREAM_AUTH")
fi

API_RESPONSE=$(curl "${CURL_OPTS[@]}" \
    "$(upstream_compare_url "$CURRENT" main)" 2>/dev/null || echo "")
HTTP_CODE=$(echo "$API_RESPONSE" | tail -1)
COMPARE_RESULT=$(echo "$API_RESPONSE" | sed '$d')

# Fail closed. "We could not ask" is not "there is nothing new" — reporting the
# latter on a 403/404/timeout is a false green, and this script is the operator's
# read on whether a vendor bump is needed. 09-analyze-impact.sh already exits 1
# on the same input; this one used to print "up to date" and exit 0.
if [ "$HTTP_CODE" = "403" ]; then
    echo "  ! Upstream API rate limited${UPSTREAM_AUTH:+ (token was sent)}"
    echo "  Upstream: UNKNOWN"
    exit 1
elif [ "$HTTP_CODE" != "200" ]; then
    echo "  ! Upstream API returned ${HTTP_CODE:-no response}"
    echo "  Upstream: UNKNOWN"
    exit 1
fi

TOTAL_COMMITS=$(echo "$COMPARE_RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('total_commits', 0))" 2>/dev/null || echo "")
if [ -z "$TOTAL_COMMITS" ]; then
    echo "  ! Could not parse upstream compare response"
    echo "  Upstream: UNKNOWN"
    exit 1
fi

if [ "$TOTAL_COMMITS" -gt 0 ]; then
    echo "  Upstream: $TOTAL_COMMITS commits ahead"
    echo ""
    echo "  Recent commits:"
    echo "$COMPARE_RESULT" | python3 -c "
import sys,json
data = json.load(sys.stdin)
for c in data.get('commits', [])[:5]:
    msg = c['commit']['message'].split('\n')[0][:60]
    sha = c['sha'][:8]
    print(f'    {sha} {msg}')
" 2>/dev/null || echo "    (could not fetch commits)"
    echo ""
    echo "  Run ./scripts/09-analyze-impact.sh to check for conflicts"
else
    echo "  Upstream: up to date"
fi
