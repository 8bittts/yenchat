#!/bin/bash
# macOS-native validation loop for YEN.
# Default mode is the narrowest trustworthy check for Codex/local iteration.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
YEN_TERMINAL_ROOT="$REPO_ROOT/yen-terminal"
XCODE_PROJECT="$REPO_ROOT/yen-terminal/ghostty/macos/YEN.xcodeproj"
XCFRAMEWORK_PATH="$REPO_ROOT/yen-terminal/ghostty/macos/YENKit.xcframework"
MODE="fast"
SKIP_VENDOR=true

usage() {
    cat <<'EOF'
Usage: bash $HOME/Documents/yenchat/scripts/native/01-macos-smoke.sh [--fast|--browser|--browser-live|--local|--build-only] [--vendor]

Modes:
  --fast          Targeted xcodebuild regression loop for the YEN macOS scheme (default)
  --browser       Focused native browser command/settings regression loop
  --browser-live  Launch zig-out/YEN.app directly and smoke the yen web bridge
  --local         Incremental local build via build-release.sh --local
  --build-only    Clean compile loop via build-release.sh --build-only

Options:
  --vendor      Keep the vendor gate enabled for --local / --build-only
  --help        Show this help

Notes:
  - --fast / --browser require yen-terminal/ghostty/macos/YENKit.xcframework to exist.
  - --browser-live requires a built yen-terminal/ghostty/zig-out/YEN.app.
  - --local / --build-only default YEN_PREBUILD_COMPONENT_GATE_MODE=off for fast iteration.
    Set YEN_PREBUILD_COMPONENT_GATE_MODE=enforce|report if you want build-release.sh to rerun
    the pre-build component gate.
  - Release packaging/signing stays on /update-yen and build-release.sh outside this helper.
  - A native UI change is verified only in a running build you have identified:
    zig-out/YEN.app and /Applications/YEN.app share com.yenchat.yen, and finding a
    string in the binary proves nothing. A view that does not render is usually its
    own data dependency, not a stale incremental build. See _docs/05-infrastructure.md
    -> Native Test Suite.
EOF
}

xcframework_ready() {
    local info_plist
    local library_count

    info_plist="$XCFRAMEWORK_PATH/Info.plist"
    library_count=0

    if [ -d "$XCFRAMEWORK_PATH" ]; then
        library_count=$(
            find "$XCFRAMEWORK_PATH" \
                \( -name "*.a" -o -name "*.dylib" \) \
                -type f 2>/dev/null | wc -l | tr -d '[:space:]'
        )
    fi

    [ -d "$XCFRAMEWORK_PATH" ] && [ -f "$info_plist" ] && [ "$library_count" -gt 0 ]
}

for arg in "$@"; do
    case "$arg" in
        --fast)
            MODE="fast"
            ;;
        --browser)
            MODE="browser"
            ;;
        --browser-live)
            MODE="browser-live"
            ;;
        --local)
            MODE="local"
            ;;
        --build-only|--build)
            MODE="build-only"
            ;;
        --vendor)
            SKIP_VENDOR=false
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $arg" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ ! -f "$XCODE_PROJECT/project.pbxproj" ]; then
    echo "ERROR: Missing Xcode project: $XCODE_PROJECT" >&2
    exit 1
fi

