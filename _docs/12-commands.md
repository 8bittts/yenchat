# Commands Reference

Every surface a user invokes: the `yen` CLI, shell integration, keyboard shortcuts, palette actions, automation (`+action`, Shortcuts, AppleScript), and the `yen ide` command and trust contract.

Feature behavior behind a command lives in its owner doc.

## Sources of truth

- `yen-cli/bin/yen` (`route_command()`, `show_usage()`, `suggest_command()`) and `yen-cli/commands/core/help`
- Default keybinds: `yen-terminal/ghostty/src/config/Config.zig`, exported by `yen +list-keybinds --default --plain`
- Settings catalog: `yen-terminal/overlays/macos/Sources/Features/Settings/KeybindRegistry.swift`
- Palette catalog: `TerminalCommandPaletteCatalog.swift`
- `+action` tiers: `src/cli/yen.zig` (patched by `apply-overlays.sh`)

**Sync rule.** A command or default shortcut change updates this file, `KeybindRegistry`, `app/docs/docs-client.tsx` and `public/llms.txt` in the same change when the row is public.
`yen ide` syntax changes also update `yen-cli/00-core-readme.md`.

## Terminal Commands

Run as `yen <command>`; in YEN shells the app commands (`browse`, `btop`, ...) also work bare.

| Command | Description | Public |
|---------|-------------|--------|
| `help` (`commands`) | Command listing and usage | Yes |
| `version` | Version (`yen version`, `yen --version`) | Yes |
| `init` | Print shell integration for `zsh` or `bash` | Yes |
| `web` | Native browser: `open [--window\|--split\|--target window\|--target split] [url]`, `back`, `forward`, `reload`, `close`, `status`; contract in `_docs/15-browser.md` | Yes |
| `ide` | IDE helper suite; see `yen ide` below | Yes |
| `agents` | Agent adapter board: `claude` and `codex` profiles with probes, sessions, `timeline`, `note`, `export` evidence bundles, `templates` | Yes |
| `pane` | `cwd <directory>`, `cwd --hook`, `cwd --clear`, `--dry-run`: report an agent's working directory for the pane (`_docs/13-desktop-features.md` → Agent worktrees) | Yes |
| `sessions` | List persistent pane sessions and report a backend listing error alongside any available results; listing, `attach <id>` and `kill <id>` use the zmx build that created the session (`_docs/01-architecture.md` → Persistent sessions) | Yes |
| `browse` (`files`, `fm`) | File browser without cd-on-quit; works without shell integration | Yes |
| `y` | File browser with cd-on-quit; only in YEN-launched shells | Yes |
| `btop` (`monitor`, `resources`) | System monitor | Yes |
| `fastfetch` (`fetch`) | System info | Yes |
| `bios` | System info with the YEN BIOS-style logo | Yes |
| `yengit` (`lazygit`, `gitlazy`, `gityen`) | Git TUI | Yes |
| `config` (`settings`, `prefs`, `preferences`), `config reset` | Show the config location; reset the config file, not UserDefaults | Yes |
| `reload` | Reload terminal configuration | Yes |
| `update` | Check signed release metadata | Yes |

Write aliases as `primary (alias1, alias2)` in every help table and list.

Integrated shells wrap `btop`, `monitor`, `resources`, `fastfetch`, `fetch`, `bios`, `browse`, `files`, `fm`, `yengit`, `lazygit`, `gitlazy` and `gityen` so they reach YEN, not a system binary.
The retired names `chat`, `mail`, `email` and `calendar` print a retirement error; `cal` and `top` stay system commands.

`yengit` uses bundled `lazygit` with bundled `delta` as pager; `yen ide pr-review` and the merge-conflict preview use bundled `delta`; the desktop PR Review renders raw diffs.
Dev mode uses `customizations/vendor/{lazygit,delta}`; a system copy is used only with `YEN_ALLOW_SYSTEM_BIN_FALLBACK=1`.

`yen update` verifies `version.json` against `version.sig` with an OpenSSL 3 binary that supports raw Ed25519 (Homebrew, MacPorts, or `YEN_UPDATE_OPENSSL_BIN`); Sparkle still installs.
`yen +edit-config` opens `~/Library/Application Support/com.yenchat.yen/config.yen`; what lives there versus `UserDefaults` is in `_docs/13-desktop-features.md` → Settings.

