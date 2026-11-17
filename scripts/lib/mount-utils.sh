#!/bin/bash
# mount-utils.sh — shared helpers for cleaning up stale YEN DMG mounts

detach_stale_yen_mounts() {
    hdiutil info 2>/dev/null | awk '
        /^image-path[[:space:]]*:/ {
            image_path = $0
            sub(/^image-path[[:space:]]*:[[:space:]]*/, "", image_path)
            is_yen_dmg = (tolower(image_path) ~ /\/yen[^\/]*\.dmg$/)
            next
        }
        /^mount-point[[:space:]]*:/ {
            mount_point = $0
            sub(/^mount-point[[:space:]]*:[[:space:]]*/, "", mount_point)
            if (is_yen_dmg && mount_point ~ /^\/Volumes\/YEN( [0-9]+)?$/) {
                print mount_point
            }
        }
    ' | while IFS= read -r stale_vol; do
        [ -z "$stale_vol" ] && continue
        hdiutil detach "$stale_vol" -force 2>/dev/null || true
    done
}