case "$MODE" in
    fast|browser)
        if ! command -v xcodebuild >/dev/null 2>&1; then
            echo "ERROR: xcodebuild not available" >&2
            exit 1
        fi

        echo "Syncing overlays into ghostty mirror..."
        bash "$YEN_TERMINAL_ROOT/apply-overlays.sh"

        echo "Linting SwiftUI view-modifier hygiene..."
        bash "$REPO_ROOT/scripts/41-lint-swift-view-modifiers.sh"

        echo "Linting overlay recurrence gates..."
        bash "$REPO_ROOT/scripts/42-lint-overlay-recurrence-gates.sh"

        if ! xcframework_ready; then
            echo "ERROR: YENKit.xcframework is missing or incomplete." >&2
            echo "Run: bash $HOME/Documents/yenchat/scripts/native/01-macos-smoke.sh --local" >&2
            exit 1
        fi

        if [ "$MODE" = "browser" ]; then
            XCODE_BROWSER_TEST_ARGS=(
                -project "$XCODE_PROJECT"
                -scheme YEN
                -configuration Debug
                -sdk macosx
                -parallel-testing-enabled NO
                -only-testing:YENTests/WebPreviewCommandTests
                -only-testing:YENTests/BrowserSplitWindowTests
            )
            XCODE_BROWSER_SETTINGS_TEST_ARGS=(
                -project "$XCODE_PROJECT"
                -scheme YEN
                -configuration Debug
                -sdk macosx
                -parallel-testing-enabled NO
                -only-testing:YENTests/TabSidebarPreferencesTests
                -only-testing:YENTests/WorkspaceSettingsStoreTests
            )

            echo "YEN macOS browser smoke"
            xcodebuild "${XCODE_BROWSER_TEST_ARGS[@]}" test
            xcodebuild "${XCODE_BROWSER_SETTINGS_TEST_ARGS[@]}" test
        else
            XCODE_TEST_ARGS=(
                -project "$XCODE_PROJECT"
                -scheme YEN
                -configuration Debug
                -sdk macosx
                -parallel-testing-enabled NO
                -only-testing:YENTests/SettingsCommandPaletteDeepLinkTests
                -only-testing:YENTests/SettingsLoadConfigNotificationTests
                -only-testing:YENTests/SettingsConfigMergeTests
                -only-testing:YENTests/SettingsConfigPathTests
                -only-testing:YENTests/SettingsThemeCatalogTests
                -only-testing:YENTests/WindowBorderPreferencesTests
                -only-testing:YENTests/WindowBorderRenderingPolicyTests
                -only-testing:YENTests/WebPreviewURLPolicyTests
                -only-testing:YENTests/WebPreviewModelTests
                -only-testing:YENTests/ServiceNotificationResponseRoutingTests
                -only-testing:YENTests/ScreenshotNotificationStatusTests
                -only-testing:YENTests/TerminalBackgroundImageLoaderTests
                -only-testing:YENTests/SettingsShortcutsCatalogTests
                -only-testing:YENTests/IntentPermissionTests
                -only-testing:YENTests/CommandEntityIdentityTests
                -only-testing:YENTests/CommandPaletteViewTests
                -only-testing:YENTests/TerminalCommandPalettePresentationTests
                -only-testing:YENTests/TerminalCommandPaletteJumpTargetsModelTests
                -only-testing:YENTests/TerminalCommandPaletteAuditEdgeCaseTests
                -only-testing:YENTests/TerminalCommandPaletteSearchTests
                -only-testing:YENTests/ReviewWorkingDirectoryTests
                -only-testing:YENTests/PullRequestReviewDiffParserTests
                -only-testing:YENTests/PullRequestReviewModelTests
                -only-testing:YENTests/IDEEditorNavigatorTests
                -only-testing:YENTests/GitDrawerPresentationTests
                -only-testing:YENTests/SplitPaneLabelRulesTests
                -only-testing:YENTests/SplitPaneWorktreeLabelRulesTests
                -only-testing:YENTests/SplitPaneWorktreeLabelStoreTests
                -only-testing:YENTests/AgentWorkingDirectoryTests
                -only-testing:YENTests/MergeConflictParserTests
                -only-testing:YENTests/MergeConflictResolutionModelTests
                -only-testing:YENTests/IDEBlockingProcessRunnerTests
                -only-testing:YENTests/GeneralSettingsStoreTests
                -only-testing:YENTests/TokenPlanUsageTests
                -only-testing:YENTests/TokenUsageIndexTests
                -only-testing:YENTests/WallpaperStateTests
                -only-testing:YENTests/WallpaperToggleTests
                -only-testing:YENTests/YouTubeDownloaderTests
                -only-testing:YENTests/KeyboardSettingsStoreTests
                -only-testing:YENTests/SoundsSettingsStoreTests
                -only-testing:YENTests/ThemesSettingsStoreTests
                -only-testing:YENTests/WorkspaceSettingsStoreTests
                -only-testing:YENTests/SplitFocusClickHitTestingTests
                -only-testing:YENTests/AppMenuShortcutControllerTests
                -only-testing:YENTests/DirectionalSplitShortcutTests
                -only-testing:YENTests/ScratchpadControllerTests
                -only-testing:YENTests/ScratchpadStorageTests
                -only-testing:YENTests/UtilityWindowLifecycleTests
                -only-testing:YENTests/TabSidebarBehaviorTests
                -only-testing:YENTests/DisabledFeatureToastTests
                -only-testing:YENTests/DictationPermissionStateTests
                -only-testing:YENTests/DictationPasteEventTests
                -only-testing:YENTests/DictationAudioDeviceTests
                -only-testing:YENTests/DictationAudioDeviceMonitorTests
                -only-testing:YENTests/DictationInputDeviceOptionsTests
                -only-testing:YENTests/DictationTwoDeviceSwitchTests
                -only-testing:YENTests/DictationAudioEngineTapConfigurationTests
                -only-testing:YENTests/DictationAudioEngineTapConfigurationTests
                -only-testing:YENTests/OverlayTokenLintTests
                -only-testing:YENTests/AppDelegateIconTests
                -only-testing:YENTests/BackgroundImageScopePreferencesTests
                -only-testing:YENTests/BackgroundImageStoreTests
                -only-testing:YENTests/ColorizedYENIconTests
                -only-testing:YENTests/ConfigTests
                -only-testing:YENTests/ConflictShortcutCacheTests
                -only-testing:YENTests/CopyOnSelectClipboardTests
                -only-testing:YENTests/DictationTranslationPreferencesTests
                -only-testing:YENTests/FixedShortcutCatalogTests
                -only-testing:YENTests/GitDrawerDiffAttributedStringTests
                -only-testing:YENTests/GitDrawerDiffCopyOnSelectIntegrationTests
                -only-testing:YENTests/GitDrawerDiffFocusProbeTests
                -only-testing:YENTests/GitDrawerSnapshotParserTests
                -only-testing:YENTests/KeyRecorderBehaviorTests
                -only-testing:YENTests/LayoutPresetTests
                -only-testing:YENTests/MenuShortcutManagerTests
                -only-testing:YENTests/NSPasteboardTypeExtensionTests
                -only-testing:YENTests/NSScreenExtensionTests
                -only-testing:YENTests/NativeFullscreenTransitionTests
                -only-testing:YENTests/NormalizedMenuShortcutKeyTests
                -only-testing:YENTests/NotificationSoundImportTests
                -only-testing:YENTests/OnboardingWindowLifecycleTests
                -only-testing:YENTests/ReleaseNotesTests
                -only-testing:YENTests/ServiceNotificationPayloadTests
                -only-testing:YENTests/SettingsAppearanceControlsTests
                -only-testing:YENTests/SettingsBackgroundImageControlsTests
                -only-testing:YENTests/SettingsBehaviorControlsTests
                -only-testing:YENTests/SettingsCursorControlsTests
                -only-testing:YENTests/SettingsDictationControlsTests
                -only-testing:YENTests/SettingsMenuShortcutTests
                -only-testing:YENTests/SettingsNotificationSoundControlsTests
                -only-testing:YENTests/SettingsPaddingControlsTests
                -only-testing:YENTests/SettingsShellControlsTests
                -only-testing:YENTests/SettingsPaneTests
                -only-testing:YENTests/SettingsTypographyControlsTests
                -only-testing:YENTests/SettingsWindowLifecycleTests
                -only-testing:YENTests/PersistentSessionReaperTests
                -only-testing:YENTests/PersistentSessionsTests
                -only-testing:YENTests/RemoteSessionsTests
                -only-testing:YENTests/TailscaleDiscoveryTests
                -only-testing:YENTests/RemoteHostsStoreTests
                -only-testing:YENTests/RemotePanesTests
                -only-testing:YENTests/RemoteHostsPaletteRowsTests
                -only-testing:YENTests/SessionStateTests
                -only-testing:YENTests/TabSidebarHostsSectionTests
                -only-testing:YENTests/SessionDirectoryRepairTests
                -only-testing:YENTests/RemoteDiscoveryContractTests
                -only-testing:YENTests/ShellTests
                -only-testing:YENTests/SplitTreeTests
                -only-testing:YENTests/SurfaceRouteEnvironmentTests
                -only-testing:YENTests/SystemSettingsOpenerTests
                -only-testing:YENTests/TabSidebarMetadataTests
                -only-testing:YENTests/TerminalChromeAppearanceTests
                -only-testing:YENTests/TerminalClipboardImagePasteboardTests
                -only-testing:YENTests/TerminalClipboardShortcutTests
                -only-testing:YENTests/TerminalCommandPaletteJumpTitleTests
                -only-testing:YENTests/TerminalPresentationSettingsTests
                -only-testing:YENTests/TerminalRestorableVersionTests
                -only-testing:YENTests/TerminalSplitDropZoneTests
                -only-testing:YENTests/TerminalSurfaceCommandLauncherTests
                -only-testing:YENTests/TerminalViewContainerTests
                -only-testing:YENTests/ThemeConfigRepairTests
                -only-testing:YENTests/ThemePreviewCacheTests
                -only-testing:YENTests/TransferablePasteboardTests
                -only-testing:YENTests/UpdateStateTests
                -only-testing:YENTests/UpdateViewModelTests
            )

            echo "YEN macOS fast smoke"
            xcodebuild "${XCODE_TEST_ARGS[@]}" build-for-testing

            # [CRITICAL] Fail closed on a run that executed nothing.
            #
            # xcodebuild prints "** TEST EXECUTE SUCCEEDED **" and exits 0 for a run
            # that executed ZERO cases -- an empty target, a suite that self-skips,
            # or an -only-testing filter matching nothing all produce that. A green
            # exit code is therefore not evidence that any test ran. Assert a
            # POSITIVE executed count instead.
            # Native source assertions read byte-verified copies, so a fresh test
            # host never needs Documents access just to inspect its own source.
            NATIVE_SOURCE_FIXTURES=$(mktemp -d "${TMPDIR:-/tmp}/yen-native-source.XXXXXX")
            trap 'rm -rf "$NATIVE_SOURCE_FIXTURES"' EXIT
            python3 "$REPO_ROOT/scripts/native/source-fixtures.py" prepare "$REPO_ROOT" "$NATIVE_SOURCE_FIXTURES"
            FAST_TEST_LOG="${TMPDIR:-/tmp}/yen-fast-test.$$.log"
            set +e
            TEST_RUNNER_YEN_NATIVE_TEST_SOURCE_ROOT="$NATIVE_SOURCE_FIXTURES" xcodebuild "${XCODE_TEST_ARGS[@]}" test-without-building 2>&1 | tee "$FAST_TEST_LOG"
            FAST_TEST_STATUS=${PIPESTATUS[0]}
            set -e

            FAST_TEST_COUNT="$(/usr/bin/sed -n 's/.*Test run with \([0-9][0-9]*\) tests.*/\1/p' "$FAST_TEST_LOG" | /usr/bin/tail -1)"
            [ -n "$FAST_TEST_COUNT" ] || FAST_TEST_COUNT=0

            if [ "$FAST_TEST_STATUS" -ne 0 ]; then
                echo "RECEIPT gate=native-fast executed=$FAST_TEST_COUNT result=FAIL"
                rm -f "$FAST_TEST_LOG"
                exit "$FAST_TEST_STATUS"
            fi

            if [ "$FAST_TEST_COUNT" -eq 0 ]; then
                echo "  ERROR: xcodebuild reported success but executed 0 tests." >&2
                echo "         An empty target, a self-skipping suite, or an -only-testing" >&2
                echo "         filter matching nothing all look identical to a pass here." >&2
                echo "RECEIPT gate=native-fast executed=0 result=FAIL"
                rm -f "$FAST_TEST_LOG"
                exit 1
            fi

            python3 "$REPO_ROOT/scripts/native/source-fixtures.py" verify "$REPO_ROOT" "$NATIVE_SOURCE_FIXTURES"

            echo "RAN|native-fast|executed=$FAST_TEST_COUNT"
            echo "RECEIPT gate=native-fast executed=$FAST_TEST_COUNT result=PASS"
            rm -f "$FAST_TEST_LOG"
        fi
        ;;
    browser-live)
        LOCAL_APP_BIN="$REPO_ROOT/yen-terminal/ghostty/zig-out/YEN.app/Contents/MacOS/yen"
        LOCAL_APP_BIN_CANONICAL=""
        WEB_CLI="$REPO_ROOT/yen-cli/commands/core/web"
        LIVE_LOG="${TMPDIR:-/tmp}/yen-browser-live-smoke.$$.log"
        STATUS_OUT="${TMPDIR:-/tmp}/yen-browser-live-status.$$.out"
        LOCAL_PID=""
        STARTED_LOCAL=false
        EXISTING_LOCAL_RUNNING=false
        NONLOCAL_YEN_RUNNING=false

        if [ ! -x "$LOCAL_APP_BIN" ]; then
            echo "ERROR: Missing built app executable: $LOCAL_APP_BIN" >&2
            echo "Run: bash $HOME/Documents/yenchat/scripts/native/01-macos-smoke.sh --build-only" >&2
            exit 1
        fi
        LOCAL_APP_BIN_CANONICAL="$(cd "$(dirname "$LOCAL_APP_BIN")" && pwd -P)/$(basename "$LOCAL_APP_BIN")"

        if [ ! -x "$WEB_CLI" ]; then
            echo "ERROR: Missing executable yen web CLI: $WEB_CLI" >&2
            exit 1
        fi

        while IFS= read -r line; do
            case "$line" in
                *"/YEN.app/Contents/MacOS/yen"*)
                    case "$line" in
                        *"$LOCAL_APP_BIN"*)
                            EXISTING_LOCAL_RUNNING=true
                            if [ -z "$LOCAL_PID" ]; then
                                set -- $line
                                LOCAL_PID="$1"
                            fi
                            ;;
                        *) NONLOCAL_YEN_RUNNING=true ;;
                    esac
                    ;;
            esac
        done <<EOF
