#!/bin/bash
# YEN Nuclear Cache Clear
#
# Comprehensive clearing of all YEN app data, caches, and state.
# Use this for fresh install testing or when debugging persistent issues.
#
# WARNING: This is destructive! All app state is lost. config.yen is backed up and
# restored automatically; every other setting (plist prefs, window state) is gone.
#
# What gets cleared (20 categories):
#   1. Running app instances (graceful quit + force kill)
#   2. Quarantine attributes (Gatekeeper flags)
#   3. Launch Services database (icon/app metadata)
#   4. Dock icon cache
#   5. Saved Application State (window positions)
#   6. Application preferences (plist)
#   7. Application Support + shared YEN state (config.yen)
#   8. Caches directory
#   9. Container sandbox data
#   10. HTTPStorages
#   11. WebKit data
#   12. Sparkle update cache (ShipIt)
#   13. Sparkle UserDefaults (update check times, last version)
#   14. Sparkle cached appcast files
#   15. Version-related UserDefaults
#   16. Force app bundle refresh (re-read Info.plist)
#   17. Crash reports
#   18. Diagnostic reports
#   19. Shell integration caches (zsh function cache, completion cache, bundled file refresh)
#   20. Current-repo local build Launch Services cache (preserves ghostty/zig-out/YEN.app for testing)
#
# config.yen and the backgrounds/ directory it references are copied to
# ~/Library/Application Support/yen-config-backups/<timestamp>/ before the wipe and
# restored afterwards, so a debugging nuke does not cost the user their settings.
# Pass --fresh to skip the restore and get a true first-launch state.
# The newest 10 backups are kept; older ones are pruned.
#
# Usage:
#   ./customizations/clear-app-cache.sh           # wipe, then restore config.yen
#   ./customizations/clear-app-cache.sh --fresh   # wipe, keep the backup, restore nothing
#
# Exit codes:
#   0 = Success
#   1 = Error

# Don't use set -e - we handle errors explicitly with || true
# This allows the script to continue even if some cleanup steps fail

# ============================================================================
# PATH RESOLUTION
# ============================================================================

# Get absolute path to script directory (works from any calling directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# REPO_DIR is yen-terminal/ directory (one level up from customizations/)
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Verify we're in the right place
if [ ! -d "$REPO_DIR/customizations" ]; then
    echo "ERROR: Script must be in yen-terminal/customizations/ directory"
    echo "  Script location: $SCRIPT_DIR"
    echo "  Expected parent: yen-terminal/"
    exit 1
fi

source "$REPO_DIR/../scripts/lib/yen-cli-resolve.sh"

# ============================================================================
# ARGUMENTS
# ============================================================================

RESTORE_CONFIG=1
for arg in "$@"; do
    case "$arg" in
        --fresh)
            RESTORE_CONFIG=0
            ;;
        -h|--help)
            echo "Usage: clear-app-cache.sh [--fresh]"
            echo "  --fresh  Do not restore config.yen after the wipe (true first-launch state)."
            echo "           A backup is still written to ~/Library/Application Support/yen-config-backups/."
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $arg"
            echo "Usage: clear-app-cache.sh [--fresh]"
            exit 1
            ;;
    esac
done

# ============================================================================
# HEADER
# ============================================================================

echo ""
echo "---------------"
echo "YEN Nuclear Cache Clear"
echo "Comprehensive clearing of all YEN app data, caches, and state"
echo "---------------"
echo ""

# Bundle IDs to clear (YEN + legacy Ghostty)
BUNDLE_IDS=(
    "com.yenchat.yen"
    "com.mitchellh.yen"
    "com.mitchellh.ghostty"
)

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
LOCAL_BUILD_APP="$REPO_DIR/ghostty/zig-out/YEN.app"
LOCAL_BUILD_CLI="$LOCAL_BUILD_APP/Contents/Resources/bin/yen"
CURRENT_REPO_XCODE_BUILD_DIR="$REPO_DIR/ghostty/macos/build"

INSTALLED_APP_PATHS=()
if [ -d "/Applications/YEN.app" ]; then
    INSTALLED_APP_PATHS+=("/Applications/YEN.app")
fi
if [ -d "$HOME/Applications/YEN.app" ]; then
    INSTALLED_APP_PATHS+=("$HOME/Applications/YEN.app")
