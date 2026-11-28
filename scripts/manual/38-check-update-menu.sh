#!/bin/bash
# Run against the recorded PID of a signed YENVerify with a terminal open.
set -euo pipefail

pid=${1:-}
[[ $# == 1 && "$pid" =~ ^[1-9][0-9]*$ ]] || { echo "Usage: $0 <YENVerify PID>" >&2; exit 1; }
exe=$(/bin/ps -ww -p "$pid" -o comm=)
case "$exe" in
    */YENVerify.app/Contents/MacOS/yenverify) ;;
    *) echo "PID $pid is not the YENVerify executable." >&2; exit 1 ;;
esac
bash "$(dirname "$0")/../lib/verify-check-only-copy.sh" "${exe%/Contents/MacOS/yenverify}"

osascript - "$pid" <<'APPLESCRIPT'
on run argv
    set targetPID to item 1 of argv as integer
    tell application "System Events"
        tell (first application process whose unix id is targetPID and bundle identifier is "com.yenchat.yenverify")
            if (count windows) is 0 then error "Open a verification terminal first."
            set frontmost to true
            click (first menu item of menu 1 of menu bar item 2 of menu bar 1 whose name starts with "Check for Updates")
            repeat 120 times
                if (name of window 1) is "Software Update" then
                    return "Check for Updates presented Software Update in PID " & targetPID
                end if
                delay 0.1
            end repeat
            error "Check for Updates did not present a foreground window."
        end tell
    end tell
end run
APPLESCRIPT
