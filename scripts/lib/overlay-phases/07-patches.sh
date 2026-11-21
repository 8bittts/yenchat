#!/bin/bash
# Sourced by apply-overlays.sh; inherits its working directory and fail-fast mode.

# ============================================================================
# RETIRED 2026-04-30: Split Opacity Bridge rollback
# ============================================================================
# Defensive rollback script that converted YEN's removed true-pane split
# transparency variant (`return opacity` + 0.7 default) back to upstream's
# overlay-fill mapping (`return 1 - opacity` + 0.85 default). The YEN variant
# was removed long ago and we now vendor fresh from upstream every vendor run,
# so the rollback's pre-patch shape never appears. Reported "idempotent skip"
# on every run since retirement of the variant. Removed for clarity.

CONFIG_SWIFT="ghostty/macos/Sources/YEN/Ghostty.Config.swift"

# ============================================================================
# Preserve upstream undo-timeout default when the config key is absent
# ============================================================================
# The Swift bridge must keep Ghostty's 5s default when `undo-timeout` is unset;
# otherwise missing config values read back as `0ms` and silently disable undo.

apply_overlay_patch config-owner-teardown
apply_overlay_patch undo-timeout-default-preservation
apply_overlay_patch workspace-titlebar-default
apply_overlay_patch workspace-tabs-tahoe
apply_overlay_patch workspace-tabs-ventura

# ============================================================================
# RETIRED 2026-04-30: SurfaceView Split Rendering rollback
# ============================================================================
# Companion to the Split Opacity Bridge retirement above. Defensive rollback
# script that reverted YEN's removed true-pane split transparency
# (SurfaceRepresentable .opacity(...) on the surface + clear overlay layer)
# back to upstream's overlay-fill semantics (opaque surface + semi-transparent
# Rectangle dim overlay). The YEN variant was removed long ago; the rollback
# never had a shape to convert and reported "idempotent skip" on every run.
# Removed for clarity.

# ============================================================================
# Fix YEN_BIN_DIR to Point to Resources/bin (Bundled Tools)
# ============================================================================
# Upstream Ghostty sets GHOSTTY_BIN_DIR (renamed to YEN_BIN_DIR by branding)
# to Contents/MacOS/ (the app executable directory). But YEN bundles tools
# (yen, yazi, fd, rg, etc.) in Contents/Resources/bin/. Without this patch,
# customers can't find bundled tools when shell frameworks reset PATH.
# Fix: prefer Resources/bin, fall back to MacOS/ if not found.

EXEC_ZIG="ghostty/src/termio/Exec.zig"
apply_overlay_patch yen-bin-dir-fix
apply_overlay_patch persistent-session-exec
apply_overlay_patch persistent-session-prepare-call
apply_overlay_patch persistent-session-subprocess-field
apply_overlay_patch persistent-session-subprocess-return
apply_overlay_patch persistent-session-threaddata-field
apply_overlay_patch persistent-session-threaddata-init
apply_overlay_patch persistent-session-termios-poll

# ============================================================================
# RETIRED: Park Hidden Renderer Swap Chains on Embedded Builds
# ============================================================================
# Three patches lived here ("hidden swap-chain import", "hidden swap-chain
# renderer", "hidden swap-chain thread ordering"). They dropped the large
# IOSurface-backed swap chain of an occluded YEN surface and restored it before
# the next draw, gated on `park_hidden_swap_chain = build_config.artifact == .lib`.
#
# Upstream ghostty-org/ghostty 683d8db6 ("renderer: release GPU resources for
# hidden surfaces (macOS)", #14017) implements the same behavior natively and
# more robustly, so carrying the fork is now pure risk:
#   - `swap_chain` became `?SwapChain`, replacing the `defunct` bool that YEN's
#     patch and upstream's `displayUnrealized` both leaned on.
#   - A new `display_realized` guard stops `drawFrame` rebuilding the chain when
#     there is no GPU context.
#   - `releaseGpuResources()` is called from `setVisible(false)` under
#     `comptime !apprt.must_draw_from_app_thread`, and the chain is rebuilt on
#     the next `drawFrame`.
#   - OpenGL grew a `gpuResourcesReleased()` hook to drop its last target.
#
# The gate is equivalent for YEN: `must_draw_from_app_thread = true` is declared
# only in `src/apprt/gtk/App.zig`, so it is false for the embedded macOS build
# and upstream releases on hide exactly where YEN's `.lib` gate did.
#
# Upstream also made `setVisible` non-fallible (`void`, not `!void`) and removed
# the `try` at its Thread.zig call site, which is what broke these anchors — the
# _docs/04-security.md row had predicted precisely that failure mode.
#
# Do not reintroduce these patches. tests/45-overlay-patching.test.ts asserts
# this block stays absent; if a future upstream drops the behavior, re-add it
# against upstream's `releaseGpuResources` shape rather than the old `defunct`
# one, and delete the marker test in the same commit.

