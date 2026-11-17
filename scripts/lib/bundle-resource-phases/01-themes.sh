#!/bin/bash
# Sourced by bundle-yen-resources.sh in the shared bundling shell.

# Replace icon with pre-compiled version
echo "  Replacing icon..."
cp -f "$YEN_TERMINAL_DIR/ghostty/macos/Yen.icns" "$APP_PATH/Contents/Resources/YEN.icns"
chmod 644 "$APP_PATH/Contents/Resources/YEN.icns"

# Bundle themes directory
# Themes must go under Resources/yen/themes/ to match the Zig runtime
# resources path resolution (resourcesdir.zig resolves to Resources/yen/)
echo "  Bundling themes..."
rm -rf "$APP_PATH/Contents/Resources/yen/themes"
rm -rf "$APP_PATH/Contents/Resources/yen/themes-full"
mkdir -p "$APP_PATH/Contents/Resources/yen/themes"

# Build output source + custom source. Curated manifest controls what ships.
BUNDLED_THEMES_DIR="$YEN_TERMINAL_DIR/ghostty/zig-out/share/yen/themes"
CUSTOM_THEMES_DIR="$CUSTOMIZATIONS_DIR/themes"
CURATED_THEME_MANIFEST="$CUSTOMIZATIONS_DIR/theme-curated-manifest.txt"
CURATED_THEME_TAGS="$CUSTOMIZATIONS_DIR/theme-curated-tags.txt"
THEME_CONTRAST_SCRIPT="$PROJECT_ROOT/scripts/theme-contrast.js"
if [ ! -f "$CURATED_THEME_MANIFEST" ]; then
    echo "ERROR: curated theme manifest missing: $CURATED_THEME_MANIFEST"
    exit 1
fi
if [ ! -f "$CURATED_THEME_TAGS" ]; then
    echo "ERROR: curated theme tags file missing: $CURATED_THEME_TAGS"
    exit 1
fi
if [ ! -f "$THEME_CONTRAST_SCRIPT" ]; then
    echo "ERROR: theme contrast script missing: $THEME_CONTRAST_SCRIPT"
    exit 1
fi
if ! command -v node >/dev/null 2>&1; then
    echo "ERROR: node is required for theme contrast normalization"
    exit 1
fi

MANIFEST_THEMES_FILE="$(mktemp)"
MANIFEST_MISSING_FILE="$(mktemp)"
CURATED_THEME_COPY_PLAN_FILE="$(mktemp)"
cleanup_theme_manifest_files() {
    rm -f "$MANIFEST_THEMES_FILE" "$MANIFEST_MISSING_FILE" "$CURATED_THEME_COPY_PLAN_FILE"
}
trap cleanup_theme_manifest_files EXIT

