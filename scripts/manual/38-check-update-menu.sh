#!/bin/bash
# Run against a signed YENVerify with a terminal window open.
set -euo pipefail
osascript <<'APPLESCRIPT'
tell application "System Events"
    set target to first application process whose bundle identifier is "com.yenchat.yenverify"
    tell target
        if (count windows) is 0 then error "Open a verification terminal first."
        set frontmost to true
        set initialWindows to count windows
        click (first menu item of menu 1 of menu bar item 2 of menu bar 1 whose name starts with "Check for Updates")
        repeat 120 times
            if (count windows) > initialWindows or (exists sheet 1 of window 1) then
                return "Check for Updates presented a foreground window: " & name of window 1
            end if
            delay 0.1
        end repeat
        error "Check for Updates did not present a foreground window."
    end tell
end tell
APPLESCRIPT