$(ps -axo pid=,args=)
EOF

        if [ "$EXISTING_LOCAL_RUNNING" != true ]; then
            "$LOCAL_APP_BIN" >"$LIVE_LOG" 2>&1 &
            LOCAL_PID=$!
            STARTED_LOCAL=true
        fi

        cleanup_browser_live() {
            rm -f "$STATUS_OUT"
            if [ "$STARTED_LOCAL" = true ] && [ -n "$LOCAL_PID" ]; then
                kill "$LOCAL_PID" >/dev/null 2>&1 || true
                wait "$LOCAL_PID" >/dev/null 2>&1 || true
            fi
        }
        trap cleanup_browser_live EXIT

        attempts=0
        while [ "$attempts" -lt 20 ]; do
            if ps -p "$LOCAL_PID" >/dev/null 2>&1; then
                break
            fi
            attempts=$((attempts + 1))
            sleep 0.5
        done

        if ! ps -p "$LOCAL_PID" >/dev/null 2>&1; then
            echo "ERROR: Local YEN.app exited before browser live smoke." >&2
            tail -n 40 "$LIVE_LOG" >&2 || true
            exit 1
        fi

        # Give AppDelegate enough time to install the distributed-notification receiver.
        sleep 2

        echo "YEN macOS browser live smoke"
        YEN_LIB="$REPO_ROOT/yen-cli/lib" "$WEB_CLI" status >"$STATUS_OUT"
        cat "$STATUS_OUT"
        if ! grep -Fq "acknowledged_executable=$LOCAL_APP_BIN_CANONICAL" "$STATUS_OUT"; then
            echo "ERROR: yen web status did not acknowledge the rebuilt app executable." >&2
            exit 1
        fi

        if [ "$NONLOCAL_YEN_RUNNING" = true ] || [ "$EXISTING_LOCAL_RUNNING" = true ]; then
            echo "Existing YEN.app process detected; skipped open/close mutation smoke."
            echo "Quit other YEN.app instances and rerun --browser-live for the full open/close path."
            exit 0
        fi

        YEN_LIB="$REPO_ROOT/yen-cli/lib" "$WEB_CLI" open >/tmp/yen-browser-live-open.$$.out
        if ! grep -q "Browser window opened" "/tmp/yen-browser-live-open.$$.out"; then
            cat "/tmp/yen-browser-live-open.$$.out"
            echo "ERROR: yen web open did not report a browser window." >&2
            exit 1
        fi

        YEN_LIB="$REPO_ROOT/yen-cli/lib" "$WEB_CLI" close >/tmp/yen-browser-live-close.$$.out
        if ! grep -q "Browser window closed" "/tmp/yen-browser-live-close.$$.out"; then
            cat "/tmp/yen-browser-live-close.$$.out"
            echo "ERROR: yen web close did not report a browser window close." >&2
            exit 1
        fi

        rm -f "/tmp/yen-browser-live-open.$$.out" "/tmp/yen-browser-live-close.$$.out"
        ;;
    local|build-only)
        BUILD_ARGS=()
        if [ "$MODE" = "local" ]; then
            BUILD_ARGS+=(--local)
        else
            BUILD_ARGS+=(--build-only)
        fi

        if [ "$SKIP_VENDOR" = true ]; then
            BUILD_ARGS+=(--skip-vendor)
        fi

        if [ -z "${YEN_PREBUILD_COMPONENT_GATE_MODE:-}" ]; then
            export YEN_PREBUILD_COMPONENT_GATE_MODE=off
        fi

        # Snapshot vendor-tracking files so we can surface a clear revert command
        # if the build fails (e.g. mid-/vendor run hits a Zig/SDK/link issue).
        SMOKE_VENDOR_SNAPSHOT_PATHS=(
            "yen-terminal/.ghostty-baseline"
            "yen-terminal/VENDOR_INFO.txt"
            "_docs/04-security.md"
        )
        SMOKE_VENDOR_DIRTY_BEFORE=""
        if command -v git >/dev/null 2>&1; then
            SMOKE_VENDOR_DIRTY_BEFORE=$(git -C "$REPO_ROOT" status --porcelain -- "${SMOKE_VENDOR_SNAPSHOT_PATHS[@]}" 2>/dev/null || true)
        fi

        set +e
        bash "$YEN_TERMINAL_ROOT/customizations/build-release.sh" "${BUILD_ARGS[@]}"
        SMOKE_BUILD_EXIT=$?
        set -e

        SMOKE_VENDOR_DIRTY_AFTER=""
        if command -v git >/dev/null 2>&1; then
            SMOKE_VENDOR_DIRTY_AFTER=$(git -C "$REPO_ROOT" status --porcelain -- "${SMOKE_VENDOR_SNAPSHOT_PATHS[@]}" 2>/dev/null || true)
        fi

        if [ "$SMOKE_BUILD_EXIT" -ne 0 ] && [ -n "$SMOKE_VENDOR_DIRTY_AFTER" ] && [ "$SMOKE_VENDOR_DIRTY_AFTER" != "$SMOKE_VENDOR_DIRTY_BEFORE" ]; then
            echo ""
            echo "  WARNING: build failed after changing vendor-tracking files."
            echo "  To roll back to the previous known-good state, run:"
            echo "    git -C \"$REPO_ROOT\" checkout -- ${SMOKE_VENDOR_SNAPSHOT_PATHS[*]}"
            echo "  (Do this BEFORE re-running the /update-yen vendor phase so 10-update-ghostty.sh can see the old baseline.)"
        fi
        exit "$SMOKE_BUILD_EXIT"
        ;;
esac
