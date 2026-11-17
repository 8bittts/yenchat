#!/bin/bash
# Paths whose changes require the native component regression slice.

is_component_xcode_relevant_path() {
    local changed_path="$1"

    case "$changed_path" in
        yen-terminal/overlays/macos/*|\
        yen-terminal/overlays/patches/*|\
        yen-terminal/overlays/build.zig|\
        yen-terminal/overlays/src/*|\
        yen-terminal/apply-overlays.sh|\
        scripts/lib/overlay-*|\
        scripts/lib/patches/*|\
        scripts/lib/patch-file.py|\
        scripts/lib/native-component-paths.sh|\
        yen-terminal/.ghostty-baseline|\
        yen-terminal/VENDOR_INFO.txt)
            return 0
            ;;
    esac

    return 1
}
