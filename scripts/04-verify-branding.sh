#!/bin/bash
# YEN Branding Verification Script
# Called by build-release.sh Step 7 (verify branding)
# Outputs single summary line on success, details on failure.
#
# Usage: ./scripts/04-verify-branding.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/gate-receipt.sh"
source "$REPO_ROOT/scripts/lib/upstream.sh"
source "$REPO_ROOT/scripts/lib/ghostty-paths.sh"
source "$REPO_ROOT/scripts/lib/sparkle-runtime-floor.sh"
cd "$REPO_ROOT/yen-terminal"

gate_begin 04-verify-branding

ISSUES=0
DETAILS=""

add_issue() {
    DETAILS="$DETAILS\n    X $1"
    ISSUES=$((ISSUES + 1))
}

# Replaces check(), which incremented a source-text constant. The real coverage
# question for this gate is whether its checks had SUBJECTS to check: 58 blocks
# sit behind `if [ -f "..." ]`, so a relocated or unbuilt tree skipped the bodies
# while the summary still printed a full green count.
SUBJECTS_TOTAL=0
SUBJECTS_PRESENT=0

subject_present() {
    local kind="$1" path="$2"
    SUBJECTS_TOTAL=$((SUBJECTS_TOTAL + 1))
    case "$kind" in
        f) [ -f "$path" ] || return 1 ;;
        d) [ -d "$path" ] || return 1 ;;
    esac
    SUBJECTS_PRESENT=$((SUBJECTS_PRESENT + 1))
    return 0
}

# Upstream-relocation gate. Most checks below sit behind
# `if [ -f "ghostty/..." ]` while check() increments unconditionally, so a
# relocated upstream tree would skip every assertion and still report a full
# green run out of this shipping gate. Resolve the declared path set first and
# raise each unresolved path as an issue, so the existing exit-code path
# handles it and the operator sees every casualty at once rather than one per
# run. See scripts/lib/ghostty-paths.sh.
MISSING_UPSTREAM_PATHS="$(ghostty_paths_verify . || true)"
if [ -n "$MISSING_UPSTREAM_PATHS" ]; then
    while IFS= read -r missing_upstream_path; do
        [ -n "$missing_upstream_path" ] || continue
        add_issue "upstream path missing (moved or removed): $missing_upstream_path"
    done <<EOF
$MISSING_UPSTREAM_PATHS
EOF
fi

# Check 1: icon.json
if subject_present f "ghostty/images/YEN.icon/icon.json"; then
    ICON_JSON_LINES=$(wc -l < ghostty/images/YEN.icon/icon.json | tr -d ' ')
    [ "$ICON_JSON_LINES" -gt 20 ] && add_issue "icon.json too complex ($ICON_JSON_LINES lines)"
    grep -qi "extended-srgb.*blue\|0.47843" ghostty/images/YEN.icon/icon.json && add_issue "icon.json contains blue color"
fi

# Check 2: Yen.icns
if subject_present f "ghostty/macos/Yen.icns"; then
    ICNS_SIZE=$(du -k ghostty/macos/Yen.icns | cut -f1)
    [ "$ICNS_SIZE" -lt 500 ] && add_issue "Yen.icns too small (${ICNS_SIZE} KB)"
else
    add_issue "Yen.icns not found"
fi

# Check 3: Bundle ID
if subject_present f "ghostty/src/build_config.zig"; then
    grep -q "com.yenchat.yen" ghostty/src/build_config.zig || add_issue "Bundle ID incorrect"
fi

# Check 4: Ghost emoji
if subject_present d "ghostty/macos/Sources"; then
    GHOST_EMOJI=$(grep -r "👻" --include="*.swift" --include="*.xib" ghostty/macos/Sources/ 2>/dev/null | wc -l | tr -d ' ')
    [ "$GHOST_EMOJI" -gt 0 ] && add_issue "Found $GHOST_EMOJI ghost emoji references"
fi

# Check 5: Zig CLI ghost emoji
ZIG_GHOST=0
[ -f "ghostty/src/cli/crash_report.zig" ] && grep -q "👻" ghostty/src/cli/crash_report.zig && ZIG_GHOST=$((ZIG_GHOST + 1))
[ -f "ghostty/src/cli/list_themes.zig" ] && grep -q "👻" ghostty/src/cli/list_themes.zig && ZIG_GHOST=$((ZIG_GHOST + 1))
[ "$ZIG_GHOST" -gt 0 ] && add_issue "Ghost emoji in Zig CLI files"

# Check 6: AppIconImage
if subject_present f "ghostty/macos/Assets.xcassets/AppIconImage.imageset/macOS-AppIcon-1024px.png"; then
    APP_ICON=$(du -k ghostty/macos/Assets.xcassets/AppIconImage.imageset/macOS-AppIcon-1024px.png | cut -f1)
    [ "$APP_ICON" -lt 400 ] && add_issue "AppIconImage too small (${APP_ICON} KB)"
fi

# Check 7: YEN.png
if subject_present f "ghostty/images/YEN.icon/Assets/YEN.png"; then
    YEN_PNG=$(du -k ghostty/images/YEN.icon/Assets/YEN.png 2>/dev/null | cut -f1 | tr -d ' ')
    [ -n "$YEN_PNG" ] && [ "$YEN_PNG" -lt 400 ] && add_issue "YEN.png too small ($YEN_PNG KB)"
fi

# Check 8: Wrong URLs
if [ -d "ghostty/macos/Sources" ] && [ -d "ghostty/src" ]; then
    WRONG_URLS=$(grep -r "https://yen\.org" --include="*.swift" --include="*.zig" ghostty/macos/Sources/ ghostty/src/ 2>/dev/null | grep -v "deps\.files\.yen\.org" | wc -l | tr -d ' ')
    [ -n "$WRONG_URLS" ] && [ "$WRONG_URLS" -gt 0 ] && add_issue "Found $WRONG_URLS incorrect URLs (yen.org)"
fi

# Check 8b: Provenance URLs in shipped extra resources point to YEN repo.
# Pattern derived from scripts/lib/upstream.sh so the Phase 1 forge swap can
# track new-host URL strings without editing this file.
UPSTREAM_URL_PATTERN="$(upstream_url_pattern_grep)"
if subject_present f "ghostty/src/extra/vim.zig"; then
    grep -Fq "$UPSTREAM_URL_PATTERN" "ghostty/src/extra/vim.zig" && \
        add_issue "vim extra resource still references upstream URL ($UPSTREAM_URL_PATTERN)"
