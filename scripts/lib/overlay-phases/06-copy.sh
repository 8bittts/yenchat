#!/bin/bash
# Sourced by apply-overlays.sh; inherits its working directory and fail-fast mode.

# ============================================================================
# Fail Closed on AppleScript Overlay Drift Before Overlay Copy
# ============================================================================
# `overlays/macos/YEN.sdef` must stay byte-for-byte aligned with the branded
# upstream dictionary produced by the rename/branding pass. If it drifts, the
# overlay copy would silently overwrite new upstream AppleScript contract
# changes and future vendor bumps would look green while dropping semantics.
verify_overlay_applescript_dictionary

# ============================================================================
# Copy Overlay Files (after branding, before post-copy patches)
# ============================================================================

if [ -d "overlays" ]; then
    cp -Rp overlays/* ghostty/
else
    echo "  ERROR: overlays/ directory not found"
    exit 1
fi

# ============================================================================
# Patch-Target Preflight (fail closed on upstream relocation)
# ============================================================================
# Every manifest path is anchored by a declared patch operation.
# Individually, each operation already fails closed on a missing target — but it
# fails on the FIRST one, so an upstream restructure that moves a whole source
# directory would take one vendor run per moved file to discover. Validate the
# whole set here instead and report every casualty at once.
#
# Runs after branding and after the overlay copy, so the paths are in their
# final post-rename shape (upstream macos/Sources/Ghostty/ is macos/Sources/YEN/
# by this point) and overlay-supplied targets are already in place.
#
# tests/45-overlay-patching.test.ts asserts the manifest stays equal to the set of
# declared patch targets, so a new patch cannot skip preflight coverage.
verify_overlay_patch_targets "$REPO_ROOT/scripts/lib/overlay-patch-targets.txt"

# Overlay deletions do not propagate through the plain recursive copy above.
# Remove retired chat observer sources explicitly so stale files do not linger
# in ghostty/macos between builds.
remove_overlay_retired_files chat

# Keep the App Intents permission helper byte-aligned with the overlay source.
# This file now carries the test-only prompt planning seams that native
# verification exercises directly, so fail closed if the mirrored build tree
# ever drifts from the overlay after the bulk copy step.
INTENT_PERMISSION_OVERLAY="overlays/macos/Sources/Features/App Intents/IntentPermission.swift"
INTENT_PERMISSION_BUILD="ghostty/macos/Sources/Features/App Intents/IntentPermission.swift"
if [ -f "$INTENT_PERMISSION_OVERLAY" ]; then
    cp -p "$INTENT_PERMISSION_OVERLAY" "$INTENT_PERMISSION_BUILD"
    if ! cmp -s "$INTENT_PERMISSION_OVERLAY" "$INTENT_PERMISSION_BUILD"; then
        echo "  ERROR: IntentPermission overlay drifted during native sync"
        exit 1
    fi
fi

# Remove retired settings and geometry tests from prior overlay copies.
remove_overlay_retired_files settings-tests

# The Studio Settings redesign replaced the sidebar, the per-tab views, the
# search index and their tests. Remove the old copies so the synchronized Xcode
# group does not compile two Settings panels.
remove_overlay_retired_files settings-studio

# Fail closed if an existing generated tree still contains the retired YEN
# Quick Terminal geometry takeover. A clean vendor refresh supplies these files;
# overlays must never silently preserve window-anchor sizing across rebuilds.
verify_overlay_native_geometry

# Keep Ghostty's Quick Terminal positioning/focus lifecycle vendor-native while
# routing its two animation groups through the same YEN motion envelope used by
# Git Drawer, transient Tab Sidebar, and Scratchpad. This patch changes only the
# animation runner and duration normalization; frame calculations remain owned
# by QuickTerminalPosition and QuickTerminalScreenStateCache.
QUICK_TERMINAL_CONTROLLER="ghostty/macos/Sources/Features/QuickTerminal/QuickTerminalController.swift"
apply_overlay_patch quick-terminal-shared-panel-motion

# Upstream's TerminalRestorableTests targets their version-7 / minimumVersion-5
# migration story (introduced in 5b89671d/c74f6d56). Our overlay carries an
# independent TerminalRestorableState (version 9 + splitPaneLabels) without the
# InternalState pattern, so the upstream test references types/properties that
# don't exist on our class. We have our own TerminalRestorableVersionTests for
# our migration coverage; drop the upstream file before Xcode auto-discovers it.
remove_overlay_retired_files restorable-tests

# Xcode's DockTilePlugin target can still synthesize legacy YEN-prefixed source
# paths for these two shared files even after the synchronized pbxproj member
# paths are rewritten to the on-disk Ghostty* filenames. Keep compatibility
# aliases in the mirrored build tree so targeted xcodebuild invocations stay
# deterministic without reintroducing stale pbxproj paths.
YEN_SHARED_SOURCES_DIR="ghostty/macos/Sources/YEN"
if [ -d "$YEN_SHARED_SOURCES_DIR" ]; then
    rm -f "$YEN_SHARED_SOURCES_DIR/YEN.ConfigTypes.swift"
    rm -f "$YEN_SHARED_SOURCES_DIR/YENPackageMeta.swift"

    if [ -f "$YEN_SHARED_SOURCES_DIR/Ghostty.ConfigTypes.swift" ]; then
        ln -s "Ghostty.ConfigTypes.swift" "$YEN_SHARED_SOURCES_DIR/YEN.ConfigTypes.swift"
    fi
    if [ -f "$YEN_SHARED_SOURCES_DIR/GhosttyPackageMeta.swift" ]; then
        ln -s "GhosttyPackageMeta.swift" "$YEN_SHARED_SOURCES_DIR/YENPackageMeta.swift"
    fi
fi
