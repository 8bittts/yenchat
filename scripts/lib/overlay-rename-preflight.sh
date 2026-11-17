#!/bin/bash
# Require the renamed layout when a rerun has fewer rename operations.

verify_overlay_renames() {
    if [ "$FILES_RENAMED" -lt 11 ]; then
        OLD_SRC_BUILD_RENAMES=0
        if [ -d "src/build" ] && find "src/build" -maxdepth 1 -type f -name 'Ghostty*.zig' | grep -q .; then
            OLD_SRC_BUILD_RENAMES=1
        fi

        OLD_MDGEN_RENAMES=0
        if [ -d "src/build/mdgen" ] && find "src/build/mdgen" -maxdepth 1 -type f -name '*ghostty*' | grep -q .; then
            OLD_MDGEN_RENAMES=1
        fi

        if [ "$OLD_SRC_BUILD_RENAMES" -eq 0 ] && \
            [ "$OLD_MDGEN_RENAMES" -eq 0 ] && \
            [ -f "src/cli/yen.zig" ] && \
            [ -f "src/main_yen.zig" ] && \
            [ -f "src/terminfo/yen.zig" ] && \
            [ -d "include/yen" ] && \
            [ -f "include/yen.h" ] && \
            [ ! -f "src/cli/ghostty.zig" ] && \
            [ ! -f "src/main_ghostty.zig" ] && \
            [ ! -f "src/terminfo/ghostty.zig" ] && \
            [ ! -d "include/ghostty" ] && \
            [ ! -f "include/ghostty.h" ] && \
            [ -d "macos/YEN.xcodeproj" ] && \
            [ ! -d "macos/Ghostty.xcodeproj" ] && \
            [ -f "macos/YEN-Info.plist" ] && \
            [ ! -f "macos/Ghostty-Info.plist" ] && \
            [ -f "macos/YEN.entitlements" ] && \
            [ -f "macos/YENDebug.entitlements" ] && \
            [ -f "macos/YENReleaseLocal.entitlements" ] && \
            [ ! -f "macos/Ghostty.entitlements" ] && \
            [ ! -f "macos/GhosttyDebug.entitlements" ] && \
            [ ! -f "macos/GhosttyReleaseLocal.entitlements" ] && \
            [ ! -d "macos/Sources/Ghostty" ] && \
            [ ! -f "macos/Sources/App/ghostty-bridging-header.h" ] && \
            [ ! -f "macos/YEN.xcodeproj/xcshareddata/xcschemes/Ghostty.xcscheme" ] && \
            [ -f "macos/Sources/Features/Custom App Icon/ColorizedYENIcon.swift" ] && \
            [ ! -f "macos/Sources/Features/Custom App Icon/ColorizedGhosttyIcon.swift" ] && \
            [ ! -f "macos/Sources/Features/Custom App Icon/ColorizedGhosttyIconImage.swift" ] && \
            [ ! -f "macos/Sources/Features/Custom App Icon/ColorizedGhosttyIconView.swift" ]; then
            echo "    File rename pass already applied (idempotent/converged state)"
            overlay_note_skipped
        else
            echo "  ERROR: File rename pass renamed too few paths ($FILES_RENAMED < 11)."
            echo "         Upstream structure may have changed; inspect rename anchors."
            exit 1
        fi
    fi

    if [ -d "macos/Sources/Features/AppleScript" ] || [ -f "macos/Ghostty.sdef" ] || [ -f "macos/YEN.sdef" ]; then
        if [ ! -f "macos/YEN.sdef" ]; then
            echo "  ERROR: AppleScript dictionary rename missing — expected macos/YEN.sdef"
            exit 1
        fi
        if [ ! -f "macos/Sources/Features/AppleScript/YEN.Input.Mods+AppleScript.swift" ]; then
            echo "  ERROR: AppleScript modifiers extension rename missing — expected YEN.Input.Mods+AppleScript.swift"
            exit 1
        fi
        if [ -f "macos/Ghostty.sdef" ] || [ -f "macos/Sources/Features/AppleScript/Ghostty.Input.Mods+AppleScript.swift" ]; then
            echo "  ERROR: AppleScript rename pass left stale Ghostty AppleScript paths in place"
            exit 1
        fi
    fi
}