fi
if subject_present f "ghostty/src/extra/bash.zig"; then
    grep -Fq "${UPSTREAM_URL_PATTERN}/discussions/2994" "ghostty/src/extra/bash.zig" && \
        add_issue "bash extra resource still references upstream discussion URL"
fi

# Check 8c: Custom shell-integration comments stay lineage-neutral
if subject_present f "customizations/shell-integration/bash/yen-integration.bash"; then
    grep -q "Based on Ghostty" "customizations/shell-integration/bash/yen-integration.bash" && \
        add_issue "bash shell integration comment still references Ghostty lineage"
fi
if subject_present f "customizations/shell-integration/zsh/yen-integration.zsh"; then
    grep -q "Based on Ghostty" "customizations/shell-integration/zsh/yen-integration.zsh" && \
        add_issue "zsh shell integration comment still references Ghostty lineage"
fi
if subject_present f "customizations/shell-integration/yen-welcome.sh"; then
    grep -q "Ghostty standard" "customizations/shell-integration/yen-welcome.sh" && \
        add_issue "welcome script comment still references Ghostty-standard wording"
fi

# Check 8d: The in-app docs stay lineage-neutral
# YEN is open source under MIT, so public/llms.txt, public/README.md and README.md credit Ghostty
# by name and are out of scope, as are internal engineering/vendor docs (_docs/, AGENTS.md, scripts/).
LINEAGE_PATTERN='ghostty|libghostty|com\.mitchellh\.ghostty'
USER_DOCS_MATCHES=""
if subject_present d "$REPO_ROOT/app/docs"; then
    USER_DOCS_MATCHES=$(grep -RniE "$LINEAGE_PATTERN" --include="*.tsx" --include="*.md" "$REPO_ROOT/app/docs" 2>/dev/null || true)
fi

if [ -n "$USER_DOCS_MATCHES" ]; then
    FIRST_LINEAGE_MATCH=$(printf "%s\n" "$USER_DOCS_MATCHES" | sed '/^$/d' | head -1 | sed "s|$REPO_ROOT/||")
    LINEAGE_MATCH_COUNT=$(printf "%s\n" "$USER_DOCS_MATCHES" | sed '/^$/d' | wc -l | tr -d ' ')
    add_issue "In-app docs contain Ghostty lineage tokens ($LINEAGE_MATCH_COUNT matches; first: $FIRST_LINEAGE_MATCH)"
fi

# Check 9: YENCustomResources.zig
[ ! -f "overlays/src/build/YENCustomResources.zig" ] && add_issue "YENCustomResources.zig not found"

# Check 11: Sparkle integration
if subject_present f "ghostty/macos/Sources/Features/Update/UpdateController.swift"; then
    grep -q "SPUStandardUpdaterController\|SPUUpdater" ghostty/macos/Sources/Features/Update/UpdateController.swift || add_issue "UpdateController not using Sparkle API"
fi

# Check 12: Sparkle auto-update defaults to permission dialog (SUEnableAutomaticChecks absent)
AUTO_UPDATE=0
# Plist must NOT contain SUEnableAutomaticChecks (let Sparkle show first-launch permission dialog)
if [ -f "ghostty/macos/YEN-Info.plist" ] && ! grep -q '<key>SUEnableAutomaticChecks</key>' ghostty/macos/YEN-Info.plist; then
    AUTO_UPDATE=$((AUTO_UPDATE + 1))
fi
# AppDelegate must not force-disable checks when config is unset (let Sparkle manage its own defaults)
if [ -f "ghostty/macos/Sources/App/AppDelegate.swift" ] && ! grep -q 'automaticallyChecksForUpdates = false' ghostty/macos/Sources/App/AppDelegate.swift; then
    AUTO_UPDATE=$((AUTO_UPDATE + 1))
fi
[ "$AUTO_UPDATE" -lt 2 ] && add_issue "Sparkle auto-update permission dialog not properly configured (SUEnableAutomaticChecks must be absent, AppDelegate must not force-disable)"

# Check 12b: Screen capture usage key stays removed (own-window capture path)
if [ -f "ghostty/macos/YEN-Info.plist" ] && grep -q '<key>NSScreenCaptureUsageDescription</key>' ghostty/macos/YEN-Info.plist; then
    add_issue "NSScreenCaptureUsageDescription should be absent (prompt-surface minimization)"
fi

# Check 12c: Tiered CLI action policy patch remains applied
if subject_present f "ghostty/src/cli/yen.zig"; then
    grep -q "pub const ActionTier = enum" ghostty/src/cli/yen.zig || add_issue "CLI action tier enum missing (yen.zig)"
    grep -q "YEN_CLI_SUPPORT_ACTIONS" ghostty/src/cli/yen.zig || add_issue "Support action override flag missing (yen.zig)"
    grep -q "YEN_CLI_INTERNAL_ACTIONS" ghostty/src/cli/yen.zig || add_issue "Internal action override flag missing (yen.zig)"
    grep -q "pub fn shouldShowInHelp" ghostty/src/cli/yen.zig || add_issue "CLI help visibility hook missing (yen.zig)"
fi
if subject_present f "ghostty/src/cli/help.zig"; then
    grep -q "action.shouldShowInHelp()" ghostty/src/cli/help.zig || add_issue "CLI help is not filtering by action policy (help.zig)"
fi

# Check 12d: App Intent hardening (allowlisted actions + scoped TTL permissions)
if subject_present f "ghostty/macos/Sources/Features/App Intents/KeybindIntent.swift"; then
    grep -q "var command: CommandEntity" "ghostty/macos/Sources/Features/App Intents/KeybindIntent.swift" || add_issue "KeybindIntent should use allowlisted CommandEntity action parameter"
    grep -q "performAllowlistedControlAction" "ghostty/macos/Sources/Features/App Intents/KeybindIntent.swift" || add_issue "KeybindIntent missing action allowlist guard"
fi
if subject_present f "ghostty/macos/Sources/Features/App Intents/Entities/CommandEntity.swift"; then
    grep -q '@IntentParameterDependency<KeybindIntent>' "ghostty/macos/Sources/Features/App Intents/Entities/CommandEntity.swift" || add_issue "CommandEntity missing @IntentParameterDependency<KeybindIntent>"
    grep -Fq 'filter(\.isSupported)' "ghostty/macos/Sources/Features/App Intents/Entities/CommandEntity.swift" || add_issue "CommandEntity should filter unsupported command palette actions"
