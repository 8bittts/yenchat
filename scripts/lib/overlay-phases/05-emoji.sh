#!/bin/bash
# Sourced by apply-overlays.sh; inherits its working directory and fail-fast mode.

# ============================================================================
# Remove Ghost Emoji from Window Titles
# ============================================================================

cd ghostty

# XIB files
# Glob all XIBs in Window Styles (catches future upstream additions like Tahoe)
while IFS= read -r -d '' xib; do
    sed -i '' 's/title="👻 YEN"/title="YEN"/g' "$xib"
    sed -i '' 's/👻 //g' "$xib"
done < <(
    find "macos/Sources/Features/Terminal/Window Styles" \
        -name "*.xib" \
        -not -name ".!*" \
        -not -name "._*" \
        -not -path "*/.zig-cache/*" \
        -not -path "*/zig-pkg/*" \
        -print0 2>/dev/null
)

# Also handle QuickTerminal XIB
if [ -f "macos/Sources/Features/QuickTerminal/QuickTerminal.xib" ]; then
    sed -i '' 's/title="👻 YEN"/title="YEN"/g' "macos/Sources/Features/QuickTerminal/QuickTerminal.xib"
    sed -i '' 's/👻 //g' "macos/Sources/Features/QuickTerminal/QuickTerminal.xib"
fi

# Swift files. Fourth bulk pass — same mtime hazard as the three above: this filter
# matches BaseTerminalController.swift and every YEN/Surface*.swift, which are among the
# most widely depended-on files in the target, so rewriting them unconditionally forced a
# broad recompile on every run even when no ghost emoji remained.
GHOST_EMOJI_FILE_LIST="$(mktemp -t yen-ghostemoji-all)"
find macos/Sources -name "*.swift" \
    -not -name ".!*" \
    -not -name "._*" \
    -not -path "*/.zig-cache/*" \
    -not -path "*/zig-pkg/*" \
    \( \
    -path "*Terminal/Window Styles*" -o \
    -name "BaseTerminalController.swift" -o \
    -path "*YEN/Surface*" -o \
    -path "*YEN/SurfaceView*" \
\) -print0 > "$GHOST_EMOJI_FILE_LIST"

rewrite_files_containing "Ghost emoji" '👻' "$GHOST_EMOJI_FILE_LIST" \
    -e 's/"👻 YEN"/"YEN"/g' \
    -e 's/"👻"/"YEN"/g'

# Zig CLI files
ZIG_CLI_FILES=(
    "src/cli/crash_report.zig"
    "src/cli/list_themes.zig"
)

for zig in "${ZIG_CLI_FILES[@]}"; do
    if [ -f "$zig" ]; then
        sed -i '' \
            -e 's/"👻 YEN Theme Preview 👻"/"YEN Theme Preview"/g' \
            -e 's/"No crash reports! 👻\\n"/"No crash reports!\\n"/g' \
            "$zig"
    fi
done

cd "$SCRIPT_DIR"
