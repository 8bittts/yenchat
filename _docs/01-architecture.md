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
| Native helpers | `yen-vidthumb/`, `yen-pdfthumb/`, `yen-svgthumb/` | arm64 Swift thumbnailers built from source for file-browser previews | `14-file-browser` |

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
Settings > General > Keep Sessions Running stores `com.yenchat.yen.persistentSessions`. It is on by default only in the release app (`com.yenchat.yen`), so the Debug build, its test host and the verify copy never start sessions in the user's state directory unless the preference is set.
- The app only marks a pane. `PersistentSessions.prepare` sets `YEN_PERSISTENT_SESSION=<pane UUID>`, `ZMX_DIR=~/.local/state/yen/zmx` and `ZMX_DIR_MODE=0700`, and always overwrites or removes an inherited marker, because a split or tab inherits its parent's environment.
- The engine wraps the final command in `src/termio/yen_session.zig` after shell integration, as `zmx attach <UUID> /bin/bash --noprofile --norc -c 'exec -l <shell>'`, so integration and login semantics apply to the shell zmx starts; the marker never reaches the child.
  The engine also drops an inherited `ZMX_SESSION` from every pane, because an app launched from a persistent pane inherits that pane's value and zmx refuses an attach under it as nested.
- A restored pane keeps its UUID, so restore reattaches to the same session and zmx replays the screen and scrollback.
- A pane with an explicit command (AppleScript, palette actions, file openers) stays ephemeral, and so does a pane whose socket path would pass 103 bytes.
- zmx stores local diagnostic logs under `<ZMX_DIR>/logs`.
  These can retain working directories and connection environment details after the session ends.
- The session directory and its `logs/` and `bin/` are private to the user. zmx creates them 0750 unless `ZMX_DIR_MODE` says otherwise, so every YEN path that runs zmx passes `ZMX_DIR_MODE=0700`: pane sessions, the close path and the reaper in the app (`PersistentSessions.zmxEnvironment`), and `yen sessions` and `list-pane-sessions.sh` in the CLI. An existing directory loses group and other access when the app claims a pane or sweeps, and when the CLI starts; each of the three is changed only when it is a real directory the user owns, never through a symlink, nothing is ever made more open, and a failed repair never stops a session.
- Closing a pane ends its session: `paneLeftTree` checks once undo can no longer bring the pane back and kills the session unless a terminal window holds it again. Ghostty can keep a closed pane alive long after that, so `SurfaceView.deinit` is only the fast path.
- Quitting only detaches: `applicationWillTerminate` sets `PersistentSessions.markTerminating()`, and quit confirmation skips panes with a live session (`quitKillsProcess`).
  A pane closed inside the undo window before the quit is the exception: `endDepartedPanes` ends its session first, because the delayed check never runs after a quit and the session would reopen in a window at the next launch.
- A restored pane whose session died gets a fresh shell in its saved directory, because `zmx attach` creates a missing session.
- A persistent pane's `YEN_SURFACE_ID` is its UUID (the app's route stamp wins over the engine's per-launch id), so `yen pane cwd` and notification routes still reach the pane after a restore. The Quick Terminal saves its split tree, so its pane reattaches when toggled after a relaunch.
- Each session is listed, attached and ended with the zmx build that created it, because a Sparkle update or vendor bump can ship a zmx with another protocol. The app keeps digest-named copies of the bundled zmx in `<ZMX_DIR>/bin/zmx-<digest>`, records the copy that started each session in `<UUID>.zmx`, and passes it to the engine as `YEN_PERSISTENT_SESSION_ZMX`; the reaper deletes copies no record uses.
  The CLI and the reaper run `yen-cli/lib/list-pane-sessions.sh`, which gives each build a private temporary directory of links to its own sockets for `zmx ls`.
  Sockets without a build record use the bundled client.
  Sessions with an unusable record appear as unreachable and are excluded from automatic recovery and cleanup.
