#!/bin/bash
# Sync the generated theme catalog section in _docs/02-design-system.md.
#
# Usage:
#   ./scripts/manual/26-sync-theme-catalog.sh
#   ./scripts/manual/26-sync-theme-catalog.sh --bundled-dir <dir> --custom-dir <dir>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DOC_PATH="$REPO_ROOT/_docs/02-design-system.md"
SETTINGS_THEME_CATALOG_PATH="$REPO_ROOT/yen-terminal/overlays/macos/Sources/Features/Settings/SettingsThemeCatalog.swift"
CUSTOM_THEMES_DIR="$REPO_ROOT/yen-terminal/customizations/themes"
BUNDLED_THEMES_DIR="$REPO_ROOT/yen-terminal/ghostty/zig-out/share/yen/themes"
BUNDLED_THEMES_DIR_FALLBACK="$REPO_ROOT/yen-terminal/ghostty/zig-out/YEN.app/Contents/Resources/yen/themes"
CURATED_THEME_MANIFEST="$REPO_ROOT/yen-terminal/customizations/theme-curated-manifest.txt"

print_usage() {
	cat <<'USAGE'
Usage: ./scripts/manual/26-sync-theme-catalog.sh [options]

Options:
  --doc <path>                Override docs file path (default: _docs/02-design-system.md)
  --settings-theme-catalog <path> Override SettingsThemeCatalog.swift path
  --settings-controller <path>   Backward-compatible alias for --settings-theme-catalog
  --bundled-dir <path>        Override bundled themes directory
  --custom-dir <path>         Override custom themes directory
  --curated-manifest <path>   Override curated theme manifest path
  -h, --help                  Show this help
USAGE
}

while [ $# -gt 0 ]; do
	case "$1" in
	--doc)
		shift
		if [ $# -eq 0 ]; then
			echo "ERROR: --doc requires a value"
			exit 1
		fi
		DOC_PATH="$1"
		;;
		--settings-theme-catalog | --settings-controller)
			option="$1"
			shift
			if [ $# -eq 0 ]; then
				echo "ERROR: $option requires a value"
				exit 1
			fi
			SETTINGS_THEME_CATALOG_PATH="$1"
		;;
	--bundled-dir)
		shift
		if [ $# -eq 0 ]; then
			echo "ERROR: --bundled-dir requires a value"
			exit 1
		fi
		BUNDLED_THEMES_DIR="$1"
		;;
	--custom-dir)
		shift
		if [ $# -eq 0 ]; then
			echo "ERROR: --custom-dir requires a value"
			exit 1
		fi
		CUSTOM_THEMES_DIR="$1"
		;;
	--curated-manifest)
		shift
		if [ $# -eq 0 ]; then
			echo "ERROR: --curated-manifest requires a value"
			exit 1
		fi
		CURATED_THEME_MANIFEST="$1"
		;;
	-h | --help)
		print_usage
		exit 0
		;;
	*)
		echo "ERROR: unknown option: $1"
		print_usage
		exit 1
		;;
	esac
	shift
done

if [ ! -f "$DOC_PATH" ]; then
	echo "ERROR: docs file not found: $DOC_PATH"
	exit 1
fi

if [ ! -f "$SETTINGS_THEME_CATALOG_PATH" ]; then
	echo "ERROR: settings theme catalog not found: $SETTINGS_THEME_CATALOG_PATH"
	exit 1
fi

if [ ! -d "$CUSTOM_THEMES_DIR" ]; then
	echo "ERROR: custom themes directory not found: $CUSTOM_THEMES_DIR"
	exit 1
fi

if [ ! -f "$CURATED_THEME_MANIFEST" ]; then
	echo "ERROR: curated theme manifest not found: $CURATED_THEME_MANIFEST"
	exit 1
fi