fi
if subject_present f "ghostty/macos/Sources/Features/App Intents/CommandPaletteIntent.swift"; then
    grep -q "performAllowlistedControlAction" "ghostty/macos/Sources/Features/App Intents/CommandPaletteIntent.swift" || add_issue "CommandPaletteIntent missing action allowlist guard"
fi
if subject_present f "ghostty/macos/Sources/Features/App Intents/IntentPermission.swift"; then
    grep -q "enum AutomationActionSource" "ghostty/macos/Sources/Features/App Intents/IntentPermission.swift" || add_issue "Automation action source enum missing"
    grep -q "enum IntentPermissionScope" "ghostty/macos/Sources/Features/App Intents/IntentPermission.swift" || add_issue "IntentPermission scope enum missing"
    grep -q "allowDuration: .duration" "ghostty/macos/Sources/Features/App Intents/IntentPermission.swift" || add_issue "IntentPermission should use bounded allowDuration TTL"
    grep -q "func isAutomationActionAllowed" "ghostty/macos/Sources/Features/App Intents/IntentPermission.swift" || add_issue "Shared automation action allowlist helper missing"
    grep -q "resolveAllowlistedAutomationActions" "ghostty/macos/Sources/Features/App Intents/IntentPermission.swift" || add_issue "Shared automation allowlist should resolve command palette entries"
    grep -q "logIntentAudit" "ghostty/macos/Sources/Features/App Intents/IntentPermission.swift" || add_issue "IntentPermission audit logging hook missing"
    grep -q "logAutomationAudit" "ghostty/macos/Sources/Features/App Intents/IntentPermission.swift" || add_issue "Shared automation audit logging hook missing"
    grep -q "allowDuration: .forever" "ghostty/macos/Sources/Features/App Intents/IntentPermission.swift" && add_issue "IntentPermission still uses .forever (must be bounded)"
fi
if subject_present f "ghostty/macos/Sources/Features/App Intents/InputIntent.swift"; then
    grep -q "requestIntentPermission(scope: .input)" "ghostty/macos/Sources/Features/App Intents/InputIntent.swift" || add_issue "InputIntent permission scope should be .input"
fi
if subject_present f "ghostty/macos/Sources/Features/App Intents/GetTerminalDetailsIntent.swift"; then
    grep -q "requestIntentPermission(scope: .read)" "ghostty/macos/Sources/Features/App Intents/GetTerminalDetailsIntent.swift" || add_issue "GetTerminalDetailsIntent permission scope should be .read"
fi

# Check 12e: AppleScript resource paths, pbxproj references, and ObjC wiring
APPLE_SCRIPT_SDEF="ghostty/macos/YEN.sdef"
APPLE_SCRIPT_OVERLAY_SDEF="overlays/macos/YEN.sdef"
APPLE_SCRIPT_DIR="ghostty/macos/Sources/Features/AppleScript"
APPLE_SCRIPT_PROJECT="ghostty/macos/YEN.xcodeproj/project.pbxproj"
APPLE_SCRIPT_APP_DELEGATE="$APPLE_SCRIPT_DIR/AppDelegate+AppleScript.swift"
if [ -d "$APPLE_SCRIPT_DIR" ] || [ -f "$APPLE_SCRIPT_SDEF" ] || [ -f "ghostty/macos/Ghostty.sdef" ]; then
    [ ! -f "$APPLE_SCRIPT_SDEF" ] && add_issue "AppleScript dictionary missing at ghostty/macos/YEN.sdef"
    [ ! -f "$APPLE_SCRIPT_OVERLAY_SDEF" ] && add_issue "Overlay AppleScript dictionary missing at overlays/macos/YEN.sdef"
    [ -f "ghostty/macos/Ghostty.sdef" ] && add_issue "Stale AppleScript dictionary path present (Ghostty.sdef)"
    [ ! -f "$APPLE_SCRIPT_DIR/YEN.Input.Mods+AppleScript.swift" ] && add_issue "AppleScript modifiers extension missing renamed YEN.Input.Mods+AppleScript.swift"
    [ -f "$APPLE_SCRIPT_DIR/Ghostty.Input.Mods+AppleScript.swift" ] && add_issue "Stale AppleScript modifiers extension path present (Ghostty.Input.Mods+AppleScript.swift)"

    if [ -f "$APPLE_SCRIPT_OVERLAY_SDEF" ] && [ -f "$APPLE_SCRIPT_SDEF" ]; then
        cmp -s "$APPLE_SCRIPT_OVERLAY_SDEF" "$APPLE_SCRIPT_SDEF" || add_issue "Overlay YEN.sdef drift detected vs branded build-tree AppleScript dictionary"
    fi

    if subject_present f "$APPLE_SCRIPT_PROJECT"; then
        grep -q 'YEN\.sdef' "$APPLE_SCRIPT_PROJECT" || add_issue "pbxproj missing YEN.sdef AppleScript resource reference"
    fi

    if subject_present f "$APPLE_SCRIPT_APP_DELEGATE"; then
        grep -q "isAppleScriptActionAllowed" "$APPLE_SCRIPT_APP_DELEGATE" || add_issue "AppleScript perform action missing shared automation allowlist guard"
        grep -q "logAutomationAudit" "$APPLE_SCRIPT_APP_DELEGATE" || add_issue "AppleScript perform action missing automation audit logging"
        grep -q "not allowlisted in YEN" "$APPLE_SCRIPT_APP_DELEGATE" || add_issue "AppleScript perform action should fail closed with explicit allowlist error"
    fi

    if [ -f "$APPLE_SCRIPT_SDEF" ] && [ -d "$APPLE_SCRIPT_DIR" ]; then
        if ! python3 - "$APPLE_SCRIPT_SDEF" "$APPLE_SCRIPT_DIR" << 'PYEOF'; then
import pathlib
import re
import sys

sdef_path = pathlib.Path(sys.argv[1])
applescript_dir = pathlib.Path(sys.argv[2])
sdef = sdef_path.read_text()

if "Ghostty" in sdef:
    sys.exit(1)

sdef_classes = {
    token
    for token in re.findall(r'<cocoa class="([^"]+)"', sdef)
    if token.startswith("YEN")
}

