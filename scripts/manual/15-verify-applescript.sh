#!/bin/bash
# Verify built-app AppleScript behavior against the branded YEN bundle.
#
# Automated checks:
# 1) Launch the target app bundle by absolute path with a reversible temporary
#    config override that pins AppleScript on.
# 2) Create a new window, new tab, and one split using AppleScript.
# 3) Verify each created terminal writes the same YEN_SURFACE_ID that AppleScript
#    exposes via `id`, and that each surface honors its configured working directory.
# 4) Verify the new tab is selected in the intended window and the expected
#    window/tab/terminal counts hold after creation.
# 5) Verify AppleScript `perform action` allows a safe action and denies a blocked
#    action with an explicit allowlist failure.
#
# Optional follow-up:
# - `--keep-open` leaves the automated window/tab/split scenario open so you can
#   manually press `Cmd + Option + 2` and confirm the focused-pane subtree expands
#   from 2 terminals to 4. AppleScript key injection does not exercise the app-wide
#   local key monitor path that owns the workspace layout shortcuts.
#
# [CRITICAL] --app does NOT let you keep another YEN running. zig-out/YEN.app and
# /Applications/YEN.app both declare com.yenchat.yen, so LaunchServices activates
# the already-running installed app and every check below then passes against the
# wrong binary -- a false PASS that looks identical to a real one on screen. The
# require_no_running_yen_instances guard exists for exactly this. To verify a local
# build while the operator's session stays up, give the copy its own identity
# (CFBundleIdentifier + CFBundleExecutable) and re-sign it ad-hoc; the recipe is in
# _docs/05-infrastructure.md -> "Validating the local zig-out build without quitting
# your own YEN.app".
#
# Usage:
#   ./scripts/manual/15-verify-applescript.sh
#   ./scripts/manual/15-verify-applescript.sh --app /abs/path/to/YEN.app
#   ./scripts/manual/15-verify-applescript.sh --keep-open

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_APP_PATH="$REPO_ROOT/yen-terminal/ghostty/zig-out/YEN.app"

APP_PATH="$DEFAULT_APP_PATH"
KEEP_OPEN=0
FAILURES=0
TMP_DIR=""
APP_LAUNCHED=0
APP_PLIST_PATH=""
APP_EXECUTABLE_NAME=""
APP_BUNDLE_IDENTIFIER=""

XDG_CONFIG_PATH="$HOME/.config/yen/config.yen"
APP_SUPPORT_CONFIG_PATH="$HOME/Library/Application Support/com.yenchat.yen/config.yen"
XDG_BACKUP_PATH=""
APP_SUPPORT_BACKUP_PATH=""

usage() {
    cat <<EOF
Usage: $0 [--app /absolute/path/to/YEN.app] [--keep-open]

Options:
  --app PATH     Target a specific built YEN.app bundle.
  --keep-open    Leave the automated AppleScript scenario open for the manual
                 Cmd + Option + 2 workspace shortcut spot-check.
  -h, --help     Show this help text.
EOF
}

pass() {
    echo "  OK: $1"
}

fail() {
    echo "  X: $1"
    FAILURES=$((FAILURES + 1))
}

warn() {
    echo "  !: $1"
}

list_running_yen_instances() {
    if [ -z "$APP_EXECUTABLE_NAME" ]; then
        return 0
    fi

    ps ax -o pid= -o command= \
        | /usr/bin/awk -v executable="$APP_EXECUTABLE_NAME" '
            index($0, "/YEN.app/Contents/MacOS/" executable) {
                pid = $1
                $1 = ""
                sub(/^[[:space:]]+/, "", $0)
                print pid "\t" $0
            }
        '
}

require_no_running_yen_instances() {
    local running_instances
    local pid

    running_instances="$(list_running_yen_instances)"
    if [ -z "$running_instances" ]; then
        return 0
    fi

    echo "ERROR: Close running YEN.app instances before using this verifier."
    echo "The verifier writes a temporary config with macos-applescript pinned on, and an already-running"
    echo "YEN process will keep using its existing config instead."
    echo "Detected YEN.app processes:"
    while IFS=$'\t' read -r pid command_path; do
        [ -z "$pid" ] && continue
        echo "  - PID $pid ($command_path)"
    done <<EOF
$running_instances
EOF

    if [ -n "$APP_BUNDLE_IDENTIFIER" ]; then
        echo "Hint: quit the blocking YEN app(s), then rerun."
        echo "Bundle identifier: $APP_BUNDLE_IDENTIFIER"
    fi
    exit 1
}

