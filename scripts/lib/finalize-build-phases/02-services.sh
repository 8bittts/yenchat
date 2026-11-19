#!/bin/bash
# Sourced by finalize-build.sh; shares its working directory, state, and traps.

# ============================================================================
# SIGNING HELPER (with retry for flaky timestamp server)
# ============================================================================

# Adaptive timestamp throttle: zero spacing until a real timestamp error is seen,
# then 1s between signs for the rest of the run so they don't compound Apple's
# rate limit. The fail-closed retry/backoff below (sleep 10, max 40 attempts) is
# the actual defense; this only avoids paying ~24s of dead time on healthy runs.
SIGN_TIMESTAMP_PRESSURE_SEEN=0

sign_with_retry() {
    local target="$1"
    local entitlements="${2:-}"
    local max_attempts=40
    local attempt=1
    local sign_stderr

    while [ $attempt -le $max_attempts ]; do
        if [ -n "$entitlements" ] && [ -f "$entitlements" ]; then
            if sign_stderr=$(codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --entitlements "$entitlements" "$target" 2>&1 >/dev/null); then
                [ "$SIGN_TIMESTAMP_PRESSURE_SEEN" = 1 ] && sleep 1  # spacing only after observed pressure
                return 0
            fi
        else
            if sign_stderr=$(codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$target" 2>&1 >/dev/null); then
                [ "$SIGN_TIMESTAMP_PRESSURE_SEEN" = 1 ] && sleep 1  # spacing only after observed pressure
                return 0
            fi
        fi
        # Only retry on timestamp-related errors; fail fast on everything else
        if ! printf '%s\n' "$sign_stderr" | grep -qi "timestamp"; then
            echo "  codesign error (not timestamp-related): $sign_stderr" >&2
            return 1
        fi
        # Timestamp pressure observed — enable pre-emptive 1s spacing on every
        # subsequent successful sign for the remainder of this run.
        SIGN_TIMESTAMP_PRESSURE_SEEN=1
        attempt=$((attempt + 1))
        if [ $attempt -le $max_attempts ]; then
            sleep 10  # Longer delay between retries for flaky timestamp service
        fi
    done
    echo "  codesign timestamp failed after $max_attempts attempts" >&2
    return 1
}

public_url_status() {
    local url="$1"
    local method="$2"
    if [ "$method" = "HEAD" ]; then
        # HEAD avoids streaming the full body (the DMG is ~102MB) just to read a
        # status code. Only the status line is consumed here; the authoritative
        # byte-exact size check lives in verify_remote_content_length (which keeps
        # its Cloudflare content-range fallback). Keep the small .sha256 probe on
        # GET so it never leans on the documented HEAD Content-Length quirk.
        curl -o /dev/null -sIL -w '%{http_code}' "$url" 2>/dev/null || true
    else
        curl -o /dev/null -sL -w '%{http_code}' "$url" 2>/dev/null || true
    fi
}

# GitHub's asset host can answer 404 for a short time after `gh release upload`
# returns: on v1.272 and v1.273 the .sha256 probe got 404 for about a minute after
# a correct upload, which failed the release. Retry the status probe for about
# three minutes by default, then fail closed.
verify_public_url() {
    local label="$1"
    local url="$2"
    local method="${3:-GET}"
    local attempts="${YEN_RELEASE_URL_VERIFY_ATTEMPTS:-18}"
    local delay="${YEN_RELEASE_URL_VERIFY_DELAY_SECONDS:-10}"
    local attempt=1
    local verify_status
    case "$attempts" in
        ''|*[!0-9]*|0)
            echo "  ERROR: ${label} upload verification misconfigured (YEN_RELEASE_URL_VERIFY_ATTEMPTS=${attempts})"
            exit 1
            ;;
    esac
    while :; do
        verify_status=$(public_url_status "$url" "$method")
        [ "$verify_status" = "200" ] && return 0
        [ "$attempt" -ge "$attempts" ] && break
        echo "  ${label}: HTTP ${verify_status:-unknown} on attempt ${attempt}/${attempts}; retrying in ${delay}s"
        attempt=$((attempt + 1))
        sleep "$delay"
    done
    echo "  ERROR: ${label} upload verification failed (HTTP ${verify_status:-unknown} after ${attempts} attempts)"
    exit 1
}

