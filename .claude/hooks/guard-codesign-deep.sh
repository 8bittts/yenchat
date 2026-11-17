#!/bin/bash
# Pre-tool hook: block codesign --deep (must sign nested frameworks bottom-up)
COMMAND=$(jq -r '.tool_input.command // empty')
if echo "$COMMAND" | grep -q 'codesign --deep'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "codesign --deep is forbidden. Sign nested frameworks bottom-up instead."
    }
  }'
else
  exit 0
fi