backup_config_if_present() {
    local source_path="$1"
    local backup_path="$2"

    if [ -f "$source_path" ]; then
        mkdir -p "$(dirname "$backup_path")"
        cp "$source_path" "$backup_path"
    fi
}

restore_config_path() {
    local target_path="$1"
    local backup_path="$2"

    if [ -n "$backup_path" ] && [ -f "$backup_path" ]; then
        mkdir -p "$(dirname "$target_path")"
        cp "$backup_path" "$target_path"
    else
        rm -f "$target_path"
    fi
}

cleanup() {
    if [ "$APP_LAUNCHED" -eq 1 ] && [ "$KEEP_OPEN" -eq 0 ] && [ -d "$APP_PATH" ]; then
        /usr/bin/osascript -e "tell application \"$APP_PATH\" to quit" >/dev/null 2>&1 || true
    fi

    if [ -n "$TMP_DIR" ]; then
        restore_config_path "$XDG_CONFIG_PATH" "$XDG_BACKUP_PATH"
        restore_config_path "$APP_SUPPORT_CONFIG_PATH" "$APP_SUPPORT_BACKUP_PATH"
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT INT TERM HUP

while [ "$#" -gt 0 ]; do
    case "$1" in
        --app)
            shift
            if [ -z "${1:-}" ]; then
                echo "ERROR: --app requires a path"
                exit 1
            fi
            APP_PATH="$1"
            ;;
        --keep-open)
            KEEP_OPEN=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App bundle not found: $APP_PATH"
    exit 1
fi

APP_PLIST_PATH="$APP_PATH/Contents/Info.plist"
if [ ! -f "$APP_PLIST_PATH" ]; then
    echo "ERROR: App bundle is missing Info.plist: $APP_PLIST_PATH"
    exit 1
fi

APP_EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PLIST_PATH" 2>/dev/null || true)
APP_BUNDLE_IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PLIST_PATH" 2>/dev/null || true)

if [ -z "$APP_EXECUTABLE_NAME" ]; then
    echo "ERROR: Could not read CFBundleExecutable from $APP_PLIST_PATH"
    exit 1
fi

if ! command -v /usr/bin/osascript >/dev/null 2>&1; then
    echo "ERROR: osascript is required"
    exit 1
fi

require_no_running_yen_instances

TMP_DIR=$(mktemp -d)
XDG_BACKUP_PATH="$TMP_DIR/xdg-config.backup"
APP_SUPPORT_BACKUP_PATH="$TMP_DIR/app-support-config.backup"

WINDOW_DIR="$TMP_DIR/window"
TAB_DIR="$TMP_DIR/tab"
SPLIT_DIR="$TMP_DIR/split"
WINDOW_ROUTE_FILE="$TMP_DIR/window-route.txt"
TAB_ROUTE_FILE="$TMP_DIR/tab-route.txt"
SPLIT_ROUTE_FILE="$TMP_DIR/split-route.txt"
WINDOW_PWD_FILE="$TMP_DIR/window-pwd.txt"
TAB_PWD_FILE="$TMP_DIR/tab-pwd.txt"
SPLIT_PWD_FILE="$TMP_DIR/split-pwd.txt"

mkdir -p "$WINDOW_DIR" "$TAB_DIR" "$SPLIT_DIR"

echo ""
echo "-------------------------"
echo "AppleScript Bundle Check"
echo "-------------------------"
echo "App: $APP_PATH"
echo ""

echo "[1/5] Preparing reversible AppleScript config override..."
backup_config_if_present "$XDG_CONFIG_PATH" "$XDG_BACKUP_PATH"
backup_config_if_present "$APP_SUPPORT_CONFIG_PATH" "$APP_SUPPORT_BACKUP_PATH"
mkdir -p "$(dirname "$XDG_CONFIG_PATH")" "$(dirname "$APP_SUPPORT_CONFIG_PATH")"
cat > "$APP_SUPPORT_CONFIG_PATH" <<'EOF'
macos-applescript = true
window-save-state = never
quit-after-last-window-closed = false
initial-window = false
EOF
cp "$APP_SUPPORT_CONFIG_PATH" "$XDG_CONFIG_PATH"
pass "Temporary config pins macos-applescript on and disables restore noise"

echo ""
echo "[2/5] Launching app and waiting for AppleScript..."
/usr/bin/osascript -e "tell application \"$APP_PATH\" to activate" >/dev/null
APP_LAUNCHED=1

READY=0
for _ in $(seq 1 20); do
    if /usr/bin/osascript -e "tell application \"$APP_PATH\" to return version" >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 1
done

if [ "$READY" -ne 1 ]; then
    fail "App never became AppleScript-ready"
    exit 1