- Password-prompt detection reads the session's inner pty. The pane's own pty belongs to the zmx client, which runs raw, so `canonical and !echo` never shows there. `scripts/48-vendor-zmx.sh` patches the zmx daemon to record its pty path in `<ZMX_DIR>/<UUID>.tty` (`zmx ls` skips non-socket files). The engine's termios poll opens that `/dev/tty*` path, reads its mode and closes it at once, because holding the slave open would keep the pty alive. Closing a pane asks its recorded backend to end the session.
  The reaper keeps recovery records while the socket exists and gives new records one normal sweep interval to acquire a socket.
- Each session records the copy of the app that shows it. `PersistentSessions.prepare` writes the bundle identifier, the bundle path and the process identifier to `<ZMX_DIR>/<UUID>.owner`, and a restored or reopened pane rewrites the record.
- After a crash, a session survives but macOS may have saved no window to restore. On the first sweep after launch, `PersistentSessionReaper` reopens each orphan this copy was showing (at most 8) in a new window under its own UUID, so it reattaches.
  An orphan qualifies only when its owner record names the same bundle identifier and bundle path and a process that is no longer running.
  A session that another copy started, such as a local build or a verification copy sharing the socket directory, opens no window; `yen sessions` lists it and the sweep below ends it.
- `PersistentSessionReaper` ends orphans: UUID-named sessions with no client that no terminal window holds. It runs only in an app whose preference is on, so a Debug build or test host sharing the socket directory never ends the release app's sessions. It sweeps 30 seconds after launch and every 10 minutes, and ends an orphan only after watching it orphaned for 24 hours without a gap: a sweep more than three intervals after the last one restarts observation, because a session detached while YEN was quit was never watched.

