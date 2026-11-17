#!/bin/bash
# Pre-tool hook: block writes to sensitive files
FILE_PATH=$(jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

if echo "$FILE_PATH" | grep -qE '\.env($|\.)|credentials\.json|\.ssh/|keychain|secrets?\.|\.pem$|\.key$'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Blocked: cannot modify sensitive file (secrets, keys, credentials, SSH)."
    }
  }'
else
  exit 0
fi