verify_signed_metadata_round_trip() {
    local payload_path="$1"
    local signature_path="$2"
    local public_key_b64="$3"

    if verify_signed_file_with_signature_file "$payload_path" "$signature_path" "$public_key_b64"; then
        return 0
    fi

    # The long-running finalize shell has intermittently failed this exact
    # round-trip even when a clean child process can validate the same files.
    # Use a standalone script to avoid shell-state and quoting ambiguity.
    env -i HOME="$HOME" PATH="$PATH" TMPDIR=/tmp \
        "$REPO_ROOT/scripts/lib/verify-signed-file.sh" "$payload_path" "$signature_path" "$public_key_b64"
}

verify_remote_content_length() {
    local label="$1"
    local url="$2"
    local local_path="$3"
    local expected_size
    local remote_size

    expected_size=$(stat -f%z "$local_path" 2>/dev/null || true)
    if [ -z "$expected_size" ]; then
        echo "  ERROR: ${label} upload verification failed (local file size unavailable)"
        exit 1
    fi

    remote_size=$(curl -sIL "$url" 2>/dev/null | tr -d '\r' | awk 'tolower($1) == "content-length:" { print $2 }' | tail -1 || true)
    if [ -z "$remote_size" ]; then
        # A CDN edge can omit Content-Length on HEAD for small text/plain assets.
        # Fall back to a single-byte range GET and parse
        # `content-range: bytes 0-0/<total>` for the authoritative size.
        remote_size=$(curl -sL -r 0-0 -D - -o /dev/null "$url" 2>/dev/null | tr -d '\r' \
            | awk 'tolower($1) == "content-range:" { split($3, a, "/"); print a[2] }' | tail -1 || true)
    fi
    if [ -z "$remote_size" ]; then
        echo "  ERROR: ${label} upload verification failed (missing Content-Length and Content-Range)"
        exit 1
    fi

    if [ "$remote_size" != "$expected_size" ]; then
        echo "  ERROR: ${label} upload verification failed (size mismatch: local=$expected_size remote=$remote_size)"
        exit 1
    fi
}

# Create the GitHub Release for this version when it does not exist yet. The tag
# points at the default branch's tip, which carries the source this build came
# from; the release commit that publishes version.json lands after it.
ensure_github_release() {
    local tag="$1"
    local title="$2"
    local notes="$3"
    local view_output=""

    if view_output=$(gh release view "$tag" --repo "$GITHUB_RELEASES_REPO" --json tagName --jq .tagName 2>&1); then
        [ "$view_output" = "$tag" ] && return 0
    elif ! printf '%s\n' "$view_output" | grep -qi "release not found"; then
        echo "  ERROR: Could not read GitHub Release $tag"
        echo "  $view_output"
        return 1
    fi

    if ! view_output=$(gh release create "$tag" --repo "$GITHUB_RELEASES_REPO" \
        --title "$title" --notes "$notes" --latest 2>&1); then
        echo "  ERROR: Could not create GitHub Release $tag"
        echo "  $view_output"
        return 1
    fi
}

# Upload one release asset, replacing an existing asset of the same name. Retries
# only transient network and server errors; anything else fails at once.
upload_github_release_asset_retry() {
    local label="$1"
    local local_path="$2"
    local tag="$3"
    local max_attempts=5
    local attempt=1
    local upload_output=""

    if [ ! -f "$local_path" ]; then
        echo "  ERROR: ${label} not found: $local_path"
        return 1
    fi

    while [ "$attempt" -le "$max_attempts" ]; do
        if upload_output=$(gh release upload "$tag" "$local_path" --repo "$GITHUB_RELEASES_REPO" --clobber 2>&1); then
            return 0
        fi

        if echo "$upload_output" | grep -Eiq "timed out|timeout|connection (reset|refused)|EOF|50[0234]|tls handshake"; then
            if [ "$attempt" -lt "$max_attempts" ]; then
                echo "    WARNING: ${label} network error (attempt $attempt/$max_attempts) — retrying..."
                sleep $((attempt * 2))
                attempt=$((attempt + 1))
                continue
            fi
        fi

        echo "  ERROR: Failed to upload ${label} to GitHub Release $tag"
        echo "  $upload_output"
        return 1
    done

    echo "  ERROR: Failed to upload ${label} to GitHub Release $tag after $max_attempts attempts"
    echo "  Last output: $upload_output"
    return 1
}

# Keychain access already verified by build-release.sh Step 1
