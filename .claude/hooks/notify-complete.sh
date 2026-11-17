#!/bin/bash
# Post-tool hook: macOS notification when build-like commands complete.
# Sends a DistributedNotification that YEN.app observes and forwards to
# UNUserNotificationCenter — shows the YEN app icon, not Script Editor.
# Notification name must match the centralized Swift definition in
# yen-terminal/overlays/macos/Sources/YEN/YENCustomNotifications.swift.
HOOK_JSON=$(cat)
COMMAND=$(printf "%s" "$HOOK_JSON" | jq -r '.tool_input.command // empty')

parse_duration_ms() {
  local raw="$1"
  local parsed
  raw=$(printf "%s" "$raw" | tr -d '[:space:]')
  if [ -z "$raw" ]; then
    return 1
  fi

  parsed=$(perl -e '
    my $raw = shift // "";
    my $micro = chr(0xB5) . "s";
    my %units = (
      ms => 1,
      us => 0.001,
      $micro => 0.001,
      ns => 0.000001,
      s => 1000,
      m => 60 * 1000,
      h => 60 * 60 * 1000,
      d => 24 * 60 * 60 * 1000,
      w => 7 * 24 * 60 * 60 * 1000,
      y => 365 * 24 * 60 * 60 * 1000,
    );
    if ($raw eq "0") {
      print 0;
      exit 0;
    }
    my $total = 0;
    pos($raw) = 0;
    while (pos($raw) < length($raw)) {
      if ($raw =~ /\G([0-9]+)(ms|us|\x{00B5}s|ns|y|w|d|h|m|s)/gc) {
        $total += $1 * $units{$2};
        next;
      }
      exit 1;
    }
    if ($total != int($total)) {
      $total = int($total) + 1;
    }
    print int($total);
  ' -- "$raw" 2>/dev/null) || return 1

  if [ -z "$parsed" ]; then
    return 1
  fi

  printf "%s" "$parsed"
}

if echo "$COMMAND" | grep -qEi '\b(build|compile|zip|zig|notarize|vendor|install|test|lint|check|tsc)\b'; then
  EXIT_CODE=$(printf "%s" "$HOOK_JSON" | jq -r '.tool_response.exit_code // .tool_output.exit_code // .tool_result.exit_code // empty')
  DURATION_MS=$(printf "%s" "$HOOK_JSON" | jq -r '.tool_response.duration_ms // .tool_output.duration_ms // .tool_result.duration_ms // empty')

  CONFIG_PATH="$HOME/Library/Application Support/com.yenchat.yen/config.yen"
  if [ -f "$CONFIG_PATH" ]; then
    NOTIFY_MODE=$(awk -F= '/^[[:space:]]*notify-on-command-finish[[:space:]]*=/{value=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); mode=tolower(value)} END{print mode}' "$CONFIG_PATH")
    NOTIFY_ACTION=$(awk -F= '/^[[:space:]]*notify-on-command-finish-action[[:space:]]*=/{value=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); action=tolower(value)} END{print action}' "$CONFIG_PATH")
    NOTIFY_AFTER_RAW=$(awk -F= '/^[[:space:]]*notify-on-command-finish-after[[:space:]]*=/{value=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); delay=tolower(value)} END{print delay}' "$CONFIG_PATH")
    NOTIFY_AFTER_MS=$(parse_duration_ms "$NOTIFY_AFTER_RAW")
    if [ -z "$NOTIFY_AFTER_MS" ]; then
      NOTIFY_AFTER_MS=5000
    fi
    if [ "$NOTIFY_MODE" = "always" ] &&
      printf "%s" "$NOTIFY_ACTION" | grep -qE '(^|,)notify(,|$)' &&
      [ -n "$DURATION_MS" ] &&
      [ "$DURATION_MS" != "null" ] &&
      [ "$DURATION_MS" -eq "$DURATION_MS" ] 2>/dev/null &&
      [ "$DURATION_MS" -ge "$NOTIFY_AFTER_MS" ]; then
      exit 0
    fi
  fi

  NORMALIZED_COMMAND=$(printf "%s" "$COMMAND" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')
  if [ -z "$NORMALIZED_COMMAND" ]; then
    NORMALIZED_COMMAND="(command unavailable)"
  fi

  TASK_LABEL="Task"
  if echo "$NORMALIZED_COMMAND" | grep -qEi '\b(notarize|notarization)\b'; then
    TASK_LABEL="Notarization"
  elif echo "$NORMALIZED_COMMAND" | grep -qEi '\b(zip|archive|package)\b'; then
    TASK_LABEL="Packaging"
  elif echo "$NORMALIZED_COMMAND" | grep -qEi '\b(vendor)\b'; then
    TASK_LABEL="Vendor Sync"
  elif echo "$NORMALIZED_COMMAND" | grep -qEi '\b(test)\b'; then
    TASK_LABEL="Test Run"
  elif echo "$NORMALIZED_COMMAND" | grep -qEi '\b(lint|check|tsc)\b'; then
    TASK_LABEL="Code Check"
  elif echo "$NORMALIZED_COMMAND" | grep -qEi '\b(build|compile|zig|install)\b'; then
    TASK_LABEL="Build"
  fi

  STATUS_LABEL="completed"
  if [ -n "$EXIT_CODE" ] && [ "$EXIT_CODE" != "0" ] && [ "$EXIT_CODE" != "null" ]; then
    STATUS_LABEL="failed (exit $EXIT_CODE)"
  fi

  DURATION_LABEL=""
  if [ -n "$DURATION_MS" ] && [ "$DURATION_MS" != "null" ] && [ "$DURATION_MS" -eq "$DURATION_MS" ] 2>/dev/null; then
    if [ "$DURATION_MS" -ge 1000 ]; then
      DURATION_LABEL=" | $((DURATION_MS / 1000))s"
    else
      DURATION_LABEL=" | ${DURATION_MS}ms"
    fi
  fi

  SHORT_COMMAND="$NORMALIZED_COMMAND"
  if [ "${#SHORT_COMMAND}" -gt 120 ]; then
    SHORT_COMMAND="${SHORT_COMMAND:0:117}..."
  fi

  export YEN_BUILD_PAYLOAD="YEN $TASK_LABEL $STATUS_LABEL
Command: $SHORT_COMMAND$DURATION_LABEL"
  export YEN_BUILD_USER_INFO="$(jq -cn \
    --arg schema_version "1" \
    --arg service "build" \
    --arg surface_id "${YEN_SURFACE_ID:-}" \
    '{schema_version:$schema_version, service:$service, surface_id:$surface_id}')"
  osascript -l JavaScript -e '
    ObjC.import("Foundation"); ObjC.import("stdlib");
    var payload = $.NSProcessInfo.processInfo.environment.objectForKey("YEN_BUILD_PAYLOAD").js;
    var userInfo = $();
    var userInfoRaw = $.NSProcessInfo.processInfo.environment.objectForKey("YEN_BUILD_USER_INFO").js;
    if (userInfoRaw && userInfoRaw.length > 0) {
      try { userInfo = $(JSON.parse(userInfoRaw)); } catch (e) {}
    }
    $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately(
      "com.yenchat.yen.buildNotification", payload, userInfo, true
    );
  ' 2>/dev/null
fi
exit 0