fi
pass "App responded to AppleScript by absolute bundle path"

echo ""
echo "[3/5] Creating window, tab, and split via AppleScript..."
AUTOMATION_RESULT=$(
    /usr/bin/osascript <<EOF
tell application "$APP_PATH"
    set windowRoutePath to POSIX file "$WINDOW_ROUTE_FILE"
    set tabRoutePath to POSIX file "$TAB_ROUTE_FILE"
    set splitRoutePath to POSIX file "$SPLIT_ROUTE_FILE"
    set windowPwdPath to POSIX file "$WINDOW_PWD_FILE"
    set tabPwdPath to POSIX file "$TAB_PWD_FILE"
    set splitPwdPath to POSIX file "$SPLIT_PWD_FILE"

    set windowInput to "printf %s " & quote & "\$YEN_SURFACE_ID" & quote & " > " & quoted form of POSIX path of windowRoutePath & linefeed & "pwd > " & quoted form of POSIX path of windowPwdPath & linefeed
    set tabInput to "printf %s " & quote & "\$YEN_SURFACE_ID" & quote & " > " & quoted form of POSIX path of tabRoutePath & linefeed & "pwd > " & quoted form of POSIX path of tabPwdPath & linefeed
    set splitInput to "printf %s " & quote & "\$YEN_SURFACE_ID" & quote & " > " & quoted form of POSIX path of splitRoutePath & linefeed & "pwd > " & quoted form of POSIX path of splitPwdPath & linefeed

    set windowConfig to {initial working directory:"$WINDOW_DIR", initial input:windowInput}
    set tabConfig to {initial working directory:"$TAB_DIR", initial input:tabInput}
    set splitConfig to {initial working directory:"$SPLIT_DIR", initial input:splitInput}

    set winRef to «event GhstNWin» given «class GNwS»:windowConfig
    delay 3
    set winTerm to terminal 1 of winRef

    set tabRef to «event GhstNTab» given «class GNtW»:winRef, «class GNtS»:tabConfig
    delay 3
    set tabTerm to terminal 1 of tabRef

    set splitRef to split tabTerm direction right with configuration splitConfig
    delay 3

    set allowedResult to «event GhstPfAc» "equalize_splits" given «class GonT»:splitRef

    set deniedMessage to ""
    try
        «event GhstPfAc» "show-config" given «class GonT»:splitRef
        set deniedMessage to "unexpected-success"
    on error errMsg number errNum
        set deniedMessage to (errNum as text) & ":" & errMsg
    end try

    return (id of winTerm as text) & "|" & ¬
        (working directory of winTerm as text) & "|" & ¬
        (id of selected tab of winRef as text) & "|" & ¬
        (id of tabRef as text) & "|" & ¬
        (id of tabTerm as text) & "|" & ¬
        (working directory of tabTerm as text) & "|" & ¬
        (id of splitRef as text) & "|" & ¬
        (working directory of splitRef as text) & "|" & ¬
        (count of windows as text) & "|" & ¬
        (count of tabs of winRef as text) & "|" & ¬
        (count of terminals of tabRef as text) & "|" & ¬
        (count of terminals of winRef as text) & "|" & ¬
        (allowedResult as text) & "|" & ¬
        deniedMessage
end tell
EOF
)
pass "AppleScript created window, tab, split, and action-policy checks"

wait_for_output_file() {
    local label="$1"
    local path="$2"

    for _ in $(seq 1 15); do
        if [ -s "$path" ]; then
            pass "$label wrote expected output"
            return 0
        fi
        sleep 1
    done

    fail "$label did not write expected output: $path"
    return 1
}

echo ""
echo "[4/5] Validating route IDs, working directories, and counts..."
wait_for_output_file "Window terminal" "$WINDOW_ROUTE_FILE"
wait_for_output_file "Window working directory" "$WINDOW_PWD_FILE"
wait_for_output_file "Tab terminal" "$TAB_ROUTE_FILE"
wait_for_output_file "Tab working directory" "$TAB_PWD_FILE"
wait_for_output_file "Split terminal" "$SPLIT_ROUTE_FILE"
wait_for_output_file "Split working directory" "$SPLIT_PWD_FILE"

IFS='|' read -r WINDOW_TERM_ID WINDOW_WORKING_DIR SELECTED_TAB_ID TAB_ID TAB_TERM_ID TAB_WORKING_DIR SPLIT_ID SPLIT_WORKING_DIR WINDOW_COUNT TAB_COUNT TAB_TERMINAL_COUNT WINDOW_TERMINAL_COUNT ALLOWED_RESULT DENIED_MESSAGE <<EOF
$AUTOMATION_RESULT
EOF

