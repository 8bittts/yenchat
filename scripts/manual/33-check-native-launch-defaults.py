"""Run both native preference launch orders against a re-identified YEN.app on macOS."""

import os
import plistlib
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SETUP = "-com.yenchat.yen.hasCompletedSetup"
SESSIONS = "-com.yenchat.yen.persistentSessions"
TOKENS = "-com.yenchat.yen.showTokenUsage"
CHILD_OPTION = "-com.yenchat.yen.childArgument"
ALERT = "Configuration Errors"
TITLE = "Native preference check"
CONFIG = "initial-window = true\nwindow-save-state = never\nconfirm-close-surface = false\n"


def ui(pid, command):
    script = f'tell application "System Events" to tell (first process whose unix id is {pid})\n{command}\nend tell'
    return subprocess.check_output(["osascript", "-e", script], text=True).strip()


def wait_for(pid, expected, has_alert):
    deadline = time.monotonic() + 15
    names = ""
    while time.monotonic() < deadline:
        try:
            names = ui(pid, "get name of windows")
        except subprocess.CalledProcessError:
            time.sleep(0.2)
            continue
        if expected in names and (ALERT in names) == has_alert:
            return
        time.sleep(0.2)
    raise AssertionError(f"Expected {expected!r}, alert={has_alert}. Found windows: {names}")


def check_child_arguments(received):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if received.exists() and received.read_text().splitlines() == [CHILD_OPTION, "YES"]:
            return
        time.sleep(0.1)
    raise AssertionError("The terminal command did not receive its two arguments")


def reload_config(pid):
    result = ui(pid, '''
        set frontmost to true
        repeat with itemRef in menu bar items of menu bar 1
            if exists menu item "Reload Configuration" of menu 1 of itemRef then
                click itemRef
                click menu item "Reload Configuration" of menu 1 of itemRef
                return "reloaded"
            end if
        end repeat''')
    assert result == "reloaded", result


def check(app, preferences):
    with tempfile.TemporaryDirectory(prefix="yen-native-launch-") as scratch:
        config = Path(scratch, "Library/Application Support/com.yenchat.yen/config.yen")
        config.parent.mkdir(parents=True)
        config.write_text(CONFIG)
        received = Path(scratch, "command-arguments")
        command = ['-e', '/bin/sh', '-c', 'printf "%s\\n" "$@" > "$0"; exec /bin/cat',
                   str(received), CHILD_OPTION, 'YES']
        process = subprocess.Popen([app, *preferences, f"--title={TITLE}", *command],
                                   env={**os.environ, "HOME": scratch, "CFFIXED_USER_HOME": scratch,
                                        "XDG_CONFIG_HOME": scratch, "YEN_CONFIG_PATH": str(config)})
        try:
            wait_for(process.pid, TITLE, False)
            check_child_arguments(received)
            config.write_text(CONFIG + "test-invalid-native-launch-field = true\n")
            reload_config(process.pid)
            wait_for(process.pid, ALERT, True)
            config.write_text(CONFIG)
            reload_config(process.pid)
            wait_for(process.pid, TITLE, False)
            print(f"PASS launch, valid CLI setting, child arguments, and error recovery: {preferences}")
        finally:
            process.terminate()
            process.wait(timeout=10)


if __name__ == "__main__":
    contents = Path(sys.argv[1]).resolve() / "Contents"
    with (contents / "Info.plist").open("rb") as info:
        bundle = plistlib.load(info)
    if bundle["CFBundleIdentifier"] == "com.yenchat.yen":
        sys.exit("Pass the re-identified test bundle from 18-make-verify-copy.sh.")
    binary = contents / "MacOS" / bundle["CFBundleExecutable"]
    check(binary, [SETUP, "YES", SESSIONS, "NO", TOKENS, "NO"])
    check(binary, [SETUP, "YES", TOKENS, "YES", SESSIONS, "NO"])
