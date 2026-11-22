#!/bin/bash
# Third-party license notices shipped in YEN.app.
#
# MIT and Apache-2.0 require their notice in every copy of the software, so
# each bundled third-party component has a text file under
# yen-terminal/customizations/notices/, and the bundle phase
# (scripts/lib/bundle-resource-phases/02-cli-resources.sh) copies them to
# Contents/Resources/Notices/.
#
# The vendor baselines are the list of components: one notice per
# yen-terminal/.<name>-baseline, named <name>.txt. The engine's notice is named
# TerminalEngine.txt, because the fingerprint gate rejects the upstream name in
# a bundle path. The notice text names the copyright holder, as the license
# requires; that gate reads paths and binaries, not text resources.
#
# Each function prints one line per issue and returns 1 when it printed any.

THIRD_PARTY_NOTICES_SUBDIR="yen-terminal/customizations/notices"

third_party_notice_name() {
    case "$1" in
        ghostty) echo "TerminalEngine.txt" ;;
        *) echo "$1.txt" ;;
    esac
}

# Prints the notice file name each vendor baseline requires.
third_party_expected_notices() {
    local repo_root="$1" baseline component
    for baseline in "$repo_root"/yen-terminal/.*-baseline; do
        [ -f "$baseline" ] || continue
        component="$(basename "$baseline")"
        component="${component#.}"
        component="${component%-baseline}"
        third_party_notice_name "$component"
    done
}

# Source check: every vendored component has a non-empty notice.
third_party_notices_source_issues() {
    local repo_root="$1" expected count=0 status=0
    while IFS= read -r expected; do
        [ -n "$expected" ] || continue
        count=$((count + 1))
        if [ ! -s "$repo_root/$THIRD_PARTY_NOTICES_SUBDIR/$expected" ]; then
            echo "license notice missing for a vendored component: $THIRD_PARTY_NOTICES_SUBDIR/$expected"
            status=1
        fi
    done < <(third_party_expected_notices "$repo_root")
    if [ "$count" -eq 0 ]; then
        echo "license notice check found no vendor baselines under yen-terminal/"
        status=1
    fi
    return "$status"
}

# Bundle check: every tracked notice is in the app, byte for byte.
third_party_notices_bundle_issues() {
    local repo_root="$1" app_path="$2" notice name count=0 status=0
    local bundled_dir="$app_path/Contents/Resources/Notices"
    for notice in "$repo_root/$THIRD_PARTY_NOTICES_SUBDIR"/*.txt; do
        [ -f "$notice" ] || continue
        count=$((count + 1))
        name="$(basename "$notice")"
        if [ ! -f "$bundled_dir/$name" ]; then
            echo "license notice not bundled: Contents/Resources/Notices/$name"
            status=1
        elif ! cmp -s "$notice" "$bundled_dir/$name"; then
            echo "bundled license notice differs from its source: Contents/Resources/Notices/$name"
            status=1
        fi
    done
    if [ "$count" -eq 0 ]; then
        echo "license notice check found no tracked notices in $THIRD_PARTY_NOTICES_SUBDIR"
        status=1
    fi
    return "$status"
}
