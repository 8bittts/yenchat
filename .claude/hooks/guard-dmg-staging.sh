#!/bin/bash
# Post-tool hook: warn if .dmg files were staged (DMGs belong on GitHub Releases, not git)
COMMAND=$(jq -r '.tool_input.command // empty')
if echo "$COMMAND" | grep -q 'git add'; then
  STAGED_DMGS=$(git diff --cached --name-only 2>/dev/null | grep '\.dmg$')
  if [ -n "$STAGED_DMGS" ]; then
    echo "WARNING: .dmg files staged for commit. DMGs belong on GitHub Releases, not git."
    echo "Staged: $STAGED_DMGS"
    echo "Run: git reset HEAD <file> to unstage."
  fi
fi
exit 0
