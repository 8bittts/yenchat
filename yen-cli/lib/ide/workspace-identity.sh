# shellcheck shell=bash
# Source-time pure workspace identity helpers for local and remote yen ide targets.

IDE_WORKSPACE_TRANSPORT=""
IDE_WORKSPACE_EXECUTION_LOCATION=""
IDE_WORKSPACE_AUTHORITY=""
IDE_WORKSPACE_PORT=""
IDE_WORKSPACE_REQUESTED_PATH=""
IDE_WORKSPACE_ROOT=""
IDE_WORKSPACE_LABEL=""
IDE_WORKSPACE_IDENTITY=""
IDE_WORKSPACE_HASH_SEED=""
IDE_WORKSPACE_TRUST_KEY=""
IDE_WORKSPACE_REQUESTED_TARGET=""

workspace_identity_reset() {
    IDE_WORKSPACE_TRANSPORT=""
    IDE_WORKSPACE_EXECUTION_LOCATION=""
    IDE_WORKSPACE_AUTHORITY=""
    IDE_WORKSPACE_PORT=""
    IDE_WORKSPACE_REQUESTED_PATH=""
    IDE_WORKSPACE_ROOT=""
    IDE_WORKSPACE_LABEL=""
    IDE_WORKSPACE_IDENTITY=""
    IDE_WORKSPACE_HASH_SEED=""
    IDE_WORKSPACE_TRUST_KEY=""
    IDE_WORKSPACE_REQUESTED_TARGET=""
}

workspace_identity_is_remote() {
    [[ "${IDE_WORKSPACE_EXECUTION_LOCATION}" == "remote" ]]
}

workspace_identity_for_root() {
    local root="$1"

    if workspace_identity_is_remote; then
        workspace_identity_build_remote_identity \
            "$(workspace_identity_remote_authority_with_port)" \
            "${root}" \
            "${IDE_WORKSPACE_LABEL}"
        return 0
    fi

    workspace_identity_build_local_identity "${root}"
}

workspace_hash_seed_for_root() {
    local root="$1"

    if workspace_identity_is_remote; then
        workspace_identity_for_root "${root}"
        return 0
    fi

    printf "%s\n" "${root}"
}

workspace_trust_key_for_root() {
    local root="$1"

    if workspace_identity_is_remote; then
        workspace_identity_for_root "${root}"
        return 0
    fi

    printf "%s\n" "${root}"
}

workspace_timeline_key_for_root() {
    workspace_trust_key_for_root "$1"
}

workspace_identity_remote_authority_with_port() {
    if [[ -n "${IDE_WORKSPACE_PORT}" ]]; then
        printf "%s:%s\n" "${IDE_WORKSPACE_AUTHORITY}" "${IDE_WORKSPACE_PORT}"
        return 0
    fi
    printf "%s\n" "${IDE_WORKSPACE_AUTHORITY}"
}

workspace_identity_build_local_identity() {
    local root="$1"
    python3 - "${root}" <<'PY'
from urllib.parse import quote
import sys

root = sys.argv[1] or "/"
if not root.startswith("/"):
    root = "/" + root
print(f"local://{quote(root, safe='/')}")
PY
}

workspace_identity_build_remote_identity() {
    local authority="$1"
    local root="$2"
    local label="$3"
    python3 - "${authority}" "${root}" "${label}" <<'PY'
from urllib.parse import quote, urlencode
import sys

authority = sys.argv[1]
root = sys.argv[2] or "/"
label = sys.argv[3]
if not root.startswith("/"):
    root = "/" + root
identity = f"ssh://{authority}{quote(root, safe='/')}"
if label:
    identity = f"{identity}?{urlencode({'label': label})}"
print(identity)
PY
}

