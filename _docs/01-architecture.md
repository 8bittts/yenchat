# Architecture

Component boundaries, cross-component contracts, native interaction and input patterns of YEN.

Feature behavior lives in its owner doc; see `_docs/00-docs-map.md`.

## Components

Each component builds and ships independently; never mix concerns between them.

| Component | Location | Owns | Owner docs |
|-----------|----------|------|------------|
| Web | `app/`, `components/`, `lib/`, `public/`, `proxy.ts` | Next.js site on Vercel, `/download`, release metadata hosting | `10-gtm`, `08-growth`, `05-infrastructure` |
| Upstream engine | `yen-terminal/ghostty/` | Generated upstream mirror: rendering, input, config system | `04-security`, `05-infrastructure` |
| Native customizations | `yen-terminal/overlays/`, `yen-terminal/customizations/`, `scripts/lib/patches/` | Branding, overlays, source patches, shell integration, bundled resources | `13-desktop-features`, `05-infrastructure` |
| CLI | `yen-cli/` | The `yen` command, bundled at `Contents/Resources/bin/yen` | `12-commands` |
| Native helpers | `yen-vidthumb/`, `yen-pdfthumb/`, `yen-svgthumb/` | Universal Swift thumbnailers built from source for file-browser previews | `14-file-browser` |

Hard boundaries:

- Never edit `yen-terminal/ghostty/`; change it through overlays, `apply-overlays.sh` patches, or branding automation.
- Never put CLI behavior in upstream source, and never bundle web code into the desktop app.
- The bundled shell CLI at `Contents/Resources/bin/yen` stays inside the release artifact fingerprint scan even though it is not Mach-O.
- Every user-facing binary in `Resources/bin/` is registered in the CLI; the checklist is `_docs/12-commands.md` → Adding New Commands.
- Chat, mail and calendar are fully removed. No runtime, route, binary or Go source remains; restore work starts from git history, never from compatibility code.

## Cross-Component Contracts

**Release distribution.**
`public/stable/version.json` is the public release source.
`app/download/route.ts` reads it once per instance and 302-redirects only to the canonical `github.com/8bittts/yenchat/releases/download/*.dmg` URL it declares (`lib/release-host.ts`).
Prefetch requests return `204` and a missing manifest returns `404` before any redirect.
The route records nothing and sends no email.
`appcast.xml`, `version.sig` and checksums are served from `public/stable/`; the DMGs and deltas are GitHub Release assets ([05-infrastructure.md](05-infrastructure.md) → Release Hosting).
The site has no database and Vercel functions run in `pdx1`.

**Engine to customizations.**
`apply-overlays.sh` brands upstream text, copies overlays, and applies fail-closed patches; the result survives every vendor bump.
`build-release.sh` assembles `ghostty/zig-out/YEN.app` and bundles the CLI, helpers and vendored binaries.

**Persistent sessions.**
A persistent pane runs inside the bundled zmx (`Contents/Resources/bin/zmx`, vendored by `scripts/48-vendor-zmx.sh`), so its shell keeps running when the app quits, crashes or updates.
The preference `com.yenchat.yen.persistentSessions` turns it on; it is off by default while Phase 2 of the plan in `_docs/todos.md` is open.
- The app only marks a pane. `PersistentSessions.prepare` sets `YEN_PERSISTENT_SESSION=<pane UUID>`, `ZMX_DIR=~/.local/state/yen/zmx` and `ZMX_DIR_MODE=0700`, and always overwrites or removes an inherited marker, because a split or tab inherits its parent's environment.
- The engine wraps the final command in `src/termio/yen_session.zig` after shell integration, as `zmx attach <UUID> /bin/bash --noprofile --norc -c 'exec -l <shell>'`, so integration and login semantics apply to the shell zmx starts; the marker never reaches the child.
- A restored pane keeps its UUID, so restore reattaches to the same session and zmx replays the screen and scrollback.
- A pane with an explicit command (AppleScript, palette actions, file openers) stays ephemeral, and so does a pane whose socket path would pass 103 bytes.
- Closing a pane ends its session: `paneLeftTree` checks once undo can no longer bring the pane back and kills the session unless a terminal window holds it again. Ghostty can keep a closed pane alive long after that, so `SurfaceView.deinit` is only the fast path.
- Quitting only detaches: `applicationWillTerminate` sets `PersistentSessions.markTerminating()`, and quit confirmation skips panes with a live session (`quitKillsProcess`).

## Native Patterns

### Native-First Interaction Parity

When a YEN surface has a native analog, mirror the analog's mechanism, curve, duration and secondary effects exactly.
Surfaces with no analog (Git drawer content, layout templates, dictation) define their own interaction.

