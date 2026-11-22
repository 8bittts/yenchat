#!/bin/bash
# Branding helpers called from the generated Ghostty root.

rewrite_files_containing() {
    local label="$1"
    local token_pattern="$2"
    local file_list="$3"
    shift 3

    # Fail closed: an empty candidate set means the vendor tree is missing or the
    # find filters went stale. Rewriting nothing must never look like success.
    if [ ! -s "$file_list" ]; then
        echo "  ERROR: ${label} scan matched zero candidate files — vendor tree missing or find filters stale"
        exit 1
    fi

    local hit_list
    hit_list="$(mktemp -t yen-rewrite-hits)"

    # `xargs` exits 123 when any batched `grep` finds nothing in its batch, so its
    # status cannot distinguish "no match here" from a real failure. Validate by
    # content instead; the per-pass spot-checks downstream are the fail-closed gate.
    xargs -0 grep -l --null -E "$token_pattern" < "$file_list" > "$hit_list" 2>/dev/null || true

    local total_count hit_count
    total_count=$(tr -cd '\0' < "$file_list" | wc -c | tr -d ' ')
    hit_count=$(tr -cd '\0' < "$hit_list" | wc -c | tr -d ' ')

    if [ -s "$hit_list" ]; then
        xargs -0 sed -i '' "$@" < "$hit_list"
    fi

    echo "    ${label}: rewrote ${hit_count} of ${total_count} candidate files"
    rm -f "$hit_list" "$file_list"
}