**Remote attach.**
Another Mac's sessions are reached over plain `ssh` to its tailnet name, with YEN installed on both ends; YEN embeds no Tailscale, runs no relay, and sends nothing to YEN.
The transport lives only in the CLI (`yen-cli/lib/sessions-remote.sh`); the app runs its bundled CLI and maps the exit code.
- `yen sessions list --host <target>` and `yen sessions attach --host <target> <id>` run `/usr/bin/ssh [options] -- <target> <command>`, where the command is fixed text: `exec /bin/sh -c '<snippet>' yen-remote <words>`. The snippet runs the first executable `Contents/Resources/bin/yen` under `/Applications/YEN.app` or `$HOME/Applications/YEN.app` with `sessions <words>`, and reports 127 when there is none, because a non-interactive login has no `yen` on `PATH`. Only `/bin/sh` parses the snippet, so the login shell runs one `exec` with a single-quoted argument; `tests/172-cli-sessions-remote.test.ts` runs it under zsh, bash and sh.
- The peer's status travels in-band, because a transport can drop it: Tailscale SSH on a macOS peer runs each command under macOS `login`, which exits 0 whatever the command's status was, so ssh reports 0 for a peer that failed (Tailscale issue 18256, open through 1.104; OpenSSH's sshd and Tailscale SSH on Linux pass the status through, and no client option changes it).
  A listing's snippet ends its stderr with one line, `yen-remote-status <n>`; the CLI takes the last such line as the peer's status, falls back to ssh's status when there is none (ssh failed before the snippet ran), and removes every such line before it replays stderr. ssh's own 255 is classified before the line is read, so a status line never becomes an ssh failure.
  An attach shares a terminal with the session, so its status cannot be read back. When the snippet's parent process is `login`, a failed attach prints why and waits for Return on the peer before it exits, so the message stays on screen although the CLI then exits 0 and the pane closes; under any other parent the snippet execs the peer's CLI as before, so its status reaches the CLI and the pane holds locally. Through Tailscale SSH on a Mac, the reconnect loop ends at that 0 like any normal end.
  `tests/182-cli-sessions-status-dropping-transport.test.ts` runs both paths through a fake ssh whose `exec-login` step does what macOS `login` does.
- The peer's own CLI lists and attaches with the zmx build that created each session, and its `attach` refuses an id with no socket, so a remote attach never creates a session.
- Input is untrusted on both sides. The target must be `[user@]host` with a DNS name (no trailing dot), an IPv4 or an IPv6 address, and never starts with `-`; the id must be a UUID. The CLI checks both byte-wise under `LC_ALL=C` before ssh runs, and `RemoteSessions.isValidTarget` mirrors the target rule for the app on printable ASCII bytes.
- Every connection passes `RemoteCommand=none` (a `RemoteCommand` in the user's config makes ssh refuse a command-line command), `ConnectTimeout=10`, `ServerAliveInterval=10`, `ServerAliveCountMax=3`, `ControlMaster=no`, `ControlPath=none`, `ForwardAgent=no`, `ForwardX11=no` and `ClearAllForwardings=yes`. Host key checking stays as the user configured it: YEN never passes `StrictHostKeyChecking` or a known-hosts file. A listing adds `BatchMode=yes` and `-T`; an attach adds `-t` and may prompt in its pane. The rest of the user's config still applies: the loopback script proves a `ProxyJump`, a `RequestTTY force` and a `LocalForward` that cannot bind leave the listing working.
- ssh runs in the background of the CLI, which waits for it, so SIGTERM, SIGINT or SIGHUP to the CLI ends ssh and removes the temporary directory at once; bash defers a trap until a foreground child exits.
- `yen sessions kill` stays local. A remote session ends from a pane attached to it, so nothing ends a peer's session without a person at its shell.

`yen sessions list --porcelain` is the only format the app and `--host` parse.
The first line is `yen-sessions<TAB>1`; each further line is `<id><TAB><state><TAB><started><TAB><directory>`.
`state` is `attached`, `detached` or `unreachable`; `started` is Unix seconds or `-`; `directory` is an absolute path or `-`, with every control character, tab and newline replaced by `?`.
A reader ignores extra trailing fields within version 1, and an incompatible change bumps the number.
`--host` skips lines before the header, which a login shell can print, then re-validates every row, drops a malformed one and exits 1.
Without a version 1 header, the peer is too old (13) when it exited 2 (a YEN with sessions rejecting `--porcelain`), printed `Unknown command: sessions` and exited 1 (a YEN from before sessions), or printed another `yen-sessions` version; any other output is a listing failure (1).

| Exit | `--host` meaning | App state (`RemoteSessionList`) |
|------|------------------|---------------------------------|
| 0 | Listed, or the attached session ended or detached normally | `.sessions(_, complete: true)` |
| 1 | The peer reported a listing error, sent a malformed row, or failed before its header | `.sessions(_, complete: false)`, or `.failed` without a header |
| 2 | Usage error: bad target, id or option | `.failed` |
| 10 | Cannot reach the host: refused, timed out, unknown name, or closed before sign-in | `.unreachable` |
| 11 | The host key is not trusted yet (unknown under BatchMode) | `.firstConnectionNeeded` |
| 12 | YEN is not installed on the peer | `.yenNotInstalled` |
| 13 | The peer's YEN predates `--porcelain` or speaks another version | `.yenTooOld` |
| 14 | `attach` only: the peer's CLI refused the attach, almost always because the session ended | not listed |
| 15 | The host key changed | `.hostKeyChanged` |
| 16 | The host key is trusted but no key signs in without a prompt, as on a peer that offers only a password | `.keySignInNeeded` |

`ssh` exits 255 for every failure of its own, so the CLI classifies its stderr: `REMOTE HOST IDENTIFICATION HAS CHANGED` is 15, `Host key verification failed` is 11, `Permission denied`, `Too many authentication failures` or `No more authentication methods` is 16, and anything else is 10. ssh checks the host key before it signs in, so a password-only peer with an unknown key reports 11 first and 16 once the key is trusted (measured against a loopback sshd with `PubkeyAuthentication no`). Remote sessions need sign-in to work without a password prompt, with an SSH key; a listing runs with `BatchMode=yes` and never prompts.
A peer status of 127 is 12, and a remote attach that exits 1 is 14. The peer's `yen sessions attach` exits 1 for a missing socket, for a damaged install (`zmx is not available`, a missing `common.sh`), and when its zmx client fails (measured: zmx attach exits 1 on a connect error and 0 when the shell exits, whatever the shell's status); the peer's own message shows in the pane first.

Reconnect lives in `attach --host`.
ssh runs `LocalCommand` only after it authenticates, so the CLI passes `PermitLocalCommand=yes` with a `LocalCommand` that touches a marker in its private temporary directory; the marker separates a dropped link from a connection that never succeeded, which both exit 255.
- A first attempt that never connects is reported with its exit code and not retried. `--retry-unreachable` (attach only) retries the unreachable class (10) from the first attempt with the same backoff and a "cannot reach … yet; retrying" line; every other failure still stops at once. YEN passes it only for a pane restored at launch, when the network or Tailscale may not be up yet.
- After a connection was established, an unreachable failure (`Connection ... closed by remote host`, `Timeout, server ... not responding`, refused, timed out) prints one status line and retries after 1, 2, 4, 8, 16, then 30 seconds, resetting after each successful connection, until it reattaches, the session is gone (14), the host key changes (15) or is no longer trusted (11), sign-in fails (16), or the user presses Ctrl-C.
- The remote zmx session keeps running through all of this, and zmx replays its screen on reattach.

**Reconnecting mark.** A remote pane's CLI tells the app it is waiting to reconnect through the pane's own terminal, with a ConEmu progress report the engine already parses and publishes on the surface (`progressReport`).
- `RemotePanes.prepare` sets `YEN_REMOTE_RECONNECT_MARK=1` in the pane's environment; without it the CLI writes nothing, so `yen sessions attach --host` run by hand in another terminal never sends OSC 9.
- While it waits (after a dropped connection, and in the `--retry-unreachable` wait), the CLI writes `ESC ] 9;4;4;0 BEL`, a report paused at 0%, which YEN reserves for this (`RemotePanes.isReconnectReport`). It writes it again before every retry and at least every 10 seconds of a wait, because the engine clears a report after 15 seconds.
- The `LocalCommand` that ssh runs after it signs in also writes `ESC ] 9;4;0 BEL` (`/usr/bin/printf`, with the same strict scratch-path rule as the marker), so the mark clears the moment the session is back, while the CLI itself is still blocked on ssh. The CLI's exit trap clears it on every other way out: Ctrl-C, a hang-up, a failure class that stops, the session gone.
- The app reads the report only for a remote pane. The tab accessory recomputes when the tree or a pane's `$progressReport` changes, and the sidebar row on its existing progress-report refresh; nothing polls or reads processes.
- The engine's own bar for that report has 0 width, so the pane shows no bar; the pane already prints the CLI's "reconnecting in Ns" line, and the tab marker carries the state. With `progress-style = false` the engine drops every report and no tab shows the mark.
- What a peer can fake: the peer, or any program in the session, can write the same sequence while connected and show "Reconnecting" on its own remote tab, or clear its own mark; it cannot reach another pane, because a report belongs to the pane that printed it. While the link is down the peer sends nothing.

Tailscale discovery is `TailscaleDiscovery` in `Sessions/TailscalePeers.swift`.
It runs `status --json` off the main thread with a 5-second deadline, from the first executable of `/Applications/Tailscale.app/Contents/MacOS/Tailscale` (with `TAILSCALE_BE_CLI=1`, because the app executable is also the CLI), `/usr/local/bin/tailscale` and `/opt/homebrew/bin/tailscale`.
It keeps peers whose `OS` is `macOS`, whose `UserID` equals `Self.UserID`, that are not `ShareeNode` or `Expired`, and that run Tailscale's peer API (a non-empty `PeerAPIURL`).
A node another app embeds (tsnet) reports the user's `OS` and `UserID` too, but no peer API (`TaildropTarget` 8) and no ssh server, so it is not one of the user's Macs.
Tailscale fills `PeerAPIURL` from the peer's Hostinfo services, the same Hostinfo that gives `OS`, not from whether the peer is online, so an offline Mac still shows as offline (`TailscaleDiscovery.isFullClient` cites the source).
The ssh target is `DNSName` without its trailing dot only when `CurrentTailnet.MagicDNSEnabled` is true and the name resolves on this Mac to one of that peer's own `TailscaleIPs`; otherwise it is the first valid entry of `TailscaleIPs`.
Tailscale fills `DNSName` from the netmap even with MagicDNS off, `CurrentTailnet` is nil when not connected, and `MagicDNSEnabled` is the tailnet's setting, not this Mac's: with "Use Tailscale DNS settings" off in the Tailscale app (`CorpDNS: false`, or `--accept-dns=false`) it still reads true while the name does not resolve here.
Discovery resolves the name of each online peer inside the refresh, all at once with a 1-second deadline each (`TailscaleDiscovery.usableNames`); an answer with any other address, such as a split-horizon or spoofed one, is never used, and an offline peer is not resolved and keeps its IP.
A peer with no valid target is dropped, and the label is `HostName` without control or format characters.
No Tailscale, a stopped backend and a logged-out node are states (`TailscaleStatus`), not errors; `status --json` prints the state and exits 0 even when stopped.
The Mac App Store and standalone Tailscale apps cannot be a Tailscale SSH server; only the open-source `tailscaled` build can (Tailscale's macOS variants page).
So a peer running either app needs an ordinary ssh server, which on macOS is Remote Login, and the tailnet only carries the connection.

**Hosts store.**
`RemoteHostsStore.shared` (`Sessions/RemoteHostsStore.swift`, main actor) holds the `TailscaleStatus`, the peers and each peer's `PeerState`: `loading` before its first listing, `offline` when Tailscale reports it offline, else `listed(RemoteSessionList)`.
YEN never runs the Tailscale CLI or ssh for discovery at launch or in the background.
- A Hosts surface calls `surfaceDidAppear` when it shows and `surfaceDidDisappear` when it hides. The tab sidebar's Hosts section is a Hosts surface only while it is expanded and its sidebar is on screen (`TabSidebarController.transientPanelShowsHosts`, `DockedTabSidebarModel.railShowsHosts`). In the command palette that is Hosts intent, not the palette itself: the palette is a Hosts surface only while its query passes `RemoteHostsIntent` (a word that starts `hosts` with at least three characters, or the whole word `remote`, `ssh` or `tailscale`; `rem` or `tail` on the way to `remove` or another command does not count). Opening the palette for anything else starts nothing.
- The first visible surface refreshes when the last refresh started 30 seconds ago or more, then a 30-second timer refreshes while any surface stays visible. The last surface to hide invalidates the timer, so with no surface visible the store holds no timer and starts no process (`RemoteHostsStoreTests`).
- An explicit refresh (the palette's Hosts rows) runs at once. A refresh in flight is reused, never stacked; one that is running when the surface hides finishes, because each process has its own deadline.
- Offline peers are never contacted. At most four listings run at once, and a peer keeps its last listing on screen while it is listed again.

**Remote panes.**
A remote pane is a local pane whose command is the bundled `yen sessions attach --host <target> <id>`; it stays ephemeral locally, and its identity (`RemotePaneIdentity`: display name, ssh target, session id) is recorded per pane UUID and read as `SurfaceView.remotePaneIdentity`.
- `RemotePanes.open` focuses the pane whose client is attached to the same target and session id, because a second client in one app only mirrors the first and resizes it; otherwise it registers the identity in process and opens a new tab whose base configuration carries only a random one-time token in `YEN_REMOTE_PANE`. AppleScript and the App Intent can fill a new surface's environment, so the identity never travels there; `prepare` honors only a token it issued, once.
- A pane counts as attached (`RemotePanes.isAttached`) while its process tree, read from the foreground process with `proc_listchildpids` and `KERN_PROCARGS2`, still names the session id. A pane whose client ended is left as it is, showing why, and selecting the session opens a new tab; the engine cannot restart a surface's command in place.
- `PersistentSessions.prepare` calls `RemotePanes.prepare` first for every new surface. It always removes `YEN_REMOTE_PANE`, ignores it on a pane that has its own command, sets the attach command, and records the identity; every other pane is recorded as local. A split or tab made from a remote pane inherits no command and no marker, so it is a local, unlabeled shell.
- The command is `/usr/bin/env /bin/sh -c <RemotePanes.attachWrapper> yen-remote-attach <bundled yen> sessions attach --host …`. The engine's `exec -l` puts a dash in front of the first word's argv[0], and env takes that dash so sh is not a login shell: run bare, bash 3.2 as /bin/sh runs `~/.bash_logout` when the wrapper calls `exit`, and dash or ksh selected as /bin/sh read `~/.profile` (measured on macOS 27; `RemotePanesContractTests`). The wrapper exits with a normal end (0) or Ctrl-C (130), so the pane closes like a local shell that exits; any other status replaces the wrapper with a shell that prints the status under the CLI's own message and waits for Return. The engine holds every surface created with a command after it exits (the embedded API forces `wait-after-command`), so each split leaf closes a remote pane when its process ends (`RemotePanes.paneProcessEnded`); the engine's own exit status is not used, because it is unreliable on macOS behind `login`.
- The identity is forgotten when the pane leaves its tree for good: `PersistentSessions.paneLeftTree` (also used for a closing window) calls `RemotePanes.paneLeftTree`, which waits out the undo time plus the close grace and keeps the identity when undo or a move put the pane back.
- The identity is checked again wherever it comes from: the target must pass `RemoteSessions.isValidTarget`, and the display name goes through `TailscaleDiscovery.displayLabel` and is cut to 32 characters.
- Window restore saves `remotePanes` (pane UUID to identity) in `TerminalRestorableState` and `QuickTerminalRestorableState` and registers it before the split tree decodes, so a restored remote pane is created with its attach command, with `--retry-unreachable`, and reattaches through the CLI. A saved entry that fails validation is dropped on its own. The window stays restorable, because its base configuration has no command (a window created with a command is not restorable). This reattach is the only ssh YEN starts at launch, and only for panes the user opened.
- Session state is recorded once per pane at creation: `RemotePanes.prepare` records the remote identity and `PersistentSessions.prepare` records whether the pane got a persistent session (`PaneSessionRecords`). Both are forgotten with the remote identity after the undo window (`RemotePanes.paneLeftTree`). A tab's state (`TabSessionState`) is a lookup over its panes' records, recomputed only when the tab's split tree changes (the tab accessory follows `surfaceTree`) and when the sidebar's row list already refreshes; nothing scans processes or files for it.
- Quit confirmation skips a remote pane (`quitKillsProcess`), because quitting ends only the local client; the session keeps running on the peer.

Test hooks, never set by the app: the CLI reads `YEN_SSH_BIN` (the ssh client, default `/usr/bin/ssh`), `YEN_SSH_RETRY_MAX_DELAY` (the backoff cap in seconds; 0 never sleeps) and `YEN_REMOTE_APP` (the one YEN.app the remote command runs); the app reads `YEN_TAILSCALE_BIN`.
`tests/172-cli-sessions-remote.test.ts` drives the CLI with `tests/fixtures/fake-ssh.sh`, and `scripts/manual/35-verify-remote-attach-loopback.sh` runs it against a real loopback sshd ([09-quality.md](09-quality.md) → Loopback SSH peer).

## Native Patterns

### Native-First Interaction Parity

When a YEN surface has a native analog, mirror the analog's mechanism, curve, duration and secondary effects exactly.
Surfaces with no analog (layout templates, dictation) define their own interaction.

Quick Terminal slides from the screen edge.
The transient Tab Sidebar slides from the terminal edge.

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

The transient Tab Sidebar uses `EdgeRevealView`, which applies Quick Terminal's `setInitial`/`setFinal` to content instead of a window.
It clips to its bounds, parks its content one full extent past its edge, and slides it to rest inside the shared envelope.
The sidebar hosts this view inside its panel.
The sidebar rests flush inside the window's content area (`contentLayoutRect`, below the titlebar) and keeps a fixed frame.
The sidebar uses its host window’s corner radius and has no separate window shadow.
The scratchpad uses an AppKit utility panel with a native title bar, resize handles, and window shadow.
Its first layout registers the text editor before the panel gives it keyboard focus.

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

## Optional desktop integrations

The token status item owns a cancelable utility worker and filesystem notifications for local Claude Code, Codex, Grok Build and OpenCode records.
Counts belong to the recording tool and use the local calendar day.
JSONL cursors and event contributions commit together in a YEN-owned SQLite cache.
Two reads of one cache file can overlap (the menu switched off and on while a read runs, or a cancelled worker still reading the Codex plan), so `TokenUsageIndex` runs one read or history pass at a time per file in the process, and every connection sets `busy_timeout` before any statement that takes a lock; SQLite answers "database is locked" without waiting where waiting could deadlock (`TokenUsageIndexTests`).
The reader parses only the lines that carry a tool's usage marker (`TokenTool.marker`).
A Claude Code record carries the whole reply beside its usage, so `TokenRecordProjection` copies the members the counter reads out of the record and only those are parsed; a record it cannot walk is parsed whole.
The reader skips a record over 8 MB for Claude Code and over 1 MB for Codex and Grok without holding it in memory (`TokenTool.recordLimit`), because usage records are small and image, tool and compaction payloads are not.
A provider directory can be a symbolic link.
OpenCode reads its database in read-only mode and prefers the current copy of a message during schema migration.
OpenCode uses cumulative session counters only when the store has no dated assistant usage across its history.
Each legacy session belongs to its creation day.
The index ranks duplicate snapshots by output and then total tokens.
Codex corrections reconcile input, cached input and output independently within a rollout.
Grok uses completed turns, and OpenCode includes all gateways in its store.
The analytics view reads the 89 finished days before today once, into a scratch index in the temporary folder, and keeps each day’s total per provider in `history.sqlite` beside the day cache.
A finished day is never read again, so its total survives the removal of its source records.
Only a gap in the saved days starts a new read, from the first missing day.
That first read runs on one core: of a 12 GB record history, 6.8 GB fell inside the 89 days, and reading it with a warm file cache takes about 10 seconds and peaks near 70 MB; later reads take under 0.1 seconds.
The scratch index has no secondary index except for Codex, whose corrections look rows up.
The menu reads Claude’s account-matched usage cache, Codex’s account limits in token-count events and Grok Build’s latest billing log reading.
Codex records its limits only while it runs, so the index also reads the newest rollout from an earlier day.
A plan reading stays until its own reset time, and a percentage outside 0 to 100 is clamped.
The token menu depends on no other app: it reads no JPtheCat file, holds no credential and opens no network connection, so Cursor and Grok Bot plan pools are not shown.
The retired connection source is listed in `scripts/lib/overlay-data/retired-paths.tsv`, which removes its copy from an existing build tree.
A source that was readable and fails one read, such as a locked store, gets one more try after the 8-second debounce; a second failure waits for the next file change, so an absent tool costs no wakeups.
macOS reports a file change when the writer closes the file, so a tool that kept its record file open would be read again only when it closed it or the panel opened; Claude Code appends and closes for each record.
Disabling the token menu cancels requests.
Measured on the release build with no terminal window open and a 12 GB record history, against the same build with the menu off: the footprint is 36 to 62 MB against 30 MB and peaks at 83 to 93 MB during the first read of the day.
With no record changing the menu uses no measurable CPU time and no idle wakeups, and a refresh holds the main thread for about 2 ms.
Typing is not measurably slower with the menu on: key-to-frame latency averaged 18.7 ms against 18.4 ms off, and ten identical runs with the menu off ranged from 17.9 to 19.8 ms.
While the first analytics read runs, the average rises by about 2 ms and the slowest keys are unchanged.
Terminal panes and the renderer do not subscribe to usage updates.

The experimental wallpaper feature hosts MovingPaper-derived AppKit panels behind desktop icons.
Video playback uses AVFoundation and animated GIFs use ImageIO.
GIF frames decode into IOSurfaces on a background task, because the main thread also handles terminal input.
`CGAnimateImageAtURLWithBlock` decodes on the main queue, and a bitmap frame is still copied and color-matched at commit, so the view uses neither.
YouTube serves one file with picture and sound only at 360p, so `YouTubeDownloader` fetches the best H.264 video up to 1080p and its sound as two streams and `YouTubeStreamMerger` copies them into one MP4.
AVFoundation reads each of those streams at twice its real length and ends it with an empty marker buffer at the doubled time; the merger copies only buffers that carry samples.
The wallpaper engine suspends occluded playback and responds to power and thermal pressure.
Its cache, preferences and controls belong to YEN, independent of standalone MovingPaper.
Reset and disable tear down feature-owned workers, observers and windows.
Stopping the wallpaper engine is final: after `WallpaperManager.tearDown`, a file choice, download or Photos export that finishes late is saved but cannot rebuild a panel.
