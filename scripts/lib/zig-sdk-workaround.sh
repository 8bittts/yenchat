#!/bin/bash
# Zig SDK linker workaround for Xcode 26.4+ arm64e-only SDKs.
#
# Xcode 26.4+ SDK ships .tbd files with arm64e-macos top-level targets only (dropped
# plain arm64-macos). Zig's MachO linker targets arm64, not arm64e, so it can't resolve
# system symbols like _abort, _free, _malloc from the Xcode SDK's libSystem.tbd.
#
# Workaround: create a synthetic macOS sysroot that uses the CLT SDK's .tbd files (which
# still include arm64-macos targets) while symlinking everything else from the Xcode SDK.
# A thin xcrun wrapper in PATH returns this synthetic sysroot for macOS SDK queries while
# delegating iOS/other SDK queries to the real xcrun — preserving xcframework builds.
#
# Bypass: set YEN_SKIP_ZIG_SDK_WORKAROUND=1 if Xcode fixes the regression.
#
# Usage:  source scripts/lib/zig-sdk-workaround.sh
#         setup_zig_sdk_workaround     # probe + (if needed) build synthetic sysroot, mutate PATH
#         teardown_zig_sdk_workaround  # restore PATH
#
# State crosses the two calls via the module globals below, so setup and teardown MUST
# run in the same shell (sourced functions, not subshells). teardown restores PATH only;
# the ${TMPDIR:-/tmp}/yen-zig-{sysroot,xcrun-wrapper} dirs are intentionally left in place
# and reaped by the caller's EXIT trap for crash safety.

ZIG_SDK_WORKAROUND_ACTIVE=""
ZIG_SDK_WORKAROUND_ORIG_PATH=""

