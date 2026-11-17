#!/bin/bash
# Pre-tool hook: block upstream technology names in user-facing content
# Rule: Never mention Ghostty, Yazi, or other upstream names in user-facing files.
# Use "YEN Terminal"/"terminal engine" instead of Ghostty,
# "file browser"/"file manager" instead of Yazi.

# Grab the file path and content from tool input
FILE_PATH=$(jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

# Only check user-facing files
case "$FILE_PATH" in
  */public/stable/appcast.xml|\
  */app/*|\
  */components/*|\
  */public/*.html|\
  */public/*.xml|\
  */public/*.json|\
  *llms.txt|\
  *sitemap*|\
  *robots.txt)
    # Check both old_string/new_string (Edit) and content (Write)
    NEW_CONTENT=$(jq -r '(.tool_input.new_string // "") + " " + (.tool_input.content // "")' 2>/dev/null)
    if echo "$NEW_CONTENT" | grep -qiE '\b(ghostty|yazi)\b'; then
      jq -n '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: "Upstream tech names (Ghostty, Yazi) must not appear in user-facing content. Use \"YEN Terminal\"/\"terminal engine\" or \"file browser\"/\"file manager\" instead."
        }
      }'
    else
      exit 0
    fi
    ;;
  *)
    exit 0
    ;;
esac