# ============================================================================
# Remove Obsolete Layout System (replaced by window-save-state = always)
# ============================================================================
# Previous builds copied layout overlay files into ghostty/. These must be
# explicitly removed since apply-overlays only copies, never deletes.

remove_overlay_retired_files layout-sources
rmdir ghostty/macos/Sources/Features/Layout 2>/dev/null || true
remove_overlay_retired_files layout-tests
rmdir ghostty/macos/Tests/Layout 2>/dev/null || true

# ============================================================================
# Set window-save-state Default to "always"
# ============================================================================
# Ghostty's compiled default is "default" (only saves on force quit on macOS).
# YEN should always save window state so splits/tabs restore on relaunch.

CONFIG_ZIG="ghostty/src/config/Config.zig"
if grep -q 'WindowSaveState = .default' "$CONFIG_ZIG"; then
    sed -i '' 's/WindowSaveState = .default/WindowSaveState = .always/' "$CONFIG_ZIG"
    sed -i '' 's/The default value is `default`/The default value is `always`/' "$CONFIG_ZIG"
    echo "    Patched window-save-state default to always"
    overlay_note_applied
fi
# Fail closed: assert the end-state regardless of how we got here. A silent
# skip on anchor drift would otherwise ship upstream's force-quit-only default.
if ! grep -q 'WindowSaveState = .always' "$CONFIG_ZIG"; then
    echo "    ERROR: window-save-state default is not .always (anchor drift or upstream change); refusing to ship" >&2
    exit 1
fi

# ============================================================================
# Persist Tab Title Overrides in Window Restoration Snapshots
# ============================================================================
# Upstream already serializes titleOverride into TerminalRestorableState, but
# BaseTerminalController does not dirty AppKit's restorable state when a user
# renames a tab. Without that invalidation, renamed vertical-tab titles can
# disappear on quit/relaunch if AppKit never takes another snapshot.

BASE_TERMINAL_CONTROLLER="ghostty/macos/Sources/Features/Terminal/BaseTerminalController.swift"
apply_overlay_patch baseterminalcontroller-titleoverride-restorable-state-invalidation

# ============================================================================
# Defer Terminal Resign-Key Focus Sync
# ============================================================================
# Opening a standalone YEN Browser window from a terminal URL click makes the
# terminal window resign key while libyen is still unwinding the surface click
# handler. Calling yen_surface_set_focus synchronously from that resign-key
# notification can recursively enter the surface unfair lock. Match the
# become-key path and defer the focus sync to the next main-loop turn.

apply_overlay_patch baseterminalcontroller-windowdidresignkey-focus-deferral

# ============================================================================
# Bound Native Window Resize Geometry
# ============================================================================
# macOS Move & Resize actions can accumulate point-rounding drift across Fill /
# Center cycles and eventually propose a frame larger than the usable display.
# Reject only oversized dimensions before AppKit accepts the resize; preserve the
# user's ability to position a normal-sized window partially off-screen.

apply_overlay_patch baseterminalcontroller-visible-frame-resize-bound

# ============================================================================
# Native Fullscreen Transition Guard + Window-State Hardening
# ============================================================================
# AppKit native fullscreen toggles are asynchronous. We keep the transition
# state on the window via overlay helpers, ignore reentrant toggle requests
# while AppKit is mid-transition, and make window-style consumers read
# effective fullscreen state instead of settled style-mask state only.

apply_overlay_patch baseterminalcontroller-native-fullscreen-guard

FULLSCREEN_HELPER="ghostty/macos/Sources/Helpers/Fullscreen.swift"
if [ -f "$FULLSCREEN_HELPER" ]; then
    python3 "$REPO_ROOT/scripts/lib/native-fullscreen-helper.py" "$FULLSCREEN_HELPER"