fi

primary_cli_script() {
    if [ -x "$LOCAL_BUILD_CLI" ]; then
        echo "$LOCAL_BUILD_CLI"
        return 0
    fi

    local app_path=""
    local candidate=""
    for app_path in "${INSTALLED_APP_PATHS[@]}"; do
        candidate="$app_path/Contents/Resources/bin/yen"
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    return 1
}

touch_shell_integration_bundle() {
    local app_path="$1"
    local shell_base="$app_path/Contents/Resources/yen/shell-integration"

    [ -d "$shell_base" ] || return 1

    touch "$shell_base/zsh/.zshenv" 2>/dev/null || true
    touch "$shell_base/zsh/yen-integration" 2>/dev/null || true
    touch "$shell_base/bash/yen.bash" 2>/dev/null || true
    touch "$shell_base/yen-welcome.sh" 2>/dev/null || true
    return 0
}

USER_CONFIG_PATH="$HOME/Library/Application Support/com.yenchat.yen/config.yen"
USER_BACKGROUNDS_DIR="$HOME/Library/Application Support/com.yenchat.yen/backgrounds"
CONFIG_BACKUP_DIR="$HOME/Library/Application Support/yen-config-backups"
CONFIG_BACKUP_PATH=""
# Backups now carry image data, so keep the directory bounded.
CONFIG_BACKUP_KEEP=10

SHELL_TYPE="$(detect_shell_type)"
CLI_SCRIPT="$(primary_cli_script || true)"

# Step 1: Kill running instances (detect and kill ALL instances)
echo "[1/20] Detecting and terminating ALL running YEN instances..."

# Count running instances first
YEN_PIDS=$(pgrep -x "yen" 2>/dev/null || true)
YEN_COUNT=0
if [ -n "$YEN_PIDS" ]; then
    YEN_COUNT=$(printf '%s\n' "$YEN_PIDS" | wc -l | tr -d ' ')
fi
if [ "$YEN_COUNT" -gt 0 ]; then
    echo "  Found $YEN_COUNT running YEN instance(s):"
    # Show each process with its path
    for pid in $YEN_PIDS; do
        PROC_PATH=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
        echo "    PID $pid: $PROC_PATH"
    done
else
    echo "  No running YEN instances found"
fi

# Also check for any yen-related processes
YEN_RELATED=$(pgrep -f "YEN.app" 2>/dev/null || true)
if [ -n "$YEN_RELATED" ]; then
    RELATED_COUNT=$(echo "$YEN_RELATED" | wc -l | tr -d ' ')
    echo "  Found $RELATED_COUNT additional YEN.app-related process(es)"
fi

# Gracefully quit via AppleScript
osascript -e 'tell application "YEN" to quit' 2>/dev/null || true
sleep 2

# Force kill any remaining instances
pkill -f "/Applications/YEN.app" 2>/dev/null || true
pkill -f "$HOME/Applications/YEN.app" 2>/dev/null || true
pkill -f "ghostty/zig-out/YEN.app" 2>/dev/null || true
pkill -f "macos/build/.*YEN.app" 2>/dev/null || true
pkill -f "DerivedData/.*YEN.app" 2>/dev/null || true
pkill -x "yen" 2>/dev/null || true
sleep 1

# Verify all killed
REMAINING=$(pgrep -x "yen" 2>/dev/null | wc -l | tr -d ' ')
if [ "$REMAINING" -gt 0 ]; then
    echo "  ⚠ Warning: $REMAINING instance(s) still running after kill"
    echo "    Attempting SIGKILL..."
    pkill -9 -x "yen" 2>/dev/null || true
    sleep 1
fi

# Final check
FINAL_COUNT=$(pgrep -x "yen" 2>/dev/null | wc -l | tr -d ' ')
if [ "$FINAL_COUNT" -eq 0 ]; then
    echo "  ✓ All YEN instances terminated"
else
    echo "  ✗ $FINAL_COUNT instance(s) could not be killed (may require sudo)"
fi