The four sliding surfaces (Quick Terminal, Local Git Drawer, Tab Sidebar, Scratchpad) share one motion: each emerges inward from behind an edge and covers what is beneath it.
Quick Terminal hides behind the screen edge; the other three hide behind the terminal window's edge (Git drawer bottom, Tab Sidebar left, Scratchpad right).

- One motion runner: `SlidingUtilityPanel.transition`.
- Constant geometry and rigid translation of one full extent; never animate a constraint from zero, which reflows content like an accordion.
- `.easeIn` in both directions at `quick-terminal-animation-duration` (default `0.2s`), with a synchronized alpha fade.
- Park hidden past the edge at alpha 0, animate to rest, then exit with synchronous `orderOut` or teardown; no controller-local `Task` hop.
- Reduce Motion passes a zero duration through the same envelope instead of a second code path.
- A shared **10pt** continuous corner radius on the edge facing the terminal.
- Floating panels set `animationBehavior = .none` so AppKit's own show/hide cannot stack on the envelope.
- The slide plays only on open and close, never on a content refresh.

Quick Terminal keeps upstream geometry, screen state, dock handling, focus restoration and lifecycle unchanged.
A fail-closed patch replaces only its two `NSAnimationContext` calls with `SlidingUtilityPanel.transition`, and `applyTerminalFacingCorners` runs only after the native controller establishes the window.

The other three use `EdgeRevealView`, which applies Quick Terminal's `setInitial`/`setFinal` to content instead of a window.
It clips to its bounds, parks its content one full extent past its edge, and slides it to rest inside the shared envelope.
The Git drawer hosts one at the bottom of `TerminalViewContainer`; the Scratchpad and transient Tab Sidebar panels use one as their content view.
Those two panels rest flush inside the window's content area (`contentLayoutRect`, below the titlebar) and never move their own frames.
A moving panel has no edge to hide behind, so it fades in mid-air over the desktop; every earlier normalization that tuned only curve and timing left that difference in place.
The panels carry no window shadow, which would outline the full panel before the content arrives, and round the outer corners they share with the window to the window's radius.
[CRITICAL] `park()` lays the hosted SwiftUI content out synchronously, so a panel's first `makeNSView` runs inside that layout pass.
Never change key window or first responder from a representable's `makeNSView`/`updateNSView` callback: the nested layout trips AttributeGraph's precondition and aborts the app on the first open.
Focus belongs to the enter completion and the re-anchor paths.
Guards: `TerminalViewContainerTests.gitDrawerHostAttachesAndRemovesBottomOverlay()`, `gitDrawerAnimatedAttachKeepsConstantHeightAndClips()`, the reveal, rest-frame and `firstLayoutRegistersEditorWithoutChangingFocus()` tests in `ScratchpadControllerTests` and `TabSidebarBehaviorTests`, and the sequence checks in `tests/45-overlay-patching.test.ts`.

### Scrollable Text Surface Alignment

Any scroll view showing code, diffs, logs or selectable text pins content top-leading in every branch, including empty states.
In SwiftUI use `.frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)`; a bare `minWidth` centers short content.
Read-only diff text uses the shared `NSTextView` surface (`SelectableDiffTextView`), which is top-leading by construction and honors Copy on Select.

### Terminal Input Patterns

| Need | Pattern | Why |
|------|---------|-----|
| Insert text at the cursor | Save the pasteboard, set the text, `NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)`, restore after 0.3s | Goes through `SurfaceView.paste(_:)`, which honors bracketed paste in every TUI |
| Run a command | Resolve the focused `SurfaceView`, send `Ctrl + C` if a clean prompt is required, then each character and Enter through `surfaceModel.sendKeyEvent` | Real keystrokes bypass bracketed paste |

Never use `sendText` for printable characters: zsh's bracketed paste wraps it in `\e[200~` sequences that leak into the prompt.
`TerminalSurfaceCommandLauncher.swift` is the shared command dispatcher; cross-app dictation paste is owned by `_docs/11-speech-to-text.md`.
A new feature is an `AppDelegate+FeatureName.swift` extension with its menu item and shortcut in `MainMenu.xib`.

### Vendor-Don't-Fork

The upstream engine is vendored as source and every other tool as a pinned binary or source build, each tracked by a git-tracked `.<name>-baseline` and listed once in `scripts/lib/vendor-manifest.sh`.
Vendor artifacts are gitignored; baselines are committed with each update.
Adding a vendor: `scripts/00-scripts-readme.md` → Adding a Vendor.
Gate contracts and overlap watch items: `_docs/04-security.md`.

## Testing

Test lanes and the test philosophy: `tests/00-tests-readme.md`.
Gate scripts: `scripts/00-scripts-readme.md`.
Native test rules (TCC, real config, green-but-empty runs): `_docs/09-quality.md` → Native Test Suite.