fi

HIDDEN_TITLEBAR_WINDOW="ghostty/macos/Sources/Features/Terminal/Window Styles/HiddenTitlebarTerminalWindow.swift"
apply_overlay_patch hiddentitlebarterminalwindow-effective-fullscreen-state

TERMINAL_CONTROLLER="ghostty/macos/Sources/Features/Terminal/TerminalController.swift"
apply_overlay_patch terminalcontroller-effective-fullscreen-state

# CSI 8 t (`vt-window-resize-allowed`) calls resizeWindow, whose upstream guard
# checks only fullscreenStyle. A native transition has no `.fullScreen` style
# mask yet, so also refuse while the window is effectively fullscreen.
apply_overlay_patch terminalcontroller-resizewindow-fullscreen-guard

TERMINAL_WINDOW="ghostty/macos/Sources/Features/Terminal/Window Styles/TerminalWindow.swift"
apply_overlay_patch terminalwindow-effective-fullscreen-state

# ============================================================================
# Set copy-on-select Default to "both" on macOS
# ============================================================================
# Ghostty's compiled default on macOS is "primary" (selection clipboard only).
# On macOS, YEN maps the selection clipboard to a private named pasteboard
# (com.yenchat.yen.selection), so selected text never reaches NSPasteboard.general.
# Fix: default to "both" which copies to the system clipboard AND the selection
# clipboard, so Cmd+V works while preserving middle-click paste from the
# selection buffer. ("clipboard" is standard-clipboard-only as of the
# CopyOnSelect enum rework; "both" is the value that keeps YEN's original
# both-clipboards behavior.)

apply_overlay_patch copy-on-select-default-patch

echo "  copy-on-select patched to .both on macOS"

# ============================================================================
# Remap write_screen_file Defaults to Avoid Scratchpad Collision
# ============================================================================
# Ghostty defaults use Cmd+Shift+J for write_screen_file:paste, which collides
# with YEN's fixed scratchpad shortcut. Keep write_screen_file behavior but move
# the trio to Cmd+Shift+U:
#   Cmd+Ctrl+Shift+U => copy path
#   Cmd+Shift+U      => paste path
#   Cmd+Opt+Shift+U  => open file
apply_overlay_patch write-screen-file-copy-remap

apply_overlay_patch write-screen-file-paste-remap

apply_overlay_patch write-screen-file-open-remap

echo "  write_screen_file hotkeys remapped to Cmd+Shift+U family"

# ============================================================================
# Add Default Quick Terminal Keybind (global: Ctrl+`)
# ============================================================================
# Upstream has no default keybind for toggle_quick_terminal. YEN adds one
# so Ctrl+` works globally out of the box. Uses putFlags with .global=true
# so the global event tap fires when YEN is not focused.

if ! grep -A2 'toggle_quick_terminal' "$CONFIG_ZIG" | grep -q '\.global = true'; then
    apply_overlay_patch quick-terminal-keybind-patch

    echo "    Injected Quick Terminal default keybind (global Ctrl+\`)"
    overlay_note_applied
fi

# Verify the keybind was injected — check toggle_quick_terminal and .global = true are in the same block
if ! grep -A2 'toggle_quick_terminal' "$CONFIG_ZIG" | grep -q '\.global = true'; then
    echo "  ERROR: Quick Terminal default keybind not found after injection"
    exit 1
fi

# ============================================================================
# Fix Shift+Enter — Keybind Sends \r in All Modes
# NOTE: Depends on the Quick Terminal keybind injection above (used as anchor).
# ============================================================================
# The terminal engine sends garbled escape sequences for Shift+Enter:
#   - Legacy mode: \x1b[27;2;13~ (xterm modifyOtherKeys) — shells dump "2;13~"
#   - Kitty protocol: \x1b[13;2u (CSI u) — many CLI tools don't handle this
# Every other major terminal (iTerm2, Terminal.app, Alacritty) sends plain \r.
# Fix: inject a default keybind so Shift+Enter sends \r. Keybinds fire before
# the key encoder, so this works in both legacy and kitty protocol modes.
# Users can override with: keybind = shift+enter=unbind

if ! grep -q 'Shift+Enter fix' "$CONFIG_ZIG"; then
    apply_overlay_patch shift-enter-keybind-patch

    echo "    Injected Shift+Enter keybind (sends \\r in all modes)"
    overlay_note_applied