## Shell Integration

YEN-launched shells get engine integration automatically (`shell-integration = detect`); the YEN command wrappers and `y` function are provided for bash and zsh.
`yen init zsh` and `yen init bash` print code for external shells; they do not install or evaluate it.
Review the output and add it to the matching startup file; neither init output defines `y`.

| Behavior | YEN shells | `yen init` |
|----------|-----------|------------|
| App command wrappers and retirement stubs | Yes | Yes |
| `PATH` to bundled tools (`YEN_BIN_DIR` → `Resources/bin`) | Yes | Yes |
| `y` with cd-on-quit, `Cmd + Shift + O` | Yes | No; use `browse` |
| OSC 133 prompts, pwd, title, sudo and cursor hooks | Yes | No |

- Entry point `.zshenv`, then `yen-integration.zsh` or `yen-integration.bash`, then `yen-welcome.sh` once per session tree (`YEN_WELCOME_SHOWN`).
- Resources resolve from `YEN_RESOURCES_DIR` only.
- Cursor hooks reset to the terminal default (`CSI 0 q`) so the Settings cursor wins.
- `TERM_PROGRAM_VERSION` and `YEN_VERSION` come from the bundled `version.json`, so tools report the release, not a build hash.
- `YEN_IDE_AUTO_CONTEXT=1` runs `yen ide detect --format env` at startup and on `cd` to keep `YEN_PROJECT_*` current; keep that path on the minimal export snapshot so new splits stay fast. `YEN_IDE_AUTO_HISTORY` and `YEN_IDE_AUTO_ENV` are opt-in.
- A wrapper missing inside YEN is bundled-integration drift: fix the build, never dotfiles.

## Keyboard Shortcuts

Fixed shortcuts are locked in Settings: `Cmd + ,`, `Option + Space`, `Cmd + Shift + O`, `Cmd + Shift + S`, `Cmd + Shift + B`, `Cmd + Shift + G`, `Cmd + Shift + J`, `Cmd + Option + 1-0`.
Every other default is rebindable; Settings mechanics are in `_docs/13-desktop-features.md` → Keyboard Shortcut Settings.
Before adding a default shortcut, check `KeybindRegistry.defaults`, the fixed handlers in `AppDelegate.swift`, `yen +list-keybinds --default --plain` and this list; reusing one requires migrating the old action, Settings, palette symbols and public docs in the same change.

