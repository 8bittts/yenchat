#!/bin/bash
# Shared overlay checks. Call from yen-terminal after sourcing the patch runtime.

remove_overlay_wrapper_sendable() {
for SWIFT_FILE in \
    "ghostty/macos/Sources/YEN/Ghostty.Surface.swift" \
    "ghostty/macos/Sources/YEN/Ghostty.Inspector.swift"; do
    if [ ! -f "$SWIFT_FILE" ]; then
        echo "  ERROR: wrapper class file missing for Sendable removal: $SWIFT_FILE; refusing to silently skip fail-closed guard"
        exit 1
    fi
    run_overlay_util python3 "$REPO_ROOT/scripts/lib/remove-wrapper-sendable.py" "$SWIFT_FILE"
done
}

verify_overlay_shift_enter() {
SHIFT_ENTER_SEGMENT=$(awk '
    /Shift\+Enter fix/ { found = 1; remaining = 40 }
    found && remaining > 0 { print; remaining--; if (remaining == 0) exit }
' "$CONFIG_ZIG")
if ! printf '%s\n' "$SHIFT_ENTER_SEGMENT" | grep -Fq ".{ .key = .{ .physical = .enter }, .mods = .{ .shift = true } }," || \
   ! printf '%s\n' "$SHIFT_ENTER_SEGMENT" | grep -Fq '.{ .text = "\\x0d" },'; then
    echo "  ERROR: Shift+Enter keybind payload not found after injection"
    exit 1
fi
}

verify_overlay_required_hooks() {
    local target="$1" manifest="$2" label="$3" hook count=0
    if [ ! -s "$manifest" ]; then
        echo "  ERROR: Required-hook manifest missing or empty: $manifest" >&2
        return 1
    fi
    while IFS= read -r hook || [ -n "$hook" ]; do
        [ -n "$hook" ] || continue
        count=$((count + 1))
        if ! grep -q "$hook" "$target"; then
            echo "  ERROR: $label overlay missing required hook: $hook"
            return 1
        fi
    done < "$manifest"
    if [ "$count" -eq 0 ]; then
        echo "  ERROR: Required-hook manifest contains no hooks: $manifest" >&2
        return 1
    fi
}

verify_overlay_app_hooks() {
APPDELEGATE="ghostty/macos/Sources/App/AppDelegate.swift"
if [ ! -f "$APPDELEGATE" ]; then
    echo "  ERROR: AppDelegate.swift not found after overlays copy"
    exit 1
fi

verify_overlay_required_hooks "$APPDELEGATE" "$REPO_ROOT/scripts/lib/overlay-data/app-delegate-hooks.txt" "AppDelegate"
APP_MENU_SHORTCUT_CONTROLLER="ghostty/macos/Sources/App/AppMenuShortcutController.swift"
verify_overlay_required_hooks "$APP_MENU_SHORTCUT_CONTROLLER" "$REPO_ROOT/scripts/lib/overlay-data/menu-shortcut-hooks.txt" "AppMenuShortcutController"

if grep -q '"search:next"' "$APPDELEGATE" || grep -q '"search:previous"' "$APPDELEGATE"; then
    echo "  ERROR: AppDelegate search action names must use navigate_search:*"
    exit 1
fi

# Cross-file method parity: upstream non-AppDelegate files may call methods on
# AppDelegate that our overlays must continue to define. Scan all macOS source
# files except AppDelegate*.swift and verify each appDelegate.method() call is
# implemented somewhere in AppDelegate*.swift.
APPDELEGATE_DIR="ghostty/macos/Sources/App"
MACOS_SOURCES_DIR="ghostty/macos/Sources"
if [ -d "$APPDELEGATE_DIR" ] && [ -d "$MACOS_SOURCES_DIR" ]; then
    MISSING_METHODS=0
    while IFS= read -r method; do
        [ -n "$method" ] || continue
        if ! grep -Eq "func[[:space:]]+$method\\b" "$APPDELEGATE_DIR"/AppDelegate*.swift; then
            echo "  ERROR: AppDelegate overlay missing method called outside AppDelegate: $method"
            MISSING_METHODS=$((MISSING_METHODS + 1))
        fi
    done < <(
        /usr/bin/find "$MACOS_SOURCES_DIR" -type f -name "*.swift" ! -name "AppDelegate*.swift" \
            -exec grep -hoE 'appDelegate\.([a-zA-Z_][a-zA-Z0-9_]*)\(' {} + 2>/dev/null \
        | /usr/bin/sed 's/appDelegate\.\(.*\)(/\1/' \
        | sort -u
    )
    if [ "$MISSING_METHODS" -gt 0 ]; then
        echo "  ERROR: $MISSING_METHODS AppDelegate method(s) missing — upstream likely added new AppDelegate APIs"
        echo "  Fix: merge the missing methods into AppDelegate.swift or AppDelegate+*.swift overlays"
        exit 1
    fi
fi
}

verify_overlay_native_geometry() {
QUICK_TERMINAL_NATIVE_GEOMETRY_FILES=(
    "ghostty/macos/Sources/Features/QuickTerminal/QuickTerminalPosition.swift"
    "ghostty/macos/Sources/Features/QuickTerminal/QuickTerminalScreenStateCache.swift"
    "ghostty/macos/Sources/Features/QuickTerminal/QuickTerminalController.swift"
)
for quick_terminal_source in "${QUICK_TERMINAL_NATIVE_GEOMETRY_FILES[@]}"; do
    if [ ! -f "$quick_terminal_source" ]; then
        echo "  ERROR: Quick Terminal geometry source missing: $quick_terminal_source" >&2
        return 1
    fi
    if grep -Eq 'windowAnchoredFrameSize|frameBounds\(for:|hasFrameAnchor|YENGeometryClamp\.sanitize' "$quick_terminal_source"; then
        echo "  ERROR: Retired YEN Quick Terminal geometry override remains in $quick_terminal_source"
        echo "         Refresh the source-vendor tree before applying overlays."
        exit 1
    fi
done
}

verify_overlay_applescript_dictionary() {
if [ -f "ghostty/macos/YEN.sdef" ]; then
    if [ ! -f "overlays/macos/YEN.sdef" ]; then
        echo "  ERROR: Overlay AppleScript dictionary missing — expected overlays/macos/YEN.sdef"
        exit 1
    fi
    if ! cmp -s "overlays/macos/YEN.sdef" "ghostty/macos/YEN.sdef"; then
        echo "  ERROR: Overlay AppleScript dictionary drifted from branded upstream YEN.sdef"
        echo "         Update overlays/macos/YEN.sdef to match the current branded upstream dictionary."
        exit 1
    fi
fi
}
