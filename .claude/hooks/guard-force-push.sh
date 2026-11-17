#!/bin/bash
# Pre-tool hook: block force push
COMMAND=$(jq -r '.tool_input.command // empty')
if echo "$COMMAND" | grep -qE 'git push.*( -f| --force)'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Force push is blocked. Use regular push only."
    }
  }'
else
  exit 0
fi