# Step 1b: Back up config.yen and the backgrounds it references
# Runs AFTER termination: the app flushes its debounced config writes on quit, so
# backing up earlier can capture a file that is missing the user's last edit.
#
# backgrounds/ travels WITH the config. TerminalBackgroundImageStore copies a chosen
# image into that directory and writes the copy's path into config.yen, so restoring
# the config without the directory leaves `background-image` pointing at a file the
# wipe deleted.
echo "[1b/20] Backing up user config..."
if [ -f "$USER_CONFIG_PATH" ]; then
    CONFIG_BACKUP_PATH="$CONFIG_BACKUP_DIR/$(date +%Y%m%d-%H%M%S)"
    if mkdir -p "$CONFIG_BACKUP_PATH" 2>/dev/null &&
        cp "$USER_CONFIG_PATH" "$CONFIG_BACKUP_PATH/config.yen" 2>/dev/null; then
        echo "  ✓ Backed up config.yen to: $CONFIG_BACKUP_PATH"
    else
        CONFIG_BACKUP_PATH=""
        echo "  ✗ Backup FAILED — aborting so settings are not lost"
        echo "    Copy it manually, then rerun:"
        echo "    cp \"$USER_CONFIG_PATH\" ~/Desktop/config.yen.backup"
        exit 1
    fi

    # `cp -R src dst` NESTS into dst when dst already exists (BSD cp). Copying the
    # contents into a pre-made directory is the same result whether or not dst exists.
    if [ -d "$USER_BACKGROUNDS_DIR" ]; then
        if mkdir -p "$CONFIG_BACKUP_PATH/backgrounds" 2>/dev/null &&
            cp -R "$USER_BACKGROUNDS_DIR/." "$CONFIG_BACKUP_PATH/backgrounds/" 2>/dev/null; then
            echo "  ✓ Backed up background images"
        else
            echo "  ✗ Background image backup FAILED — aborting"
            echo "    A restored config.yen would point at deleted images."
            exit 1
        fi
    fi
else
    echo "  • No existing config.yen to back up"
fi

# Step 2: Clear quarantine attributes
echo "[2/20] Clearing quarantine attributes..."
if [ "${#INSTALLED_APP_PATHS[@]}" -gt 0 ]; then
    for app_path in "${INSTALLED_APP_PATHS[@]}"; do
        xattr -cr "$app_path" 2>/dev/null || true
        echo "  ✓ Cleared quarantine attributes: $app_path"
    done
else
    echo "  Skipped (no installed YEN.app found in /Applications or ~/Applications)"
fi

# Step 3: Rebuild Launch Services database
echo "[3/20] Rebuilding Launch Services database..."
# Contract: clear installed-app registrations plus known build artifacts, while
# preserving the current repo's ghostty/zig-out/YEN.app for local testing.
echo "  Unregistering installed app copies and stale build artifacts..."
for app_path in "${INSTALLED_APP_PATHS[@]}"; do
    "$LSREGISTER" -u "$app_path" 2>/dev/null || true
    echo "  ✓ Unregistered installed app: $app_path"
done
# Find and unregister Xcode DerivedData instances (old build artifacts)
find ~/Library/Developer/Xcode/DerivedData -name "YEN.app" -type d -print0 2>/dev/null | while IFS= read -r -d '' app_path; do
    "$LSREGISTER" -u "$app_path" 2>/dev/null || true
done
# Unregister current-repo Xcode build artifacts if present.
if [ -d "$CURRENT_REPO_XCODE_BUILD_DIR" ]; then
    find "$CURRENT_REPO_XCODE_BUILD_DIR" -name "YEN.app" -type d -print0 2>/dev/null | while IFS= read -r -d '' app_path; do
        "$LSREGISTER" -u "$app_path" 2>/dev/null || true
    done
fi
# Now rebuild the database
"$LSREGISTER" -kill -r -domain local -domain system -domain user 2>/dev/null || true
# Re-register the current repo's local build if it exists.
if [ -d "$LOCAL_BUILD_APP" ]; then
    "$LSREGISTER" "$LOCAL_BUILD_APP" 2>/dev/null || true
    echo "  ✓ Re-registered current repo build: $LOCAL_BUILD_APP"
fi
echo "  ✓ Done (installed apps reset, current repo build preserved)"

