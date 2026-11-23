#!/bin/bash
# Centralized Ghostty upstream coordinates + forge adapter shim.
#
# Phase 0 of the Ghostty-leaving-GitHub migration plan (_docs/todos.md).
# Centralizes every literal reference to github.com/ghostty-org/ghostty so
# Phase 1 can swap to a different forge (Forgejo / Sourcehut / Codeberg /
# custom — TBD) by writing one new adapter file and flipping defaults.
#
# Source from any vendor/branding/fingerprint script:
#   source "$REPO_ROOT/scripts/lib/upstream.sh"
#
# Public symbols (every value is overridable via YEN_UPSTREAM_*):
#   UPSTREAM_HOST     - default: github.com
#   UPSTREAM_OWNER    - default: ghostty-org
#   UPSTREAM_REPO     - default: ghostty
#   UPSTREAM_FORGE    - default: github   (selects forge_<name>_* adapter)
#
# Functions (forge-agnostic; dispatch into forge_<name>_* adapters):
#   upstream_repo_path        - "<owner>/<repo>"
#   upstream_web_url          - https://<host>/<owner>/<repo>
#   upstream_git_url          - https://<host>/<owner>/<repo>.git
#   upstream_tarball_url <sha-or-ref>
#   upstream_compare_url <base> <head>
#   upstream_commit_url <ref>
#   upstream_url_pattern_grep   - literal "<host>/<owner>/<repo>" for grep -F / grep BRE
#   upstream_url_pattern_regex  - same with `.` escaped, for grep -E / sed BRE
#
# Forge adapters: forge_<name>_<verb> functions. Today's only impl: forge_github.
# Phase 1 will add a second adapter without touching the call sites above.