fi

# Verify the keybind payload, not just the marker comment.
verify_overlay_shift_enter

# ============================================================================
# Fix MenuShortcutKey Private Access for Tests
# ============================================================================
# Upstream added NormalizedMenuShortcutKeyTests (commit d85051a5) that references
# the private property `modifiersRawValue` on `MenuShortcutKey`. `@testable import`
# exposes internal symbols, not private ones, so the test bundle fails to build.
# Fix: demote access level from `private` to internal (drop the keyword) so tests
# compile. No runtime impact — the type is still nested in a non-public struct.

MSM_SWIFT="ghostty/macos/Sources/YEN/Ghostty.MenuShortcutManager.swift"
if [ -f "$MSM_SWIFT" ]; then
    if grep -q 'private let modifiersRawValue: UInt' "$MSM_SWIFT"; then
        sed -i '' 's|private let modifiersRawValue: UInt|let modifiersRawValue: UInt|' "$MSM_SWIFT"
        echo "    Applied MenuShortcutKey.modifiersRawValue access-level patch"
        overlay_note_applied
    else
        echo "    MenuShortcutKey.modifiersRawValue access-level patch already applied (idempotent skip)"
        overlay_note_skipped
    fi
    if grep -q 'private let modifiersRawValue: UInt' "$MSM_SWIFT"; then
        echo "  ERROR: MenuShortcutKey.modifiersRawValue access-level patch failed"
        exit 1
    fi
    if ! grep -q '^        let modifiersRawValue: UInt' "$MSM_SWIFT"; then
        echo "  ERROR: MenuShortcutKey.modifiersRawValue expected internal declaration missing"
        exit 1
    fi
fi

# ============================================================================
# Fix Cursor Style Reload (Force Configured Cursor on Config Change)
# ============================================================================
# Upstream's changeConfig() applies the configured cursor via
# terminal.setDefaultCursorStyle/setDefaultCursorBlink, both of which only
# re-apply it when the cursor still follows its defaults (Terminal.zig guards on
# cursor.is_default). So reloading config.yen while a program/editor has selected
# a custom cursor via CSI q silently ignores the user's configured cursor
# preference. Fix: force the configured cursor after the defaults are updated so a
# config reload always wins. This guard has been removed and re-added upstream
# multiple times, and moved from stream_handler.zig into Terminal.zig in the
# f3c9a2b7 cursor refactor — keep this patch.

STREAM_HANDLER="ghostty/src/termio/stream_handler.zig"
apply_overlay_patch cursor-style-reload-fix

# ============================================================================
# Fix Runtime Window Padding Reload (Apply to Existing Surfaces)
# ============================================================================

SURFACE_ZIG="ghostty/src/Surface.zig"
# Upstream docs state window-padding-x/y apply to new terminals only. For YEN
# Settings, users expect padding changes to update immediately in open surfaces.
# Fix: during Surface.updateConfig(), recompute explicit/balanced padding from
# current content scale before resizing so live reload reflects new values.

apply_overlay_patch runtime-padding-reload-fix


# ============================================================================
# Fix Selection Repaint on Mouse Release (copy-on-select)
# ============================================================================
# The left-mouse release path re-applies selection to update clipboard contents
# when copy-on-select is enabled, but upstream doesn't queue a render there.
# This can leave selection visually stale/intermittently invisible until a later
# repaint, even though the selected text was copied correctly.

apply_overlay_patch selection-repaint-fix


# ============================================================================
# Disable Right-Click Auto-Selection Before Context Menu
# ============================================================================
# Upstream right-click context-menu behavior force-selects a word/link on mouse
# down before showing the menu. That can create accidental highlight/copy churn
# from incidental trackpad/mouse interactions. Preserve current selection state
# and let AppKit open the context menu without creating a new selection.

apply_overlay_patch right-click-context-menu-selection-patch


apply_overlay_patch right-click-context-menu-stale-block-self-heal


# ============================================================================
# Tiered CLI Action Policy (public/support/internal)
# ============================================================================
# Keep high-risk actions off the default +help surface while preserving
# support workflows behind explicit operator flags.

CLI_YEN_ZIG="ghostty/src/cli/yen.zig"
apply_overlay_patch cli-action-policy