workspace_identity_set_resolved_root() {
    local root="$1"

    IDE_WORKSPACE_ROOT="${root}"
    if workspace_identity_is_remote; then
        IDE_WORKSPACE_IDENTITY=$(
            workspace_identity_build_remote_identity \
                "$(workspace_identity_remote_authority_with_port)" \
                "${IDE_WORKSPACE_ROOT}" \
                "${IDE_WORKSPACE_LABEL}"
        )
        IDE_WORKSPACE_HASH_SEED="${IDE_WORKSPACE_IDENTITY}"
        IDE_WORKSPACE_TRUST_KEY="${IDE_WORKSPACE_IDENTITY}"
        return 0
    fi

    IDE_WORKSPACE_ROOT=$(canonicalize_path "${IDE_WORKSPACE_ROOT}")
    IDE_WORKSPACE_IDENTITY=$(workspace_identity_build_local_identity "${IDE_WORKSPACE_ROOT}")
    # Preserve existing local hash/trust semantics until local-state migration lands.
    IDE_WORKSPACE_HASH_SEED="${IDE_WORKSPACE_ROOT}"
    IDE_WORKSPACE_TRUST_KEY="${IDE_WORKSPACE_ROOT}"
}

workspace_identity_parse_target() {
    local target="$1"
    local parsed=""

    workspace_identity_reset
    IDE_WORKSPACE_REQUESTED_TARGET="${target}"

    if [[ -n "${target}" && "${target}" == ssh://* ]]; then
        parsed=$(python3 - "${target}" <<'PY'
import json
import sys
from urllib.parse import parse_qs, urlsplit

ALLOWED_HOST = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
ALLOWED_USER = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")

try:
    parsed = urlsplit(sys.argv[1])
except Exception:
    raise SystemExit(1)

if parsed.scheme != "ssh" or not parsed.netloc or not parsed.path or not parsed.path.startswith("/"):
    raise SystemExit(1)

if parsed.fragment:
    raise SystemExit(1)

host = parsed.hostname or ""
if not host or any(ch not in ALLOWED_HOST for ch in host):
    raise SystemExit(1)

username = parsed.username or ""
if username and any(ch not in ALLOWED_USER for ch in username):
    raise SystemExit(1)

query = parse_qs(parsed.query, keep_blank_values=True)
extra_keys = sorted(key for key in query.keys() if key != "label")
if extra_keys:
    raise SystemExit(1)

label = query.get("label", [""])[0]
if len(query.get("label", [])) > 1:
    raise SystemExit(1)
authority = host.lower()
if username:
    authority = f"{username}@{authority}"

try:
    port = parsed.port or ""
except ValueError:
    raise SystemExit(1)
print(json.dumps({
    "authority": authority,
    "port": port,
    "path": parsed.path,
    "label": label,
}, sort_keys=True))
PY
) || return 1
        IDE_WORKSPACE_AUTHORITY=$(python3 - "${parsed}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
print(payload.get("authority", ""))
PY
)
        IDE_WORKSPACE_PORT=$(python3 - "${parsed}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
print(payload.get("port", ""))
PY
)
        IDE_WORKSPACE_REQUESTED_PATH=$(python3 - "${parsed}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
print(payload.get("path", ""))
PY
)
        IDE_WORKSPACE_LABEL=$(python3 - "${parsed}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
print(payload.get("label", ""))
PY
)
        IDE_WORKSPACE_TRANSPORT="ssh"
        IDE_WORKSPACE_EXECUTION_LOCATION="remote"
        IDE_WORKSPACE_ROOT="${IDE_WORKSPACE_REQUESTED_PATH}"
        IDE_WORKSPACE_IDENTITY=$(
            workspace_identity_build_remote_identity \
                "$(workspace_identity_remote_authority_with_port)" \
                "${IDE_WORKSPACE_REQUESTED_PATH}" \
                "${IDE_WORKSPACE_LABEL}"
        )
        IDE_WORKSPACE_HASH_SEED="${IDE_WORKSPACE_IDENTITY}"
        IDE_WORKSPACE_TRUST_KEY="${IDE_WORKSPACE_IDENTITY}"
        return 0
    fi

    IDE_WORKSPACE_TRANSPORT="local"
    IDE_WORKSPACE_EXECUTION_LOCATION="local"
    IDE_WORKSPACE_REQUESTED_PATH=$(resolve_start_path "${target}")
    IDE_WORKSPACE_ROOT="${IDE_WORKSPACE_REQUESTED_PATH}"
    workspace_identity_set_resolved_root "${IDE_WORKSPACE_ROOT}"
}
