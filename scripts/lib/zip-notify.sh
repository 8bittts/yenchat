#!/bin/bash
# Milestone notifications for the /update-yen release pipeline.
#
# Posts the same DistributedNotification that YEN.app observes and forwards
# to UNUserNotificationCenter (com.yenchat.yen.buildNotification — name must
# match yen-terminal/overlays/macos/Sources/YEN/YENCustomNotifications.swift).
# Major release sections ONLY (build started / app compiled / verification
# passed / notarized / upload complete / failure). Per-command completion
# notifications remain owned by .claude/hooks/notify-complete.sh.
#
# Usage:  source scripts/lib/zip-notify.sh
#         zip_notify "Title" ["detail line"]
#
# Disable: YEN_ZIP_NOTIFY=off (notifications are best-effort and never fail
# the build; if YEN.app is not running the notification is silently dropped).

zip_notify() {
    local title="$1"
    local detail="${2:-}"
    if [ "${YEN_ZIP_NOTIFY:-on}" = "off" ]; then
        return 0
    fi
    command -v osascript >/dev/null 2>&1 || return 0

    local payload="YEN Release: $title"
    if [ -n "$detail" ]; then
        payload="$payload
$detail"
    fi

    YEN_BUILD_PAYLOAD="$payload" \
    YEN_BUILD_USER_INFO="$(jq -cn \
        --arg schema_version "1" \
        --arg service "build" \
        --arg surface_id "${YEN_SURFACE_ID:-}" \
        '{schema_version:$schema_version, service:$service, surface_id:$surface_id}' 2>/dev/null || true)" \
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
    ' >/dev/null 2>&1 || true
    return 0
}