setup_zig_sdk_workaround() {
    ZIG_SDK_WORKAROUND_ACTIVE=""
    ZIG_SDK_WORKAROUND_ORIG_PATH="$PATH"
    # Probe-first detection: link a trivial Zig program against libSystem to see
    # whether the current SDK actually resolves libSystem symbols for Zig. This
    # catches SDK/.tbd states where the top-`targets:` heuristic below would say
    # "fine" but the linker still fails (seen 2026-04-15 on Xcode 26.4+ machines
    # with Zig 0.15.2: undefined symbols _free/_getcwd/_malloc_size…).
    #
    # The probe declares its libc symbols with `extern "c"` and never imports
    # `std`. That is deliberate and load-bearing: the previous probe called
    # `std.posix.getenv`, which Zig 0.16 removed, so the probe failed to COMPILE
    # on every run and was misread as an SDK link failure — activating the
    # synthetic sysroot unconditionally on a machine that did not need it. A
    # probe for a linker bug must not depend on a moving std API surface.
    #
    # `pub export fn main` + `-lc` uses the C entry point, so the probe skips
    # Zig's std start code entirely while still forcing a real libSystem link.
    #
    # Outcome is three-valued: pass | fail | inconclusive. Only a genuine LINK
    # failure counts as `fail`; anything else (compile error, toolchain quirk)
    # is `inconclusive` and defers to the .tbd heuristic rather than asserting
    # the SDK is broken.
    local _sdk_probe_result="inconclusive"
    if [ -z "$YEN_SKIP_ZIG_SDK_WORKAROUND" ] && command -v zig >/dev/null 2>&1; then
        local _probe_dir
        _probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/yen-zig-sdk-probe.XXXXXX")"
        cat > "$_probe_dir/probe.zig" << 'ZIG_SDK_PROBE'
extern "c" fn malloc(n: usize) ?*anyopaque;
extern "c" fn free(p: ?*anyopaque) void;
extern "c" fn getcwd(buf: [*c]u8, size: usize) [*c]u8;
pub export fn main() c_int {
    const p = malloc(64) orelse return 1;
    _ = getcwd(@ptrCast(p), 64);
    free(p);
    return 0;
}
ZIG_SDK_PROBE
        # Use native target (no -target flag) — this matches how zig build
        # compiles build.zig into a runner executable, which is where the
        # libSystem link failure actually surfaces. Targeting aarch64-macos
        # explicitly masked the problem (2026-04-15).
        echo "  Running Zig SDK link probe..."
        local _probe_out
        if _probe_out="$( (cd "$_probe_dir" && zig build-exe probe.zig -lc) 2>&1 )"; then
            _sdk_probe_result="pass"
            echo "  Zig SDK link probe PASSED"
        elif echo "$_probe_out" | /usr/bin/grep -qiE 'undefined symbol|symbol not found|unable to resolve|undefined reference'; then
            _sdk_probe_result="fail"
            echo "  Zig SDK link probe FAILED (unresolved libSystem symbols) — will activate synthetic sysroot workaround"
        else
            _sdk_probe_result="inconclusive"
            echo "  WARNING: Zig SDK link probe INCONCLUSIVE — probe did not reach the linker."
            echo "           This is a probe bug or toolchain change, NOT evidence the SDK is broken."
            echo "           Falling back to the libSystem.tbd targets heuristic. First lines:"
            echo "$_probe_out" | head -3 | sed 's/^/             /'
        fi
        rm -rf "$_probe_dir"
    fi
    # A passing probe is authoritative: Zig demonstrably links against this SDK,
    # so the synthetic sysroot is unnecessary regardless of what the top-level
    # `targets:` line says. Zig 0.16 resolves arm64e-macos .tbd targets that Zig
    # 0.15.2 could not, which is exactly the case the heuristic alone gets wrong.
    if [ "$_sdk_probe_result" = "pass" ]; then
        return 0
    fi
    if [ -z "$YEN_SKIP_ZIG_SDK_WORKAROUND" ]; then
        local xcode_sdk
        xcode_sdk="$(/usr/bin/xcrun --show-sdk-path 2>/dev/null || true)"
        if [ -n "$xcode_sdk" ] && [ -f "$xcode_sdk/usr/lib/libSystem.tbd" ]; then
            local top_targets
            top_targets="$(/usr/bin/grep -m1 '^targets:' "$xcode_sdk/usr/lib/libSystem.tbd" || true)"
            # Activate synthetic sysroot when EITHER the probe proved a link
            # failure OR (probe inconclusive) the top-`targets:` heuristic fires.
            # A passing probe already returned above.
            if [ "$_sdk_probe_result" = "fail" ] || ([ -n "$top_targets" ] && ! echo "$top_targets" | /usr/bin/grep -q 'arm64-macos[^e]'); then
                # Hunt for any SDK whose libSystem.tbd still lists arm64-macos.
                # The current default CLT may have been updated to arm64e-macos-only
                # (seen 2026-04-15 with CLT tracking macOS 26.4), in which case an
                # older SDK under CLT/SDKs/MacOSX<N>.sdk still carries arm64-macos.
                local clt_sdk=""
                for candidate in \
                    /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
                    /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk; do
                    [ -f "$candidate/usr/lib/libSystem.tbd" ] || continue
                    if /usr/bin/grep -m1 '^targets:' "$candidate/usr/lib/libSystem.tbd" 2>/dev/null | /usr/bin/grep -q 'arm64-macos[^e]'; then
                        clt_sdk="$candidate"
                        break
                    fi
                done
                if [ -n "$clt_sdk" ]; then
                    local clt_top
                    clt_top="$(/usr/bin/grep -m1 '^targets:' "$clt_sdk/usr/lib/libSystem.tbd" || true)"
                    if echo "$clt_top" | /usr/bin/grep -q 'arm64-macos[^e]'; then
                        if [ "$_sdk_probe_result" = "fail" ]; then
                            echo "  WARNING: Zig SDK link probe failed — libSystem symbols unresolved against current Xcode SDK"
                        else
                            echo "  WARNING: Xcode SDK .tbd targets lack arm64-macos (Xcode 26.4+ regression)"
                        fi
                        echo "  Creating synthetic sysroot with CLT .tbd files for Zig linker"

                        local synth="${TMPDIR:-/tmp}/yen-zig-sysroot"
                        local wrapper_dir="${TMPDIR:-/tmp}/yen-zig-xcrun-wrapper"
                        rm -rf "$synth" "$wrapper_dir"

                        # Build synthetic sysroot: CLT .tbd files + Xcode SDK structure
                        mkdir -p "$synth/usr/lib/system"
                        for item in "$xcode_sdk"/*; do
                            local bn; bn=$(basename "$item")
                            if [ "$bn" = "usr" ]; then
                                mkdir -p "$synth/usr"
                                for subitem in "$xcode_sdk/usr"/*; do
                                    local sbn; sbn=$(basename "$subitem")
                                    if [ "$sbn" = "lib" ]; then
                                        mkdir -p "$synth/usr/lib"
                                        for libitem in "$xcode_sdk/usr/lib"/*; do
                                            local lbn; lbn=$(basename "$libitem")
                                            case "$lbn" in
                                                *.tbd) ln -sf "$clt_sdk/usr/lib/$lbn" "$synth/usr/lib/$lbn" 2>/dev/null || ln -sf "$libitem" "$synth/usr/lib/$lbn" ;;
                                                system)
                                                    mkdir -p "$synth/usr/lib/system"
                                                    for sysitem in "$xcode_sdk/usr/lib/system"/*; do
                                                        local sybn; sybn=$(basename "$sysitem")
                                                        case "$sybn" in
                                                            *.tbd) ln -sf "$clt_sdk/usr/lib/system/$sybn" "$synth/usr/lib/system/$sybn" 2>/dev/null || ln -sf "$sysitem" "$synth/usr/lib/system/$sybn" ;;
                                                            *) ln -sf "$sysitem" "$synth/usr/lib/system/$sybn" ;;
                                                        esac
                                                    done
                                                    ;;
                                                *) ln -sf "$libitem" "$synth/usr/lib/$lbn" ;;
                                            esac
                                        done
                                    else
                                        ln -sf "$subitem" "$synth/usr/$sbn"
                                    fi
                                done
                            else
                                ln -sf "$item" "$synth/$bn"
                            fi
                        done

                        # Create xcrun wrapper that returns synthetic sysroot for macOS queries.
                        # IMPORTANT: only intercept when NOT in an xcodebuild context.
                        # xcodebuild and Apple's ld64 handle arm64e-only .tbd targets natively.
                        # xcodebuild sets BUILT_PRODUCTS_DIR; Zig does not.
                        mkdir -p "$wrapper_dir"
                        cat > "$wrapper_dir/xcrun" << 'XCRUN_WRAPPER'
#!/bin/bash
REAL_XCRUN=/usr/bin/xcrun
SYNTH_SYSROOT="__SYNTH_PLACEHOLDER__"

# Skip synthetic sysroot when running inside xcodebuild (sets BUILT_PRODUCTS_DIR)
if [ -z "${BUILT_PRODUCTS_DIR:-}" ] && [[ " $* " == *" --show-sdk-path "* ]]; then
    sdk=""; prev_was_sdk=0
    for arg in "$@"; do
        if [ "$prev_was_sdk" = "1" ]; then sdk="$arg"; break; fi
        [ "$arg" = "--sdk" ] && prev_was_sdk=1 || prev_was_sdk=0
    done
    if [ -z "$sdk" ] || [ "$sdk" = "macosx" ]; then
        if [ -d "$SYNTH_SYSROOT" ]; then echo "$SYNTH_SYSROOT"; exit 0; fi
    fi
fi
exec "$REAL_XCRUN" "$@"
XCRUN_WRAPPER
                        sed -i '' "s|__SYNTH_PLACEHOLDER__|$synth|" "$wrapper_dir/xcrun"
                        chmod +x "$wrapper_dir/xcrun"

                        export PATH="$wrapper_dir:$PATH"
                        ZIG_SDK_WORKAROUND_ACTIVE="1"
                        echo "  Synthetic sysroot ready: $synth"
                    fi
                fi
            fi
        fi
    fi
}

teardown_zig_sdk_workaround() {
    if [ -n "$ZIG_SDK_WORKAROUND_ACTIVE" ]; then
        export PATH="$ZIG_SDK_WORKAROUND_ORIG_PATH"
        ZIG_SDK_WORKAROUND_ACTIVE=""
    fi
}
