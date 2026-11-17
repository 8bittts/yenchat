#!/bin/bash
# bundle-yen-resources.sh
#
# Bundles all YEN-specific resources into the app bundle.
# Called by YENCustomResources.zig during the zig build process.
#
# This script replaces 12 separate Zig build steps with a single, maintainable script.
# Ordered phases share this script's paths and bundle state.
#
# Usage: ./bundle-yen-resources.sh /path/to/YEN.app
#        APP_PATH=/path/to/YEN.app ./bundle-yen-resources.sh
#
# The app path comes from the first argument (the Zig build passes it, because
# Zig 0.17 resolves the install prefix only at build time) or from APP_PATH.

set -e

# Ensure deterministic locale for slug sanitization
LC_ALL=C
export LC_ALL

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YEN_TERMINAL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$YEN_TERMINAL_DIR/.." && pwd)"

# Paths
YEN_CLI_DIR="$PROJECT_ROOT/yen-cli"
VERSION_JSON="$PROJECT_ROOT/public/stable/version.json"
CUSTOMIZATIONS_DIR="$SCRIPT_DIR"
GH_VENDOR_DIR="$CUSTOMIZATIONS_DIR/vendor/gh"

if [ -d "$GH_VENDOR_DIR" ]; then
    echo "ERROR: Removed vendor directory reintroduced: $GH_VENDOR_DIR"
    echo "Explicitly re-evaluate GitHub CLI bundling before re-adding vendor/gh"
    exit 1
fi

# Source shared utilities
require_bundle_source() {
    if [ ! -r "$1" ]; then
        echo "ERROR: resource bundling source missing: $1" >&2
        exit 1
    fi
}

require_bundle_source "$PROJECT_ROOT/scripts/lib/version-utils.sh"
source "$PROJECT_ROOT/scripts/lib/version-utils.sh"
require_bundle_source "$PROJECT_ROOT/scripts/lib/python-utils.sh"
source "$PROJECT_ROOT/scripts/lib/python-utils.sh"

require_python3 "for bundle manifest validation" || exit 1

# Validate the required app path
APP_PATH="${1:-${APP_PATH:-}}"
if [ -z "$APP_PATH" ]; then
    echo "ERROR: app path not set"
    echo "Usage: ./bundle-yen-resources.sh /path/to/YEN.app"
    exit 1
fi

# Validate paths exist
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: APP_PATH does not exist: $APP_PATH"
    exit 1
fi

if [ ! -f "$VERSION_JSON" ]; then
    echo "ERROR: version.json not found: $VERSION_JSON"
    exit 1
fi

# Extract version info using shared utilities
VERSION=$(get_version "$VERSION_JSON")
VERSION_INT=$(get_version_int "$VERSION")
COMMIT=$(get_git_commit "$PROJECT_ROOT")

echo "Bundling YEN resources v$VERSION ($COMMIT)..."

for bundle_phase in \
    01-themes.sh \
    02-cli-resources.sh \
    03-binaries.sh \
    04-yazi.sh \
    05-shell-integration.sh \
    06-locales.sh
do
    bundle_phase_path="$PROJECT_ROOT/scripts/lib/bundle-resource-phases/$bundle_phase"
    require_bundle_source "$bundle_phase_path"
    source "$bundle_phase_path"
done

# Skip re-signing (finalize-build.sh handles proper signing)
# finalize-build.sh will do proper Developer ID signing of the outer app bundle.

echo "Done. YEN resources bundled successfully."