WINDOW_ROUTE_VALUE=$(cat "$WINDOW_ROUTE_FILE" 2>/dev/null || true)
TAB_ROUTE_VALUE=$(cat "$TAB_ROUTE_FILE" 2>/dev/null || true)
SPLIT_ROUTE_VALUE=$(cat "$SPLIT_ROUTE_FILE" 2>/dev/null || true)
WINDOW_PWD_VALUE=$(cat "$WINDOW_PWD_FILE" 2>/dev/null || true)
TAB_PWD_VALUE=$(cat "$TAB_PWD_FILE" 2>/dev/null || true)
SPLIT_PWD_VALUE=$(cat "$SPLIT_PWD_FILE" 2>/dev/null || true)

[ "$WINDOW_ROUTE_VALUE" = "$WINDOW_TERM_ID" ] && pass "Window terminal route ID matches AppleScript id" || fail "Window terminal route ID mismatch"
[ "$TAB_ROUTE_VALUE" = "$TAB_TERM_ID" ] && pass "Tab terminal route ID matches AppleScript id" || fail "Tab terminal route ID mismatch"
[ "$SPLIT_ROUTE_VALUE" = "$SPLIT_ID" ] && pass "Split terminal route ID matches AppleScript id" || fail "Split terminal route ID mismatch"

[ "$WINDOW_PWD_VALUE" = "$WINDOW_DIR" ] && pass "Window working directory applied to shell" || fail "Window working directory mismatch"
[ "$TAB_PWD_VALUE" = "$TAB_DIR" ] && pass "Tab working directory applied to shell" || fail "Tab working directory mismatch"
[ "$SPLIT_PWD_VALUE" = "$SPLIT_DIR" ] && pass "Split working directory applied to shell" || fail "Split working directory mismatch"

[ "$WINDOW_WORKING_DIR" = "$WINDOW_DIR" ] && pass "AppleScript window terminal reports configured working directory" || fail "AppleScript window terminal working directory mismatch"
[ "$TAB_WORKING_DIR" = "$TAB_DIR" ] && pass "AppleScript tab terminal reports configured working directory" || fail "AppleScript tab terminal working directory mismatch"
[ "$SPLIT_WORKING_DIR" = "$SPLIT_DIR" ] && pass "AppleScript split terminal reports configured working directory" || fail "AppleScript split terminal working directory mismatch"

[ "$SELECTED_TAB_ID" = "$TAB_ID" ] && pass "New tab became the selected tab in its window" || fail "New tab did not become selected"
[ "$WINDOW_COUNT" = "1" ] && pass "Window count remained stable after tab/split creation" || fail "Unexpected window count: $WINDOW_COUNT"
[ "$TAB_COUNT" = "2" ] && pass "Window contains expected tab count after AppleScript new tab" || fail "Unexpected tab count in window: $TAB_COUNT"
[ "$TAB_TERMINAL_COUNT" = "2" ] && pass "Selected AppleScript tab contains the expected split pair" || fail "Unexpected terminal count in selected tab: $TAB_TERMINAL_COUNT"
[ "$WINDOW_TERMINAL_COUNT" = "3" ] && pass "Window contains expected total terminal count across tabs" || fail "Unexpected total terminal count in window: $WINDOW_TERMINAL_COUNT"

echo ""
echo "[5/5] Validating AppleScript action policy..."
[ "$ALLOWED_RESULT" = "true" ] && pass "Allowlisted perform action succeeded (equalize_splits)" || fail "Allowlisted perform action did not succeed"
case "$DENIED_MESSAGE" in
    *not\ allowlisted\ in\ YEN*)
        pass "Blocked perform action failed closed with explicit allowlist error"
        ;;
    "unexpected-success")
        fail "Blocked perform action unexpectedly succeeded"
        ;;
    *)
        fail "Blocked perform action returned unexpected error: $DENIED_MESSAGE"
        ;;
esac

echo ""
if [ "$KEEP_OPEN" -eq 1 ]; then
    warn "App will remain open for the physical keyboard follow-up."
    warn "Manual follow-up: with the scripted split still visible in the selected tab, press Cmd + Option + 2 and confirm the focused-pane subtree expands from 2 terminals to 4."
else
    warn "Manual follow-up when AppleScript or layout shortcut handling changed: rerun with --keep-open, then press Cmd + Option + 2 in the scripted split tab and confirm the focused-pane subtree expands from 2 terminals to 4."
fi

echo ""
if [ "$FAILURES" -gt 0 ]; then
    echo "AppleScript verification failed with $FAILURES issue(s)."
    exit 1
fi

echo "AppleScript verification passed."
