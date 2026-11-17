#!/bin/bash
# Sourced by build-release.sh; shares its working directory, state, and traps.

echo "[1/9] Validating environment..."

if [ -f "customizations/validate-environment.sh" ]; then
    bash customizations/validate-environment.sh || {
        echo "  ERROR: Environment validation failed"
        exit 1
    }
else
    echo "  ERROR: validate-environment.sh not found — build prerequisites cannot be verified"
    exit 1
fi

if [ "$BUILD_ONLY" != true ]; then
    echo ""
    echo "  Verifying keychain access (saves 10+ min if locked)..."
    if [ ! -r "$REPO_ROOT/scripts/lib/signing-constants.sh" ]; then
        echo "ERROR: Signing constants missing or unreadable" >&2
        exit 1
    fi
    source "$REPO_ROOT/scripts/lib/signing-constants.sh"
    TEST_BIN=$(mktemp)
    echo 'int main(){return 0;}' | clang -x c -o "$TEST_BIN" -
    if ! codesign --sign "$SIGNING_IDENTITY" "$TEST_BIN" >/dev/null 2>&1; then
        rm -f "$TEST_BIN"
        echo "  ERROR: Keychain locked or signing certificate unavailable"
        echo "  Run: security unlock-keychain ~/Library/Keychains/login.keychain-db"
        exit 1
    fi
    rm -f "$TEST_BIN"
    echo "  Keychain access verified"

    if ! NOTARY_HISTORY="$(xcrun notarytool history --keychain-profile "$NOTARIZATION_PROFILE" --keychain "$NOTARIZATION_KEYCHAIN" 2>/dev/null)"; then
        echo "  ERROR: Notarization profile '$NOTARIZATION_PROFILE' is unavailable"
        echo "  Run: xcrun notarytool store-credentials \"$NOTARIZATION_PROFILE\" --keychain \"$NOTARIZATION_KEYCHAIN\""
        exit 1
    fi
    if [ -z "$NOTARY_HISTORY" ]; then
        echo "  ERROR: Notarization credential check returned no positive receipt"
        exit 1
    fi
    echo "  Notarization credentials verified"

    # Release-credential fail-fast. These are validated authoritatively inside
    # finalize-build.sh, but only AFTER the build (and the EdDSA-key check only
    # AFTER notarization). Probe them here — cheap, read-only — so a missing
    # credential aborts before the ~15-20 min build+notarize instead of after it.
    # finalize-build.sh keeps its own copies as defense-in-depth; do not remove
    # those. This block only runs for full shipping builds (--local/--build-only
    # set BUILD_ONLY=true and never reach here, and never call finalize-build.sh).
    echo ""
    echo "  Verifying release credentials (saves a full build+notarize on failure)..."
    bash "$REPO_ROOT/scripts/01-verify-release-target.sh" || exit 1
    SPARKLE_SIGN_TOOL="$REPO_ROOT/tools/sparkle/bin/sign_update"
    SPARKLE_KEY_TOOL="$REPO_ROOT/tools/sparkle/bin/generate_keys"
    if [ ! -x "$SPARKLE_SIGN_TOOL" ]; then
        echo "  ERROR: Sparkle sign_update tool not found or not executable: $SPARKLE_SIGN_TOOL"
        exit 1
    fi
    if [ ! -x "$SPARKLE_KEY_TOOL" ]; then
        echo "  ERROR: Sparkle generate_keys tool not found or not executable: $SPARKLE_KEY_TOOL"
        exit 1
    fi
    if ! "$SPARKLE_KEY_TOOL" -p >/dev/null 2>&1; then
        echo "  ERROR: Sparkle EdDSA private key not found in keychain (required for signed version metadata)"
        echo "  Without this, finalize-build.sh would fail AFTER notarization — re-import the Sparkle key."
        exit 1
    fi
    echo "  Release credentials verified (notarization, GitHub release target, Sparkle sign/key tools, EdDSA key)"
fi

echo ""
if [ "$SKIP_VENDOR" = true ]; then
    echo "[2/9] Skipping vendor gate (caller already validated)..."
else
    echo "[2/9] Enforcing vendor and audit gates..."

    if [ -f "$REPO_ROOT/scripts/14-vendor.sh" ]; then
        bash "$REPO_ROOT/scripts/14-vendor.sh" --check || {
            echo "  ERROR: Vendor hard gate failed"
            echo "  Run: bash $REPO_ROOT/scripts/14-vendor.sh"
            echo "  Then complete the /yen-zip vendor audit (Step V3) and update _docs/04-security.md"
            exit 1
        }
    else
        echo "  ERROR: scripts/14-vendor.sh not found"
        exit 1
    fi
fi

# Audit doc check runs independently of vendor gate (catches stale _docs/04-security.md)
if [ -f "$REPO_ROOT/scripts/12-verify-vendor-audit.sh" ]; then
    bash "$REPO_ROOT/scripts/12-verify-vendor-audit.sh" || {
        echo "  ERROR: Canonical vendor audit doc check failed"
        echo "  Update _docs/04-security.md and re-run build"
        exit 1
    }
else
    echo "  ERROR: scripts/12-verify-vendor-audit.sh not found"
    exit 1
fi

case "$PREBUILD_COMPONENT_GATE_MODE" in
    off|report|enforce) ;;
    *)
        echo "  ERROR: invalid pre-build component gate mode: $PREBUILD_COMPONENT_GATE_MODE (expected off|report|enforce)"
        exit 1
        ;;
esac

if [ "$PREBUILD_COMPONENT_GATE_MODE" = "off" ]; then
    echo "  Pre-build component gate skipped (YEN_PREBUILD_COMPONENT_GATE_MODE=off)"
else
    echo "  Running pre-build component fail-fast gate (03-verify-components.sh)..."
    if ! bash "$REPO_ROOT/scripts/03-verify-components.sh"; then
        if [ "$PREBUILD_COMPONENT_GATE_MODE" = "enforce" ]; then
            echo "  ERROR: Pre-build component gate failed"
            exit 1
        fi
        echo "  WARNING: Pre-build component gate failed (report mode)"
    fi
fi

echo ""