# The sed data owns both substitutions and the exact token filter.
rewrite_overlay_url_files() {
    local label="$1" file_list="$2" rules="$3" token_pattern
    if [ ! -s "$rules" ]; then
        echo "  ERROR: URL rewrite rules missing or empty: $rules" >&2
        return 1
    fi
    token_pattern=$(awk -F '|' '
        NF != 4 || $1 != "s" || $4 != "g" || $2 == "" { exit 1 }
        { if (NR > 1) printf "|"; printf "%s", $2 }
    ' "$rules") || { echo "  ERROR: Invalid URL rewrite rule: $rules" >&2; return 1; }
    rewrite_files_containing "$label" "$token_pattern" "$file_list" -f "$rules"
}

restore_overlay_project_paths() {
PBXPROJ_PATH=""
if [ -f "macos/YEN.xcodeproj/project.pbxproj" ]; then
    PBXPROJ_PATH="macos/YEN.xcodeproj/project.pbxproj"
elif [ -f "macos/Ghostty.xcodeproj/project.pbxproj" ]; then
    PBXPROJ_PATH="macos/Ghostty.xcodeproj/project.pbxproj"
fi
if [ -n "$PBXPROJ_PATH" ]; then
    # RETIRED: Sparkle runtime security floor content patch. Upstream e8aa0986
    # (ghostty-org/ghostty#14082) pins the SPM requirement to
    # `exactVersion 2.9.6`, which supersedes the 2.5.1 -> 2.9.4 `minimumVersion`
    # patch YEN carried (scripts/lib/patches/sparkle-runtime-floor.{old,new},
    # deleted). Patching the block again would only fight upstream's pin, so
    # the floor is now a fail-closed assertion: whatever requirement upstream
    # ships must resolve to at least SPARKLE_RUNTIME_FLOOR
    # (scripts/lib/sparkle-runtime-floor.sh), or this run aborts before any
    # tracking file is written. 04-verify-branding.sh repeats the assertion as
    # a release gate.
    assert_sparkle_runtime_floor "$PBXPROJ_PATH" "$SPARKLE_RUNTIME_FLOOR" || exit 1

    PBXPROJ_RESTORE_PATHS=(
        'App/AppDelegate+YEN\.swift|App/AppDelegate+Ghostty.swift'
        'Features/App Intents/YENIntentError\.swift|Features/App Intents/GhosttyIntentError.swift'
        'Features/Settings/SettingsView\.swift|Features/Settings/SettingsPanel.swift'
        'YEN/YEN\.ConfigTypes\.swift|YEN/Ghostty.ConfigTypes.swift'
        'YEN/YENPackageMeta\.swift|YEN/GhosttyPackageMeta.swift'
        'YEN/YENPackage\.swift|YEN/GhosttyPackage.swift'
        'YEN/YEN\.Action\.swift|YEN/Ghostty.Action.swift'
        'YEN/YEN\.App\.swift|YEN/Ghostty.App.swift'
        'YEN/YEN\.Command\.swift|YEN/Ghostty.Command.swift'
        'YEN/YEN\.Config\.swift|YEN/Ghostty.Config.swift'
        'YEN/YEN\.Error\.swift|YEN/Ghostty.Error.swift'
        'YEN/YEN\.Event\.swift|YEN/Ghostty.Event.swift'
        'YEN/YEN\.Input\.swift|YEN/Ghostty.Input.swift'
        'YEN/YEN\.Inspector\.swift|YEN/Ghostty.Inspector.swift'
        'YEN/YEN\.Shell\.swift|YEN/Ghostty.Shell.swift'
        'YEN/YEN\.MenuShortcutManager\.swift|YEN/Ghostty.MenuShortcutManager.swift'
        'YEN/YEN\.Surface\.swift|YEN/Ghostty.Surface.swift'
        'YEN/YENDelegate\.swift|YEN/GhosttyDelegate.swift'
    )
    PBXPROJ_SED_ARGS=()
    for restore_pair in "${PBXPROJ_RESTORE_PATHS[@]}"; do
        PBXPROJ_SED_ARGS+=(-e "s|$restore_pair|g")
    done
    sed -i '' "${PBXPROJ_SED_ARGS[@]}" "$PBXPROJ_PATH"

    python3 "$REPO_ROOT/scripts/lib/rewrite-pbxproj-membership-exclusions.py" "$PBXPROJ_PATH"
fi
}

rewrite_overlay_urls() {
# Branding changed ghostty.org → yen.org, but we need deps.files.ghostty.org
DEP_URL_FILE_LIST="$(mktemp -t yen-depurl-all)"
find . -type f \( -name "*.zig" -o -name "*.zon" \) \
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
  -print0 > "$DEP_URL_FILE_LIST"

rewrite_overlay_url_files "Dependency URLs" "$DEP_URL_FILE_LIST" "$REPO_ROOT/scripts/lib/overlay-data/dependency-urls.sed"

# Change yen.org to yen.chat for user-facing URLs.
# `https://yen.org` is a prefix of both appcast alternatives, so the single
# `https://yen\.org|https://(tip|release)\.files\.yen\.org` union below is the
# exact reachable set for all three substitutions.
USER_URL_FILE_LIST="$(mktemp -t yen-userurl-all)"
find . -type f \( -name "*.swift" -o -name "*.zig" -o -name "*.xib" \) \
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
  -print0 > "$USER_URL_FILE_LIST"

rewrite_overlay_url_files "User-facing URLs" "$USER_URL_FILE_LIST" "$REPO_ROOT/scripts/lib/overlay-data/user-urls.sed"

# Spot-check: verify no stale yen.org URLs remain in user-facing files
if grep -rq --exclude-dir=.zig-cache --exclude-dir=zig-pkg 'https://yen\.org' --include="*.swift" --include="*.xib" .; then
    echo "  ERROR: URL branding incomplete — 'https://yen.org' still found in Swift/XIB files"
    exit 1
fi

# Keep runtime-facing provenance strings on YEN paths, not Ghostty upstream URLs.
VERSION_ZIG="src/cli/version.zig"
if [ -f "$VERSION_ZIG" ]; then
    sed -i '' \
        -e 's|https://github\.com/ghostty-org/ghostty/commit/|https://github.com/8bittts/yenchat/commit/|g' \
        "$VERSION_ZIG"
fi

HELPGEN_ACTIONS_ZIG="src/input/helpgen_actions.zig"
if [ -f "$HELPGEN_ACTIONS_ZIG" ]; then
    sed -i '' \
        -e 's|https://github\.com/ghostty-org/ghostty/edit/main/src/input/Binding\.zig|https://github.com/8bittts/yenchat/edit/main|g' \
        "$HELPGEN_ACTIONS_ZIG"
fi

EXTRA_VIM_ZIG="src/extra/vim.zig"
if [ -f "$EXTRA_VIM_ZIG" ]; then
    sed -i '' \
        -e 's|https://github\.com/ghostty-org/ghostty|https://github.com/8bittts/yenchat|g' \
        "$EXTRA_VIM_ZIG"
fi

EXTRA_BASH_ZIG="src/extra/bash.zig"
if [ -f "$EXTRA_BASH_ZIG" ]; then
    sed -i '' \
        -e 's|https://github\.com/ghostty-org/ghostty/discussions/2994|https://github.com/8bittts/yenchat/discussions|g' \
        "$EXTRA_BASH_ZIG"
fi

CONFIG_TEMPLATE="src/config/config-template"
if [ -f "$CONFIG_TEMPLATE" ]; then
    # Backticks are literal Markdown in the configuration template.
    # shellcheck disable=SC2016
    sed -i '' \
        -e 's/This is the configuration file for Ghostty\./This is the configuration file for YEN./g' \
        -e 's/Run `ghostty +show-config --default --docs`/Run `yen +show-config --default --docs`/g' \
        -e 's/`ghostty +show-config/`yen +show-config/g' \
        -e 's/`ghostty show-config/`yen show-config/g' \
        -e 's|https://ghostty\.org/docs/config|https://yen.chat/docs/config|g' \
        -e "s/Ghostty's website/YEN's website/g" \
        -e 's/Ghostty/YEN/g' \
        "$CONFIG_TEMPLATE"
fi

SHADER_PREFIX="src/renderer/shaders/shadertoy_prefix.glsl"
if [ -f "$SHADER_PREFIX" ]; then
    sed -i '' \
        -e 's/unused currently by Ghostty/unused currently by YEN/g' \
        "$SHADER_PREFIX"
fi

# Spot-check: verify provenance rewrites landed
if [ -f "$VERSION_ZIG" ] && ! grep -q 'https://github\.com/8bittts/yenchat/commit/' "$VERSION_ZIG"; then
    echo "  ERROR: version provenance URL rewrite missing in src/cli/version.zig"
    exit 1
fi
if [ -f "$HELPGEN_ACTIONS_ZIG" ] && ! grep -q 'https://github\.com/8bittts/yenchat/edit/main' "$HELPGEN_ACTIONS_ZIG"; then
    echo "  ERROR: action docs provenance URL rewrite missing in src/input/helpgen_actions.zig"
    exit 1
fi
if [ -f "$CONFIG_TEMPLATE" ] && grep -q 'https://ghostty\.org/docs/config' "$CONFIG_TEMPLATE"; then
    echo "  ERROR: config-template still references https://ghostty.org/docs/config"
    exit 1
fi
}

configure_overlay_project() {
source "$REPO_ROOT/yen-cli/lib/macos-version.sh"
PBXPROJ="macos/YEN.xcodeproj/project.pbxproj"
if [ -f "$PBXPROJ" ]; then
    sed -i '' \
        -e 's/GhosttyKit/YENKit/g' \
        -e 's/GhosttyReleaseLocal/YENReleaseLocal/g' \
        -e 's/GhosttyDebug/YENDebug/g' \
        -e 's/GhosttyTests/YENTests/g' \
        -e 's/Ghostty\.icon/YEN.icon/g' \
        -e 's/"Ghostty"/"YEN"/g' \
        -e 's/= Ghostty;/= YEN;/g' \
        -e 's/productName = Ghostty;/productName = YEN;/g' \
        -e 's/name = Ghostty;/name = YEN;/g' \
        -e 's/Ghostty-Info\.plist/YEN-Info.plist/g' \
        -e 's/path = Ghostty\.app;/path = YEN.app;/g' \
        -e 's/path = Ghostty\.entitlements;/path = YEN.entitlements;/g' \
        -e 's/INFOPLIST_KEY_CFBundleDisplayName = Ghostty;/INFOPLIST_KEY_CFBundleDisplayName = YEN;/g' \
        -e 's/within Ghostty/within YEN/g' \
        -e 's/INFOPLIST_PREPROCESS = YES;/INFOPLIST_PREPROCESS = NO;/g' \
        -e "s/MACOSX_DEPLOYMENT_TARGET = [0-9.][0-9.]*;/MACOSX_DEPLOYMENT_TARGET = $YEN_MIN_MACOS;/g" \
        -e '/INFOPLIST_KEY_NSCalendarsUsageDescription = /d' \
        "$PBXPROJ"
fi
}

# Keep only the privacy entitlements a YEN feature uses, in all three signing
# profiles: Release, Debug and ReleaseLocal. Upstream declares more so that
# programs in the terminal can ask for them; YEN drops the ones none of its
# features need. The hardened runtime denies a protected resource without its
# entitlement and shows no prompt.
configure_overlay_entitlements() {
local ent_dir="$1"
local ent_file
for ent_file in YEN.entitlements YENDebug.entitlements YENReleaseLocal.entitlements; do
    [ -f "$ent_dir/$ent_file" ] || continue
    python3 -c "
import sys, plistlib
ent_file = sys.argv[1]
try:
    with open(ent_file, 'rb') as f:
        d = plistlib.load(f)
except Exception as e:
    print(f'  ERROR: Failed to parse {ent_file}: {e}')
    sys.exit(1)
for k in ['com.apple.security.personal-information.addressbook',
           'com.apple.security.personal-information.calendars',
           'com.apple.security.personal-information.location',
           'com.apple.security.device.camera']:
    d.pop(k, None)
# Dictation requires both microphone and speech-recognition privacy grants.
d['com.apple.security.device.audio-input'] = True
d['com.apple.security.personal-information.speech-recognition'] = True
# Shuffle from Photos reads the library through PhotoKit.
d['com.apple.security.personal-information.photos-library'] = True
with open(ent_file, 'wb') as f:
    plistlib.dump(d, f)
" "$ent_dir/$ent_file" || { echo "  ERROR: Entitlements cleanup failed for $ent_file"; exit 1; }
done
}