# Idempotent guard — harmless to source twice.
if [ -n "${_YEN_UPSTREAM_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
_YEN_UPSTREAM_LOADED=1

UPSTREAM_HOST="${YEN_UPSTREAM_HOST:-github.com}"
UPSTREAM_OWNER="${YEN_UPSTREAM_OWNER:-ghostty-org}"
UPSTREAM_REPO="${YEN_UPSTREAM_REPO:-ghostty}"
UPSTREAM_FORGE="${YEN_UPSTREAM_FORGE:-github}"

upstream_repo_path() {
    printf '%s/%s' "$UPSTREAM_OWNER" "$UPSTREAM_REPO"
}

upstream_web_url() {
    printf 'https://%s/%s/%s' "$UPSTREAM_HOST" "$UPSTREAM_OWNER" "$UPSTREAM_REPO"
}

upstream_git_url() {
    printf '%s.git' "$(upstream_web_url)"
}

upstream_url_pattern_grep() {
    printf '%s/%s/%s' "$UPSTREAM_HOST" "$UPSTREAM_OWNER" "$UPSTREAM_REPO"
}

upstream_url_pattern_regex() {
    local host_escaped="${UPSTREAM_HOST//./\\.}"
    printf '%s/%s/%s' "$host_escaped" "$UPSTREAM_OWNER" "$UPSTREAM_REPO"
}

upstream_tarball_url() {
    "forge_${UPSTREAM_FORGE}_tarball_url" "$1"
}

upstream_compare_url() {
    "forge_${UPSTREAM_FORGE}_compare_url" "$1" "$2"
}

upstream_commit_url() {
    "forge_${UPSTREAM_FORGE}_commit_url" "$1"
}

# Read a file from an immutable commit through the selected forge.
upstream_file_content() {
    "forge_${UPSTREAM_FORGE}_file_content" "$1" "$2"
}

upstream_verified_commit_sha() {
    "forge_${UPSTREAM_FORGE}_verified_commit_sha" "$1"
}

# Newest commit on a branch whose forge signature verifies, or empty output.
# A rebase merge leaves a branch head unsigned while older commits stay
# signed, so the vendor gate targets this commit instead of the head.
upstream_newest_verified_commit_sha() {
    "forge_${UPSTREAM_FORGE}_newest_verified_commit_sha" "$1"
}

# Curl auth header for the configured forge, or empty output when no token is
# available. Anonymous requests are rate-limited far more aggressively, and a
# rate-limited status probe is the most common way a vendor script reports
# "up to date" when it actually learned nothing — so every script that hits the
# forge API should send this. Use as:
#   AUTH="$(upstream_auth_header)"
#   if [ -n "$AUTH" ]; then CURL_OPTS+=(-H "$AUTH"); fi
upstream_auth_header() {
    "forge_${UPSTREAM_FORGE}_auth_header"
}

# === GitHub forge adapter ===
# When the destination is announced, add forge_<name>_* siblings here and
# flip UPSTREAM_FORGE default. Keep forge_github_* for the GH read-only
# mirror fallback during the transition.

forge_github_tarball_url() {
    printf 'https://%s/%s/%s/archive/%s.tar.gz' \
        "$UPSTREAM_HOST" "$UPSTREAM_OWNER" "$UPSTREAM_REPO" "$1"
}

forge_github_compare_url() {
    printf 'https://api.%s/repos/%s/%s/compare/%s...%s' \
        "$UPSTREAM_HOST" "$UPSTREAM_OWNER" "$UPSTREAM_REPO" "$1" "$2"
}

forge_github_commit_url() {
    printf 'https://api.%s/repos/%s/%s/commits/%s' \
        "$UPSTREAM_HOST" "$UPSTREAM_OWNER" "$UPSTREAM_REPO" "$1"
}

forge_github_file_content() {
    local commit="$1"
    local path="$2"
    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || return 1
    local auth_header
    local -a curl_opts
    auth_header="$(forge_github_auth_header)"
    curl_opts=(-H "Accept: application/vnd.github.raw+json")
    [ -n "$auth_header" ] && curl_opts+=(-H "$auth_header")
    curl --retry 3 --retry-delay 1 --max-time 30 --connect-timeout 10 -sfL \
        "${curl_opts[@]}" \
        "https://api.$UPSTREAM_HOST/repos/$UPSTREAM_OWNER/$UPSTREAM_REPO/contents/$path?ref=$commit"
}

forge_github_verified_commit_sha() {
    local ref="$1"
    local auth_header
    local -a curl_opts
    auth_header="$(forge_github_auth_header)"
    curl_opts=(-H "Accept: application/vnd.github+json")
    [ -n "$auth_header" ] && curl_opts+=(-H "$auth_header")
    curl --retry 3 --retry-delay 1 --max-time 30 --connect-timeout 10 -sfL \
        "${curl_opts[@]}" "$(forge_github_commit_url "$ref")" 2>/dev/null \
      | python3 -c 'import json,sys
d=json.load(sys.stdin)
v=d.get("commit", {}).get("verification", {})
print(d.get("sha", "") if v.get("verified") is True else "")'
}

forge_github_newest_verified_commit_sha() {
    local ref="$1"
    local auth_header
    local -a curl_opts
    auth_header="$(forge_github_auth_header)"
    curl_opts=(-H "Accept: application/vnd.github+json")
    [ -n "$auth_header" ] && curl_opts+=(-H "$auth_header")
    curl --retry 3 --retry-delay 1 --max-time 30 --connect-timeout 10 -sfL \
        "${curl_opts[@]}" \
        "https://api.$UPSTREAM_HOST/repos/$UPSTREAM_OWNER/$UPSTREAM_REPO/commits?sha=$ref&per_page=100" 2>/dev/null \
      | python3 -c 'import json,re,sys
for c in json.load(sys.stdin):
    sha=c.get("sha", "")
    if c.get("commit", {}).get("verification", {}).get("verified") is True and re.fullmatch(r"[0-9a-f]{40}", sha):
        print(sha)
        break'
}

forge_github_auth_header() {
    local token="${GITHUB_TOKEN:-}"
    if [ -z "$token" ] && command -v gh >/dev/null 2>&1; then
        token="$(gh auth token 2>/dev/null || true)"
    fi
    [ -n "$token" ] || return 0
    printf 'Authorization: token %s' "$token"
}
