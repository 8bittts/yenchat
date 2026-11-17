#!/bin/bash
# Analyze Impact Script
# Manual utility for Ghostty upstream impact review (not invoked by 14-vendor.sh)
#
# Analyzes upstream changes and checks for conflicts with YEN customizations.
#
# Usage: ./scripts/09-analyze-impact.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/scripts/lib/python-utils.sh"
source "$REPO_ROOT/scripts/lib/upstream.sh"

require_python3 "for impact JSON analysis" || exit 1

BASELINE_FILE="yen-terminal/.ghostty-baseline"

echo "Impact Analysis"

# Get baseline
if [ ! -f "$BASELINE_FILE" ]; then
    echo "ERROR: .ghostty-baseline not found"
    exit 1
fi

CURRENT=$(grep "^upstream_commit=" "$BASELINE_FILE" | cut -d'=' -f2)

# Fetch comparison. Same token handling as 08 — anonymous requests hit the rate
# limit quickly, which here turns a usable impact report into a hard abort.
CURL_OPTS=(--max-time 30 --connect-timeout 10 -s -w "\n%{http_code}")
UPSTREAM_AUTH="$(upstream_auth_header)"
if [ -n "$UPSTREAM_AUTH" ]; then
    CURL_OPTS+=(-H "$UPSTREAM_AUTH")
fi

API_RESPONSE=$(curl "${CURL_OPTS[@]}" \
    "$(upstream_compare_url "$CURRENT" main)" 2>/dev/null || echo "")
HTTP_CODE=$(echo "$API_RESPONSE" | tail -1)
COMPARE_RESULT=$(echo "$API_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "403" ]; then
    echo "ERROR: Upstream API rate limited${UPSTREAM_AUTH:+ (token was sent)}"
    exit 1
elif [ "$HTTP_CODE" != "200" ]; then
    echo "ERROR: Upstream API returned ${HTTP_CODE:-no response}"
    exit 1
fi

# Analyze and categorize in single pass
echo "$COMPARE_RESULT" | python3 -c "
import sys, json

data = json.load(sys.stdin)
files = [f['filename'] for f in data.get('files', [])]

categories = {
    'Build System': [],
    'macOS App': [],
    'Shell Integration': [],
    'Terminal Core': [],
    'Other': []
}

for f in files:
    if 'build' in f and f.endswith('.zig'):
        categories['Build System'].append(f)
    elif f.startswith('macos/'):
        categories['macOS App'].append(f)
    elif 'shell-integration' in f:
        categories['Shell Integration'].append(f)
    elif any(x in f for x in ['terminal/', 'renderer/', 'pty/', 'input/', 'font/']):
        categories['Terminal Core'].append(f)
    else:
        categories['Other'].append(f)

# Output summary
warnings = 0
conflict_cats = ['Build System', 'macOS App', 'Shell Integration']

for cat, cat_files in categories.items():
    if cat_files:
        count = len(cat_files)
        if cat in conflict_cats:
            warnings += 1
            print(f'  ! {cat}: {count} files (may affect YEN)')
        else:
            print(f'  {cat}: {count} files')

if warnings == 0:
    print('')
    print('  No conflicts detected')
else:
    print('')
    print(f'  {warnings} categories may need review')
" 2>/dev/null || echo "  (could not analyze files)"

echo ""

# Verify YEN customization files exist
cd yen-terminal
MISSING=0

CUSTOM_FILES=(
    # Build system overlays
    "overlays/build.zig"
    "overlays/src/build/main.zig"
    "overlays/src/build/YENCustomResources.zig"
    # macOS accent color
    "overlays/macos/Assets.xcassets/AccentColor.colorset/Contents.json"
    # App delegate extension (Settings Cmd+,)
    "overlays/macos/Sources/App/AppDelegate+Settings.swift"
    "overlays/macos/Sources/App/MainMenu.xib"
    # About feature
    "overlays/macos/Sources/Features/About/AboutView.swift"
    "overlays/macos/Sources/Features/About/AboutController.swift"
    # Dictation feature (Option+Space)
    "overlays/macos/Sources/Features/Dictation/DictationController.swift"
    "overlays/macos/Sources/Features/Dictation/DictationHotKey.swift"
    "overlays/macos/Sources/Features/Dictation/DictationRecognizer.swift"
    # Settings feature (Cmd+,)
    "overlays/macos/Sources/Features/Settings/SettingsController.swift"
    "overlays/macos/Sources/Features/Settings/SettingsPanel.swift"
    # Terminal extensions
    "overlays/macos/Sources/Features/Terminal/ConfigReloadToast.swift"
    "overlays/macos/Sources/Features/Terminal/TerminalView.swift"
    # Customizations (not overlays)
    "customizations/shell-integration/yen-welcome.sh"
    "customizations/icons/icon.json"
)

for f in "${CUSTOM_FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Missing: $(basename "$f")"
        MISSING=1
    fi
done

if [ $MISSING -eq 0 ]; then
    echo "  Customization files: OK"
fi

# Check for changes to files with YEN patch/coupling risk.
PATCHED_FILES=(
    "src/termio/Exec.zig"                    # YEN_BIN_DIR patch anchor
    "src/config/Config.zig"                  # copy-on-select + keybind injections
    "macos/Ghostty.xcodeproj/project.pbxproj"  # INFOPLIST_PREPROCESS + deployment target
    "src/termio/stream_handler.zig"          # Upstream cursor reload behavior dependency
)

echo ""
echo "  Checking patched files..."
PATCH_WARNINGS=0
for pf in "${PATCHED_FILES[@]}"; do
    if echo "$COMPARE_RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
files = [f['filename'] for f in data.get('files', [])]
sys.exit(0 if '$pf' in files else 1)
" 2>/dev/null; then
        echo "  ! PATCHED FILE CHANGED: $pf"
        PATCH_WARNINGS=$((PATCH_WARNINGS + 1))
    fi
done

if [ "$PATCH_WARNINGS" -eq 0 ]; then
    echo "  No patch/coupling files affected"
else
    echo "  $PATCH_WARNINGS patch/coupling files changed — verify apply-overlays.sh anchors and cursor behavior assumptions"
fi

echo ""
echo "  Run ./scripts/10-update-ghostty.sh main to update"
