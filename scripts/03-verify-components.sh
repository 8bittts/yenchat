#!/bin/bash
# Component Verification Script
# Verifies each YEN component independently before full build.
# Outputs compact summary on success, details on failure.
#
# Usage: ./scripts/03-verify-components.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Source shared utilities
source "$REPO_ROOT/scripts/lib/version-utils.sh"
source "$REPO_ROOT/scripts/lib/privileged-surface-utils.sh"
source "$REPO_ROOT/scripts/lib/non-concurrency-utils.sh"
source "$REPO_ROOT/scripts/lib/gate-receipt.sh"

gate_begin 03-verify-components

FAILED=0
DETAILS=""
# Per-unit runtime counters. These are MEASUREMENTS — the old "(16 checks)"
# summary counted `CHECKS=$((CHECKS + 1))` statements in the source text, every
# one of them at column 0 outside any guard, so it printed 16 whether a check
# ran or self-skipped.
SHELL_SCANNED=0
CLI_SCANNED=0
HELPERS_SCANNED=0
LUA_SCANNED=0
WRAPPERS_SCANNED=0
LAUNCH_SCANNED=0

fail() {
    DETAILS="$DETAILS\n    X $1"
    FAILED=1
}

check_bash_syntax() {
    local script="$1"
    local syntax_err=""
    if [ ! -f "$script" ]; then
        fail "Missing script for syntax check: $(echo "$script" | sed "s|$REPO_ROOT/||")"
        return
    fi
    if ! syntax_err=$(bash -n "$script" 2>&1); then
        fail "Syntax error in $(basename "$script"): $syntax_err"
    fi
}

# Decide whether a changed path implies the native macOS slice must run.
#
# [CRITICAL] Every path here must be TRACKED. This predicate is fed only by
# `git diff --name-only`, which cannot emit an ignored path, so an ignored
# pattern is unreachable and reads as coverage it can never provide.
#
# `yen-terminal/ghostty/macos/*` used to sit in this list and was exactly that:
# `.gitignore` ignores `yen-terminal/ghostty/` wholesale (zero tracked files),
# so a Ghostty vendor bump — which rewrites that entire tree — matched nothing
# and the gate auto-skipped its most expensive slice while looking correct. The
# tracked evidence of such a bump is the baseline pair below, so match on that
# instead. Measured 2026-08-25: a 31-commit Ghostty bump skipped the native
# suites until the run was forced with
# YEN_COMPONENT_XCODE_REGRESSION_MODE=always, which then executed 269 tests.
#
# This is the second defect in this predicate of the same shape as the
# last-release anchoring fix below: both let a real change look like no change.
source "$REPO_ROOT/scripts/lib/native-component-paths.sh"

should_run_component_xcode_regression() {
    local mode="${YEN_COMPONENT_XCODE_REGRESSION_MODE:-auto}"
    local last_deploy_ref=""
    local changed_paths=""
    local sorted_paths=""
    local changed_path=""

    case "$mode" in
        always)
            return 0
            ;;
        off)
            echo "  [WARNING] skipping xcodebuild regression — YEN_COMPONENT_XCODE_REGRESSION_MODE=off"
            XCODE_REGRESSION_SKIPPED="mode=off"
            return 1
            ;;
        auto)
            ;;
        *)
            fail "Invalid YEN_COMPONENT_XCODE_REGRESSION_MODE=$mode (expected auto, always, or off)"
            return 1
            ;;
    esac

    if ! git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi

    changed_paths=$(mktemp)
    sorted_paths=$(mktemp)

    # Anchor on the last RELEASE commit ("v1.167: ... [deploy]"), not on any
    # commit carrying [deploy]. That marker also rides web-only deploys — most
    # reliably the "docs: publish v<version> release notes [deploy]" commit that
    # every /update-yen pushes immediately AFTER the release, plus routine package
    # bumps. Anchoring on [deploy] therefore moved the window past the native
    # changes the release had just shipped, and the gate reported "no native
    # macOS changes" for work that was never covered by the native slice.
    last_deploy_ref=$(git -C "$REPO_ROOT" log -n 1 --format=%H -E --grep='^v[0-9]+\.[0-9]+: ' 2>/dev/null || true)
    if [ -n "$last_deploy_ref" ]; then
        git -C "$REPO_ROOT" diff --name-only "$last_deploy_ref"..HEAD -- >> "$changed_paths" 2>/dev/null || true
    else
        rm -f "$changed_paths" "$sorted_paths"
        return 0
    fi
    git -C "$REPO_ROOT" diff --name-only HEAD -- >> "$changed_paths" 2>/dev/null || true
    sort -u "$changed_paths" > "$sorted_paths"

    while IFS= read -r changed_path; do
        [ -n "$changed_path" ] || continue
        if is_component_xcode_relevant_path "$changed_path"; then
            rm -f "$changed_paths" "$sorted_paths"
            return 0
        fi
    done < "$sorted_paths"

    rm -f "$changed_paths" "$sorted_paths"
    echo "  (skipping xcodebuild regression — no native macOS changes since latest [deploy] release; set YEN_COMPONENT_XCODE_REGRESSION_MODE=always to force)"
    XCODE_REGRESSION_SKIPPED="no native macOS changes since latest [deploy]"
    return 1
}

# ============================================================================
# Check 1: Shell Compatibility
# ============================================================================
SHELL_OK=1

# Check for bash 4.0+ syntax in scripts that run on the macOS Bash 3.2 path.
BASH4_PATTERN='\$\{[^}]+,,|\$\{[^}]+\^\^|\breadarray\b|\bmapfile\b|\|\&'
while IFS= read -r script; do
    if [ -f "$script" ]; then
        SHELL_SCANNED=$((SHELL_SCANNED + 1))
        if grep -qE "$BASH4_PATTERN" "$script" 2>/dev/null; then
            fail "Bash 4.0+ syntax in $(basename "$script")"
            SHELL_OK=0
        fi
    fi
done < <(find "$REPO_ROOT/yen-cli" -name "*.sh" -type f 2>/dev/null || true)

