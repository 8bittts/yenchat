#!/bin/bash
# Sourced by bundle-yen-resources.sh in the shared bundling shell.

# Rebrand locale catalogs so shipped .mo payloads do not surface Ghostty UI strings.
LOCALE_CATALOG_COUNT=0
if command -v msgunfmt >/dev/null 2>&1 && command -v msgfmt >/dev/null 2>&1; then
    while IFS= read -r -d '' locale_mo; do
        LOCALE_CATALOG_COUNT=$((LOCALE_CATALOG_COUNT + 1))
        locale_po_in="$(mktemp "${TMPDIR:-/tmp}/yen-locale-in.XXXXXX")"
        locale_po_out="$(mktemp "${TMPDIR:-/tmp}/yen-locale-out.XXXXXX")"

        if ! msgunfmt "$locale_mo" > "$locale_po_in"; then
            echo "ERROR: msgunfmt failed for locale catalog: $locale_mo"
            rm -f "$locale_po_in" "$locale_po_out"
            exit 1
        fi

        sed \
            -e 's/com\.mitchellh\.ghostty/com.yenchat.yen/g' \
            -e 's/Ghostty/YEN/g' \
            -e 's/ghostty/yen/g' \
            "$locale_po_in" > "$locale_po_out"

        if ! msgfmt --check --output-file="$locale_mo" "$locale_po_out"; then
            echo "ERROR: msgfmt failed for locale catalog: $locale_mo"
            rm -f "$locale_po_in" "$locale_po_out"
            exit 1
        fi

        rm -f "$locale_po_in" "$locale_po_out"
    done < <(find "$APP_PATH/Contents/Resources/locale" -type f -name "com.yenchat.yen.mo" -print0 2>/dev/null)
else
    echo "ERROR: msgunfmt/msgfmt are required to rebrand locale catalogs"
    exit 1
fi

if [ "$LOCALE_CATALOG_COUNT" -eq 0 ]; then
    echo "ERROR: no locale catalogs found for resource verification"
    exit 1
fi

# Fail closed if locale catalogs still contain Ghostty branding.
LOCALE_BRAND_HITS=""
while IFS= read -r -d '' locale_mo; do
    locale_strings=$(strings "$locale_mo" 2>/dev/null || true)
    if echo "$locale_strings" | grep -Eiq "ghostty|com\\.mitchellh\\.ghostty"; then
        LOCALE_BRAND_HITS="$LOCALE_BRAND_HITS
$locale_mo"
    fi
done < <(find "$APP_PATH/Contents/Resources/locale" -type f -name "com.yenchat.yen.mo" -print0 2>/dev/null)
if [ -n "$LOCALE_BRAND_HITS" ]; then
    echo "ERROR: Ghostty branding residue detected in locale catalogs:"
    echo "$LOCALE_BRAND_HITS" | sed '/^$/d'
    exit 1
fi

# Fail closed if Ghostty-branded filenames remain in shipped shell/theme assets.
LEGACY_NAME_HITS=$(
    find \
        "$APP_PATH/Contents/Resources/yen/shell-integration" \
        "$APP_PATH/Contents/Resources/yen/themes" \
        -type f -iname "*ghostty*" 2>/dev/null || true
)
if [ -n "$LEGACY_NAME_HITS" ]; then
    echo "ERROR: Legacy Ghostty filename residue detected in bundled resources:"
    echo "$LEGACY_NAME_HITS"
    exit 1
fi

echo "    Verified $LOCALE_CATALOG_COUNT locale catalogs"

: # Keep optional final checks from becoming a failed source command.