swift_classes = set()
for path in applescript_dir.glob("*.swift"):
    swift_classes.update(
        token
        for token in re.findall(r'(?m)^\s*@objc\(([^)]+)\)', path.read_text())
        if token.startswith("YEN")
    )

required_classes = {
    "YENScriptInputTextCommand",
    "YENScriptKeyEventCommand",
    "YENScriptMouseButtonCommand",
    "YENScriptMousePosCommand",
    "YENScriptMouseScrollCommand",
    "YENScriptTab",
    "YENScriptTerminal",
    "YENScriptWindow",
}

sys.exit(0 if (sdef_classes == required_classes == swift_classes) else 1)
PYEOF
            add_issue "AppleScript sdef / @objc class wiring mismatch or Ghostty residue detected"
        fi
    fi
fi

# Check 12f: Native fullscreen transition patch remains applied
FULLSCREEN_HELPER="ghostty/macos/Sources/Features/Terminal/TerminalController+FullscreenNotifications.swift"
FULLSCREEN_CONTROLLER="ghostty/macos/Sources/Features/Terminal/TerminalController.swift"
FULLSCREEN_HELPER_CORE="ghostty/macos/Sources/Helpers/Fullscreen.swift"
if subject_present f "$FULLSCREEN_CONTROLLER"; then
    grep -q "handleToggleFullscreenNotification(notification)" "$FULLSCREEN_CONTROLLER" || \
        add_issue "TerminalController fullscreen notification path is not routed through the shared helper"
fi
if subject_present f "$FULLSCREEN_HELPER"; then
    grep -q "func handleToggleFullscreenNotification" "$FULLSCREEN_HELPER" || \
        add_issue "TerminalController fullscreen notification helper is missing its handler entry point"
    grep -q "target == focusedSurface" "$FULLSCREEN_HELPER" || \
        add_issue "TerminalController fullscreen notification helper is missing the focused-surface guard"
    grep -q "toggleFullscreen(mode: mode)" "$FULLSCREEN_HELPER" || \
        add_issue "TerminalController fullscreen notification helper is missing the toggle dispatch"
else
    add_issue "TerminalController fullscreen notification helper file missing"
fi
if subject_present f "$FULLSCREEN_HELPER_CORE"; then
    grep -q "var isFullscreen: Bool { window.yenIsEffectivelyFullscreen }" "$FULLSCREEN_HELPER_CORE" || \
        add_issue "Native fullscreen helper is not using effective fullscreen state"
fi

# Check 13: Dictation feature files (4 files: HotKey, Controller, Recognizer, Overlay)
DICTATION_OK=0
[ -f "ghostty/macos/Sources/Features/Dictation/DictationHotKey.swift" ] && DICTATION_OK=$((DICTATION_OK + 1))
[ -f "ghostty/macos/Sources/Features/Dictation/DictationController.swift" ] && DICTATION_OK=$((DICTATION_OK + 1))
[ -f "ghostty/macos/Sources/Features/Dictation/DictationRecognizer.swift" ] && DICTATION_OK=$((DICTATION_OK + 1))
[ -f "ghostty/macos/Sources/Features/Dictation/DictationOverlay.swift" ] && DICTATION_OK=$((DICTATION_OK + 1))
[ "$DICTATION_OK" -lt 4 ] && add_issue "Dictation feature files missing ($DICTATION_OK/4 found)"

# Check 14: Dictation initialization in AppDelegate
if subject_present f "ghostty/macos/Sources/App/AppDelegate.swift"; then
    grep -q "DictationController.shared.setup()" ghostty/macos/Sources/App/AppDelegate.swift || add_issue "DictationController.setup() not in AppDelegate"
fi
APPDELEGATE_SOURCES_DIR="ghostty/macos/Sources/App"
MACOS_SOURCES_DIR="ghostty/macos/Sources"
if [ -d "$APPDELEGATE_SOURCES_DIR" ] && [ -d "$MACOS_SOURCES_DIR" ]; then
    while IFS= read -r method; do
        [ -n "$method" ] || continue
        if ! grep -Eq "func[[:space:]]+$method\\b" "$APPDELEGATE_SOURCES_DIR"/AppDelegate*.swift; then
            add_issue "AppDelegate cross-file parity missing method called outside AppDelegate: $method"
        fi
    done < <(
        /usr/bin/find "$MACOS_SOURCES_DIR" -type f -name "*.swift" ! -name "AppDelegate*.swift" \
            -exec grep -hoE 'appDelegate\.([a-zA-Z_][a-zA-Z0-9_]*)\(' {} + 2>/dev/null \
        | /usr/bin/sed 's/appDelegate\.\(.*\)(/\1/' \
        | sort -u
    )
fi

# Check 15: Settings feature files (2 files: Controller, Panel)
SETTINGS_OK=0
[ -f "ghostty/macos/Sources/Features/Settings/SettingsController.swift" ] && SETTINGS_OK=$((SETTINGS_OK + 1))
[ -f "ghostty/macos/Sources/Features/Settings/SettingsPanel.swift" ] && SETTINGS_OK=$((SETTINGS_OK + 1))
[ "$SETTINGS_OK" -lt 2 ] && add_issue "Settings feature files missing ($SETTINGS_OK/2 found)"
PBXPROJ_PATH=""
[ -f "ghostty/macos/YEN.xcodeproj/project.pbxproj" ] && PBXPROJ_PATH="ghostty/macos/YEN.xcodeproj/project.pbxproj"
[ -z "$PBXPROJ_PATH" ] && [ -f "ghostty/macos/Ghostty.xcodeproj/project.pbxproj" ] && PBXPROJ_PATH="ghostty/macos/Ghostty.xcodeproj/project.pbxproj"
if [ -n "$PBXPROJ_PATH" ]; then
    grep -q 'App/AppDelegate+YEN.swift' "$PBXPROJ_PATH" && add_issue "pbxproj still references deleted AppDelegate+YEN.swift"
    grep -q 'Features/App Intents/YENIntentError.swift' "$PBXPROJ_PATH" && add_issue "pbxproj still references deleted YENIntentError.swift"
    grep -q 'Features/Settings/SettingsView.swift' "$PBXPROJ_PATH" && add_issue "pbxproj still references deleted SettingsView.swift"
    # Check 15b: Sparkle runtime security floor (release-time tripwire).
    # apply-overlays.sh asserts the same floor at vendor time; repeating it here
    # makes it a shipping gate, so a pbxproj edited after the vendor run cannot
    # ship a downgraded or unpinned updater. See scripts/lib/sparkle-runtime-floor.sh.
    SPARKLE_FLOOR_RESULT="$(assert_sparkle_runtime_floor "$PBXPROJ_PATH" "$SPARKLE_RUNTIME_FLOOR" 2>&1)" \
        || add_issue "$(printf '%s\n' "$SPARKLE_FLOOR_RESULT" | sed -n '1s/^[[:space:]]*ERROR: //p')"
    # These upstream-named files are ordinary members of the synchronized root
    # group; with the iOS target gone there is no second target's
    # membershipExceptions list to anchor a positive pbxproj text match, so
    # presence is checked on disk instead (see Check 15 above for Settings).
    [ -f "ghostty/macos/Sources/App/AppDelegate+Ghostty.swift" ] || add_issue "AppDelegate+Ghostty.swift missing from disk"
    [ -f "ghostty/macos/Sources/Features/App Intents/GhosttyIntentError.swift" ] || add_issue "GhosttyIntentError.swift missing from disk"