# Check extensionless scripts that the normal find glob misses.
BASH4_SCAN_FILES=(
    "$REPO_ROOT/yen-cli/bin/yen"
    "$REPO_ROOT/yen-terminal/apply-overlays.sh"
    "$REPO_ROOT"/scripts/lib/overlay-*.sh
    "$REPO_ROOT"/scripts/lib/overlay-phases/*.sh
    "$REPO_ROOT"/scripts/lib/build-release-phases/*.sh
    "$REPO_ROOT/scripts/lib/build-cleanup.sh"
    "$REPO_ROOT"/scripts/lib/finalize-build-phases/*.sh
    "$REPO_ROOT/scripts/lib/finalize-cleanup.sh"
    "$REPO_ROOT"/scripts/lib/bundle-resource-phases/*.sh
)
for script in "${BASH4_SCAN_FILES[@]}"; do
    if [ -f "$script" ]; then
        SHELL_SCANNED=$((SHELL_SCANNED + 1))
        if grep -qE "$BASH4_PATTERN" "$script" 2>/dev/null; then
            fail "Bash 4.0+ syntax in ${script#$REPO_ROOT/}"
            SHELL_OK=0
        fi
    fi
done

# Check generated shell command wrappers that may not use a .sh suffix.
while IFS= read -r script; do
    if [ -f "$script" ]; then
        SHELL_SCANNED=$((SHELL_SCANNED + 1))
        if grep -qE "$BASH4_PATTERN" "$script" 2>/dev/null; then
            fail "Bash 4.0+ syntax in ${script#$REPO_ROOT/}"
            SHELL_OK=0
        fi
    fi
done < <(find "$REPO_ROOT/yen-cli/commands" -type f 2>/dev/null || true)

# Check for GNU-only patterns not available in BSD/macOS shell tools
BSD_SCAN_DIRS=(
    "$REPO_ROOT/yen-cli"
    "$REPO_ROOT/scripts"
    "$REPO_ROOT/yen-terminal/customizations"
    "$REPO_ROOT/yen-terminal"
)
for BSD_DIR in "${BSD_SCAN_DIRS[@]}"; do
    while IFS= read -r bsd_script; do
        [ -f "$bsd_script" ] || continue
        SHELL_SCANNED=$((SHELL_SCANNED + 1))
        # Skip self — our grep patterns would match themselves
        [ "$(basename "$bsd_script")" = "03-verify-components.sh" ] && continue
        case "$bsd_script" in
            "$REPO_ROOT/yen-terminal/ghostty/"*) continue ;;
        esac
        # sed -i without '' backup extension (GNU form)
        if grep -qE "sed -i [^']" "$bsd_script" 2>/dev/null; then
            fail "GNU sed -i (no backup ext) in $(basename "$bsd_script") — use sed -i '' for BSD"
            SHELL_OK=0
        fi
        # bash 4+ associative arrays
        if grep -qE '\bdeclare -A\b' "$bsd_script" 2>/dev/null; then
            fail "declare -A (bash 4+ associative array) in $(basename "$bsd_script")"
            SHELL_OK=0
        fi
        # Perl regex in grep (not available in macOS grep)
        if grep -qE '\bgrep -P\b' "$bsd_script" 2>/dev/null; then
            fail "grep -P (Perl regex) in $(basename "$bsd_script") — use grep -E for BSD compat"
            SHELL_OK=0
        fi
        # GNU find -perm / syntax (BSD uses -perm +)
        if grep -qE 'find .* -perm /' "$bsd_script" 2>/dev/null; then
            fail "find -perm / (GNU syntax) in $(basename "$bsd_script") — use -perm + for BSD"
            SHELL_OK=0
        fi
    done < <(find "$BSD_DIR" -name "*.sh" -type f 2>/dev/null || true)
done

# Check POSIX compliance of shell-agnostic scripts
POSIX_SCRIPT="$REPO_ROOT/yen-terminal/customizations/shell-integration/yen-welcome.sh"
if [ -f "$POSIX_SCRIPT" ]; then
    SHEBANG=$(head -1 "$POSIX_SCRIPT")
    if [ "$SHEBANG" = "#!/bin/sh" ]; then
        if grep -E '^\s*\[\[|[^[]]\[\[|\(\(' "$POSIX_SCRIPT" 2>/dev/null | grep -qvE '\[\[:'; then
            fail "Bash-isms in POSIX script yen-welcome.sh"
            SHELL_OK=0
        fi
    fi
fi

gate_unit_ran shell-compat "scanned=$SHELL_SCANNED"

# ============================================================================
# Check 2: version.json
# ============================================================================
VERSION_JSON="$REPO_ROOT/public/stable/version.json"

if [ ! -f "$VERSION_JSON" ]; then
    fail "version.json not found"
fi

# Extract version using shared utilities
VERSION=$(get_version "$VERSION_JSON")
if [ -n "${VERSION:-}" ]; then
    gate_unit_ran version-json "version=$VERSION"
else
    fail "version.json carried no readable version"
    gate_unit_ran version-json "version=unreadable"
fi

# ============================================================================
# Check 3: YEN CLI
# ============================================================================
CLI_DIR="$REPO_ROOT/yen-cli"
COMMON_SH="$CLI_DIR/lib/common.sh"
YEN_BIN="$CLI_DIR/bin/yen"

if [ ! -d "$CLI_DIR" ]; then
    fail "yen-cli directory not found"
elif [ ! -f "$COMMON_SH" ]; then
    fail "lib/common.sh not found"
elif [ ! -f "$YEN_BIN" ]; then
    fail "bin/yen not found"
else
    # Verify CLI can read version dynamically
    CLI_VERSION=$("$YEN_BIN" version 2>/dev/null | head -1 | awk '{print $2}')
    if [ -z "$CLI_VERSION" ]; then
        fail "CLI version command failed"
    elif [ "$CLI_VERSION" != "dev" ] && [ "$CLI_VERSION" != "$VERSION" ]; then
        fail "CLI version mismatch: $CLI_VERSION (expected $VERSION)"
    fi

    # Verify syntax for *.sh files
    while IFS= read -r script; do
        [ -n "$script" ] || continue
        CLI_SCANNED=$((CLI_SCANNED + 1))
        check_bash_syntax "$script"
    done < <(find "$CLI_DIR" -name "*.sh" -type f 2>/dev/null || true)

    # Verify syntax for executable extensionless CLI entry points/commands
    while IFS= read -r script; do
        [ -n "$script" ] || continue
        [ -x "$script" ] || continue
        CLI_SCANNED=$((CLI_SCANNED + 1))
        check_bash_syntax "$script"
    done < <(find "$CLI_DIR/bin" "$CLI_DIR/commands" -type f 2>/dev/null || true)

    IDE_TEST_STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/yen-ide-component.XXXXXX" 2>/dev/null || echo "")
    if [ -z "$IDE_TEST_STATE_DIR" ]; then
        fail "Unable to allocate temp dir for IDE component verification"
    else
        IDE_LSP_ENV=$(YEN_IDE_STATE_DIR="$IDE_TEST_STATE_DIR" "$YEN_BIN" ide lsp status --format env 2>/dev/null || echo "")
        if ! printf "%s" "$IDE_LSP_ENV" | grep -q "YEN_IDE_LSP_STATE="; then
            fail "IDE lsp status --format env did not emit expected exports"
        fi

        IDE_SHARE_ENV=$(YEN_IDE_STATE_DIR="$IDE_TEST_STATE_DIR" "$YEN_BIN" ide share status --format env 2>/dev/null || echo "")
        if ! printf "%s" "$IDE_SHARE_ENV" | grep -q "YEN_IDE_SHARE_STATE="; then
            fail "IDE share status --format env did not emit expected exports"
        fi

        IDE_INSTALL_OUTPUT=$(YEN_IDE_STATE_DIR="$IDE_TEST_STATE_DIR" "$YEN_BIN" ide lsp install status --all 2>/dev/null || echo "")
        if ! printf "%s" "$IDE_INSTALL_OUTPUT" | grep -q "LANGUAGE"; then
            fail "IDE lsp install status --all did not emit the install matrix"
        fi

        rm -rf "$IDE_TEST_STATE_DIR"
    fi
fi

if [ "$CLI_SCANNED" -gt 0 ]; then
    gate_unit_ran cli-syntax "scanned=$CLI_SCANNED"
else
    # A CLI tree that yielded zero scannable scripts is a moved/renamed tree, not
    # a clean one. Empty scan set = failure, never a pass.
    fail "CLI syntax scan matched zero scripts under yen-cli/ — tree missing or find filters stale"
    gate_unit_skipped cli-syntax "scan set empty"
fi

# ============================================================================
# Check 4: YEN Terminal
# ============================================================================
TERMINAL_DIR="$REPO_ROOT/yen-terminal"

if [ ! -d "$TERMINAL_DIR" ]; then
    fail "yen-terminal directory not found"
elif [ ! -d "$TERMINAL_DIR/customizations" ]; then
    fail "customizations directory not found"
elif ! command -v zig &>/dev/null; then
    fail "Zig not available"
elif [ ! -f "$TERMINAL_DIR/ghostty/build.zig" ]; then
    fail "ghostty/build.zig not found"
fi

# Verify syntax/permissions for executable wrapper scripts in customizations/bin
TERMINAL_WRAPPERS=(
    "$TERMINAL_DIR/customizations/bin/browse"
    "$TERMINAL_DIR/customizations/bin/yen-quicklook"
    "$TERMINAL_DIR/customizations/bin/yen-yazi-edit"
)

if [ -e "$TERMINAL_DIR/customizations/bin/generate-yazi-theme.sh" ]; then
    fail "Legacy terminal wrapper should be removed: yen-terminal/customizations/bin/generate-yazi-theme.sh"
fi

for wrapper in "${TERMINAL_WRAPPERS[@]}"; do
    if [ ! -f "$wrapper" ]; then
        fail "Terminal wrapper missing: $(echo "$wrapper" | sed "s|$REPO_ROOT/||")"
        continue
    fi
    if [ ! -x "$wrapper" ]; then
        fail "Terminal wrapper is not executable: $(echo "$wrapper" | sed "s|$REPO_ROOT/||")"
    fi
    WRAPPERS_SCANNED=$((WRAPPERS_SCANNED + 1))
    check_bash_syntax "$wrapper"
done

YAZI_EDIT_WRAPPER="$TERMINAL_DIR/customizations/bin/yen-yazi-edit"
if [ -f "$YAZI_EDIT_WRAPPER" ]; then
    grep -Fq 'if [ "$editor_name" = "micro" ]; then' "$YAZI_EDIT_WRAPPER" || \
        fail "Yazi editor wrapper missing micro branch"
    grep -Fq -- "-ruler false" "$YAZI_EDIT_WRAPPER" || \
        fail "Yazi editor wrapper missing micro ruler-disable flag"
    grep -Fq -- "-softwrap true" "$YAZI_EDIT_WRAPPER" || \
        fail "Yazi editor wrapper missing micro softwrap flag"
    grep -Fq -- "-wordwrap true" "$YAZI_EDIT_WRAPPER" || \
        fail "Yazi editor wrapper missing micro wordwrap flag"
fi

gate_unit_ran terminal-prereqs "wrappers=$WRAPPERS_SCANNED"

# ============================================================================
# Check 5: Native Helper Sources
# ============================================================================

NATIVE_HELPERS=(
    "$REPO_ROOT/yen-vidthumb/build.sh"
    "$REPO_ROOT/yen-vidthumb/main.swift"
    "$REPO_ROOT/yen-pdfthumb/build.sh"
    "$REPO_ROOT/yen-pdfthumb/main.swift"
    "$REPO_ROOT/yen-svgthumb/build.sh"
    "$REPO_ROOT/yen-svgthumb/main.swift"
    "$REPO_ROOT/yen-thumbcommon/ThumbCommon.swift"
)

for helper_file in "${NATIVE_HELPERS[@]}"; do
    if [ ! -f "$helper_file" ]; then
        fail "Native helper missing: $(echo "$helper_file" | sed "s|$REPO_ROOT/||")"
    else
        HELPERS_SCANNED=$((HELPERS_SCANNED + 1))
    fi
done

for helper_build in \
    "$REPO_ROOT/yen-vidthumb/build.sh" \
    "$REPO_ROOT/yen-pdfthumb/build.sh" \
    "$REPO_ROOT/yen-svgthumb/build.sh"; do
    if [ -f "$helper_build" ] && [ ! -x "$helper_build" ]; then
        fail "Native helper build script is not executable: $(echo "$helper_build" | sed "s|$REPO_ROOT/||")"
    fi
done

gate_unit_ran native-helper-sources "present=$HELPERS_SCANNED/${#NATIVE_HELPERS[@]}"

# ============================================================================
# Check 6: Lua Plugin Syntax
# ============================================================================

if command -v luac &>/dev/null; then
    YAZI_CONFIG_DIR="$TERMINAL_DIR/customizations/yazi-config"
    while IFS= read -r lua_file; do
        LUA_SCANNED=$((LUA_SCANNED + 1))
        if ! luac -p "$lua_file" 2>/dev/null; then
            fail "Lua syntax error in $(echo "$lua_file" | sed "s|$REPO_ROOT/||")"
        fi
    done < <(find "$YAZI_CONFIG_DIR" -name "*.lua" -type f 2>/dev/null || true)
    if [ "$LUA_SCANNED" -gt 0 ]; then
        gate_unit_ran lua-plugin-syntax "scanned=$LUA_SCANNED"
    else
        fail "Lua syntax scan matched zero .lua files under yazi-config/ — tree missing or moved"
        gate_unit_skipped lua-plugin-syntax "scan set empty"
    fi
else
    fail "luac not available — cannot verify Lua plugin syntax"
    gate_unit_skipped lua-plugin-syntax "luac not available"
fi

# ============================================================================
# Check 7: Yazi Flavor Assets
# ============================================================================

YAZI_FLAVORS_DIR="$TERMINAL_DIR/customizations/yazi-config/flavors"
if [ ! -d "$YAZI_FLAVORS_DIR" ]; then
    fail "Yazi flavors directory missing: yen-terminal/customizations/yazi-config/flavors"
    gate_unit_skipped yazi-flavor-assets "flavors directory missing"
else
    YAZI_FLAVORS_CHECKED=0
    for flavor in catppuccin-mocha catppuccin-latte; do
        YAZI_FLAVORS_CHECKED=$((YAZI_FLAVORS_CHECKED + 1))
        flavor_dir="$YAZI_FLAVORS_DIR/$flavor.yazi"
        [ ! -d "$flavor_dir" ] && fail "Yazi flavor missing: $flavor"
        [ ! -f "$flavor_dir/flavor.toml" ] && fail "Yazi flavor missing flavor.toml: $flavor"
        [ ! -f "$flavor_dir/tmtheme.xml" ] && fail "Yazi flavor missing tmtheme.xml: $flavor"
        [ ! -f "$flavor_dir/LICENSE" ] && fail "Yazi flavor missing LICENSE: $flavor"
        [ ! -f "$flavor_dir/LICENSE-tmtheme" ] && fail "Yazi flavor missing LICENSE-tmtheme: $flavor"
    done
    gate_unit_ran yazi-flavor-assets "flavors=$YAZI_FLAVORS_CHECKED"
fi

# ============================================================================
# Check 8: Yazi Launch-Surface Simplicity Guards
# ============================================================================

BROWSE_LAUNCH_FILE="$TERMINAL_DIR/customizations/bin/browse"
if [ ! -f "$BROWSE_LAUNCH_FILE" ]; then
    fail "Yazi launch surface missing: $(echo "$BROWSE_LAUNCH_FILE" | sed "s|$REPO_ROOT/||")"
else
    grep -q "YAZI_CONFIG_HOME=" "$BROWSE_LAUNCH_FILE" || fail "Browse launcher missing YAZI_CONFIG_HOME wiring"
    grep -q "yazi-config" "$BROWSE_LAUNCH_FILE" || fail "Browse launcher missing bundled yazi-config path wiring"
    if grep -Eq "GENERATED_YAZI_CONFIG_HOME|generate-yazi-theme\\.sh" "$BROWSE_LAUNCH_FILE"; then
        fail "Browse launcher still contains generated theme config complexity"
    fi
fi

for launch_file in \
    "$TERMINAL_DIR/customizations/shell-integration/zsh/yen-integration.zsh" \
    "$TERMINAL_DIR/customizations/shell-integration/bash/yen-integration.bash"; do
    if [ ! -f "$launch_file" ]; then
        fail "Yazi launch surface missing: $(echo "$launch_file" | sed "s|$REPO_ROOT/||")"
        continue
    fi
    LAUNCH_SCANNED=$((LAUNCH_SCANNED + 1))
    grep -q "browse_bin" "$launch_file" || fail "Shell launch surface missing browse-wrapper wiring: $(echo "$launch_file" | sed "s|$REPO_ROOT/||")"
    grep -q -- "--cwd-file=\"\$tmp\"" "$launch_file" || fail "Shell launch surface missing --cwd-file handoff: $(echo "$launch_file" | sed "s|$REPO_ROOT/||")"
    if grep -Eq "generated_yazi_config|generate-yazi-theme\\.sh" "$launch_file"; then
        fail "Shell launch surface still contains generated theme config complexity: $(echo "$launch_file" | sed "s|$REPO_ROOT/||")"
    fi
done

if [ -f "$BROWSE_LAUNCH_FILE" ]; then
    LAUNCH_SCANNED=$((LAUNCH_SCANNED + 1))
fi
gate_unit_ran yazi-launch-surface "surfaces=$LAUNCH_SCANNED"

# ============================================================================
# Check 9: Removed GitHub CLI Guard
# ============================================================================

if [ -e "$REPO_ROOT/yen-cli/commands/core/gh" ]; then
    fail "Removed command reintroduced: yen-cli/commands/core/gh"
fi
# An absence check still records what it examined — "checked" is the measurement,
# not the result.
gate_unit_ran removed-gh-guard "paths_checked=1"

# ============================================================================
# Check 10: Overlay + Workspace + CLI Alias Regression Tests
# ============================================================================

if ! command -v bun &>/dev/null; then
    fail "bun not available — cannot run regression tests"
    gate_unit_skipped regression-tests "bun not available"
    XCODE_REGRESSION_SKIPPED="not reached: bun absent"
    XCODE_TEST_SOURCES_PRESENT=1
else
    YAZI_CONFIG_TEST="$REPO_ROOT/tests/35-yazi-config.test.ts"
    OVERLAY_PATCH_TEST="$REPO_ROOT/tests/45-overlay-patching.test.ts"
    CLI_ALIAS_PARITY_TEST="$REPO_ROOT/tests/51-cli-alias-parity.test.ts"
    SETTINGS_DEEPLINK_TEST="$REPO_ROOT/yen-terminal/overlays/macos/Tests/Settings/SettingsCommandPaletteDeepLinkTests.swift"
    SETTINGS_PANE_TEST="$REPO_ROOT/yen-terminal/overlays/macos/Tests/Settings/SettingsPaneTests.swift"
    SETTINGS_SHORTCUTS_CATALOG_TEST="$REPO_ROOT/yen-terminal/overlays/macos/Tests/Settings/SettingsShortcutsCatalogTests.swift"
    COMMAND_PALETTE_PRESENTATION_TEST="$REPO_ROOT/yen-terminal/overlays/macos/Tests/Settings/TerminalCommandPalettePresentationTests.swift"
    COMMAND_PALETTE_JUMP_TARGETS_TEST="$REPO_ROOT/yen-terminal/overlays/macos/Tests/Settings/TerminalCommandPaletteJumpTargetsModelTests.swift"
    COMMAND_PALETTE_EDGE_CASES_TEST="$REPO_ROOT/yen-terminal/overlays/macos/Tests/Settings/TerminalCommandPaletteAuditEdgeCaseTests.swift"

    # The gate/process guardrail suites run here too. They were previously
    # invoked by nothing — not this script, not /update-yen, not a hook — so the
    # fingerprint scanner shipped release-wired while the test proving it fails
    # closed only ran if somebody typed `bun test` by hand. Folding them into
    # this existing check keeps the pinned 16-check count unchanged.
    # ~9s total; none of them need a built app (46 and 47 use synthetic fixtures).
    REGRESSION_TESTS=(
        "$YAZI_CONFIG_TEST"
        "$OVERLAY_PATCH_TEST"
        "$CLI_ALIAS_PARITY_TEST"
        "$REPO_ROOT/tests/46-artifact-fingerprint-gate.test.ts"
        "$REPO_ROOT/tests/47-update-signature-gate.test.ts"
        "$REPO_ROOT/tests/119-vendor-process-guardrails.test.ts"
        "$REPO_ROOT/tests/120-zip-process-guardrails.test.ts"
        "$REPO_ROOT/tests/123-release-script-hardening.test.ts"
        "$REPO_ROOT/tests/124-upstream-lib-contract.test.ts"
        "$REPO_ROOT/tests/127-overlay-recurrence-gates.test.ts"
        "$REPO_ROOT/tests/145-gate-receipt-contract.test.ts"
    )

    # Fail closed on a missing suite: a deleted or renamed test file must abort,
    # never quietly shrink the set that runs.
    REGRESSION_TESTS_MISSING=0
    for regression_test in "${REGRESSION_TESTS[@]}"; do
        if [ ! -f "$regression_test" ]; then
            fail "Missing regression test: ${regression_test#"$REPO_ROOT/"}"
            REGRESSION_TESTS_MISSING=$((REGRESSION_TESTS_MISSING + 1))
        fi
    done

    if [ "$REGRESSION_TESTS_MISSING" -eq 0 ]; then
        # Captured, not discarded: the pass count is this unit's evidence. A
        # `>/dev/null` here is what made a green run indistinguishable from a run
        # that never invoked bun at all.
        REGRESSION_OUT=""
        if ! REGRESSION_OUT="$(bun test "${REGRESSION_TESTS[@]}" 2>&1)"; then
            fail "Regression tests failed (bun test ${REGRESSION_TESTS[*]//$REPO_ROOT\//})"
            DETAILS="$DETAILS\n$(printf '%s\n' "$REGRESSION_OUT" | grep -E '\(fail\)|error:' | head -10)"
            gate_unit_skipped regression-tests "bun test failed"
        else
            REGRESSION_PASS=$(printf '%s\n' "$REGRESSION_OUT" | grep -Eo '^[[:space:]]*[0-9]+ pass' | grep -Eo '[0-9]+' | tail -1)
            [ -n "$REGRESSION_PASS" ] || REGRESSION_PASS=0
            if [ "$REGRESSION_PASS" -eq 0 ]; then
                fail "bun test reported zero passing assertions across ${#REGRESSION_TESTS[@]} suites — the run did not execute"
                gate_unit_skipped regression-tests "zero assertions executed"
            else
                gate_unit_ran regression-tests "suites=${#REGRESSION_TESTS[@]} pass=$REGRESSION_PASS"
            fi
        fi
    else
        gate_unit_skipped regression-tests "$REGRESSION_TESTS_MISSING declared suite(s) missing"
    fi

    for macos_test in \
        "$SETTINGS_DEEPLINK_TEST" \
        "$SETTINGS_PANE_TEST" \
        "$SETTINGS_SHORTCUTS_CATALOG_TEST" \
        "$COMMAND_PALETTE_PRESENTATION_TEST" \
        "$COMMAND_PALETTE_JUMP_TARGETS_TEST" \
        "$COMMAND_PALETTE_EDGE_CASES_TEST"; do
        if [ ! -f "$macos_test" ]; then
            fail "Missing macOS regression test: $(echo "$macos_test" | sed "s|$REPO_ROOT/||")"
        fi
    done

    if [ -f "$SETTINGS_DEEPLINK_TEST" ] && \
       [ -f "$SETTINGS_PANE_TEST" ] && \
       [ -f "$SETTINGS_SHORTCUTS_CATALOG_TEST" ] && \
       [ -f "$COMMAND_PALETTE_PRESENTATION_TEST" ] && \
       [ -f "$COMMAND_PALETTE_JUMP_TARGETS_TEST" ] && \
       [ -f "$COMMAND_PALETTE_EDGE_CASES_TEST" ]; then
        XCODE_TEST_SOURCES_PRESENT=1
        XCFRAMEWORK_PATH="$REPO_ROOT/yen-terminal/ghostty/macos/YENKit.xcframework"
        XCFRAMEWORK_INFO_PLIST="$XCFRAMEWORK_PATH/Info.plist"
        XCFRAMEWORK_LIBRARY_COUNT=0
        if [ -d "$XCFRAMEWORK_PATH" ]; then
            XCFRAMEWORK_LIBRARY_COUNT=$(
                find "$XCFRAMEWORK_PATH" \
                    \( -name "*.a" -o -name "*.dylib" \) \
                    -type f 2>/dev/null | wc -l | tr -d '[:space:]'
            )
        fi

        if [ ! -d "$XCFRAMEWORK_PATH" ] || [ ! -f "$XCFRAMEWORK_INFO_PLIST" ] || [ "$XCFRAMEWORK_LIBRARY_COUNT" -eq 0 ]; then
            # An absent xcframework must never read as a silent pass. `always` means
            # "force this slice", so it cannot be satisfied by skipping — it fails.
            # In `auto` the skip is still allowed (build-release.sh rebuilds the
            # xcframework), but it is recorded so the summary cannot report a clean
            # "Components verified" while the native regression slice never ran.
            # This is the shape that let a failing WebPreviewCommandTests suite ship:
            # every release built from a cleaned tree, so the slice always skipped.
            if [ "${YEN_COMPONENT_XCODE_REGRESSION_MODE:-auto}" = "always" ]; then
                fail "xcodebuild regression forced (mode=always) but YENKit.xcframework is missing/incomplete — build it first (scripts/native/01-macos-smoke.sh --build-only)"
                XCODE_REGRESSION_SKIPPED="xcframework missing/incomplete (mode=always)"
            else
                echo "  [WARNING] skipping xcodebuild regression — xcframework missing/incomplete, will be rebuilt by build-release.sh"
                echo "            the native regression suites did NOT run in this invocation"
                XCODE_REGRESSION_SKIPPED="xcframework missing/incomplete"
            fi
        elif ! should_run_component_xcode_regression; then
            :
        elif ! command -v xcodebuild >/dev/null 2>&1; then
            fail "xcodebuild not available — cannot run workspace macOS regression tests"
            XCODE_REGRESSION_SKIPPED="xcodebuild not available"
        else
            XCODE_TEST_ARGS=(
                -project "$REPO_ROOT/yen-terminal/ghostty/macos/YEN.xcodeproj"
                -scheme YEN
                -configuration Debug
                -sdk macosx
                -parallel-testing-enabled NO
                -only-testing:YENTests/SettingsCommandPaletteDeepLinkTests
                -only-testing:YENTests/SettingsConfigMergeTests
                -only-testing:YENTests/SettingsConfigPathTests
                -only-testing:YENTests/SettingsPaneTests
                -only-testing:YENTests/SettingsThemeCatalogTests
                -only-testing:YENTests/WebPreviewURLPolicyTests
                -only-testing:YENTests/WebPreviewModelTests
                -only-testing:YENTests/SettingsShortcutsCatalogTests
                -only-testing:YENTests/CommandPaletteViewTests
                -only-testing:YENTests/TerminalCommandPalettePresentationTests
                -only-testing:YENTests/TerminalCommandPaletteJumpTargetsModelTests
                -only-testing:YENTests/TerminalCommandPaletteAuditEdgeCaseTests
                -only-testing:YENTests/UtilityWindowLifecycleTests
            )

            # Output is CAPTURED, never discarded. Both of these were
            # `>/dev/null 2>&1`, which made the most expensive slice in the gate
            # emit nothing at all on the success path — so "it ran" could only be
            # inferred from the absence of a SKIPPED suffix printed elsewhere.
            # That inference is exactly what this contract exists to make
            # unnecessary. `XCODE_EXECUTED` is the positive evidence.
            XCODE_EXECUTED=0
            XCODE_SUITES=0

            # The declared suites are Swift Testing, whose total lives in
            # "Test run with N tests in M suites passed". xcodebuild ALSO prints a
            # legacy XCTest line -- "Executed 0 tests, with 0 failures" -- for the
            # empty XCTest bucket. Parsing only the legacy line reports zero while
            # the suites really ran, so both are summed.
            count_executed_tests() {
                printf '%s\n' "$1" \
                    | grep -Eo 'Test run with [0-9]+ test|Executed [0-9]+ test' \
                    | grep -Eo '[0-9]+' \
                    | awk '{t+=$1} END {print t+0}'
            }
            count_executed_suites() {
                printf '%s\n' "$1" \
                    | grep -Eo 'in [0-9]+ suites?' \
                    | grep -Eo '[0-9]+' \
                    | awk '{t+=$1} END {print t+0}'
            }
            if ! xcodebuild "${XCODE_TEST_ARGS[@]}" build-for-testing >/dev/null 2>&1; then
                fail "Workspace macOS regression build failed (targeted xcodebuild build-for-testing)"
            else
                SETTINGS_TEST_OUT=$(xcodebuild "${XCODE_TEST_ARGS[@]}" test-without-building 2>&1) || true
                if ! printf '%s\n' "$SETTINGS_TEST_OUT" | grep -q "TEST EXECUTE SUCCEEDED"; then
                    fail "Workspace macOS regression tests failed (targeted xcodebuild test-without-building)"
                    DETAILS="$DETAILS\n$(printf '%s\n' "$SETTINGS_TEST_OUT" | grep -E 'Failing tests|error:' | head -10)"
                else
                    XCODE_EXECUTED=$((XCODE_EXECUTED + $(count_executed_tests "$SETTINGS_TEST_OUT")))
                    XCODE_SUITES=$((XCODE_SUITES + $(count_executed_suites "$SETTINGS_TEST_OUT")))
                fi
            fi

            # The browser suites drive real NSWindow lifecycle, so they get their own
            # xcodebuild invocation to keep window state off the batched settings host.
            #
            # These used to fail here every run, and the failure was long misread as a
            # "transient XCTest host launch crash" worth retrying. It was not transient:
            # the test windows never set `isReleasedWhenClosed = false`, so close() over-
            # released them and killed the host mid-suite (runner "exited with code 1
            # before finishing running tests"), marking every remaining test failed. The
            # retry simply re-ran a deterministic failure three times. Fixed in
            # BrowserTestSupport; the single attempt below is deliberate, so a real
            # failure fails loudly on the first run instead of being retried into a
            # generic message. Long-form browser coverage still also runs in
            # scripts/native/01-macos-smoke.sh --browser.
            WEBPREVIEW_COMMAND_TEST_ARGS=(
                -project "$REPO_ROOT/yen-terminal/ghostty/macos/YEN.xcodeproj"
                -scheme YEN
                -configuration Debug
                -sdk macosx
                -parallel-testing-enabled NO
                -only-testing:YENTests/WebPreviewCommandTests
                -only-testing:YENTests/BrowserSplitWindowTests
            )
            if ! xcodebuild "${WEBPREVIEW_COMMAND_TEST_ARGS[@]}" build-for-testing >/dev/null 2>&1; then
                fail "Browser regression build failed (isolated xcodebuild build-for-testing)"
            else
                WEBPREVIEW_OUT=$(xcodebuild "${WEBPREVIEW_COMMAND_TEST_ARGS[@]}" test-without-building 2>&1) || true
                if ! printf '%s\n' "$WEBPREVIEW_OUT" | grep -q "TEST EXECUTE SUCCEEDED"; then
                    fail "Browser regression tests failed (WebPreviewCommandTests + BrowserSplitWindowTests, isolated xcodebuild test-without-building)"
                    DETAILS="$DETAILS\n$(printf '%s\n' "$WEBPREVIEW_OUT" | grep -E 'Failing tests|^	[A-Za-z]+Tests\.' | head -10)"
                else
                    XCODE_EXECUTED=$((XCODE_EXECUTED + $(count_executed_tests "$WEBPREVIEW_OUT")))
                    XCODE_SUITES=$((XCODE_SUITES + $(count_executed_suites "$WEBPREVIEW_OUT")))
                fi
            fi

            # A slice that built and reported success but executed zero tests has
            # not covered anything. Fail rather than record a hollow RAN.
            if [ "$XCODE_EXECUTED" -eq 0 ]; then
                fail "xcodebuild regression executed zero tests — the -only-testing identifiers no longer resolve to any suite"
                gate_unit_skipped xcode-regression "zero tests executed"
            else
                gate_unit_ran xcode-regression "suites=$XCODE_SUITES executed=$XCODE_EXECUTED"
            fi
        fi
    fi
fi

# Every path that leaves the native slice unrun records its own reason, so an
# unrecorded xcode-regression unit is itself a gate failure at gate_end.
if [ -z "${XCODE_TEST_SOURCES_PRESENT:-}" ] && [ -z "${XCODE_REGRESSION_SKIPPED:-}" ]; then
    XCODE_REGRESSION_SKIPPED="declared macOS test sources missing"
fi
if [ -n "${XCODE_REGRESSION_SKIPPED:-}" ]; then
    gate_unit_skipped xcode-regression "$XCODE_REGRESSION_SKIPPED"
fi

# ============================================================================
# Check 11: Privileged-Action Surface Baseline (Pre-Build Gate)
# ============================================================================

PRIVILEGED_SURFACE_BASELINE_FILE="$REPO_ROOT/scripts/lib/privileged-action-surface-baseline.txt"
CLI_ENTRYPOINT="$REPO_ROOT/yen-cli/bin/yen"
APP_INTENTS_PERMISSION_POLICY="$REPO_ROOT/yen-terminal/overlays/macos/Sources/Features/App Intents/IntentPermission.swift"

if [ ! -f "$PRIVILEGED_SURFACE_BASELINE_FILE" ]; then
    fail "Privileged-action surface baseline missing: scripts/lib/privileged-action-surface-baseline.txt"
    gate_unit_skipped privileged-surface "baseline file missing"
else
    SURFACE_SNAPSHOT=$(mktemp)
    snapshot_privileged_action_surface "$SURFACE_SNAPSHOT" "$CLI_ENTRYPOINT" "$APP_INTENTS_PERMISSION_POLICY"

    if ! SURFACE_DIFF=$(diff_privileged_action_surface "$SURFACE_SNAPSHOT" "$PRIVILEGED_SURFACE_BASELINE_FILE"); then
        SURFACE_SUMMARY=$(echo "$SURFACE_DIFF" | head -n 20 | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')
        fail "Privileged-action surface drift (update baseline before build): $SURFACE_SUMMARY"
    fi

    if ! grep -Fxq "app-intent-guard:deny-plus-prefix" "$SURFACE_SNAPSHOT"; then
        fail "Privileged-action surface guard missing: app-intent deny-plus-prefix"
    fi

    SURFACE_ENTRIES=$(wc -l < "$SURFACE_SNAPSHOT" | tr -d '[:space:]')
    if [ "${SURFACE_ENTRIES:-0}" -gt 0 ]; then
        gate_unit_ran privileged-surface "entries=$SURFACE_ENTRIES"
    else
        fail "Privileged-action surface snapshot is empty — the scanner matched nothing"
        gate_unit_skipped privileged-surface "snapshot empty"
    fi
    rm -f "$SURFACE_SNAPSHOT"
fi

# ============================================================================
# Check 12: Non-Concurrency Warning Allowlist Metadata
# ============================================================================

NON_CONCURRENCY_ALLOWLIST_FILE="$REPO_ROOT/scripts/lib/non-concurrency-warning-allowlist.txt"
NON_CONCURRENCY_ALLOWLIST_REVIEW_DEADLINE="${YEN_NON_CONCURRENCY_ALLOWLIST_REVIEW_DEADLINE:-2026-10-30}"

NON_CONCURRENCY_FINDINGS_FILE=$(mktemp)
validate_non_concurrency_allowlist_metadata \
    "$NON_CONCURRENCY_ALLOWLIST_FILE" \
    "$NON_CONCURRENCY_FINDINGS_FILE" \
    "$NON_CONCURRENCY_ALLOWLIST_REVIEW_DEADLINE"

NON_CONCURRENCY_FINDINGS_COUNT=$(wc -l < "$NON_CONCURRENCY_FINDINGS_FILE" | tr -d '[:space:]')
if [ "$NON_CONCURRENCY_FINDINGS_COUNT" -gt 0 ]; then
    NON_CONCURRENCY_SUMMARY=$(head -n 5 "$NON_CONCURRENCY_FINDINGS_FILE" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')
    fail "Non-concurrency warning allowlist metadata/review gate failed: $NON_CONCURRENCY_SUMMARY"
fi
NON_CONCURRENCY_ENTRIES=$(grep -cv '^[[:space:]]*\(#\|$\)' "$NON_CONCURRENCY_ALLOWLIST_FILE" 2>/dev/null || true)
[ -n "$NON_CONCURRENCY_ENTRIES" ] || NON_CONCURRENCY_ENTRIES=0
gate_unit_ran non-concurrency-allowlist "entries=$NON_CONCURRENCY_ENTRIES findings=$NON_CONCURRENCY_FINDINGS_COUNT"
rm -f "$NON_CONCURRENCY_FINDINGS_FILE"

# ============================================================================
# Check 13: Weather Removal Regression Guard
# ============================================================================

[ ! -e "$REPO_ROOT/yen-cli/commands/core/weather" ] \
    || fail "Retired weather command returned: yen-cli/commands/core/weather"

if command -v rg >/dev/null 2>&1; then
    WEATHER_REMOVAL_HITS=$(
        rg -n --no-messages -e "yen-weather|--device-location|--fallback-only|YEN_WEATHER_NATIVE_" \
            "$REPO_ROOT/yen-cli" \
            "$REPO_ROOT/scripts" \
            "$REPO_ROOT/yen-terminal/customizations" \
            "$REPO_ROOT/yen-terminal/overlays" \
            "$REPO_ROOT/app" \
            "$REPO_ROOT/_docs" \
            "$REPO_ROOT/README.md" \
            "$REPO_ROOT/AGENTS.md" \
            "$REPO_ROOT/public/llms.txt" \
            -g "*.sh" -g "*.swift" -g "*.ts" -g "*.tsx" \
            -g "*.md" -g "*.txt" -g "*.json" -g "*.toml" \
            -g "*.lua" -g "*.zig" -g "*.go" \
            -g "!03-verify-components.sh" \
            -g "!05-detect-failures.sh" \
            -g "!**/bundle-resource-phases/03-binaries.sh" \
            -g "!_docs/todos.md" \
            || true
    )
    WEATHER_ACTIVE_SURFACE_HITS=$(rg -n -i --no-messages "weather|open-meteo" \
        "$REPO_ROOT/yen-cli/bin/yen" \
        "$REPO_ROOT/yen-cli/commands/core/help" \
        "$REPO_ROOT/yen-terminal/customizations/shell-integration/zsh/yen-integration.zsh" \
        "$REPO_ROOT/yen-terminal/customizations/shell-integration/bash/yen-integration.bash" \
        "$REPO_ROOT/yen-terminal/overlays/macos/Sources/Features/Command Palette/TerminalCommandPaletteTypes.swift" \
        "$REPO_ROOT/app/docs/docs-client.tsx" \
        "$REPO_ROOT/app/privacy/privacy-client.tsx" \
        "$REPO_ROOT/app/terms/terms-client.tsx" \
        "$REPO_ROOT/public/llms.txt" \
        || true)