if [ ! -d "$BUNDLED_THEMES_DIR" ]; then
	if [ -d "$BUNDLED_THEMES_DIR_FALLBACK" ]; then
		BUNDLED_THEMES_DIR="$BUNDLED_THEMES_DIR_FALLBACK"
	else
		echo "ERROR: bundled themes directory not found"
		echo "Checked:"
		echo "  $BUNDLED_THEMES_DIR"
		echo "  $BUNDLED_THEMES_DIR_FALLBACK"
		echo "Run a desktop build first so bundled themes are generated."
		exit 1
	fi
fi

if ! grep -q "<!-- THEME_CATALOG_START -->" "$DOC_PATH"; then
	echo "ERROR: missing catalog start marker in $DOC_PATH"
	exit 1
fi

if ! grep -q "<!-- THEME_CATALOG_END -->" "$DOC_PATH"; then
	echo "ERROR: missing catalog end marker in $DOC_PATH"
	exit 1
fi

TAB="$(printf '\t')"

RAW_THEMES_FILE="$(mktemp)"
RANKED_THEMES_FILE="$(mktemp)"
EFFECTIVE_THEMES_FILE="$(mktemp)"
CURATED_THEMES_FILE="$(mktemp)"
FILTERED_EFFECTIVE_THEMES_FILE="$(mktemp)"
CURATED_MISSING_FILE="$(mktemp)"
PINNED_THEMES_FILE="$(mktemp)"
PINNED_MATCHED_NAMES_FILE="$(mktemp)"
PICKER_ORDER_FILE="$(mktemp)"
CATALOG_SECTION_FILE="$(mktemp)"
DOC_TEMP_FILE="$(mktemp)"

cleanup() {
	rm -f "$RAW_THEMES_FILE" "$RANKED_THEMES_FILE" "$EFFECTIVE_THEMES_FILE"
	rm -f "$CURATED_THEMES_FILE" "$FILTERED_EFFECTIVE_THEMES_FILE" "$CURATED_MISSING_FILE"
	rm -f "$PINNED_THEMES_FILE" "$PINNED_MATCHED_NAMES_FILE" "$PICKER_ORDER_FILE"
	rm -f "$CATALOG_SECTION_FILE" "$DOC_TEMP_FILE"
}
trap cleanup EXIT

collect_themes() {
	local dir="$1"
	local source="$2"

	if [ ! -d "$dir" ]; then
		return
	fi

	find "$dir" -mindepth 1 -maxdepth 1 -type f ! -name ".*" -print0 |
	while IFS= read -r -d '' file_path; do
		name="$(basename "$file_path")"
		name="${name%.yen}"
		if [ -n "$name" ]; then
			printf '%s\t%s\n' "$name" "$source"
		fi
	done
}

extract_pinned_themes() {
	awk '
	/private static let pinnedThemeOrder:[[:space:]]*\[/ { in_list = 1; next }
	in_list {
		line = $0
		while (match(line, /"[^"]+"/)) {
			item = substr(line, RSTART + 1, RLENGTH - 2)
			print item
			line = substr(line, RSTART + RLENGTH)
		}
		if ($0 ~ /\]/) {
			in_list = 0
		}
	}
	' "$SETTINGS_THEME_CATALOG_PATH"
}