fi
[ -L "ghostty/macos/Sources/YEN/YEN.ConfigTypes.swift" ] || add_issue "missing DockTilePlugin compatibility alias YEN.ConfigTypes.swift"
[ -L "ghostty/macos/Sources/YEN/YENPackageMeta.swift" ] || add_issue "missing DockTilePlugin compatibility alias YENPackageMeta.swift"

# Check 16: Settings initialization in AppDelegate
if subject_present f "ghostty/macos/Sources/App/AppDelegate+Settings.swift"; then
    grep -q "showSettings" ghostty/macos/Sources/App/AppDelegate+Settings.swift || add_issue "showSettings action not in AppDelegate+Settings"
else
    add_issue "AppDelegate+Settings.swift not found"
fi

# Check 17: MainMenu.xib Settings menu item wiring (Cmd+,)
if subject_present f "ghostty/macos/Sources/App/MainMenu.xib"; then
    grep -q 'keyEquivalent=","' ghostty/macos/Sources/App/MainMenu.xib || add_issue "MainMenu.xib missing Settings keyEquivalent (Cmd+,)"
    grep -q 'selector="showSettings:"' ghostty/macos/Sources/App/MainMenu.xib || add_issue "MainMenu.xib missing showSettings: action"
else
    add_issue "MainMenu.xib not found"
fi

# Check 18: Theme bundle path (bundle script must target Resources/yen/themes/)
THEME_BUNDLE_PHASE="$REPO_ROOT/scripts/lib/bundle-resource-phases/01-themes.sh"
if subject_present f "$THEME_BUNDLE_PHASE"; then
    grep -q 'Resources/yen/themes' "$THEME_BUNDLE_PHASE" || add_issue "Theme bundle phase not targeting Resources/yen/themes/"
    # Ensure old wrong path is not used as the destination
    grep -q 'mkdir -p.*Resources/themes"$' "$THEME_BUNDLE_PHASE" && add_issue "Theme bundle phase still using old Resources/themes/ path"
else
    add_issue "Theme bundle phase missing"
fi

# Check 19: Custom YEN theme file exists in customizations
[ ! -f "customizations/themes/YEN" ] && add_issue "Custom YEN theme file missing from customizations/themes/"
if [ ! -f "customizations/theme-curated-manifest.txt" ]; then
    add_issue "Curated theme manifest missing: customizations/theme-curated-manifest.txt"
else
    grep -Fxq "YEN" "customizations/theme-curated-manifest.txt" || add_issue "Curated theme manifest missing required theme: YEN"
    grep -Fxq "Retro Terminal" "customizations/theme-curated-manifest.txt" || add_issue "Curated theme manifest missing required theme: Retro Terminal"
    grep -Fxq "CutePretzel" "customizations/theme-curated-manifest.txt" || add_issue "Curated theme manifest missing required theme: CutePretzel"
fi

# Check 20: sendText("\r") anti-pattern (use sendKeyEvent(.enter) instead)
# Excludes comments (/// or //) to allow documentation warnings about the anti-pattern
if subject_present d "overlays/macos/Sources"; then
    SENDTEXT_CR=$(grep -r 'sendText.*\\r' --include="*.swift" overlays/macos/Sources/ 2>/dev/null | grep -v '//.*sendText' | wc -l | tr -d ' ')
    [ "$SENDTEXT_CR" -gt 0 ] && add_issue "Found $SENDTEXT_CR sendText with \\r (use sendKeyEvent(.enter) to execute commands)"
fi

# Check 21: Cursor behavior remains fixed upstream (default_cursor guard absent)
if subject_present f "ghostty/src/termio/stream_handler.zig"; then
    grep -q 'if (self\.default_cursor) self\.setCursorStyle(\.default)' ghostty/src/termio/stream_handler.zig && add_issue "Cursor behavior regressed (default_cursor guard reintroduced in stream_handler.zig)"
fi

# Check 22: Screenshot feature file
if subject_present f "ghostty/macos/Sources/App/AppDelegate+Screenshot.swift"; then
    grep -q "takeScreenshot" ghostty/macos/Sources/App/AppDelegate+Screenshot.swift || add_issue "takeScreenshot action not in AppDelegate+Screenshot"
else
    add_issue "AppDelegate+Screenshot.swift not found"
fi

# Check 23: MainMenu.xib Screenshot menu item wiring (Cmd+Shift+S)
if subject_present f "ghostty/macos/Sources/App/MainMenu.xib"; then
    grep -q 'selector="takeScreenshot:"' ghostty/macos/Sources/App/MainMenu.xib || add_issue "MainMenu.xib missing takeScreenshot: action"
fi

# Check 24: window-save-state default patched to "always"
if subject_present f "ghostty/src/config/Config.zig"; then
    grep -q 'WindowSaveState = .always' ghostty/src/config/Config.zig || add_issue "window-save-state default not patched to always"
fi

# Check 24b: macos-applescript default stays enabled
if subject_present f "ghostty/src/config/Config.zig"; then
    grep -q '@"macos-applescript": bool = true,' ghostty/src/config/Config.zig || add_issue "macos-applescript default drifted from true"
fi