CLI_HELP_ZIG="ghostty/src/cli/help.zig"
apply_overlay_patch cli-help-tiered-action-filtering

# ============================================================================
# Align AppleScript perform action with shared automation policy
# ============================================================================
# Keep AppleScript `perform action` on the same allowlisted command surface as
# App Intents so AppleScript cannot bypass future automation policy.

APPLE_SCRIPT_APP_DELEGATE_SWIFT="ghostty/macos/Sources/Features/AppleScript/AppDelegate+AppleScript.swift"
if [ -f "$APPLE_SCRIPT_APP_DELEGATE_SWIFT" ]; then
    run_overlay_util python3 "$REPO_ROOT/scripts/lib/apple-script-action-policy.py" "$APPLE_SCRIPT_APP_DELEGATE_SWIFT"
fi

# ============================================================================
# Scope App Intents permission prompts by intent category
# ============================================================================
# Keep high-volume input intents on a narrower permission scope than control
# and read-only intents.

INPUT_INTENT_SWIFT="ghostty/macos/Sources/Features/App Intents/InputIntent.swift"
if [ -f "$INPUT_INTENT_SWIFT" ]; then
    if grep -q "requestIntentPermission(scope: .input)" "$INPUT_INTENT_SWIFT"; then
        echo "    Input intent permission scope already set to .input (idempotent skip)"
        overlay_note_skipped
    else
        sed -i '' 's/requestIntentPermission()/requestIntentPermission(scope: .input)/g' "$INPUT_INTENT_SWIFT"
        # Fail closed: the sed above is a silent no-op if upstream renamed the
        # call site, which would ship the intent at its broader default scope.
        if grep -q "requestIntentPermission(scope: .input)" "$INPUT_INTENT_SWIFT"; then
            echo "    Scoped InputIntent permission checks to .input"
        else
            echo "    ERROR: InputIntent anchor 'requestIntentPermission()' not found (upstream drift); refusing to ship an unscoped input intent" >&2
            exit 1
        fi
    fi
fi

# ============================================================================
# Use async UserNotifications API in SurfaceView callback paths
# ============================================================================
# Avoid @MainActor-to-@Sendable callback coercion in showUserNotification.

# ============================================================================
# Route terminal-surface local notifications through the managed notification pipeline
# ============================================================================
# Keep command-finish and desktop notifications on the same permission, sound,
# and surface-routing path as the overlay-managed notification service.

GHOSTTY_APP_SWIFT="ghostty/macos/Sources/YEN/Ghostty.App.swift"
apply_overlay_patch ghostty-app-managed-notification-delivery

apply_overlay_patch ghostty-app-terminal-browser-link-routing

SURFACE_VIEW_APPKIT_SWIFT="ghostty/macos/Sources/YEN/Surface View/SurfaceView_AppKit.swift"
apply_overlay_patch surfaceview-async-notification-callback

# ============================================================================
# Use content-view coordinates for split-focus hit testing
# ============================================================================
# The split-focus click filter verifies that the click belongs to this surface
# before it suppresses the terminal mouse event. That hit test has to run in the
# window content view's coordinate space, otherwise non-origin sibling panes can
# resolve to the wrong split when they share the same local click offset.

apply_overlay_patch split-focus-hit-test-coordinate-fix


# ============================================================================
# RETIRED: stale split-focus mouse-up suppression guard
# ============================================================================
# Upstream ghostty-org/ghostty #15190 ("macos: fix split activation mouse
# handling") renamed the flag to suppressLeftMouseUntilRelease, resets it on
# every left-mouse-down in the local monitor and on focus loss, and has
# mouseDown honor it, so a stranded flag cannot swallow a later real click.
# scripts/lib/patches/stale-split-focus-mouseup.{old,new} are deleted;
# 04-verify-branding.sh asserts the upstream reset instead.


# ============================================================================
# Materialize raw clipboard images as temporary file paths
# ============================================================================
# Terminal paste operations fundamentally move text, file URLs, or other string-
# addressable data. Raw image clipboard payloads need a bridge. YEN treats image
# data on the pasteboard as a temporary local file path so Cmd+V can drive file-
# aware terminal workflows without app-specific image clipboard APIs.

