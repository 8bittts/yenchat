#!/bin/bash
# Verify that build DistributedNotification names stay centralized and in sync.
#
# Pattern:
#   - Swift source of truth: yen-terminal/overlays/macos/Sources/YEN/YENCustomNotifications.swift
#   - Swift receivers reference centralized Notification.Name entries
#   - Claude build hook stays aligned with the centralized build notification name
#
# Exit 0: all names in sync
# Exit 1: mismatches found or files missing

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXIT_CODE=0

SWIFT_CONTRACT="$REPO_ROOT/yen-terminal/overlays/macos/Sources/YEN/YENCustomNotifications.swift"
SWIFT_BUILD="$REPO_ROOT/yen-terminal/overlays/macos/Sources/App/AppDelegate+Build.swift"
HOOK_BUILD="$REPO_ROOT/.claude/hooks/notify-complete.sh"

echo "Checking build DistributedNotification name centralization and sync..."
echo ""

check_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "ERROR: $file not found"
    EXIT_CODE=1
    return 1
  fi
  return 0
}

extract_first() {
  local pattern="$1"
  local file="$2"
  grep -o "$pattern" "$file" | head -n 1 || true
}

check_reference() {
  local label="$1"
  local needle="$2"
  local file="$3"

  if grep -q "$needle" "$file"; then
    echo "[OK] $label reference: $needle"
  else
    echo "ERROR: expected $label to reference $needle"
    echo "  File: $file"
    EXIT_CODE=1
  fi
}

for file in \
  "$SWIFT_CONTRACT" \
  "$SWIFT_BUILD" \
  "$HOOK_BUILD"
do
  check_file "$file" || true
done

if grep -q 'com\.yenchat\.yen\.buildNotification' "$SWIFT_CONTRACT"; then
  echo "[OK] Build identifier: com.yenchat.yen.buildNotification"
else
  echo "ERROR: Build notification name not found in $SWIFT_CONTRACT"
  EXIT_CODE=1
fi
check_reference "Build Swift observer" '\.yenBuildNotification' "$SWIFT_BUILD"
check_reference "Build Claude hook" 'com\.yenchat\.yen\.buildNotification' "$HOOK_BUILD"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
  echo "All notification names centralized and in sync."
else
  echo "Notification name sync check FAILED."
fi

exit $EXIT_CODE
