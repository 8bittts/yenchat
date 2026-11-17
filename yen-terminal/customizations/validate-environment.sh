#!/bin/bash
# Validate Build Environment
#
# Checks Xcode version and CoreSimulator compatibility before building.
# Exits with error code if environment is not ready.
#
# Usage: ./customizations/validate-environment.sh

set -e

VE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$VE_SCRIPT_DIR/../../scripts/lib/xcode-policy.sh"
source "$VE_SCRIPT_DIR/../../scripts/lib/zig-toolchain.sh"

# ============================================================================
# CHECK XCODE
# ============================================================================

if ! command -v xcodebuild &> /dev/null; then
    echo "  ✗ xcodebuild not found"
    echo "    Install Xcode from App Store or run: xcode-select --install"
    exit 1
fi

XCODE_VERSION=$(xcodebuild -version 2>&1 | head -1)
echo "  ✓ $XCODE_VERSION"

validate_selected_xcode_release_policy || exit 1

# Check if we can build (this will fail if CoreSimulator is mismatched)
if xcodebuild -version &> /dev/null; then
    echo "  ✓ Xcode build tools available"
else
    echo "  ✗ Xcode build tools not available"
    exit 1
fi

# Check for CoreSimulator issues by attempting to list simulators
if xcodebuild -showsdks &> /dev/null; then
    echo "  ✓ CoreSimulator accessible"
else
    echo "  ⚠ CoreSimulator check failed (may still build for macOS)"
    echo "    If build fails, update macOS/Xcode:"
    echo "    System Settings → Software Update"
fi

# ============================================================================
# CHECK ZIG
# ============================================================================

if ! command -v zig &> /dev/null; then
    echo "  ✗ Zig not found"
    echo "    Install Zig: brew install zig"
    exit 1
fi

ZIG_VERSION=$(zig version)
echo "  ✓ Zig installed: $ZIG_VERSION"

# Compare against Ghostty's pinned minimum_zig_version — fail fast with a clear
# recovery command instead of letting zig build emit cryptic stdlib errors.
# Bypass: YEN_SKIP_ZIG_VERSION_CHECK=1 (not recommended).
# Resolve path from this script's location so CWD is irrelevant (caller may
# invoke us from repo root or yen-terminal/).
ZIG_ZON="$VE_SCRIPT_DIR/../ghostty/build.zig.zon"
if [ -f "$ZIG_ZON" ] && [ "${YEN_SKIP_ZIG_VERSION_CHECK:-}" != "1" ]; then
    ZIG_CHECK_STATUS=0
    zig_toolchain_check "$ZIG_ZON" || ZIG_CHECK_STATUS=$?
    if [ "$ZIG_CHECK_STATUS" -ne 0 ]; then
        echo "  ✗ Zig version mismatch: have $ZIG_VERSION, Ghostty requires exactly $ZIG_TOOLCHAIN_REQUIRED"
        echo "    Recovery: $(zig_toolchain_recovery_command "$ZIG_TOOLCHAIN_REQUIRED")"
        echo "    Override: YEN_SKIP_ZIG_VERSION_CHECK=1 (will likely fail later with stdlib API mismatch)"
        exit 1
    fi
    if [ -n "$ZIG_TOOLCHAIN_REQUIRED" ]; then
        echo "  ✓ Zig version matches Ghostty minimum_zig_version ($ZIG_TOOLCHAIN_REQUIRED)"
    fi
fi

# ============================================================================
# CHECK GO
# ============================================================================

if ! command -v go &> /dev/null; then
    echo "  ✗ Go not found"
    echo "    Install Go: brew install go"
    exit 1
fi

GO_VERSION=$(go version | awk '{print $3}')
echo "  ✓ Go installed: $GO_VERSION"

# ============================================================================
# CHECK GETTEXT TOOLS (locale catalog rebranding)
# ============================================================================

if ! command -v msgfmt &> /dev/null; then
    echo "  ✗ msgfmt not found"
    echo "    Install gettext: brew install gettext"
    exit 1
fi

if ! command -v msgunfmt &> /dev/null; then
    echo "  ✗ msgunfmt not found"
    echo "    Install gettext: brew install gettext"
    exit 1
fi

echo "  ✓ gettext tools available (msgfmt/msgunfmt)"
