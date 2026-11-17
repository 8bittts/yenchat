#!/bin/bash
# signature-utils.sh — shared base64 decode + Ed25519 signature verification helpers

signature_verify_debug() {
    if [ "${YEN_DEBUG_SIGNATURE_VERIFY:-0}" = "1" ]; then
        printf 'signature-debug: %s\n' "$*" >&2
    fi
}

signature_verify_debug_file() {
    local label="$1"
    local path="$2"

    if [ "${YEN_DEBUG_SIGNATURE_VERIFY:-0}" = "1" ] && [ -f "$path" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            printf 'signature-debug: %s %s\n' "$label" "$line" >&2
        done < "$path"
    fi
}

resolve_signature_openssl() {
    local candidate
    local path_candidate

    if [ -n "${SIGNATURE_OPENSSL_BIN_CACHE:-}" ] && [ -x "$SIGNATURE_OPENSSL_BIN_CACHE" ]; then
        printf '%s\n' "$SIGNATURE_OPENSSL_BIN_CACHE"
        return 0
    fi

    for candidate in \
        "${YEN_SIGNATURE_OPENSSL_BIN:-}" \
        "/opt/homebrew/bin/openssl" \
        "/opt/homebrew/opt/openssl@3/bin/openssl" \
        "/usr/local/bin/openssl" \
        "/usr/local/opt/openssl@3/bin/openssl" \
        "/opt/local/bin/openssl"
    do
        [ -n "$candidate" ] || continue
        [ -x "$candidate" ] || continue
        if "$candidate" pkeyutl -help 2>&1 | grep -q -- '-rawin'; then
            SIGNATURE_OPENSSL_BIN_CACHE="$candidate"
            printf '%s\n' "$SIGNATURE_OPENSSL_BIN_CACHE"
            return 0
        fi
    done

    path_candidate=$(command -v openssl 2>/dev/null || true)
    if [ -n "$path_candidate" ] && [ -x "$path_candidate" ] && \
       "$path_candidate" pkeyutl -help 2>&1 | grep -q -- '-rawin'; then
        SIGNATURE_OPENSSL_BIN_CACHE="$path_candidate"
        printf '%s\n' "$SIGNATURE_OPENSSL_BIN_CACHE"
        return 0
    fi

    if [ -x /usr/bin/openssl ] && /usr/bin/openssl pkeyutl -help 2>&1 | grep -q -- '-rawin'; then
        SIGNATURE_OPENSSL_BIN_CACHE=/usr/bin/openssl
        printf '%s\n' "$SIGNATURE_OPENSSL_BIN_CACHE"
        return 0
    fi

    return 1
}

decode_base64_to_file() {
    local input="$1"
    local output="$2"

    if printf "%s" "$input" | base64 --decode > "$output" 2>/dev/null; then
        return 0
    fi
    if printf "%s" "$input" | base64 -d > "$output" 2>/dev/null; then
        return 0
    fi
    if printf "%s" "$input" | base64 -D > "$output" 2>/dev/null; then
        return 0
    fi

    signature_verify_debug "base64 decode failed for $output"
    return 1
}

read_signature_file_body() {
    local signature_path="$1"
    if [ ! -f "$signature_path" ]; then
        signature_verify_debug "signature file missing: $signature_path"
        return 1
    fi

    local signature_body
    signature_body=$(tr -d '[:space:]' < "$signature_path")
    if [ -z "$signature_body" ]; then
        signature_verify_debug "signature body empty: $signature_path"
        return 1
    fi
    if ! echo "$signature_body" | grep -Eq '^[A-Za-z0-9+/=]+$'; then
        signature_verify_debug "signature body not base64 text: $signature_path"
        return 1
    fi

    printf "%s" "$signature_body"
}

verify_signed_file_with_public_key() {
    local payload_path="$1"
    local signature_body="$2"
    local public_key_b64="$3"
    local openssl_bin

    openssl_bin=$(resolve_signature_openssl) || openssl_bin=""
    if [ -z "$openssl_bin" ] || ! command -v xxd >/dev/null 2>&1; then
        signature_verify_debug "missing supported openssl or xxd in PATH=$PATH"
        return 1
    fi
    signature_verify_debug "using openssl $("$openssl_bin" version 2>/dev/null || printf '%s' "$openssl_bin")"

    local verify_dir
    verify_dir=$(mktemp -d)
    if [ -z "$verify_dir" ] || [ ! -d "$verify_dir" ]; then
        signature_verify_debug "mktemp -d failed"
        return 1
    fi
    local pub_raw="$verify_dir/public-key.raw"
    local pub_der="$verify_dir/public-key.der"
    local sig_bin="$verify_dir/signature.bin"

    if ! decode_base64_to_file "$public_key_b64" "$pub_raw"; then
        signature_verify_debug "public key base64 decode failed"
        rm -rf "$verify_dir"
        return 1
    fi
    if ! decode_base64_to_file "$signature_body" "$sig_bin"; then
        signature_verify_debug "signature base64 decode failed"
        rm -rf "$verify_dir"
        return 1
    fi

    local pub_size
    pub_size=$(wc -c < "$pub_raw" | tr -d '[:space:]')
    local sig_size
    sig_size=$(wc -c < "$sig_bin" | tr -d '[:space:]')
    if [ "$pub_size" != "32" ] || [ "$sig_size" != "64" ]; then
        signature_verify_debug "decoded sizes unexpected pub_size=$pub_size sig_size=$sig_size"
        rm -rf "$verify_dir"
        return 1
    fi

    local pub_hex
    pub_hex=$(xxd -p "$pub_raw" | tr -d '\n')
    printf "302a300506032b6570032100%s" "$pub_hex" | xxd -r -p > "$pub_der"

    local openssl_debug_log="$verify_dir/openssl-debug.log"
    if "$openssl_bin" pkeyutl -verify -rawin -pubin -keyform DER -inkey "$pub_der" -in "$payload_path" -sigfile "$sig_bin" >/dev/null 2>"$openssl_debug_log"; then
        signature_verify_debug "signature verification succeeded via DER payload=$payload_path"
        rm -rf "$verify_dir"
        return 0
    fi

    signature_verify_debug "direct DER verify failed; trying PEM conversion fallback"
    signature_verify_debug_file "pkeyutl(der):" "$openssl_debug_log"

    local pub_pem="$verify_dir/public-key.pem"
    : > "$openssl_debug_log"
    if ! "$openssl_bin" pkey -pubin -inform DER -in "$pub_der" -out "$pub_pem" >/dev/null 2>"$openssl_debug_log"; then
        signature_verify_debug "openssl pkey conversion failed"
        signature_verify_debug_file "pkey(der->pem):" "$openssl_debug_log"
        rm -rf "$verify_dir"
        return 1
    fi

    : > "$openssl_debug_log"
    if ! "$openssl_bin" pkeyutl -verify -rawin -pubin -inkey "$pub_pem" -in "$payload_path" -sigfile "$sig_bin" >/dev/null 2>"$openssl_debug_log"; then
        signature_verify_debug "openssl pkeyutl verify failed payload=$payload_path"
        signature_verify_debug_file "pkeyutl(pem):" "$openssl_debug_log"
        rm -rf "$verify_dir"
        return 1
    fi

    signature_verify_debug "signature verification succeeded payload=$payload_path"
    rm -rf "$verify_dir"
    return 0
}

verify_signed_file_with_signature_file() {
    local payload_path="$1"
    local signature_path="$2"
    local public_key_b64="$3"
    local signature_body

    signature_body=$(read_signature_file_body "$signature_path") || return 1
    verify_signed_file_with_public_key "$payload_path" "$signature_body" "$public_key_b64"
}

# assert_universal_binary <path> — 0 when the file is a fat binary containing
# BOTH arm64 and x86_64, non-zero otherwise (including a missing file).
#
# `file <path> | grep -q universal` is NOT sufficient and was used at ten sites:
# it also passes an arm64+arm64e fat binary that lacks x86_64 entirely, which
# would ship an app that cannot run on Intel. scripts/lib/vendor-binary.sh:310
# already documents this and uses `lipo -archs`; this is that check, shared.
assert_universal_binary() {
    local binary_path="$1"
    local archs=""

    [ -f "$binary_path" ] || return 1
    archs=$(lipo -archs "$binary_path" 2>/dev/null || echo "")
    [ -n "$archs" ] || return 1
    echo " $archs " | grep -q " arm64 " || return 1
    echo " $archs " | grep -q " x86_64 " || return 1
    return 0
}