| Shortcut | Action | Public |
|----------|--------|--------|
| `Cmd + Shift + P` | Command palette | Yes |
| `Cmd + ,` | Toggle Settings (fixed) | Yes |
| `Option + Space` (hold) | Dictation, exact modifier (fixed) | Yes |
| `Cmd + Shift + O` | File browser (fixed) | Yes |
| `Cmd + Shift + S` | Screenshot to file and clipboard (fixed) | Yes |
| `Cmd + Shift + B` | Tab sidebar (fixed) | Yes |
| `Cmd + Shift + J` | Scratchpad (fixed) | Yes |
| `Cmd + Option + 1` … `0` | Layouts: Single Pane, Three Columns, Right Stack, Bottom Stack, Quad, Eastward 1-3, Eastward 2-1, Eastward 2-3, Center Stage, Three Column Bottom (fixed) | Yes |
| `` Ctrl + ` `` | Quick Terminal | Yes |
| `Cmd + Shift + U`, `Cmd + Ctrl + Shift + U`, `Cmd + Option + Shift + U` | Write the visible screen to a temp file, then paste, copy or open its path | Yes |
| `Cmd + T`, `Cmd + N`, `Cmd + W` | New tab, new window, close | Yes |
| `Cmd + D`, `Cmd + Shift + D` | Split right, split down | Yes |
| `Cmd + F` | Find in terminal output | Yes |
| `Cmd + Option + Arrow`, `Cmd + Shift + Enter` | Focus a split; toggle split zoom | Yes |
| Hold an arrow, then `Cmd + D` | Split in that direction | Yes |
| `Cmd + C`, `Cmd + V` | Copy; paste (images arrive as temp-file paths) | Yes |
| `Cmd + +`, `Cmd + -` | Font size | Yes |
| `Cmd + Enter` | Fullscreen | Yes |

Inside panels:

- Tab sidebar: click switches; context menu Change Title, color swatch, pin (transient or docked), gear (Settings > General), `Esc` dismisses the transient panel unless a title field has focus. Rows show `Cmd + 1-9` labels when macOS ordering makes them addressable.
- Scratchpad: `Cmd + C`, `Cmd + V`, and highlight-to-copy.
- File browser keys are in `_docs/14-file-browser.md`.

## Command Palette Actions

| Action | Notes | Public |
|--------|-------|--------|
| Browser | Native browser window; also found by native web, web preview, localhost, loopback and dev-server queries | Yes |
| Browser Split | Browser beside the active terminal; found by split and terminal-browser queries | Yes |
| Review Pull Request, Resolve Merge Conflicts | Only for a workflow-trusted repo root | Yes |
| IDE quick actions | Workspace Doctor, Merge Readiness, Agents Timeline and Export, Benchmark Status and Run, Format, Lint, Fix, Debug Status and TUI, LSP Status, Diagnostics and Install Matrix, Share Status, Host (Read-Only) and Revoke, Devcontainer Status, VS Code Inventory and Import (Dry Run), AST Status | Yes |

A non-empty query lists matching actions first and runs project search only when the catalog misses; indexing skips `node_modules`, `.next`, `vendor`, `ghostty`, caches and `DerivedData`.
Clearing the query drops the file and symbol indexes so retyping finds files created during the same palette session.

## Automation

**`+action` tiers.**
Public (shown in `yen +help`): `--version`, `+help`, `+list-fonts`, `+list-keybinds`, `+list-themes`, `+list-colors`, `+list-actions`, `+edit-config`, `+explain-config`, `+validate-config`, `+show-face`, `+ssh`, `+ssh-cache`, `+new-window`, `+toggle-quick-terminal`.
Support-only, hidden and runnable with `YEN_CLI_SUPPORT_ACTIONS=1`: `+show-config`, `+crash-report`.
Internal, blocked unless `YEN_CLI_INTERNAL_ACTIONS=1`: `+boo`.
`05-detect-failures.sh` verifies the tiers on the built binary.

**Shortcuts (`macos-shortcuts`, macOS 14+).** `ask` prompts once per scope, `allow` skips prompts, `deny` refuses every intent.
Allow grants last 10 minutes for `control`, 5 for `input`, 3 for `read`.
`KeybindIntent` and `CommandPaletteIntent` accept only allowlisted `CommandEntity` values that persist canonical action identities (older family tokens still resolve); denials raise intent errors and are logged.
A request with no window foregrounds YEN and falls back to an app-modal prompt.
Source: `yen-terminal/overlays/macos/Sources/Features/App Intents/`.

**AppleScript (`macos-applescript`, default `true`).** File-configured only; there is no Settings toggle.
Supported surface, which is also the vendor compatibility boundary: `windows`, `tabs`, `terminals`, `new window`, `new tab`, `split`, `focus`, `close`, `input text`, `send key`, `send mouse *`, `surface configuration`.
Any process allowed to send Apple Events to YEN can use all of it, including input injection; `macos-applescript = false` disables it.
`perform action` accepts only the App Intents allowlist and fails closed otherwise; layout presets, scratchpad, tab sidebar and PR review are not exposed, so recipes compose windows, tabs, splits and `surface configuration` instead of cloning `LayoutTemplate`.
YEN ships no first-party wrappers.
`send key` does not derive text from the keyboard layout (upstream limitation; `_docs/09-quality.md` → Native Test Suite, known-warning baseline).
Target the app by absolute bundle path; `new window` and `new tab` need raw event forms because the parser rejects the natural ones:

```applescript
set appPath to "/absolute/path/to/YEN.app"
tell application appPath
	set windowRef to «event GhstNWin» given «class GNwS»:{initial working directory:"/path/to/project"}
	set tabRef to «event GhstNTab» given «class GNtW»:windowRef, «class GNtS»:{initial input:"bun test" & linefeed}
	split terminal 1 of tabRef direction right with configuration {initial input:"bun run dev" & linefeed}
