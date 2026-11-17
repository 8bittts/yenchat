#!/bin/bash
# .claude/hooks/guard-cwd-drift.sh
# Pre-tool hook: block "bash scripts/" without CWD prefix or absolute path
# Prevents CWD drift after build-release.sh cd's into yen-terminal/ghostty/

COMMAND=$(jq -r '.tool_input.command')

# Block bare relative "bash scripts/" — require either:
#   1. cd "$CLAUDE_PROJECT_DIR" && bash scripts/...
#   2. bash "$CLAUDE_PROJECT_DIR"/scripts/...
if echo "$COMMAND" | grep -qE '^bash scripts/' ; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "CWD drift guard: use absolute path instead. Replace: bash scripts/foo.sh → bash $CLAUDE_PROJECT_DIR/scripts/foo.sh"
    }
  }'
else
  exit 0
fi