display_path_for_docs() {
	local path="$1"

	case "$path" in
	"$REPO_ROOT"/*)
		printf '.%s' "${path#"$REPO_ROOT"}"
		;;
	*)
		printf '%s' "$path"
		;;
	esac
}

collect_themes "$BUNDLED_THEMES_DIR" "bundled" > "$RAW_THEMES_FILE"
collect_themes "$CUSTOM_THEMES_DIR" "custom" >> "$RAW_THEMES_FILE"

if [ ! -s "$RAW_THEMES_FILE" ]; then
	echo "ERROR: no themes found in source directories"
	exit 1
fi

awk -F "$TAB" -v OFS="$TAB" '
{
	priority = ($2 == "custom") ? 0 : 1
	print $1, $2, priority
}
' "$RAW_THEMES_FILE" |
LC_ALL=C sort -f -t "$TAB" -k1,1 -k3,3n > "$RANKED_THEMES_FILE"

awk -F "$TAB" -v OFS="$TAB" '
{
	key = tolower($1)
	if (!(key in seen)) {
		seen[key] = 1
		print $1, $2
	}
}
' "$RANKED_THEMES_FILE" > "$EFFECTIVE_THEMES_FILE"

awk '
{
	line = $0
	sub(/^[[:space:]]+/, "", line)
	sub(/[[:space:]]+$/, "", line)
	if (line == "" || line ~ /^#/) next
	print line
}
' "$CURATED_THEME_MANIFEST" > "$CURATED_THEMES_FILE"

if [ ! -s "$CURATED_THEMES_FILE" ]; then
	echo "ERROR: curated theme manifest is empty: $CURATED_THEME_MANIFEST"
	exit 1
fi

awk '
{
	key = tolower($0)
	count[key]++
	if (count[key] == 2) {
		print $0
	}
}
' "$CURATED_THEMES_FILE" > "$CURATED_MISSING_FILE"
if [ -s "$CURATED_MISSING_FILE" ]; then
	echo "ERROR: curated theme manifest has duplicate entries:"
	sed 's/^/  - /' "$CURATED_MISSING_FILE"
	exit 1
fi

: > "$CURATED_MISSING_FILE"
while IFS= read -r curated_theme; do
	[ -n "$curated_theme" ] || continue
	matched_row="$(awk -F "$TAB" -v target="$curated_theme" '
		tolower($1) == tolower(target) { print; exit }
	' "$EFFECTIVE_THEMES_FILE")"

	if [ -n "$matched_row" ]; then
		printf '%s\n' "$matched_row" >> "$FILTERED_EFFECTIVE_THEMES_FILE"
	else
		printf '%s\n' "$curated_theme" >> "$CURATED_MISSING_FILE"
	fi
done < "$CURATED_THEMES_FILE"

if [ -s "$CURATED_MISSING_FILE" ]; then
	echo "ERROR: curated theme manifest references themes that were not found in source directories:"
	sed 's/^/  - /' "$CURATED_MISSING_FILE"
	exit 1
fi

extract_pinned_themes > "$PINNED_THEMES_FILE"
if [ ! -s "$PINNED_THEMES_FILE" ]; then
	echo "ERROR: could not extract pinnedThemeOrder from $SETTINGS_THEME_CATALOG_PATH"
	exit 1
fi

: > "$PINNED_MATCHED_NAMES_FILE"
: > "$PICKER_ORDER_FILE"

while IFS= read -r pinned_theme; do
	if [ -z "$pinned_theme" ]; then
		continue
	fi

	matched_row="$(awk -F "$TAB" -v target="$pinned_theme" '
		tolower($1) == tolower(target) { print; exit }
	' "$FILTERED_EFFECTIVE_THEMES_FILE")"

	if [ -n "$matched_row" ]; then
		printf '%s\n' "$matched_row" >> "$PICKER_ORDER_FILE"
		printf '%s\n' "$matched_row" | awk -F "$TAB" '{ print $1 }' >> "$PINNED_MATCHED_NAMES_FILE"
	fi
done < "$PINNED_THEMES_FILE"

awk -F "$TAB" '
NR == FNR {
	seen[tolower($1)] = 1
	next
}
!(tolower($1) in seen) {
	print
}
' "$PINNED_MATCHED_NAMES_FILE" "$FILTERED_EFFECTIVE_THEMES_FILE" |
LC_ALL=C sort -f -t "$TAB" -k1,1 >> "$PICKER_ORDER_FILE"

TOTAL_EFFECTIVE_THEMES="$(wc -l < "$PICKER_ORDER_FILE" | tr -d ' ')"
TOTAL_CUSTOM_EFFECTIVE="$(awk -F "$TAB" '$2 == "custom" { c++ } END { print c + 0 }' "$PICKER_ORDER_FILE")"
TOTAL_BUNDLED_EFFECTIVE="$(awk -F "$TAB" '$2 == "bundled" { c++ } END { print c + 0 }' "$PICKER_ORDER_FILE")"
TOTAL_CUSTOM_SOURCE_FILES="$(find "$CUSTOM_THEMES_DIR" -mindepth 1 -maxdepth 1 -type f ! -name ".*" | wc -l | tr -d ' ')"
TOTAL_BUNDLED_SOURCE_FILES="$(find "$BUNDLED_THEMES_DIR" -mindepth 1 -maxdepth 1 -type f ! -name ".*" | wc -l | tr -d ' ')"
CURATED_THEME_COUNT="$(wc -l < "$CURATED_THEMES_FILE" | tr -d ' ')"

PINNED_ORDER="$(awk 'BEGIN { sep = "" } { printf "%s%s", sep, $0; sep = ", " } END { printf "" }' "$PINNED_THEMES_FILE")"
if [ -z "$PINNED_ORDER" ]; then
	PINNED_ORDER="(none)"
fi

GENERATED_AT_UTC="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
BUNDLED_THEMES_DIR_DISPLAY="$(display_path_for_docs "$BUNDLED_THEMES_DIR")"
CUSTOM_THEMES_DIR_DISPLAY="$(display_path_for_docs "$CUSTOM_THEMES_DIR")"
CURATED_THEME_MANIFEST_DISPLAY="$(display_path_for_docs "$CURATED_THEME_MANIFEST")"

{
	echo "### Master Theme Catalog (Generated)"
	echo
	echo "Generated by \`./scripts/manual/26-sync-theme-catalog.sh\` on $GENERATED_AT_UTC."
	echo
	echo "- Effective bundled themes (after custom overrides): $TOTAL_EFFECTIVE_THEMES"
	echo "- Effective themes sourced from \`customizations/themes\`: $TOTAL_CUSTOM_EFFECTIVE"
	echo "- Effective themes sourced from upstream bundled source: $TOTAL_BUNDLED_EFFECTIVE"
	echo "- Source files in \`customizations/themes\`: $TOTAL_CUSTOM_SOURCE_FILES"
	echo "- Source files in bundled directory: $TOTAL_BUNDLED_SOURCE_FILES"
	echo "- Curated manifest entries: $CURATED_THEME_COUNT"
	echo "- Picker pinned order: $PINNED_ORDER"
	echo "- Bundled source directory: \`$BUNDLED_THEMES_DIR_DISPLAY\`"
	echo "- Custom source directory: \`$CUSTOM_THEMES_DIR_DISPLAY\`"
	echo "- Curated manifest: \`$CURATED_THEME_MANIFEST_DISPLAY\`"
	echo
	echo "| # | Theme | Source |"
	echo "|---|-------|--------|"

	index=1
	while IFS="$TAB" read -r theme_name theme_source; do
		if [ -z "$theme_name" ]; then
			continue
		fi

		theme_name_safe="$(printf '%s' "$theme_name" | sed -e 's/`/\\`/g' -e 's/|/\\|/g')"
		printf '| %s | `%s` | %s |\n' "$index" "$theme_name_safe" "$theme_source"
		index=$((index + 1))
	done < "$PICKER_ORDER_FILE"
} > "$CATALOG_SECTION_FILE"

awk -v start_marker="<!-- THEME_CATALOG_START -->" -v end_marker="<!-- THEME_CATALOG_END -->" -v catalog_file="$CATALOG_SECTION_FILE" '
$0 == start_marker {
	print
	while ((getline line < catalog_file) > 0) {
		print line
	}
	in_generated_block = 1
	next
}
$0 == end_marker {
	in_generated_block = 0
	print
	next
}
!in_generated_block {
	print
}
' "$DOC_PATH" > "$DOC_TEMP_FILE"

mv "$DOC_TEMP_FILE" "$DOC_PATH"

echo "Theme catalog updated: $DOC_PATH"
echo "Effective theme count: $TOTAL_EFFECTIVE_THEMES"