# Step 4: Clear Dock icon cache
echo "[4/20] Clearing Dock icon cache..."
rm -rf ~/Library/Caches/com.apple.dock.iconcache 2>/dev/null || true
rm -rf ~/Library/Caches/com.apple.iconservices.store 2>/dev/null || true
killall Dock 2>/dev/null || true
sleep 2
echo "  ✓ Done (Dock restarted)"

# Step 5: Clear Saved Application State
echo "[5/20] Clearing Saved Application State..."
for bundle in "${BUNDLE_IDS[@]}"; do
    rm -rf ~/Library/Saved\ Application\ State/${bundle}.savedState 2>/dev/null || true
done
echo "  ✓ Done"

# Step 6: Clear Application preferences
echo "[6/20] Clearing Application preferences..."
for bundle in "${BUNDLE_IDS[@]}"; do
    rm -f ~/Library/Preferences/${bundle}.plist 2>/dev/null || true
    defaults delete ${bundle} 2>/dev/null || true
done
echo "  ✓ Done"

# Step 7: Clear Application Support + shared YEN state (includes config.yen)
echo "[7/20] Clearing Application Support and shared YEN state..."
for bundle in "${BUNDLE_IDS[@]}"; do
    rm -rf ~/Library/Application\ Support/${bundle} 2>/dev/null || true
done
rm -rf ~/Library/Application\ Support/YEN 2>/dev/null || true
rm -rf ~/Library/Application\ Support/Ghostty 2>/dev/null || true
rmdir ~/.config/yen 2>/dev/null || true
echo "  ✓ Done (config.yen removed)"

# Step 8: Clear Caches directory
echo "[8/20] Clearing Caches directory..."
for bundle in "${BUNDLE_IDS[@]}"; do
    rm -rf ~/Library/Caches/${bundle} 2>/dev/null || true
done
rm -rf ~/Library/Caches/YEN 2>/dev/null || true
rm -rf ~/Library/Caches/Ghostty 2>/dev/null || true
echo "  ✓ Done"

# Step 9: Clear Container sandbox data
echo "[9/20] Clearing Container sandbox data..."
for bundle in "${BUNDLE_IDS[@]}"; do
    rm -rf ~/Library/Containers/${bundle} 2>/dev/null || true
done
echo "  ✓ Done"

# Step 10: Clear HTTPStorages
echo "[10/20] Clearing HTTPStorages..."
for bundle in "${BUNDLE_IDS[@]}"; do
    rm -rf ~/Library/HTTPStorages/${bundle} 2>/dev/null || true
done
echo "  ✓ Done"

# Step 11: Clear WebKit data
echo "[11/20] Clearing WebKit data..."
for bundle in "${BUNDLE_IDS[@]}"; do
    rm -rf ~/Library/WebKit/${bundle} 2>/dev/null || true
done
echo "  ✓ Done"

# Step 12: Clear Sparkle update cache (ShipIt)
echo "[12/20] Clearing Sparkle update cache (ShipIt)..."
for bundle in "${BUNDLE_IDS[@]}"; do
    rm -rf ~/Library/Caches/${bundle}.ShipIt 2>/dev/null || true
done
echo "  ✓ Done"

# Step 13: Clear Sparkle UserDefaults (update check times, last version checked)
echo "[13/20] Clearing Sparkle UserDefaults..."
for bundle in "${BUNDLE_IDS[@]}"; do
    # Clear Sparkle update check preferences
    defaults delete ${bundle} SULastCheckTime 2>/dev/null || true
    defaults delete ${bundle} SULastUpdateCheckDate 2>/dev/null || true
    defaults delete ${bundle} SUSkippedVersion 2>/dev/null || true
    defaults delete ${bundle} SUHasLaunchedBefore 2>/dev/null || true
    defaults delete ${bundle} SUFeedURL 2>/dev/null || true
    defaults delete ${bundle} SUEnableAutomaticChecks 2>/dev/null || true
    defaults delete ${bundle} SUAutomaticallyUpdate 2>/dev/null || true
    defaults delete ${bundle} SUAllowsAutomaticUpdates 2>/dev/null || true
    defaults delete ${bundle} SUUpdateGroupIdentifier 2>/dev/null || true
    defaults delete ${bundle} SULastProfileSubmissionDate 2>/dev/null || true
done
echo "  ✓ Done (Sparkle update preferences cleared)"

