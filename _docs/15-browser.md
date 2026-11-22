# Native Browser

Owns the built-in WebKit browser: a utility window and an opt-in split for docs, HTTPS pages and local dev servers.
It is a preview surface, never a general browser, and stays isolated from terminal rendering.

## Sources of truth

- `yen-terminal/overlays/macos/Sources/Features/WebPreview/` — the whole feature
- `WebPreviewURLPolicy.swift` — every URL decision
- `BrowserCommandService.swift` — command execution, presentation and targeting
- `WebPreviewCommands.swift` (`WebPreviewCommandReceiver`) — the `yen web` notification bridge
- `yen-cli/commands/core/web` and the `browser:open` / `browser:open-split` palette actions

## Product Boundary

YEN uses Apple WebKit only (`WKWebView`, `WKNavigationDelegate`, `WKUIDelegate` when needed, `NSWorkspace.open` for handoff).
Never add Chromium, CEF, Electron, Tauri or Qt WebEngine, a persistent store, profile, cookie or history import, a default-browser entitlement, App-Bound Domains, or automation or agent control.
Never scan terminal output or detect local servers; links open only on an explicit user action.
Any expansion starts as a `_docs/todos.md` phase that points back here.

## Surfaces

| Surface | Opened by | Controls |
|---------|-----------|----------|
| Utility window (default) | Palette `Browser`, `yen web open`, terminal links | Native `NSToolbar`; first open shows `https://yen.chat/#guide`; reopening focuses without resetting the page |
| Split beside a terminal | Palette `Browser Split`, `yen web open --split` or `--target split`, or the default-off Open the Browser in a Split setting | Inline `BrowserSplitPane` toolbar |

Each surface has its own `WebPreviewModel`, so address, loading and history stay independent.
`BrowserCommandService` shares target resolution across model commands, close, and focused status; a resolved surface owns its model, name, and close operation.
The window is a standard `NSWindow` (`isReleasedWhenClosed = false`, visible title, no `.fullSizeContentView`); on close it drops its toolbar, delegate and content view and cancels its tasks.
A split lives in overlay code only: it never touches the renderer, inherits no scrollback, selection or shell state, and is keyed by weak `NSWindow` identity, never `windowNumber`.
`Cmd + W` closes the focused browser window, or the split only when WebKit content has focus; terminal shortcuts stay terminal-owned in a terminal split.

## URL Policy

Every entry point calls `WebPreviewURLPolicy` before loading or handing off: `show(url:)`, address entry, main-frame, target-blank and subframe navigation, `yen web open`, split launch and terminal links.
The trusted direct-load helper stays private to browser-owned defaults and already-validated URLs.

| Decision | URLs |
|----------|------|
| Load | `https://`; `http://` on `localhost`, `127.x.x.x`, `[::1]` and `*.localhost` |
| Hand off to macOS | `mailto:`, `tel:` (main frame or explicit target-blank only) |
| Block | `file:`, `data:`, `javascript:`, `blob:`, non-loopback `http:`, and any scheme not explicitly allowlisted |

Loopback is decided by the URL alone, never by DNS.
Entry normalization: a bare remote host gets `https://` (port kept); a bare loopback host gets `http://`; explicit non-loopback HTTP stays blocked, including lookalikes such as `http://localhost.evil.test:3000`.
Subframes may load allowed URLs but never hand off, so embedded content cannot launch another app.
Address-entry blocks and delegate blocks share one status path.
External handoff checks the `NSWorkspace.open(_:)` result and reports failure.
Previews of local files go through a loopback server, never `file://`.

## WebKit Rules

- `WKWebsiteDataStore.nonPersistent()` is set before the view is created, because the configuration default is persistent.
- `WKNavigationDelegate` is the only policy boundary, so blocked schemes never reach the content process.
- `allowsBackForwardNavigationGestures` is on deliberately.
- The coordinator records web-view identity and a generation token before queued updates; stale callbacks fail closed, and dismantle clears loading and delegates for every view but clears ownership only for the matching identity.
- Content-process termination is surfaced as status.

## `yen web`

`yen web open [--window|--split|--target window|split] [url]`, plus `back`, `forward`, `reload`, `close` and `status`, each accepting `--automatic`, `--window`, `--split`, `--focused` or `--target automatic|window|split|focused`.

- Only `open` may create a surface; the others fail closed when the target surface does not exist.
- `automatic` prefers an existing split for compatibility; explicit and focused targets fail closed when unavailable.
- `status` reports `window=open|closed`, `split=open|closed` and `focused=window|split|none`.
- The CLI fails closed when YEN is not running and validates input before dispatch.
- The receiver accepts schema `1` and executable-targeted schema `2`, acknowledges the target executable in `status`, and writes responses only to direct `/tmp` or `/private/tmp` `yen-web-command.*` paths.
- `browse`, `files`, `fm` and `y` belong to the file browser; never reuse them here.

## Terminal Links

Settings > General > Links has two toggles, both default off: Open Links in YEN (terminal link capture) and Open the Browser in a Split.
When Open Links in YEN is on, only explicit URL activations route through `TerminalBrowserLinkRouter` and the policy; `mailto:` and `tel:` keep the existing external path.

[CRITICAL] Opening the standalone window from a link makes it key while the terminal's URL-activation stack is still running.
`apply-overlays.sh` patches `BaseTerminalController.windowDidResignKey(_:)` to defer `syncFocusToSurfaceTree()` to the next run-loop turn, preventing a re-entrant `Surface.encodeKey` lock.
Keep that deferral through any change to window activation, link routing, focus sync or split targeting; Open the Browser in a Split is a preference, not the fix.
Guard: `tests/45-overlay-patching.test.ts`, then `01-macos-smoke.sh --browser` and `--browser-live`, then a manual link click in a local build with Open the Browser in a Split off and on.

## Verification

```bash
bash $HOME/Documents/yenchat/scripts/native/01-macos-smoke.sh --browser
bash $HOME/Documents/yenchat/scripts/native/01-macos-smoke.sh --browser-live
bun test tests/51-cli-alias-parity.test.ts
bun run test:prod
```

`--browser-live` targets the exact rebuilt `zig-out` executable and, when any YEN is running, only checks `yen web status`.
`WebPreviewRepresentableTests` runs as its own `-only-testing` invocation because it creates real web views.
`test:prod` covers the deployed browser copy on `/docs`, `/llms.txt` and `/manifest.webmanifest`.
Manually check `Cmd + W`, `Cmd + Shift + P`, `Cmd + ,`, copy and paste, reload, back and forward.

## Removal

The feature compiles out cleanly: revert the `WebPreview/` folder, the `yen web` registration, the palette actions and the two settings, then run `01-macos-smoke.sh --build-only`.
A persistent store would need a user-state cleanup step before it lands.