# Check 25: Layout system removed (no dead files in build tree)
[ -f "ghostty/macos/Sources/Features/Layout/LayoutTemplate.swift" ] && add_issue "Dead LayoutTemplate.swift in build tree"
[ -f "ghostty/macos/Sources/Features/Layout/LayoutManager.swift" ] && add_issue "Dead LayoutManager.swift in build tree"
[ -f "ghostty/macos/Sources/App/AppDelegate+Layout.swift" ] && add_issue "Dead AppDelegate+Layout.swift in build tree"

# Check 26: Quick Terminal shortcut in MainMenu.xib (Ctrl+`)
if subject_present f "ghostty/macos/Sources/App/MainMenu.xib"; then
    grep -q 'title="Quick Terminal — ⌃`" keyEquivalent="`"' ghostty/macos/Sources/App/MainMenu.xib || add_issue "MainMenu.xib missing Quick Terminal keyEquivalent (Ctrl+\`)"
    grep -A2 'title="Quick Terminal — ⌃`"' ghostty/macos/Sources/App/MainMenu.xib | grep -q 'control="YES"' || add_issue "MainMenu.xib missing control modifier for Quick Terminal"
fi

# Check 27: Quick Terminal default keybind in Config.zig (verify binding + global flag in same block)
if subject_present f "ghostty/src/config/Config.zig"; then
    grep -A2 'toggle_quick_terminal' ghostty/src/config/Config.zig | grep -q '\.global = true' || add_issue "Quick Terminal default keybind missing or not global in Config.zig"
fi

# Check 28: Config reload notification injected
if subject_present f "ghostty/macos/Sources/App/AppDelegate.swift"; then
    grep -q "yenConfigDidReload" ghostty/macos/Sources/App/AppDelegate.swift || add_issue "Config reload notification (yenConfigDidReload) not injected"
fi

# Check 29: Tab sidebar feature files (3 files: Controller, View, Panel)
TABSIDEBAR_OK=0
[ -f "ghostty/macos/Sources/Features/TabSidebar/TabSidebarController.swift" ] && TABSIDEBAR_OK=$((TABSIDEBAR_OK + 1))
[ -f "ghostty/macos/Sources/Features/TabSidebar/TabSidebarView.swift" ] && TABSIDEBAR_OK=$((TABSIDEBAR_OK + 1))
[ -f "ghostty/macos/Sources/Features/TabSidebar/TabSidebarPanel.swift" ] && TABSIDEBAR_OK=$((TABSIDEBAR_OK + 1))
[ "$TABSIDEBAR_OK" -lt 3 ] && add_issue "Tab sidebar feature files missing ($TABSIDEBAR_OK/3 found)"

# Check 30: copy-on-select default patched to both on macOS
if subject_present f "ghostty/src/config/Config.zig"; then
    if grep -A3 '@"copy-on-select"' ghostty/src/config/Config.zig | grep -q '.macos => .both'; then
        : # patched correctly
    else
        add_issue "copy-on-select default not patched to both on macOS"
    fi
fi

# Check 31: Shift+Enter keybind injected (sends \r in all modes via Config.zig)
if subject_present f "ghostty/src/config/Config.zig"; then
    if ! python3 - << 'PYEOF'; then
import sys

path = "ghostty/src/config/Config.zig"
with open(path, "r") as f:
    content = f.read()

start = content.find("Shift+Enter fix")
if start == -1:
    sys.exit(1)

segment = content[start:start + 800]
ok = (
    ".{ .key = .{ .physical = .enter }, .mods = .{ .shift = true } }," in segment and
    '.{ .text = "\\\\x0d" },' in segment
)
sys.exit(0 if ok else 1)
PYEOF
        add_issue "Shift+Enter keybind not injected in Config.zig"
    fi
fi

# Check 32: INFOPLIST_PREPROCESS = NO prevents SUFeedURL truncation
XCODE_PROJECT="ghostty/macos/YEN.xcodeproj/project.pbxproj"
if subject_present f "$XCODE_PROJECT"; then
    if grep -q 'INFOPLIST_PREPROCESS = NO' "$XCODE_PROJECT"; then
        : # preprocessor disabled correctly
    else
        add_issue "INFOPLIST_PREPROCESS = NO not found in pbxproj — SUFeedURL will be truncated"
    fi
fi

# Check 33: Selection repaint fix in copy-on-select release path +
# right-click context-menu preserves current selection state
if subject_present f "ghostty/src/Surface.zig"; then
    if ! python3 - << 'PYEOF'; then
import sys

path = "ghostty/src/Surface.zig"
with open(path, "r") as f:
    content = f.read()

start = content.find("if (button == .left and action == .release) {")
if start == -1:
    sys.exit(1)
end = content.find("// Handle link clicking.", start)
if end == -1:
    sys.exit(1)
segment = content[start:end]

left_release_ok = (
    "if (self.config.copy_on_select != .none)" in segment and
    "queueRender(" in segment
)

context_start = content.find('.@"context-menu" => {')
if context_start == -1:
    sys.exit(1)
context_end = content.find("},", context_start)
if context_end == -1:
    sys.exit(1)
context_segment = content[context_start:context_end]

right_click_ok = (
    "Preserve the current selection state on right-click and" in context_segment and
    "return false;" in context_segment and
    "selectWord(" not in context_segment and
    "linkAtPos(" not in context_segment and
    "setSelection(" not in context_segment
)

sys.exit(0 if (left_release_ok and right_click_ok) else 1)
PYEOF
        add_issue "Surface.zig copy-on-select release repaint or right-click context-menu selection guard missing"
    fi
fi

# Check 34: Runtime config loader stays on YEN paths (no Ghostty config fallback)
if subject_present f "ghostty/src/config/file_load.zig"; then
    if grep -Eq 'com\.mitchellh\.ghostty|\.config/ghostty|ghostty/config\.ghostty' ghostty/src/config/file_load.zig; then
        add_issue "Ghostty config path fallback detected in runtime config loader (file_load.zig)"
    fi
fi

# Check 35: Lazygit is a pure vendor (no in-binary YEN branding patch)
LAZYGIT_VENDOR_BIN="customizations/vendor/lazygit/lazygit"
if subject_present f "$LAZYGIT_VENDOR_BIN"; then
    LC_ALL=C grep -aFq "YEN loves:" "$LAZYGIT_VENDOR_BIN" && add_issue "Lazygit binary contains retired YEN branding patch (must be pure vendor; re-vendor with ./scripts/14-vendor.sh lazygit --force)"
fi