end tell
```

## `yen ide`

A local-first control surface for project detection, health, trust, LSP and AST queries, tests and quality tools, native tasks, debugging, devcontainers, VS Code migration, terminal sharing, and PR review.
It fails explicitly: missing tools, unreadable state, expired trust and failed transports are reported, and a local result never stands in for unavailable remote evidence.

**Remote targets.** `detect`, `doctor`, `trust status`, `verify status`, `workflow`, `devcontainer`, `debug` and `share` accept `ssh://user@host/abs/path`.
They probe read-only over `ssh` plus remote `python3`, report `executionLocation` and `workspaceIdentity`, label remote-probe data apart from local state, key trust and reports by workspace identity, keep `--watch` local-only, and fail closed on an unreachable host or an ambiguous nested root.

| Command | Contract |
|---------|----------|
| `yen ide detect [path\|ssh://user@host/abs/path] [--format text\|env\|json] [--cached]` | Project root, types, runtime and tooling. `--cached` reuses the env snapshot only for the same local path, env-trust state and root mtime |
| `yen ide doctor [path\|ssh://user@host/abs/path] [--format text\|env\|json] [--strict]` | Aggregates detect, env, debug, LSP, devcontainer and verify state |
| `yen ide trust status [path\|ssh://user@host/abs/path]`, `yen ide trust revoke <surface\|all>`, `yen ide trust reset <surface\|all>` | Workspace Trust Center (`yen ide trust`): one read-only view of env, LSP, debug, devcontainer, share and workflow trust; revoke and reset go through each capability's own command |
| `yen ide env status\|trust\|untrust\|list\|load` | Trusted `.env` workflows |
| `yen ide lsp start [path]`, `yen ide lsp status [path]`, `yen ide lsp stop [path]` | Starts a supervised local server from `PATH` after trust, or a placeholder daemon with explicit guidance (`unsupported-language`, `unavailable-server`, `placeholder-forced`). A per-project lock serializes lifecycle changes. `status` (`--format env\|json`) reports lifecycle, health, resolver, protocol and crash state |
| `yen ide lsp diagnostics [path] [--severity levels --limit N]` | Renders `diagnostics.json` from `publishDiagnostics`, labeled `fresh`, `stale`, `waiting` or `unavailable` |
| `yen ide lsp hover\|definition\|references\|code-actions\|rename <file:line[:col]>` | Live requests labeled `Source: lsp`. `code-actions --apply` applies only a single or preferred edit-only action; `rename` writes only with `--write` |
| `yen ide lsp install status\|install\|update [language]` | Managed installs under `~/.config/yen/ide/lsp-tools`; Swift and Rust stay toolchain-managed |
| `yen ide lsp trust\|untrust\|trusted` | Consent per project root; `untrust` tears down the runtime |
| `yen ide ast status\|definition\|references` | Syntax fallback for Python, JS/TS, Go and Swift, labeled `Source: ast` |
| `yen ide test status [path]`, `yen ide test run [path] [--runner <id>] [--failed] [--quick] [--watch --watch-interval <sec> --max-runs <N>]` | Runs the runners `verify` detects, with grouped failures and semantic `path:line[:col]` targets; reports go to `~/.config/yen/ide/test/`. Watch mode keeps a fixed runner-id snapshot |
| `yen ide verify [--quick] [--no-build] [--no-security] [--strict] [--watch ...]`, `verify status` | Verification bundle with `gitleaks`, package audit and `osv-scanner`; missing tools warn explicitly |
| `yen ide format\|lint\|fix status`, `... run [--dry-run] [--changed] [--trust] ...` | Repo-native candidates on the workflow trust, gate and report model |
| `yen ide workflow discover\|list\|show\|run\|trust\|untrust\|trusted` | Authored `.yen/workflows/*.toml` and discovered package, Make, Just and Task tasks; untrusted repos are blocked |
| `yen ide workflow run --native <task-id> [--watch --watch-interval <sec> --max-runs <N>]` | Runs one discovered task explicitly and never falls back from a workflow name. `run --native --watch` keeps a fixed native-task id snapshot |
| `yen ide search <query> [--sources ...]` | Files, symbols, content, diagnostics, history and actions, with CODEOWNERS and history hints |
| `yen ide merge-readiness [path]` | Read-only `safe to review`, `safe to merge` or `needs human check` over doctor, trust, verify, gate, PR and git state |
| `yen ide open <path:line[:col]> [--editor CMD] [--dry-run]` | One editor-jump planner, also bundled for the macOS review workspaces; the native spawn runs off the main actor |
| `yen ide debug status\|tui\|start\|continue\|next\|step\|out\|stack\|inspect\|breakpoint\|watch\|transcript\|stop\|trust` | Trust-gated `python-pdb`, `node-inspect` and `lldb` sessions, local, SSH or tracked devcontainer. Attach-to-pid, TypeScript direct-file and Go/Rust package debugging are reported as blocked, never faked |
| `yen ide devcontainer status\|up\|shell\|down\|trust\|untrust\|trusted` | Wraps the `devcontainer` CLI after trust; refuses `--privileged`, `--cap-add` and unsafe mounts without `--allow-unsafe` |
| `yen ide vscode inventory\|import [--dry-run]` | Classifies `.vscode/` items, then writes only `.yen/vscode-import/` and `.yen/workflows/vscode-task-*.toml` atomically |
| `yen ide share host [path\|ssh://user@host/abs/path] [--read-only\|--interactive] [--ttl-seconds N\|--ttl-minutes N] [--passphrase value] [--replace]` | Hosts a trusted share over `upterm`, falling back to `tmate`; the token is encrypted with a passphrase and expires on a watcher |
| `yen ide share status\|join\|revoke\|trust\|untrust\|trusted` | `join` decrypts and validates locally before any transport runs and trusts nothing locally |
| `yen ide pr-review [options] [pr]`, `yen ide pr-notify [--watch] [--ci-status]` | Review with semantic hunk targets, explicit posting, and evidence bundles carrying the verify snapshot. The desktop workspace shows raw selectable/colorized focused diffs |
| `yen ide benchmark status\|run [--suite ...] [--write-baseline]` | Fixture-backed suites in `yen-cli/fixtures/ide-benchmark/`; runs fail on a missing or regressed baseline; each run isolates its state and LSP sockets |
| `yen ide history`, `replay`, `profile`, `ports`, `parse`, `explain` (`??`), `gate`, `timeline`, `non-interference` | Project history, profiling, port and process inspection, output parsing, failure explanation, approval gates, the audit timeline, and SLO guardrails |

