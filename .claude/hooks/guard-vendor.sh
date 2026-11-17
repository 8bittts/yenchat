#!/bin/bash
# Pre-tool hook: protect vendor directories from direct modification
FILE_PATH=$(jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

if echo "$FILE_PATH" | grep -qE 'ghostty/|customizations/vendor/'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Vendor directories are read-only. Use overlays/ for customizations."
    }
  }'
else
  exit 0
fi