else
    WEATHER_REMOVAL_HITS=$(
        grep -rn -E "yen-weather|--device-location|--fallback-only|YEN_WEATHER_NATIVE_" \
            "$REPO_ROOT/yen-cli" \
            "$REPO_ROOT/scripts" \
            "$REPO_ROOT/yen-terminal/customizations" \
            "$REPO_ROOT/yen-terminal/overlays" \
            "$REPO_ROOT/app" \
            "$REPO_ROOT/_docs" \
            "$REPO_ROOT/README.md" \
            "$REPO_ROOT/AGENTS.md" \
            "$REPO_ROOT/public/llms.txt" \
            --include="*.sh" --include="*.swift" --include="*.ts" --include="*.tsx" \
            --include="*.md" --include="*.txt" --include="*.json" --include="*.toml" \
            --include="*.lua" --include="*.zig" --include="*.go" \
            2>/dev/null \
        | grep -v "03-verify-components.sh" \
        | grep -v "05-detect-failures.sh" \
        | grep -v "/scripts/lib/bundle-resource-phases/03-binaries.sh:" \
        | grep -v "_docs/todos.md" \
        || true
    )
    WEATHER_ACTIVE_SURFACE_HITS=$(grep -ni -E "weather|open-meteo" \
        "$REPO_ROOT/yen-cli/bin/yen" \
        "$REPO_ROOT/yen-cli/commands/core/help" \
        "$REPO_ROOT/yen-terminal/customizations/shell-integration/zsh/yen-integration.zsh" \
        "$REPO_ROOT/yen-terminal/customizations/shell-integration/bash/yen-integration.bash" \
        "$REPO_ROOT/yen-terminal/overlays/macos/Sources/Features/Command Palette/TerminalCommandPaletteTypes.swift" \
        "$REPO_ROOT/app/docs/docs-client.tsx" \
        "$REPO_ROOT/app/privacy/privacy-client.tsx" \
        "$REPO_ROOT/app/terms/terms-client.tsx" \
        "$REPO_ROOT/public/llms.txt" \
        2>/dev/null || true)
