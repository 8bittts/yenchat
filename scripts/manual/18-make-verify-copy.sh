#!/bin/bash
# Make the YENVerify copy of the local zig-out build
#
# Copies yen-terminal/ghostty/zig-out/YEN.app to one fixed path as
# YENVerify.app, renames its executable and bundle identifier, and re-signs it
# with the release Developer ID identity.
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

DEST_APP="$DEST_DIR/YENVerify.app"

[ -x "$SOURCE_APP/Contents/MacOS/yen" ] || {
	echo "ERROR: no built app at $SOURCE_APP; run scripts/native/01-macos-smoke.sh --local first" >&2
	exit 1
}

if lsappinfo info -only pid -app "$VERIFY_ID" 2>/dev/null | /usr/bin/grep -Eq 'pid ?= ?[0-9]+'; then
	echo "ERROR: $VERIFY_ID is running; quit it first: osascript -e 'tell application id \"$VERIFY_ID\" to quit'" >&2
	exit 1
fi

ENTITLEMENTS="$(mktemp -t yenverify-entitlements)"
trap '/bin/rm -f "$ENTITLEMENTS"' EXIT
codesign -d --entitlements "$ENTITLEMENTS" --xml "$SOURCE_APP/Contents/MacOS/yen" 2>/dev/null

/bin/mkdir -p "$DEST_DIR"
/bin/rm -rf "$DEST_APP"
/bin/cp -R "$SOURCE_APP" "$DEST_APP"
/bin/mv "$DEST_APP/Contents/MacOS/yen" "$DEST_APP/Contents/MacOS/yenverify"
PLIST="$DEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable yenverify' "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $VERIFY_ID" "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName YENVerify' "$PLIST"

# Nested frameworks and helpers keep the build's own Developer ID signatures;
# only the outer bundle changed, so only it is re-signed.
SIGN_ARGS=(--force --sign "$SIGNING_IDENTITY" --identifier "$VERIFY_ID" --options runtime --timestamp=none)
if [ -s "$ENTITLEMENTS" ]; then
	SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
fi
codesign "${SIGN_ARGS[@]}" "$DEST_APP"

codesign --verify --deep --strict "$DEST_APP"
REQUIREMENT="$(codesign -d -r- "$DEST_APP" 2>&1 | /usr/bin/sed -n 's/^designated => //p')"
case "$REQUIREMENT" in
*"identifier \"$VERIFY_ID\""*"$TEAM_ID"*) ;;
*)
	echo "ERROR: unexpected designated requirement: $REQUIREMENT" >&2
	exit 1
	;;
esac

echo "RAN|verify-copy|identifier=$VERIFY_ID team=$TEAM_ID"
echo "YEN_VERIFY_APP=$DEST_APP"