# Check 36: Lazygit startup popup + bottom-line prompt overrides
LAZYGIT_CONFIG="customizations/lazygit/config.yml"
if subject_present f "$LAZYGIT_CONFIG"; then
    grep -q "disableStartupPopups: true" "$LAZYGIT_CONFIG" || add_issue "Lazygit config missing disableStartupPopups override"
    grep -q "showBottomLine: true" "$LAZYGIT_CONFIG" || add_issue "Lazygit config missing showBottomLine: true"
else
    add_issue "Lazygit config missing at customizations/lazygit/config.yml"
fi

# Check 37: Surface route environment stamping for notification routing
SPLIT_TREE_VIEW_SWIFT="ghostty/macos/Sources/Features/Splits/TerminalSplitTreeView.swift"
SURFACE_VIEW_SWIFT="ghostty/macos/Sources/YEN/Surface View/SurfaceView.swift"
SURFACE_VIEW_APPKIT_SWIFT="ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift"
if subject_present f "$SPLIT_TREE_VIEW_SWIFT"; then
    grep -q "enum SplitFocusClickHitTesting" "$SPLIT_TREE_VIEW_SWIFT" || add_issue "Split-focus hit-testing helper missing in TerminalSplitTreeView.swift"
    grep -q "surfaceOwnsContentViewHit(" "$SPLIT_TREE_VIEW_SWIFT" || add_issue "Split-focus content-view hit helper missing in TerminalSplitTreeView.swift"
    grep -q "isDescendant(of: surfaceView)" "$SPLIT_TREE_VIEW_SWIFT" || add_issue "Split-focus content-view hit helper missing descendant ownership guard"
fi
if subject_present f "$SURFACE_VIEW_SWIFT"; then
    grep -q 'surfaceRouteEnvironmentKey = "YEN_SURFACE_ID"' "$SURFACE_VIEW_SWIFT" || add_issue "Surface route env key missing in SurfaceView.swift"
    grep -q "setRouteEnvironmentID(_ routeID: UUID)" "$SURFACE_VIEW_SWIFT" || add_issue "Surface route env setter missing in SurfaceView.swift"
    grep -q "existingRouteID" "$SURFACE_VIEW_SWIFT" || add_issue "Surface route env inheritance guard missing in SurfaceView.swift"
fi
if subject_present f "$SURFACE_VIEW_APPKIT_SWIFT"; then
    grep -q "surface_cfg.setRouteEnvironmentID(self.id)" "$SURFACE_VIEW_APPKIT_SWIFT" || add_issue "AppKit surface route env stamp missing in SurfaceView_AppKit.swift"
    grep -q "SplitFocusClickHitTesting.surfaceOwnsWindowClick" "$SURFACE_VIEW_APPKIT_SWIFT" || add_issue "AppKit split-focus hit testing is not using content-view coordinates"
    grep -q "suppressLeftMouseUntilRelease = false" "$SURFACE_VIEW_APPKIT_SWIFT" || add_issue "AppKit split-focus suppression reset missing in SurfaceView_AppKit.swift (upstream retired the stale mouse-up patch)"
fi
# Check 37b: Ghostty.App desktop notifications use managed surface routing
GHOSTTY_APP_SWIFT="ghostty/macos/Sources/YEN/Ghostty.App.swift"
if subject_present f "$GHOSTTY_APP_SWIFT"; then
    grep -q 'deliverManagedSurfaceNotification(' "$GHOSTTY_APP_SWIFT" || add_issue "Ghostty.App desktop notifications are not routed through managed surface delivery"
    grep -q 'requestAuthorization(options: \[.alert, .sound\])' "$GHOSTTY_APP_SWIFT" && add_issue "Ghostty.App still requests notification authorization directly for desktop notifications"
fi

# Check 37c: Ghostty.Config undo-timeout bridge preserves upstream default when unset
GHOSTTY_CONFIG_SWIFT="ghostty/macos/Sources/YEN/Ghostty.Config.swift"
if subject_present f "$GHOSTTY_CONFIG_SWIFT"; then
    grep -q 'guard yen_config_get(config, &v, key, UInt(key.lengthOfBytes(using: .utf8))) else {' "$GHOSTTY_CONFIG_SWIFT" || add_issue "Ghostty.Config undo-timeout bridge does not preserve the upstream default when the key is unset"
    grep -q 'return \.seconds(5)' "$GHOSTTY_CONFIG_SWIFT" || add_issue "Ghostty.Config undo-timeout bridge is missing the upstream 5 second default fallback"
fi

# Check 38: DockTilePlugin Tahoe icon reset avoids NSWorkspace icon round-trip
# Upstream now handles Tahoe icon chrome correctly via a NSDockTile.setIcon
# extension that sets self.contentView = nil when passed a nil NSImage. The
# former overlay patch was retired once upstream adopted this shape.
DOCKTILE_SWIFT="ghostty/macos/Sources/Features/Custom App Icon/DockTilePlugin.swift"
if subject_present f "$DOCKTILE_SWIFT"; then
    if grep -q 'NSWorkspace.shared.icon(forFile: appBundlePath)' "$DOCKTILE_SWIFT"; then
        add_issue "DockTilePlugin Tahoe resetIcon still uses NSWorkspace.shared.icon(forFile:) round-trip"
    fi
    if ! grep -q 'self.contentView = nil' "$DOCKTILE_SWIFT" && ! grep -q 'dockTile.contentView = nil' "$DOCKTILE_SWIFT"; then
        add_issue "DockTilePlugin Tahoe icon reset does not clear contentView on nil"
    fi
fi

# Check 39: Tab title overrides dirty restorable state so renamed tabs survive relaunch restore
BASE_TERMINAL_CONTROLLER="ghostty/macos/Sources/Features/Terminal/BaseTerminalController.swift"
if subject_present f "$BASE_TERMINAL_CONTROLLER"; then
    if ! python3 - "$BASE_TERMINAL_CONTROLLER" <<'PYEOF'
import re
import sys

path = sys.argv[1]
with open(path, "r") as f:
    content = f.read()

match = re.search(
    r"    var titleOverride: String\? \{\n(?P<body>.*?)\n    \}\n\n    /// The last computed title",
    content,
    re.S,
)
if not match:
    sys.exit(1)

body = match.group("body")
ok = (
    "applyTitleToWindow()" in body and
    "NSApp.invalidateRestorableState()" in body and
    "window?.invalidateRestorableState()" in body
)

