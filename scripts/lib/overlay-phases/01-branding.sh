#!/bin/bash
# Sourced by apply-overlays.sh; inherits its working directory and fail-fast mode.

# ============================================================================
# Apply Global Branding (Ghostty → YEN)
# ============================================================================

cd ghostty

# Rewrite in place, but only the files that can actually match.
#
# `sed` on a token-free file is a no-op by definition, yet `sed -i ''` still
# rewrites the file and bumps its mtime — and the Swift driver keys incremental
# build inputs on stat signature. The three bulk passes below used to rewrite
# every candidate file unconditionally, so a one-file overlay edit recompiled
# the entire macOS target on every `01-macos-smoke.sh --fast` run.
#
# $2 (the token pattern) MUST stay the exact union of the `sed` left-hand sides
# passed in $4.., or this would skip a file the pass is supposed to rewrite.
#
# NUL-safe end to end: BSD `grep` ignores `-Z` but honours the long `--null`,
# so filenames never round-trip through newline-delimited text.
#
# Usage: rewrite_files_containing <label> <token-pattern> <nul-file-list> <sed args...>

# Global text replacement for user-visible branding.
# `s/ghostty/yen/g` runs before the `com.mitchellh.` rules, so a file holding
# only `com.mitchellh.<x>` is still caught by the trailing alternative.
BRANDING_FILE_LIST="$(mktemp -t yen-branding-all)"
find . -type f \( -name "*.swift" -o -name "*.zig" -o -name "*.xib" \
                  -o -name "*.sdef" \
                  -o -name "*.h" -o -name "*.c" -o -name "*.m" -o -name "*.cpp" \
                  -o -name "*.plist" -o -name "*.pbxproj" -o -name "*.xcscheme" \
                  -o -name "*.xctestplan" \
                  -o -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "*.blp" \
                  -o -name "*.fish" -o -name "*.elv" -o -name "*.nu" \) \
  -not -name ".!*" \
  -not -name "._*" \
  -not -path "*/.zig-cache/*" \
  -not -path "*/zig-pkg/*" \
  -not -path "*/.backup/*" \
  -not -path "*/zig-cache/*" \
  -not -path "*/zig-out/*" \
  -not -path "*/macos/build/*" \
  -not -name "build.zig.zon" \
  -not -name "build.zig.zon.json" \
  -print0 > "$BRANDING_FILE_LIST"

rewrite_files_containing "Branding" 'GHOSTTY|Ghostty|ghostty|com\.mitchellh\.' "$BRANDING_FILE_LIST" \
    -e 's/GHOSTTY/YEN/g' \
    -e 's/Ghostty/YEN/g' \
    -e 's/ghostty/yen/g' \
    -e 's/com\.mitchellh\.yen/com.yenchat.yen/g' \
    -e 's/com\.mitchellh\./com.yenchat./g'

# Spot-check: verify critical branding substitutions landed
if ! grep -rq 'com\.yenchat\.yen' macos/; then
    echo "  ERROR: Bundle ID branding failed — 'com.yenchat.yen' not found in macos/"
    exit 1
fi

if [ -f "macos/Ghostty.sdef" ] && grep -q "Ghostty" "macos/Ghostty.sdef"; then
    echo "  ERROR: AppleScript dictionary branding incomplete — macos/Ghostty.sdef still contains Ghostty residue"
    exit 1
fi

# ============================================================================
# Fix pbxproj paths for Sources/YEN/ (files keep Ghostty prefix on disk)
# ============================================================================
# The branding sed renames Ghostty → YEN in pbxproj path references, but
# PBXFileSystemSynchronizedBuildFileExceptionSet paths must match actual filenames.
# Files in Sources/YEN/ keep their Ghostty*.swift names; only their CONTENT is branded.
# GhosttyPackageMeta.swift (enum YEN) is compiled in BOTH the main target and
# DockTilePlugin — do NOT exclude the on-disk Ghostty* files from the main
# macOS target. Only the YEN-prefixed compatibility aliases stay excluded.
# Check both pre-rename and post-rename xcodeproj paths.
# On first run from 10-update-ghostty.sh, the directory is still Ghostty.xcodeproj
# because file renames run in the next phase. On subsequent idempotent runs,
# it's already YEN.xcodeproj.
restore_overlay_project_paths

# Remove stale Package.swift if overlay copy placed one (retired overlay file —
# upstream split GhosttyPackage.swift into GhosttyPackageMeta + GhosttyPackage
# and our custom notifications now live in YENCustomNotifications.swift)
if [ -f "macos/Sources/YEN/Package.swift" ]; then
    rm "macos/Sources/YEN/Package.swift"
    echo "    Removed stale Package.swift from build tree"
    overlay_note_applied
fi

# ============================================================================
# Restore Dependency URLs & Fix User-Facing URLs
# ============================================================================

rewrite_overlay_urls