PASTEBOARD_EXTENSION_SWIFT="ghostty/macos/Sources/Helpers/Extensions/NSPasteboard+Extension.swift"
apply_overlay_patch opinionated-clipboard-image-path-bridge


apply_overlay_patch opinionated-clipboard-image-temp-root-hardening


apply_overlay_patch opinionated-clipboard-image-retention-hardening


apply_overlay_patch opinionated-clipboard-image-readability-check


apply_overlay_patch opinionated-clipboard-image-temp-file-permissions


# ============================================================================
# Route performable clipboard shortcuts through AppKit edit commands
# ============================================================================
# Cmd+V and Cmd+Shift+V are clipboard commands first and terminal key events
# second. When AppKit sees them as standard edit commands, routing them straight
# back through the surface's paste selectors keeps clipboard semantics aligned
# with other macOS apps while preserving performable "only consume when
# the clipboard has usable contents" behavior.

apply_overlay_patch performable-clipboard-selector-helper

apply_overlay_patch performable-clipboard-selector-fixed-shortcut-upgrade

apply_overlay_patch performable-clipboard-shortcut-routing

apply_overlay_patch performable-clipboard-shortcut-fixed-shortcut-upgrade

apply_overlay_patch directional-split-chord-routing

apply_overlay_patch paste-selection-validation-purity


# ============================================================================
# Stamp per-surface route identity into terminal env (YEN_SURFACE_ID)
# ============================================================================
# Each surface process must expose a stable route key so notification clicks
# can resolve to the exact tab/split that emitted the event. We patch the
# shared surface config helper and both platform initializers so each surface
# has a route key while tab/split-created surfaces preserve inherited routes.

SURFACE_VIEW_SWIFT="ghostty/macos/Sources/YEN/Surface View/SurfaceView.swift"
apply_overlay_patch surface-route-environment-helper

apply_overlay_patch appkit-surface-route-environment-stamp

# ============================================================================
# Persistent sessions (_docs/01-architecture.md -> Persistent sessions)
# ============================================================================
# The pane marks itself for its zmx session right after the route stamp. A pane
# that leaves its split tree or window ends its session once undo expires
# (PersistentSessions.paneLeftTree); deinit is the fast path. Exec.zig wraps the final
# command in `zmx attach` after shell integration (src/termio/yen_session.zig).

apply_overlay_patch persistent-session-prepare
apply_overlay_patch persistent-session-close
apply_overlay_patch persistent-session-tree-leave
apply_overlay_patch persistent-session-window-close

# ============================================================================
# Remove unsafe Sendable conformance from C-pointer wrapper classes
# ============================================================================
# YEN Surface/Inspector wrappers hold raw pointers and are operated on the
# main actor. They should not advertise general Sendable semantics.

remove_overlay_wrapper_sendable

# ============================================================================
# Remove redundant Sendable retrofit for C surface pointer wrapper
# ============================================================================
# UnsafeMutableRawPointer already conforms to Sendable; avoid duplicate
# retroactive conformance warnings in GhosttyPackage.swift.

GHOSTTY_PACKAGE_SWIFT="ghostty/macos/Sources/YEN/GhosttyPackage.swift"
apply_overlay_patch ghosttypackage-sendable-retrofit-removal

# ============================================================================
# DockTilePlugin — retired (upstream now handles Tahoe icon chrome correctly)
# ============================================================================
# Upstream ghostty commit (post-853183e9) restructured DockTilePlugin.swift:
#   - iconDidChange no longer round-trips through NSWorkspace.shared.icon(forFile:)
#     for Tahoe; it uses newIcon?.image(in: pluginBundle) directly, matching
#     our overlay's bundled-image intent.
#   - resetIcon now passes an optional NSImage? to a new NSDockTile.setIcon
#     extension that handles nil by setting self.contentView = nil and
#     displaying, which is exactly what our overlay's reset block did.
#   - On Tahoe Release, appIcon = nil triggers the system default (glassy) icon
#     via the new contentView = nil path, plus NSWorkspace.shared.setIcon(nil, ...)
#     resets the Finder-cached icon.
# The overlay patch previously lived here; it is now obsolete. Branding check
# #38 still verifies the round-trip is absent and the contentView-nil handling
# is present in the upstream NSDockTile.setIcon extension.

apply_overlay_patch pane-header-focus
apply_overlay_patch pane-header-grab-handle
apply_overlay_patch pane-tab-icons
