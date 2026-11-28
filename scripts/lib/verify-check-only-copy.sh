#!/bin/bash
# Check the finished QA bundle before exposing it to the public update feed.
set -euo pipefail

app=${1:?Pass the path to YENVerify.app}
framework="$app/Contents/Frameworks/Sparkle.framework"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" != com.yenchat.yenverify ||
      ! -x "$framework/Sparkle" ]]; then
    echo "Expected YENVerify with a working Sparkle framework." >&2
    exit 1
fi
installers=$(/usr/bin/find "$framework" \( -name Autoupdate -o -name Autoupdate.app \) -print)
if [[ -n "$installers" ]]; then
    echo "Unsafe verification copy contains Sparkle's installer. Rebuild it with 18-make-verify-copy.sh." >&2
    exit 1
fi
codesign --verify --deep --strict "$app"
echo "Verified signed YENVerify with Sparkle checks available and its installer removed."