# Step 14: Clear Sparkle cached appcast files
echo "[14/20] Clearing Sparkle cached appcast files..."
for bundle in "${BUNDLE_IDS[@]}"; do
    # Sparkle caches appcast.xml in multiple locations:
    # 1. Bundle-specific cache directory
    rm -rf ~/Library/Caches/${bundle}/appcast* 2>/dev/null || true
    rm -rf ~/Library/Caches/${bundle}/*appcast* 2>/dev/null || true
    # 2. Application Support Sparkle directory
    rm -rf ~/Library/Application\ Support/${bundle}/Sparkle/appcast* 2>/dev/null || true
    rm -rf ~/Library/Application\ Support/${bundle}/Sparkle/*appcast* 2>/dev/null || true
    # 3. Global Sparkle cache (org.sparkle-project.Sparkle)
    rm -rf ~/Library/Caches/org.sparkle-project.Sparkle/${bundle}* 2>/dev/null || true
    # 4. Find and remove any appcast files matching bundle ID
    find "$HOME/Library/Caches" -type f -iname "*appcast*" -ipath "*${bundle}*" -print0 2>/dev/null | xargs -0 rm -f 2>/dev/null || true
    find "$HOME/Library/Application Support" -type f -iname "*appcast*" -ipath "*${bundle}*" -print0 2>/dev/null | xargs -0 rm -f 2>/dev/null || true
done
# Also clear global Sparkle appcast cache if it exists
rm -rf ~/Library/Caches/org.sparkle-project.Sparkle/*appcast* 2>/dev/null || true
echo "  ✓ Done"

# Step 15: Clear version-related UserDefaults
echo "[15/20] Clearing version-related UserDefaults..."
for bundle in "${BUNDLE_IDS[@]}"; do
    # Clear any additional version-related keys (beyond Sparkle keys cleared in step 13)
    # These are app-specific version tracking keys if they exist
    defaults delete ${bundle} YENVersion 2>/dev/null || true
    defaults delete ${bundle} YENBuild 2>/dev/null || true
    defaults delete ${bundle} LastVersionCheck 2>/dev/null || true
done
echo "  ✓ Done"

# Step 16: Force app bundle refresh (re-read Info.plist)
echo "[16/20] Forcing app bundle refresh..."
if [ "${#INSTALLED_APP_PATHS[@]}" -gt 0 ]; then
    for app_path in "${INSTALLED_APP_PATHS[@]}"; do
        touch "$app_path" 2>/dev/null || true
        touch "$app_path/Contents/Info.plist" 2>/dev/null || true
        echo "  ✓ Refreshed bundle metadata: $app_path"
    done
else
    echo "  Skipped (no installed YEN.app found in /Applications or ~/Applications)"
fi

# Step 17: Clear crash reports
echo "[17/20] Clearing crash reports..."
rm -rf ~/Library/Logs/DiagnosticReports/YEN* 2>/dev/null || true
rm -rf ~/Library/Logs/DiagnosticReports/yen* 2>/dev/null || true
rm -rf ~/Library/Logs/DiagnosticReports/Ghostty* 2>/dev/null || true
echo "  ✓ Done"

# Step 18: Clear diagnostic reports
echo "[18/20] Clearing diagnostic reports..."
rm -rf /Library/Logs/DiagnosticReports/YEN* 2>/dev/null || true
rm -rf /Library/Logs/DiagnosticReports/yen* 2>/dev/null || true
rm -rf /Library/Logs/DiagnosticReports/Ghostty* 2>/dev/null || true
echo "  ✓ Done"

# Step 19: Clear shell integration caches and stale function definitions
echo "[19/20] Clearing shell integration caches and stale function definitions..."
# Clear zsh function cache and completion cache
rm -f ~/.zshcache 2>/dev/null || true
rm -f ~/.zcompdump* 2>/dev/null || true
# Clear any stale yen() function definitions from user's shell configs
# Check if user has yen() function or alias in their shell configs
if [ -f ~/.zshrc ]; then
    # Flag stale manual wrappers so users can remove them if they no longer need
    # external-shell access. YEN Terminal itself injects bundled integration.
    if grep -q '^[[:space:]]*yen()' ~/.zshrc 2>/dev/null; then
        echo "  ⚠ Found manual yen() function in ~/.zshrc - remove it unless you want YEN CLI in non-YEN shells"
    fi
fi
if [ -f ~/.bashrc ]; then
    if grep -q '^[[:space:]]*yen()' ~/.bashrc 2>/dev/null; then
        echo "  ⚠ Found manual yen() function in ~/.bashrc - remove it unless you want YEN CLI in non-YEN shells"
    fi
fi
# Force re-read of bundled shell integration files by touching installed app copies.
TOUCHED_SHELL_INTEGRATION=0
for app_path in "${INSTALLED_APP_PATHS[@]}"; do
    if touch_shell_integration_bundle "$app_path"; then
        echo "  ✓ Bundled shell integration files touched: $app_path"
        TOUCHED_SHELL_INTEGRATION=1
    fi
done
if [ "$TOUCHED_SHELL_INTEGRATION" -eq 0 ]; then
    echo "  Skipped (no installed app bundle with bundled shell integration found)"
fi
# Clear any cached function definitions in current shell session
# Note: This only affects the current shell - new shells will read fresh files
echo "  ✓ Shell integration caches cleared"
echo "  INFO: Close and reopen terminal windows to reload shell integration files"
echo "  INFO: YEN Terminal should not need a manual yen() wrapper in shell dotfiles"

# Step 20: Clear current-repo local build Launch Services cache (preserve app bundle)
echo "[20/20] Clearing current-repo local build Launch Services cache..."
# Do NOT remove the current repo's zig-out app bundle; developers need it for testing.
if [ -d "$CURRENT_REPO_XCODE_BUILD_DIR" ]; then
    echo "  Found $CURRENT_REPO_XCODE_BUILD_DIR - clearing Launch Services cache for current-repo Xcode build artifacts..."
    find "$CURRENT_REPO_XCODE_BUILD_DIR" -name "YEN.app" -type d -print0 2>/dev/null | while IFS= read -r -d '' app_path; do
        "$LSREGISTER" -u "$app_path" 2>/dev/null || true
    done
fi
# The current repo build remains registered for local testing.
if [ -d "$LOCAL_BUILD_APP" ]; then
    echo "  ✓ Preserved current repo build: $LOCAL_BUILD_APP"
fi
echo "  ✓ Done (current-repo build artifacts cleared, local zig-out app preserved)"

# Restore config.yen unless --fresh was requested
echo ""
echo "[restore] User config..."
if [ -z "$CONFIG_BACKUP_PATH" ]; then
    echo "  • Nothing to restore (no config.yen existed)"
elif [ "$RESTORE_CONFIG" -eq 0 ]; then
    echo "  • Skipped (--fresh): next launch uses bundled YEN defaults"
    echo "    Backup kept at: $CONFIG_BACKUP_PATH"
else
    mkdir -p "$(dirname "$USER_CONFIG_PATH")" 2>/dev/null || true

    # Restore backgrounds BEFORE the config, so the app never observes a config.yen
    # whose background-image path is not yet on disk.
    if [ -d "$CONFIG_BACKUP_PATH/backgrounds" ]; then
        if mkdir -p "$USER_BACKGROUNDS_DIR" 2>/dev/null &&
            cp -R "$CONFIG_BACKUP_PATH/backgrounds/." "$USER_BACKGROUNDS_DIR/" 2>/dev/null; then
            echo "  ✓ Restored background images"
        else
            echo "  ✗ Background image restore FAILED — restore it manually:"
            echo "    cp -R \"$CONFIG_BACKUP_PATH/backgrounds/.\" \"$USER_BACKGROUNDS_DIR/\""
            exit 1
        fi
    fi

    if cp "$CONFIG_BACKUP_PATH/config.yen" "$USER_CONFIG_PATH" 2>/dev/null; then
        echo "  ✓ Restored config.yen (settings preserved)"
        echo "    Backup kept at: $CONFIG_BACKUP_PATH"
    else
        echo "  ✗ Restore FAILED — restore it manually:"
        echo "    cp \"$CONFIG_BACKUP_PATH/config.yen\" \"$USER_CONFIG_PATH\""
        exit 1
    fi
fi

# Prune old backups, newest first, keeping CONFIG_BACKUP_KEEP.
# Timestamped names sort lexicographically in chronological order.
if [ -d "$CONFIG_BACKUP_DIR" ]; then
    ls "$CONFIG_BACKUP_DIR" 2>/dev/null | sort -r | tail -n +$((CONFIG_BACKUP_KEEP + 1)) |
        while IFS= read -r stale; do
            [ -n "$stale" ] || continue
            rm -rf "$CONFIG_BACKUP_DIR/$stale" 2>/dev/null || true
            echo "  • Pruned old backup: $stale"
        done
fi

# Summary
echo ""
echo ""
echo "Cleared:"
echo "  • Running instances"
echo "  • Quarantine/Gatekeeper flags"
echo "  • Launch Services (icon cache)"
echo "  • Dock icon cache"
echo "  • Saved Application State"
echo "  • Preferences (plist)"
echo "  • Application Support + shared YEN state (config.yen backed up first)"
echo "  • Caches"
echo "  • Container sandbox"
echo "  • HTTPStorages"
echo "  • WebKit data"
echo "  • Sparkle cache (ShipIt)"
echo "  • Sparkle UserDefaults (update check times, last version)"
echo "  • Sparkle cached appcast files"
echo "  • Version-related UserDefaults"
echo "  • App bundle metadata (Info.plist will be re-read)"
echo "  • Crash reports"
echo "  • Diagnostic reports"
echo "  • Shell integration caches (zsh function cache, bundled file refresh)"
echo "  • Current-repo local build Launch Services cache"
echo ""
if [ "$RESTORE_CONFIG" -eq 1 ] && [ -n "$CONFIG_BACKUP_PATH" ]; then
    echo "Next launch keeps your config.yen; all other state returns to YEN defaults."
else
    echo "Next launch will use bundled YEN defaults."
fi
echo "This tool clears user state plus installed-app metadata while preserving the current repo's zig-out build for local testing."
echo ""
if [ -d "$LOCAL_BUILD_APP" ]; then
    echo "IMPORTANT: For local testing, use the current repo build directly:"
    echo "  open $LOCAL_BUILD_APP"
    echo ""
    echo "NOTE: $LOCAL_BUILD_APP is preserved (not cleared) for local testing after builds."
    echo "  Launch Services cache for the current repo build is refreshed, not cleared."
    echo ""
fi
if [ "${#INSTALLED_APP_PATHS[@]}" -gt 0 ]; then
    echo "Installed app copies reset:"
    for app_path in "${INSTALLED_APP_PATHS[@]}"; do
        echo "  • $app_path"
    done
    echo ""
fi
echo "If testing an installed app copy, ensure it matches the latest version."
echo ""
if [ -n "$CONFIG_BACKUP_PATH" ]; then
    echo "Config backups live in: $CONFIG_BACKUP_DIR"
    echo "To restore an older one:"
    echo "  cp \"$CONFIG_BACKUP_DIR/<timestamp>/config.yen\" \"$USER_CONFIG_PATH\""
    echo "  cp -R \"$CONFIG_BACKUP_DIR/<timestamp>/backgrounds/.\" \"$USER_BACKGROUNDS_DIR/\""
    echo "Keeping the newest $CONFIG_BACKUP_KEEP backups; older ones are pruned."
fi
echo ""
echo "SHELL INTEGRATION: Close and reopen all terminal windows to reload shell integration files."
echo "  This ensures the bundled shell integration is reloaded."
echo ""
echo "CLI REMEDIATION:"
echo "  1. Inside YEN Terminal, reopening the shell should be enough; no manual wrapper is required."
if [ -n "$CLI_SCRIPT" ]; then
    if [ "$SHELL_TYPE" = "zsh" ] || [ "$SHELL_TYPE" = "bash" ]; then
        echo "  2. In non-YEN shells only, run: \"$CLI_SCRIPT\" init $SHELL_TYPE"
        echo "  3. Add that output to your shell config only if you want external-shell access."
    else
        echo "  2. In non-YEN shells only, use the bundled CLI directly: \"$CLI_SCRIPT\" --version"
        echo "  3. Add $(dirname "$CLI_SCRIPT") to PATH only if you want external-shell access."
    fi
else
    echo "  2. In non-YEN shells only, install or build a YEN.app first, then rerun diagnose-yen-cli.sh."
fi
echo ""

exit 0