sys.exit(0 if ok else 1)
PYEOF
    then
        add_issue "BaseTerminalController titleOverride does not invalidate app/window restorable state"
    fi
fi

# Check 40: Clipboard bridge keeps raw image paste usable for native Cmd+V flows
PASTEBOARD_EXTENSION_SWIFT="ghostty/macos/Sources/Helpers/Extensions/NSPasteboard+Extension.swift"
if subject_present f "$PASTEBOARD_EXTENSION_SWIFT"; then
    grep -q "func hasOpinionatedStringContents() -> Bool" "$PASTEBOARD_EXTENSION_SWIFT" || add_issue "NSPasteboard opinionated contents helper missing hasOpinionatedStringContents()"
    grep -q "com.yenchat.yen.clipboard-image-" "$PASTEBOARD_EXTENSION_SWIFT" || add_issue "NSPasteboard opinionated contents helper missing clipboard image temp-file prefix"
    grep -q "com.yenchat.yen.clipboard-images" "$PASTEBOARD_EXTENSION_SWIFT" || add_issue "NSPasteboard opinionated contents helper missing dedicated clipboard image temp root"
    grep -q "NSImage(pasteboard: self)" "$PASTEBOARD_EXTENSION_SWIFT" || add_issue "NSPasteboard opinionated contents helper missing image materialization fallback"
    grep -q "pruneStaleOpinionatedClipboardImageFiles" "$PASTEBOARD_EXTENSION_SWIFT" || add_issue "NSPasteboard opinionated contents helper missing stale clipboard image pruning"
    grep -q "posixPermissions: 0o700" "$PASTEBOARD_EXTENSION_SWIFT" || add_issue "NSPasteboard opinionated contents helper missing temp-root permission hardening"
    grep -q "posixPermissions: 0o600" "$PASTEBOARD_EXTENSION_SWIFT" || add_issue "NSPasteboard opinionated contents helper missing temp-file permission hardening"
fi
if subject_present f "$SURFACE_VIEW_APPKIT_SWIFT"; then
    grep -q "NSPasteboard.general.hasOpinionatedStringContents()" "$SURFACE_VIEW_APPKIT_SWIFT" || add_issue "SurfaceView_AppKit performable clipboard routing is not using hasOpinionatedStringContents() for the standard clipboard"
    grep -q "NSPasteboard.yenSelection.hasOpinionatedStringContents()" "$SURFACE_VIEW_APPKIT_SWIFT" || add_issue "SurfaceView_AppKit performable clipboard routing is not using hasOpinionatedStringContents() for the selection clipboard"
    grep -q "return pb.hasOpinionatedStringContents()" "$SURFACE_VIEW_APPKIT_SWIFT" || add_issue "SurfaceView_AppKit pasteSelection validation is not using hasOpinionatedStringContents()"
fi

# Check 49: IDE quick actions still inject full commands into the active surface
PALETTE_SWIFT_DIR=""
if subject_present d "overlays/macos/Sources/Features/Command Palette"; then
    PALETTE_SWIFT_DIR="overlays/macos/Sources/Features/Command Palette"
elif [ -d "ghostty/macos/Sources/Features/Command Palette" ]; then
    PALETTE_SWIFT_DIR="ghostty/macos/Sources/Features/Command Palette"
fi
if [ -n "$PALETTE_SWIFT_DIR" ]; then
    PALETTE_SWIFT_COMBINED="${TMPDIR:-/tmp}/yen-command-palette-sources.$$"
    : > "$PALETTE_SWIFT_COMBINED"
    for palette_file in "$PALETTE_SWIFT_DIR"/TerminalCommandPalette*.swift; do
        [ -f "$palette_file" ] || continue
        cat "$palette_file" >> "$PALETTE_SWIFT_COMBINED"
        printf '\n' >> "$PALETTE_SWIFT_COMBINED"
    done
    grep -Eq 'surfaceView\.surfaceModel\?\.sendKeyEvent|TerminalSurfaceCommandLauncher\.dispatch' "$PALETTE_SWIFT_COMBINED" || add_issue "Terminal command palette no longer uses sendKeyEvent or TerminalSurfaceCommandLauncher for command injection"
    grep -Eq 'terminalCommandInputSteps\(for:|TerminalSurfaceCommandLauncher\.commandInputSteps\(for:' "$PALETTE_SWIFT_COMBINED" || add_issue "Terminal command palette no longer routes commands through terminalCommandInputSteps or TerminalSurfaceCommandLauncher"
    grep -q 'yen ide lsp install status --all' "$PALETTE_SWIFT_COMBINED" || add_issue "IDE LSP Install Matrix quick action missing"
    grep -q 'yen ide share host --read-only' "$PALETTE_SWIFT_COMBINED" || add_issue "IDE Share Host (Read-Only) quick action missing"
    grep -q 'yen ide vscode import --dry-run' "$PALETTE_SWIFT_COMBINED" || add_issue "IDE VS Code Import (Dry Run) quick action missing"
    rm -f "$PALETTE_SWIFT_COMBINED"
else
    add_issue "TerminalCommandPalette sources not found for IDE command-injection check"
fi

# Summary
MANIFEST_TOTAL="${#GHOSTTY_REQUIRED_PATHS[@]}"
MANIFEST_MISSING=$(printf '%s\n' "$MISSING_UPSTREAM_PATHS" | grep -c . || true)
[ -n "$MANIFEST_MISSING" ] || MANIFEST_MISSING=0
gate_unit_ran upstream-path-manifest "resolved=$((MANIFEST_TOTAL - MANIFEST_MISSING))/$MANIFEST_TOTAL"

# Floor. A collapsed subject set is a broken gate, not a clean tree: the bodies
# never ran, so "0 issues" means "nothing was examined".
MIN_SUBJECTS_PRESENT=45
if [ "$SUBJECTS_PRESENT" -lt "$MIN_SUBJECTS_PRESENT" ]; then
    add_issue "Branding subject set collapsed: only $SUBJECTS_PRESENT of $SUBJECTS_TOTAL guarded paths resolved (expected >= $MIN_SUBJECTS_PRESENT) — the check bodies did not run"
fi
gate_unit_ran guarded-subjects "present=$SUBJECTS_PRESENT/$SUBJECTS_TOTAL"

if [ "$ISSUES" -ne 0 ]; then
    echo "  X Branding failed ($ISSUES issues)"
    echo -e "$DETAILS"
fi
gate_end "$ISSUES"
