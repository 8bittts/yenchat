#!/bin/bash
# Verify that a shipping build can publish to the configured GitHub Releases repo.
#
# The repository must be public (a private repo's release assets need a login,
# so every download and Sparkle update would fail) and the gh session must be
# able to push to it, because creating a release and uploading assets needs push.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/scripts/lib/release-constants.sh"

if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh CLI not installed — required for release uploads" >&2
    exit 1
fi

if ! REPO_STATE="$(gh api "repos/${GITHUB_RELEASES_REPO}" --jq '[.visibility, .permissions.push] | @tsv' 2>/dev/null)"; then
    echo "ERROR: GitHub release repository ${GITHUB_RELEASES_REPO} is not reachable with the current gh session" >&2
    echo "Run: gh auth status" >&2
    exit 1
fi

VISIBILITY="$(printf '%s\n' "$REPO_STATE" | cut -f1)"
CAN_PUSH="$(printf '%s\n' "$REPO_STATE" | cut -f2)"

if [ "$VISIBILITY" != "public" ]; then
    echo "ERROR: GitHub release repository ${GITHUB_RELEASES_REPO} is ${VISIBILITY:-unknown}, not public; release downloads would need a login" >&2
    exit 1
fi

if [ "$CAN_PUSH" != "true" ]; then
    echo "ERROR: the current gh session cannot push to ${GITHUB_RELEASES_REPO}, so it cannot create releases" >&2
    exit 1
fi

echo "RAN|github-release-target|repo=${GITHUB_RELEASES_REPO} visibility=public push=verified"