fi
if [ -n "$WEATHER_REMOVAL_HITS" ]; then
    fail "Weather removal regression detected in active runtime/docs: $WEATHER_REMOVAL_HITS"
fi

if [ -n "$WEATHER_ACTIVE_SURFACE_HITS" ]; then
    fail "Retired weather feature returned to an active product surface: $WEATHER_ACTIVE_SURFACE_HITS"
fi
gate_unit_ran weather-removal-guard "legacy_patterns=4 active_surfaces=9 command_files=1"

# ============================================================================
# Check 14: Curated Theme Manifest Gate
# ============================================================================

CURATED_THEME_MANIFEST="$TERMINAL_DIR/customizations/theme-curated-manifest.txt"
CURATED_THEME_TAGS="$TERMINAL_DIR/customizations/theme-curated-tags.txt"
if [ ! -f "$CURATED_THEME_MANIFEST" ]; then
    fail "Curated theme manifest missing: yen-terminal/customizations/theme-curated-manifest.txt"
    gate_unit_skipped theme-manifest "manifest file missing"
else
    CURATED_THEMES_FILE=$(mktemp)
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
        fail "Curated theme manifest is empty"
    else
        CURATED_THEME_COUNT=$(wc -l < "$CURATED_THEMES_FILE" | tr -d '[:space:]')
        if [ "$CURATED_THEME_COUNT" -lt 16 ] || [ "$CURATED_THEME_COUNT" -gt 24 ]; then
            fail "Curated theme count out of bounds (expected 16-24, found $CURATED_THEME_COUNT)"
        fi

        CURATED_DUPLICATES=$(awk '
        {
            key = tolower($0)
            count[key]++
            if (count[key] == 2) print $0
        }
        ' "$CURATED_THEMES_FILE")
        if [ -n "$CURATED_DUPLICATES" ]; then
            fail "Curated theme manifest has duplicate entries: $(echo "$CURATED_DUPLICATES" | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g')"
        fi

        CURATED_REQUIRED_MISSING=""
        while IFS= read -r required_theme; do
            [ -n "$required_theme" ] || continue
            if ! grep -Fqx "$required_theme" "$CURATED_THEMES_FILE"; then
                CURATED_REQUIRED_MISSING="$CURATED_REQUIRED_MISSING $required_theme"
            fi
        done <<'EOF'
YEN
Retro Terminal
CutePretzel
EOF
        if [ -n "$CURATED_REQUIRED_MISSING" ]; then
            fail "Curated theme manifest missing required pinned themes:$CURATED_REQUIRED_MISSING"
        fi
    fi

    if [ "${CURATED_THEME_COUNT:-0}" -gt 0 ]; then
        gate_unit_ran theme-manifest "themes=$CURATED_THEME_COUNT"
    else
        gate_unit_skipped theme-manifest "manifest parsed to zero themes"
    fi
    rm -f "$CURATED_THEMES_FILE"
fi

if [ ! -f "$CURATED_THEME_TAGS" ]; then
    fail "Curated theme tags file missing: yen-terminal/customizations/theme-curated-tags.txt"
else
    if ! python3 - "$CURATED_THEME_MANIFEST" "$CURATED_THEME_TAGS" <<'PYEOF'; then
import sys

manifest_path, tags_path = sys.argv[1], sys.argv[2]
allowed = {"dark", "light", "retro", "neon", "low-contrast", "high-contrast"}

manifest = []
with open(manifest_path, "r", encoding="utf-8") as f:
    for raw in f:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        manifest.append(line)

tags_by_theme = {}
extra = []
with open(tags_path, "r", encoding="utf-8") as f:
    for raw in f:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "|" not in line:
            print(f"invalid curated tag line (missing '|'): {line}")
            sys.exit(1)
        theme, raw_tags = line.split("|", 1)
        theme = theme.strip()
        tags = [t.strip().lower() for t in raw_tags.split(",") if t.strip()]
        if not theme:
            print(f"invalid curated tag line (empty theme): {line}")
            sys.exit(1)
        if not tags:
            print(f"curated tags missing categories for theme: {theme}")
            sys.exit(1)
        invalid = sorted({tag for tag in tags if tag not in allowed})
        if invalid:
            print(f"curated tags contain unsupported categories for theme {theme}: {', '.join(invalid)}")
            sys.exit(1)
        key = theme.lower()
        if key in tags_by_theme:
            print(f"duplicate curated tags entry for theme: {theme}")
            sys.exit(1)
        tags_by_theme[key] = set(tags)

manifest_lower = {name.lower() for name in manifest}
missing = [name for name in manifest if name.lower() not in tags_by_theme]
for key in sorted(tags_by_theme):
    if key not in manifest_lower:
        extra.append(key)

if missing:
    print("curated tags missing manifest themes:")
    for name in missing:
        print(name)
    sys.exit(1)

if extra:
    print("curated tags include themes not in manifest:")
    for name in extra:
        print(name)
    sys.exit(1)
PYEOF
        fail "Curated theme tags validation failed"
    fi
fi

# ============================================================================
# Check: SwiftUI view-modifier hygiene (bare modifier silently binds to self)
# ============================================================================
# 41 already prints "scanned N SwiftUI of M Swift file(s)". That measurement used
# to die at this caller; it is now this unit's evidence.
if ! VIEW_MODIFIER_LINT_OUT="$(bash "$REPO_ROOT/scripts/41-lint-swift-view-modifiers.sh" 2>&1)"; then
    fail "SwiftUI view-modifier lint (missing leading dot -> self-recursion / stack overflow)"
    DETAILS="$DETAILS\n$VIEW_MODIFIER_LINT_OUT"
    gate_unit_skipped view-modifier-lint "lint reported failures"
else
    VIEW_MODIFIER_EVIDENCE="$(printf '%s\n' "$VIEW_MODIFIER_LINT_OUT" | grep -Eo 'scanned [0-9]+ SwiftUI of [0-9]+ Swift file' | tail -1)"
    [ -n "$VIEW_MODIFIER_EVIDENCE" ] || VIEW_MODIFIER_EVIDENCE="lines=$(printf '%s\n' "$VIEW_MODIFIER_LINT_OUT" | grep -c . || true)"
    gate_unit_ran view-modifier-lint "$VIEW_MODIFIER_EVIDENCE"
fi

# ============================================================================
# Check: Overlay recurrence gates (prints, timers, god-files, patch heredocs)
# ============================================================================
if ! OVERLAY_RECURRENCE_LINT_OUT="$(bash "$REPO_ROOT/scripts/42-lint-overlay-recurrence-gates.sh" 2>&1)"; then
    fail "Overlay recurrence gates failed (non-DEBUG prints, timer tolerance, or apply-overlays heredoc drift)"
    DETAILS="$DETAILS\n$OVERLAY_RECURRENCE_LINT_OUT"
    gate_unit_skipped overlay-recurrence "lint reported failures"
else
    OVERLAY_RECURRENCE_EVIDENCE="$(printf '%s\n' "$OVERLAY_RECURRENCE_LINT_OUT" | grep -E '^RECEIPT ' | tail -1)"
    [ -n "$OVERLAY_RECURRENCE_EVIDENCE" ] || OVERLAY_RECURRENCE_EVIDENCE="lines=$(printf '%s\n' "$OVERLAY_RECURRENCE_LINT_OUT" | grep -c . || true)"
    gate_unit_ran overlay-recurrence "$OVERLAY_RECURRENCE_EVIDENCE"
fi

# ============================================================================
# Summary
# ============================================================================
if [ "$FAILED" -ne 0 ]; then
    echo "  X Component verification failed"
    echo -e "$DETAILS"
    echo ""
    echo "  Fix issues and re-run: ./scripts/03-verify-components.sh"
fi

# gate_end prints every RAN|/SKIP| line on BOTH branches, then the RECEIPT digest,
# then exits. It refuses to report PASS unless every unit declared in
# scripts/lib/units/03-verify-components.units was accounted for exactly once —
# so a new skip route nobody anticipated fails the gate instead of vanishing.
gate_end "$FAILED"
