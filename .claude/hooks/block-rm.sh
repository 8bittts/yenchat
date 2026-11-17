#!/bin/bash
# .claude/hooks/block-rm.sh
# Pre-tool hook: block rm -rf except on known-safe build artifact paths

COMMAND=$(jq -r '.tool_input.command')

if echo "$COMMAND" | grep -q 'rm -rf'; then
  # Allow rm -rf on known-safe build/cache directories
  if echo "$COMMAND" | grep -qE 'rm -rf.*(DerivedData|zig-cache|\.zig-cache|zig-out|\.yen-zig-global-cache|\.zig-global-cache|node_modules/\.cache|\.next|/tmp/|/var/folders/)'; then
    exit 0
  fi
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "rm -rf blocked. Use trash for general cleanup. Build caches (DerivedData, zig-cache, .next, tmp) are allowed."
    }
  }'
else
  exit 0
fi