**State and trust.** Everything lives under `~/.config/yen/ide/`.

- Trust registries are per project root: `trusted-lsp-projects`, `trusted-share-projects`, `trusted-devcontainer-projects`, plus env, debug and workflow registries. Read-only commands never widen trust.
- LSP state is `lsp/<project-hash>/` (`state.env`, `diagnostics.json`, `lsp.pid`, `daemon.log`) with locks in `lsp/locks/`; the socket is `/tmp/yen-lsp-<uid>/<project-id>.sock` to stay under the macOS socket-path limit.
- Share state is `share/<project-hash>/` (`state.env`, PID files, transport sockets) with locks in `share/locks/`.
- `state.env` and `diagnostics.json` are rewritten through a temp file and atomic rename.
- `<project-hash>` hashes the local root, or the workspace identity for `ssh://` targets, so remote and local state never collide.
- Timeline events include `lsp-trust`, `lsp-start`, `lsp-stop`, `lsp-crash`, `lsp-diagnostics`, `search`, `share-trust`, `share-host`, `share-join`, `share-revoke` and `share-expire`.
- Runtime needs a local `python3` (LSP supervision, AST) and `openssl` (share tokens); neither is bundled. Vendor posture: `_docs/04-security.md` → IDE Lifecycle Vendor Posture.

## Adding New Commands

1. Implement the command.
2. Register it in `yen-cli/bin/yen`: `show_usage()`, `suggest_command()`, and `route_command()` only for a bin-only command with no `commands/core/` script (today only `browse`). Add it to `yen-cli/commands/core/help`.
3. Copy the new `suggest_command()` list into the `cli-builtins:` line of `scripts/lib/privileged-action-surface-baseline.txt`; `03-verify-components.sh` fails the release on drift, and `bun test` does not check it.
4. Add a palette descriptor in `TerminalCommandPaletteCatalog.swift` with an SF Symbol, shortcut symbols and search tags; appearance features get quick actions.
5. Add the row here with Public set to No.
6. To publish, add it to `CommandsSection` in `app/docs/docs-client.tsx` and to `public/llms.txt`, then set Public to Yes.

[CRITICAL] A binary that is not registered in the CLI is invisible: `yen help` is how users find commands.
Helpers that are not user-facing, such as `delta`, need only the inventory and gate entries in `_docs/04-security.md`.
