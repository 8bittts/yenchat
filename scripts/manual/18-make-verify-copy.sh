#!/bin/bash
# Make the YENVerify copy of the local zig-out build
#
# Copies yen-terminal/ghostty/zig-out/YEN.app to one fixed path as
# YENVerify.app, renames its executable and bundle identifier, and re-signs it
# and every nested framework, helper and tool with the release Developer ID
# identity, so a local ad-hoc build works too. Only the QA copy omits Sparkle's installer.
#
# Why a fixed path and a real signature: macOS keys an Accessibility or
# Automation grant to the app's code requirement. An ad-hoc signature changes
# with every build, and a copy under mktemp is deleted after the run, so each
# new copy asked for access again and System Settings had no row to toggle.
# With the identifier and Team ID fixed, one grant covers every later copy.
#
# Usage: ./scripts/manual/18-make-verify-copy.sh [--app <source YEN.app>]
#   Prints the copy's path on the last line as YEN_VERIFY_APP=<path>.
#   YEN_VERIFY_DIR overrides the destination folder.
#
# Exit codes:
#   0 = Copy made and verified
#   1 = Failed (missing source, copy running, signing or verification failed)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/lib/signing-constants.sh"

VERIFY_ID="com.yenchat.yenverify"
SOURCE_APP="$REPO_ROOT/yen-terminal/ghostty/zig-out/YEN.app"
DEST_DIR="${YEN_VERIFY_DIR:-$HOME/.local/state/yen/verify}"

while [ $# -gt 0 ]; do
	case "$1" in
	--app)
		[ $# -ge 2 ] || { echo "ERROR: --app needs a path" >&2; exit 1; }
		SOURCE_APP="$2"
		shift 2
		;;
	*)
		echo "ERROR: unknown argument: $1" >&2
		exit 1
		;;
	esac
done

PUBLISHED_APP="$DEST_DIR/YENVerify.app"

[ -x "$SOURCE_APP/Contents/MacOS/yen" ] || {
	echo "ERROR: no built app at $SOURCE_APP; run scripts/native/01-macos-smoke.sh --local first" >&2
	exit 1
}

# A copy can have the production identity after an older build updated itself.
# Check the executable at this destination, independent of the bundle ID.
check_destination_idle() {
    local exe pid
    if pid=$(/usr/bin/pgrep -x yenverify); then
        echo "ERROR: YENVerify is running (pid $pid). Wait for that verification to finish." >&2
        exit 1
    elif [[ $? != 1 ]]; then
        echo "ERROR: Could not check for a running YENVerify." >&2
        exit 1
    fi
    for exe in yenverify yen; do
        [[ -f "$PUBLISHED_APP/Contents/MacOS/$exe" ]] || continue
        if pid=$(/usr/sbin/lsof -t "$PUBLISHED_APP/Contents/MacOS/$exe"); then
            echo "ERROR: $PUBLISHED_APP is in use (pid $pid). Leave it in place." >&2
            exit 1
        elif [[ $? != 1 ]]; then
            echo "ERROR: Could not check whether $PUBLISHED_APP is in use." >&2
            exit 1
        fi
    done
}
check_destination_idle

# The release entitlements sit beside the build's zig-out folder. A local build
# is ad-hoc signed and can carry none, so never read them from the binary.
ENTITLEMENTS="$(cd "$SOURCE_APP/../.." && pwd)/macos/YEN.entitlements"
[ -s "$ENTITLEMENTS" ] || {
	echo "ERROR: release entitlements not found at $ENTITLEMENTS" >&2
	exit 1
}

/bin/mkdir -p "$DEST_DIR"
lock="$DEST_DIR/.verify-copy.lock"
if ! /usr/bin/shlock -p "$$" -f "$lock"; then
    echo "ERROR: Another builder owns $DEST_DIR." >&2
    exit 1
fi
trap '/bin/rm -f "$lock"' EXIT
staging=$(mktemp -d "$DEST_DIR/.verify-copy.XXXXXXXX")
trap '/bin/rm -rf "$staging"; /bin/rm -f "$lock"' EXIT
DEST_APP="$staging/YENVerify.app"
/bin/cp -R "$SOURCE_APP" "$DEST_APP"
/bin/mv "$DEST_APP/Contents/MacOS/yen" "$DEST_APP/Contents/MacOS/yenverify"
PLIST="$DEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable yenverify' "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $VERIFY_ID" "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName YENVerify' "$PLIST"

# Sign every piece inside-out with one identity, in finalize-build's order.
# A local build is ad-hoc throughout, and the hardened runtime refuses to load
# a framework whose Team ID differs from the app's, so the copy died at launch
# with "Library not loaded: Sparkle" when only the outer bundle was re-signed.
sign() {
	codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp=none "$@"
}
for bin in "$DEST_APP"/Contents/Resources/bin/*; do
	[ -f "$bin" ] || continue
	/usr/bin/file "$bin" | /usr/bin/grep -q 'Mach-O' || continue
	if [ -f "$bin.entitlements" ]; then
		sign --entitlements "$bin.entitlements" "$bin"
	else
		sign "$bin"
	fi
done
SPARKLE="$DEST_APP/Contents/Frameworks/Sparkle.framework"
# Pin the layout so a new Sparkle installer cannot slip into a QA copy unnoticed.
[[ -L "$SPARKLE/Autoupdate" && -f "$SPARKLE/Versions/B/Autoupdate" &&
   "$SPARKLE/Autoupdate" -ef "$SPARKLE/Versions/B/Autoupdate" ]] || {
    echo "ERROR: Unknown Sparkle installer layout. Review it before launching YENVerify." >&2
    exit 1
}
/bin/rm "$SPARKLE/Autoupdate" "$SPARKLE/Versions/B/Autoupdate"
for nested in "$SPARKLE"/Versions/B/XPCServices/*.xpc "$SPARKLE/Versions/B/Updater.app"; do
    if [ -e "$nested" ]; then sign "$nested"; fi
done
sign "$SPARKLE"
for plugin in "$DEST_APP"/Contents/PlugIns/*.plugin; do
	if [ -d "$plugin" ]; then sign "$plugin"; fi
done
sign --identifier "$VERIFY_ID" --entitlements "$ENTITLEMENTS" "$DEST_APP"

bash "$REPO_ROOT/scripts/lib/verify-check-only-copy.sh" "$DEST_APP"
for framework in "$DEST_APP"/Contents/Frameworks/*; do
	[ -e "$framework" ] || continue
	team="$(codesign -dv "$framework" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p')"
	[ "$team" = "$TEAM_ID" ] || {
		echo "ERROR: $(basename "$framework") is not signed by team $TEAM_ID (found: ${team:-none})" >&2
		exit 1
	}
done
REQUIREMENT="$(codesign -d -r- "$DEST_APP" 2>&1 | /usr/bin/sed -n 's/^designated => //p')"
case "$REQUIREMENT" in
*"identifier \"$VERIFY_ID\""*"$TEAM_ID"*) ;;
*)
	echo "ERROR: unexpected designated requirement: $REQUIREMENT" >&2
	exit 1
	;;
esac

check_destination_idle
/bin/rm -rf "$PUBLISHED_APP"
/bin/mv "$DEST_APP" "$PUBLISHED_APP"
echo "RAN|verify-copy|identifier=$VERIFY_ID team=$TEAM_ID"
echo "YEN_VERIFY_APP=$PUBLISHED_APP"
