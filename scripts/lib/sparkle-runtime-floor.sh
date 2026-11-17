#!/bin/bash
# Sparkle runtime security floor.
#
# Shared by yen-terminal/apply-overlays.sh (vendor time) and
# scripts/04-verify-branding.sh (release gate, build-release.sh step 7).
#
# WHY THIS EXISTS
# The Sparkle updater linked into YEN comes from SPM, pinned by the
# `XCRemoteSwiftPackageReference "Sparkle"` block in project.pbxproj. Upstream
# Ghostty used to declare `upToNextMajorVersion` from a 2.5.1 floor, which let a
# gitignored Package.resolved keep an older vulnerable runtime indefinitely, so
# apply-overlays.sh patched that floor up to the audited version
# (scripts/lib/patches/sparkle-runtime-floor.{old,new} — retired, deleted).
#
# Upstream e8aa0986 (ghostty-org/ghostty#14082) pins `exactVersion 2.9.6`. A
# content patch would only fight that pin, so the floor is now an ASSERTION:
# whatever requirement upstream ships must resolve to at least
# SPARKLE_RUNTIME_FLOOR, or the caller fails closed. That catches upstream
# loosening back to a broad floor, downgrading, or switching to a branch or
# revision pin that carries no comparable version. It never skips: a missing
# project file or a missing Sparkle block is a failure, not a clean result.
#
# Raise SPARKLE_RUNTIME_FLOOR and tests/123-release-script-hardening.test.ts in
# the same change whenever a Sparkle security release is audited. 2.9.5 and
# 2.9.6 were both security fixes (delta symlink hardening; root privilege
# escalation in the installer path).

SPARKLE_RUNTIME_FLOOR="2.9.6"

# version_ge A B -> exit 0 when dotted-numeric A >= B.
# bash 3.2 and BSD awk safe. Deliberately not `sort -V`: it is not part of the
# POSIX sort contract, and a lexical compare would rank 2.10.0 below 2.9.6.
version_ge() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        na = split(a, A, "."); nb = split(b, B, ".")
        n = (na > nb) ? na : nb
        for (i = 1; i <= n; i++) {
            x = (i <= na) ? A[i] + 0 : 0
            y = (i <= nb) ? B[i] + 0 : 0
            if (x > y) exit 0
            if (x < y) exit 1
        }
        exit 0
    }'
}

# assert_sparkle_runtime_floor <pbxproj> [<floor>]
# Exit 0 when the Sparkle SPM requirement in <pbxproj> resolves to at least
# <floor> (default SPARKLE_RUNTIME_FLOOR). Prints one ERROR block and returns 1
# otherwise. Every failure path is explicit so a caller under `set -e` aborts
# and a caller collecting issues can quote the first line.
assert_sparkle_runtime_floor() {
    local pbxproj="$1"
    local floor="${2:-$SPARKLE_RUNTIME_FLOOR}"
    local block kind version

    if [ ! -f "$pbxproj" ]; then
        echo "  ERROR: Sparkle runtime floor — project file missing: $pbxproj"
        return 1
    fi

    # The reference DEFINITION opens with `= {`. The product-dependency entry
    # also names `XCRemoteSwiftPackageReference "Sparkle"` but ends in `;`, so
    # it must not start the capture. Print from the definition through the
    # first `};`, which closes its `requirement = { ... };` block.
    block="$(awk '
        /XCRemoteSwiftPackageReference "Sparkle" \*\/ = [{]/ { in_block = 1 }
        in_block { print }
        in_block && /^[[:space:]]*[}];[[:space:]]*$/ { exit }
    ' "$pbxproj")"
    if [ -z "$block" ]; then
        echo "  ERROR: Sparkle runtime floor — no XCRemoteSwiftPackageReference \"Sparkle\" block in $pbxproj"
        echo "         Upstream moved or removed the Sparkle package reference; re-anchor this assertion."
        return 1
    fi

    kind="$(printf '%s\n' "$block" | awk '
        /^[[:space:]]*kind = [A-Za-z]+;/ { sub(/^[[:space:]]*kind = /, ""); sub(/;.*$/, ""); print; exit }')"
    version="$(printf '%s\n' "$block" | awk '
        /^[[:space:]]*(minimumVersion|version) = [0-9]+(\.[0-9]+)*;/ { sub(/^[[:space:]]*[A-Za-z]+ = /, ""); sub(/;.*$/, ""); print; exit }')"

    case "$kind" in
        exactVersion|upToNextMajorVersion|upToNextMinorVersion|versionRange) ;;
        *)
            echo "  ERROR: Sparkle runtime floor — requirement kind '${kind:-missing}' has no comparable version"
            echo "         (a branch or revision pin cannot prove the audited floor $floor)."
            return 1
            ;;
    esac
    if [ -z "$version" ]; then
        echo "  ERROR: Sparkle runtime floor — no version in the Sparkle requirement block ($kind) of $pbxproj"
        return 1
    fi
    if ! version_ge "$version" "$floor"; then
        echo "  ERROR: Sparkle runtime floor — $pbxproj resolves Sparkle $kind $version, below the audited floor $floor"
        echo "         Upstream loosened or downgraded its Sparkle pin, so a gitignored Package.resolved"
        echo "         could keep a vulnerable runtime. Port upstream's pin forward, or raise the floor deliberately."
        return 1
    fi

    echo "  ✓ Sparkle runtime floor: $kind $version >= $floor"
    return 0
}