awk '
{
    line = $0
    sub(/^[[:space:]]+/, "", line)
    sub(/[[:space:]]+$/, "", line)
    if (line == "" || line ~ /^#/) next
    print line
}
' "$CURATED_THEME_MANIFEST" > "$MANIFEST_THEMES_FILE"

if [ ! -s "$MANIFEST_THEMES_FILE" ]; then
    echo "ERROR: curated theme manifest is empty: $CURATED_THEME_MANIFEST"
    exit 1
fi

DUPLICATE_MANIFEST_THEMES=$(awk '
{
    key = tolower($0)
    count[key]++
    if (count[key] == 2) {
        print $0
    }
}
' "$MANIFEST_THEMES_FILE")
if [ -n "$DUPLICATE_MANIFEST_THEMES" ]; then
    echo "ERROR: curated theme manifest has duplicate entries:"
    echo "$DUPLICATE_MANIFEST_THEMES" | sed 's/^/  - /'
    exit 1
fi

THEME_COUNT=$(wc -l < "$MANIFEST_THEMES_FILE" | tr -d ' ')
if [ "$THEME_COUNT" -lt 16 ] || [ "$THEME_COUNT" -gt 24 ]; then
    echo "ERROR: curated theme manifest count must stay within 16-24 (found $THEME_COUNT)"
    exit 1
fi

for required_theme in "YEN" "Retro Terminal" "CutePretzel"; do
    if ! grep -Fqx "$required_theme" "$MANIFEST_THEMES_FILE"; then
        echo "ERROR: curated theme manifest missing required theme: $required_theme"
        exit 1
    fi
done

if ! python3 - "$MANIFEST_THEMES_FILE" "$CURATED_THEME_TAGS" <<'PYEOF'; then
import sys

manifest_path, tags_path = sys.argv[1], sys.argv[2]
allowed = {"dark", "light", "retro", "neon", "low-contrast", "high-contrast"}

manifest = []
with open(manifest_path, "r", encoding="utf-8") as f:
    for line in f:
        theme = line.strip()
        if theme:
            manifest.append(theme)

tags_by_theme = {}
extra = []
with open(tags_path, "r", encoding="utf-8") as f:
    for raw in f:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "|" not in line:
            print(f"ERROR: invalid curated tag line (missing '|'): {line}")
            sys.exit(1)
        theme, raw_tags = line.split("|", 1)
        theme = theme.strip()
        tag_tokens = [t.strip().lower() for t in raw_tags.split(",") if t.strip()]
        if not theme:
            print(f"ERROR: invalid curated tag line (empty theme): {line}")
            sys.exit(1)
        if not tag_tokens:
            print(f"ERROR: curated theme '{theme}' has no category tags")
            sys.exit(1)
        invalid = sorted({tag for tag in tag_tokens if tag not in allowed})
        if invalid:
            print(f"ERROR: curated theme '{theme}' has unsupported tags: {', '.join(invalid)}")
            sys.exit(1)
        if theme.lower() in tags_by_theme:
            print(f"ERROR: duplicate curated tags entry for theme: {theme}")
            sys.exit(1)
        tags_by_theme[theme.lower()] = set(tag_tokens)

manifest_lower = {name.lower() for name in manifest}
missing = [name for name in manifest if name.lower() not in tags_by_theme]
for name in sorted(tags_by_theme.keys()):
    if name not in manifest_lower:
        extra.append(name)

if missing:
    print("ERROR: curated theme tags file is missing entries for:")
    for name in missing:
        print(f"  - {name}")
    sys.exit(1)

if extra:
    print("ERROR: curated theme tags file includes non-manifest themes:")
    for name in extra:
        print(f"  - {name}")
    sys.exit(1)
PYEOF
    exit 1
fi

resolve_theme_source() {
    local theme_name="$1"
    local base
    for base in "$CUSTOM_THEMES_DIR" "$BUNDLED_THEMES_DIR"; do
        [ -d "$base" ] || continue
        if [ -f "$base/$theme_name" ]; then
            printf '%s\n' "$base/$theme_name"
            return 0
        fi
        if [ -f "$base/$theme_name.yen" ]; then
            printf '%s\n' "$base/$theme_name.yen"
            return 0
        fi
    done
    return 1
}

normalize_theme_copy_manifest() {
    local manifest_path="$1"
    if [ ! -s "$manifest_path" ]; then
        return 0
    fi

    if ! node "$THEME_CONTRAST_SCRIPT" normalize-manifest "$manifest_path"; then
        echo "ERROR: theme contrast normalization failed for manifest: $manifest_path"
        exit 1
    fi
}

CURATED_CUSTOM_COUNT=0
CURATED_BUNDLED_COUNT=0
while IFS= read -r theme_name; do
    [ -n "$theme_name" ] || continue
    if ! theme_source="$(resolve_theme_source "$theme_name")"; then
        echo "$theme_name" >> "$MANIFEST_MISSING_FILE"
        continue
    fi

    printf '%s\t%s\n' \
        "$theme_source" \
        "$APP_PATH/Contents/Resources/yen/themes/$theme_name" >> "$CURATED_THEME_COPY_PLAN_FILE"
    if [[ "$theme_source" == "$CUSTOM_THEMES_DIR/"* ]]; then
        CURATED_CUSTOM_COUNT=$((CURATED_CUSTOM_COUNT + 1))
    else
        CURATED_BUNDLED_COUNT=$((CURATED_BUNDLED_COUNT + 1))
    fi
done < "$MANIFEST_THEMES_FILE"

if [ -s "$MANIFEST_MISSING_FILE" ]; then
    echo "ERROR: curated theme manifest references missing themes:"
    sed 's/^/  - /' "$MANIFEST_MISSING_FILE"
    exit 1
fi

normalize_theme_copy_manifest "$CURATED_THEME_COPY_PLAN_FILE"

# Rename upstream default theme to YEN branding so the shipped bundle
# does not leak Ghostty lineage in file paths / code-signature entries.
LEGACY_THEME_PATH="$APP_PATH/Contents/Resources/yen/themes/Ghostty Default Style Dark"
RENAMED_THEME_PATH="$APP_PATH/Contents/Resources/yen/themes/YEN Default Style Dark"
if [ -f "$LEGACY_THEME_PATH" ]; then
    mv -f "$LEGACY_THEME_PATH" "$RENAMED_THEME_PATH"
fi

chmod 644 "$APP_PATH/Contents/Resources/yen/themes/"*
echo "    Bundled $THEME_COUNT curated themes ($CURATED_BUNDLED_COUNT bundled + $CURATED_CUSTOM_COUNT custom)"
cp -f "$CURATED_THEME_MANIFEST" "$APP_PATH/Contents/Resources/yen/theme-curated-manifest.txt"
cp -f "$CURATED_THEME_TAGS" "$APP_PATH/Contents/Resources/yen/theme-curated-tags.txt"
chmod 644 "$APP_PATH/Contents/Resources/yen/theme-curated-manifest.txt"
chmod 644 "$APP_PATH/Contents/Resources/yen/theme-curated-tags.txt"

# Skins are retired in favor of themes. Remove any legacy bundled skin payload.
rm -rf "$APP_PATH/Contents/Resources/yen/skins"

# Verify themes landed at the correct path (must match Zig runtime resolution)
if [ ! -f "$APP_PATH/Contents/Resources/yen/themes/YEN" ]; then
    echo "ERROR: YEN theme not found at Resources/yen/themes/YEN"
    echo "Themes must be at Resources/yen/themes/ to match Zig runtime path resolution"
    exit 1
fi
# Guard against the old wrong path (Resources/themes/ without yen/ prefix)
if [ -d "$APP_PATH/Contents/Resources/themes" ]; then
    echo "ERROR: Found themes at wrong path Resources/themes/"
    echo "Themes must be at Resources/yen/themes/ (not Resources/themes/)"
    exit 1
fi

: # Keep optional final checks from becoming a failed source command.
