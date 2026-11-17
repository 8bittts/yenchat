#!/bin/bash
# Canonical upstream tree paths the YEN verification scripts depend on.
#
# WHY THIS EXISTS
# `04-verify-branding.sh` wraps most of its checks in `if [ -f "ghostty/..." ]`
# while `check()` increments the counter unconditionally. If upstream relocates
# a source directory — the shape an API-boundary refactor produces — every one
# of those checks skips its assertions and the script still prints a full green
# "Branding verified (N checks)" and exits 0. That script is a shipping gate
# (build-release.sh step 7), so the failure mode is a signed, notarized release
# built from a tree nothing actually verified.
#
# This module is the single declaration of those paths. A consumer calls
# ghostty_paths_verify and treats any output as a hard failure, independent of
# whatever the individual guards do.
#
# Entries are "<kind>|<path>", kind f = file, d = directory, path relative to
# yen-terminal/. Paths are in their POST-branding shape (upstream
# macos/Sources/Ghostty/ is macos/Sources/YEN/ by the time these run).
#
# NOT in this list, deliberately:
#   - retired paths asserted ABSENT (Ghostty.sdef, LayoutManager.swift, ...) —
#     those already fail closed, since presence is what raises the issue;
#   - pre-rename alternates (Ghostty.xcodeproj) resolved by an explicit
#     either/or at the call site.
#
# tests/123-release-script-hardening.test.ts asserts this list stays a superset
# of every path 04-verify-branding.sh guards on — BOTH the literal
# `[ -f "ghostty/..." ]` form and the indirect `[ -f "$VAR" ]` form, resolved
# through the VAR="ghostty/..." assignments. The first version of that test
# matched literals only, so 12 variable-guarded files silently escaped this
# manifest while the comment claimed they could not.

GHOSTTY_REQUIRED_PATHS=(
    "f|ghostty/images/YEN.icon/Assets/YEN.png"
    "f|ghostty/images/YEN.icon/icon.json"
    "f|ghostty/macos/Assets.xcassets/AppIconImage.imageset/macOS-AppIcon-1024px.png"
    "d|ghostty/macos/Sources"
    "d|ghostty/macos/Sources/App"
    "f|ghostty/macos/Sources/App/AppDelegate+Ghostty.swift"
    "f|ghostty/macos/Sources/App/AppDelegate+Screenshot.swift"
    "f|ghostty/macos/Sources/App/AppDelegate+Settings.swift"
    "f|ghostty/macos/Sources/App/AppDelegate.swift"
    "f|ghostty/macos/Sources/App/MainMenu.xib"
    "f|ghostty/macos/Sources/Features/App Intents/CommandPaletteIntent.swift"
    "f|ghostty/macos/Sources/Features/App Intents/Entities/CommandEntity.swift"
    "f|ghostty/macos/Sources/Features/App Intents/GetTerminalDetailsIntent.swift"
    "f|ghostty/macos/Sources/Features/App Intents/GhosttyIntentError.swift"
    "f|ghostty/macos/Sources/Features/App Intents/InputIntent.swift"
    "f|ghostty/macos/Sources/Features/App Intents/IntentPermission.swift"
    "f|ghostty/macos/Sources/Features/App Intents/KeybindIntent.swift"
    "d|ghostty/macos/Sources/Features/Command Palette"
    "f|ghostty/macos/Sources/Features/Dictation/DictationController.swift"
    "f|ghostty/macos/Sources/Features/Dictation/DictationHotKey.swift"
    "f|ghostty/macos/Sources/Features/Dictation/DictationOverlay.swift"
    "f|ghostty/macos/Sources/Features/Dictation/DictationRecognizer.swift"
    "f|ghostty/macos/Sources/Features/Settings/SettingsController.swift"
    "f|ghostty/macos/Sources/Features/Settings/SettingsPanel.swift"
    "f|ghostty/macos/Sources/Features/TabSidebar/TabSidebarController.swift"
    "f|ghostty/macos/Sources/Features/TabSidebar/TabSidebarPanel.swift"
    "f|ghostty/macos/Sources/Features/TabSidebar/TabSidebarView.swift"
    "f|ghostty/macos/Sources/Features/Update/UpdateController.swift"
    "f|ghostty/macos/YEN-Info.plist"
    "f|ghostty/macos/YEN.xcodeproj/project.pbxproj"
    "f|ghostty/macos/Yen.icns"
    "d|ghostty/src"
    "f|ghostty/src/Surface.zig"
    "d|ghostty/macos/Sources/Features/AppleScript"
    "f|ghostty/macos/Sources/Features/Custom App Icon/DockTilePlugin.swift"
    "f|ghostty/macos/Sources/Features/Splits/TerminalSplitTreeView.swift"
    "f|ghostty/macos/Sources/Features/Terminal/BaseTerminalController.swift"
    "f|ghostty/macos/Sources/Features/Terminal/TerminalController+FullscreenNotifications.swift"
    "f|ghostty/macos/Sources/Features/Terminal/TerminalController.swift"
    "f|ghostty/macos/Sources/Helpers/Extensions/NSPasteboard+Extension.swift"
    "f|ghostty/macos/Sources/Helpers/Fullscreen.swift"
    "f|ghostty/macos/Sources/YEN/Ghostty.App.swift"
    "f|ghostty/macos/Sources/YEN/Ghostty.Config.swift"
    "f|ghostty/macos/Sources/YEN/Surface View/SurfaceView.swift"
    "f|ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift"
    "f|ghostty/src/build_config.zig"
    "f|ghostty/src/cli/crash_report.zig"
    "f|ghostty/src/cli/help.zig"
    "f|ghostty/src/cli/list_themes.zig"
    "f|ghostty/src/cli/yen.zig"
    "f|ghostty/src/config/Config.zig"
    "f|ghostty/src/config/file_load.zig"
    "f|ghostty/src/extra/bash.zig"
    "f|ghostty/src/extra/vim.zig"
    "f|ghostty/src/termio/stream_handler.zig"
)

# Emits one unresolved path per line on stdout. Returns 0 when every declared
# path resolves, 1 otherwise. Call with the yen-terminal directory as $1
# (default: cwd). Under `set -e`, invoke in a conditional or command
# substitution so the caller controls the failure handling.
ghostty_paths_verify() {
    local root="${1:-.}"
    local record kind path rc=0

    if [ "${#GHOSTTY_REQUIRED_PATHS[@]}" -eq 0 ]; then
        printf '%s\n' "(GHOSTTY_REQUIRED_PATHS is empty — refusing to report success)"
        return 1
    fi

    for record in "${GHOSTTY_REQUIRED_PATHS[@]}"; do
        kind="${record%%|*}"
        path="${record#*|}"
        case "$kind" in
            f) [ -f "$root/$path" ] || { printf '%s\n' "$path"; rc=1; } ;;
            d) [ -d "$root/$path" ] || { printf '%s\n' "$path"; rc=1; } ;;
            *) printf '%s\n' "$path (bad kind '$kind')"; rc=1 ;;
        esac
    done

    return "$rc"
}
