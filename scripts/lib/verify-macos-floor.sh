#!/bin/bash
# Check the packaged YEN targets. Vendor frameworks and tools have their own floors.
set -euo pipefail
source "$(dirname "$0")/../../yen-cli/lib/macos-version.sh"
contents="$1/Contents"
for plist in "$contents/Info.plist" "$contents/PlugIns/DockTilePlugin.plugin/Contents/Info.plist"; do
    actual=$(plutil -extract LSMinimumSystemVersion raw "$plist")
    if [[ "$actual" != "$YEN_MIN_MACOS" ]]; then
        echo "ERROR: $plist requires $actual, expected $YEN_MIN_MACOS" >&2
        exit 1
    fi
done
for binary in "$contents/MacOS/yen" "$contents/PlugIns/DockTilePlugin.plugin/Contents/MacOS/DockTilePlugin" \
              "$contents/Resources/bin/yen-pdfthumb" "$contents/Resources/bin/yen-svgthumb" "$contents/Resources/bin/yen-vidthumb"; do
    arches=$(lipo -archs "$binary")
    [[ " $arches " == *" arm64 "* ]] || { echo "ERROR: Missing arm64 in $binary" >&2; exit 1; }
    for arch in $arches; do
        actual=$(xcrun vtool -arch "$arch" -show-build "$binary" | awk '$1 == "minos" {print $2}')
        if [[ "$actual" != "$YEN_MIN_MACOS" ]]; then
            echo "ERROR: $binary ($arch) requires '$actual', expected $YEN_MIN_MACOS" >&2
            exit 1
        fi
    done
done
echo "Verified macOS $YEN_MIN_MACOS for YEN, the Dock plug-in, and all three thumbnail helpers."
