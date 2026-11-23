# Quality

The native test suite, web quality baselines, release gates and the standing manual QA matrix for YEN.


## Gates

The required gates before a commit and the vendor-tree preflight are in [AGENTS.md](../AGENTS.md#required-gates).
`tests/00-tests-readme.md` catalogs the test surfaces and lanes.

## Native Test Suite

`TokenUsageIndexTests` uses local provider fixtures for replay, rotation, partial writes, day rollover and OpenCode schema migration.
The provider comparison covers streamed Claude snapshots, Codex counter resets, per-model Grok replay and legacy OpenCode log identities.
The OpenCode database tests distinguish empty message history from a day without usage.
The same suite covers records that cross the reader's buffer, the record limit of each tool, the record projection against whole-record parsing, and the marker search.
`TokenProjectUsageTests` covers each tool's working folder, today's hours, Grok turns still running (finished requests minus completed turns), the finished-day hours behind the weekday chart, the sidebar's folder match and the `yen usage` report; `TokenLimitAlertsTests` covers the once-per-window alerts and the JP the Cat sound.
`TokenPlanUsageTests` switches the menu on and off 12 times and requires each menu to be released, some while their first read runs.
A release build is checked without focus in the verify copy: launch it in the background with a scratch home of fixture records and read the status item's accessibility text, which states the exact total and how many of the four sources were read.
- Concurrent writes: append records the way the tool does, open, write and close for each one; the total rises in whole records and ends exact.
- Locked stores: hold `BEGIN EXCLUSIVE` on the fixture OpenCode database, then on the copy's `today.sqlite`; the locked source drops out, the others stay, and it returns after the lock clears.
- Day rollover: launch the copy with `TZ` set to a zone whose midnight is minutes away; at that midnight the total resets, and only records stamped in the new day count.
`scripts/manual/34-measure-key-latency.swift` measures key-to-frame latency in a frontmost copy: it posts a key to that process only and reads the display time of the next frame whose pixels changed.
Run the two sides in alternating order, at least 5 runs of 150 keys each, with `cat` in the pane so every key echoes at once; the mean of a 150-key run ranged from 17.9 to 19.8 ms across ten identical runs, so a smaller gap is no difference.
A launch argument the engine does not know, such as `-ApplePersistenceIgnoreState`, opens a Configuration Errors window that takes the keys, so pass only `-com.yenchat.yen.*` arguments.
The wallpaper's Photos path is checked in the same copy: Wallpaper Controls opens the "Choose a Video from Photos" panel, the operator picks the video, and the pick arrives as a file under the copy's `MovingWallpaper/Photos` folder and becomes the assignment; a panel closed without a pick leaves the assignment as it was.
Check the menu anchor before and after expanding a provider row.
Its filesystem test observes and counts a change through a symbolic link.
The history test checks each finished day against its fixture and reads again after the source is gone.
A Debug build beside a scratch home exposes the panel and the Settings switch to Accessibility, so a helper can press them by description without activating the app.
An Accessibility press does not exercise hit testing: after a change to the card flip, click the analytics view’s return button with a real pointer event, because a face left at a half turn takes no clicks.
Capture a frame during the turn without the window shadow and confirm that no opaque pixel touches its top row.
The contrast test holds `TokenBarTone.link` at 4.5:1 on both panels; confirm a hovered label in a light and a dark capture as well.
For native acceptance, check that an appended record changes the menu without opening it.
`WallpaperToggleTests` drives the Moving Wallpaper switch with its own preferences and fails when a panel outlives the switch.
`YouTubeDownloaderTests` runs the real downloader against a script in yt-dlp's place, so the stream merge and the single-file fallback are tested without the network.
For native acceptance, click the switch in a verify copy and count that process's windows one level above `CGWindowLevelForKey(.desktopWindow)`: one per display when on, none when off.
With two displays, assign the videos through launch arguments so the pass needs no clicks: `-com.yenchat.yen.movingWallpaper.enabled YES`, `-com.yenchat.yen.movingWallpaper.wallpaperMode perDesktop` (or `allDesktops`) and `-com.yenchat.yen.movingWallpaper.desktopFiles` with an XML `<array>` of `<dict>` records holding integer `displayID` and `spaceID` and a string `path`; Space 0 is a display's all-desktops slot.
Each display must then own one wallpaper window with that display's bounds, the windows must stop changing under `sudo pmset -a powermode 1` and change again after `powermode 0`, and an unplugged display's window must go away while the others keep playing.

Native fast tests inspect a temporary snapshot of their Swift source, shortcut docs, and vendored config.
`scripts/native/source-fixtures.py` verifies file counts and hashes against the current checkout before and after execution.
The host receives that path through Xcode's `TEST_RUNNER_` environment forwarding, so source assertions do not require Documents access.
Missing, empty, unreadable, or changed fixture inputs fail the gate.

`xcodebuild test` must report zero failures; the rules below explain every past exception.

**A green exit is not evidence.** `xcodebuild` prints `** TEST EXECUTE SUCCEEDED **` for a run that executed zero cases (empty target, self-skipping suite, or an `-only-testing` filter that matched nothing).
`--fast` fails closed on `RECEIPT gate=native-fast executed=<n>`; quote that number.
Swift Testing single-case filters need the display name with trailing parentheses, such as `-only-testing:'YENTests/TabSidebarBehaviorTests/toggleHotkeyMatchesCommandShiftB()'`, and target suite type names, not file names.
The one or two `Executed 0 tests` lines `test-without-building` prints before Swift Testing output are a preamble, not the result.
`--fast` links the prebuilt `YENKit.xcframework` and never rebuilds the engine, so a patch that changes a `Config.zig` default fails its Swift test until the engine is rebuilt (`--local` or `/update-yen`); compare the framework's modification time with the patch commit before treating that failure as a regression.

**Verify UI in the app you think you are running.** Finding a string in the binary with `strings` proves nothing.
Four stale layers have each produced a confident false result: an old `zig-out` bundle, a process started before the build (`open -a` only activates it), incremental `macos/build` state, and identity.
Identity survives every other check: `zig-out/YEN.app` and `/Applications/YEN.app` both declare `com.yenchat.yen` and the same version, so opening the local build while the installed one runs hands you the installed one.
Confirm with `ps -o pid,lstart`, the `txt` mapping from `lsof -p`, and `lsappinfo info -only bundlepath "$(lsappinfo front)"`; more than one `YEN` in `lsappinfo list` means two bundles are live.
A view that does not render is usually its own data dependency (an option list populated only in `.onAppear`), not the build system.
Never `pkill` YEN to relaunch it.

**A native UI finding is verified in a running local build before it is reported.** An audit, review or fix of a native surface ends with a pass through the `com.yenchat.yenverify` copy that `scripts/manual/18-make-verify-copy.sh` builds (`_docs/05-infrastructure.md` → Validating the local `zig-out` build), and the report labels each finding as observed, code-only or not reproduced.
Quit a verify copy by the pid recorded when it launched, never by a name pattern: the verify identity is shared between concurrent native lanes, so a pattern can quit another lane's copy.
A code read, a unit test and an offscreen render have each been wrong about the same panel.
An offscreen `NSHostingView` render showed `.tint(.red)` leaving a bordered button unchanged, while the running Settings window draws that button red.
A Settings window can render dark while the system appearance is Light, so confirm the rendered appearance before reporting a contrast finding.
Synthetic input has limits of its own: Escape never reaches the verification copy, so an Esc finding cannot be told apart from a harness artifact; the shipped recorder's Esc cancel fails there the same way.

**Capture tests never request permissions.** A prompt is modal and steals focus from every suite.
- Engine-bound dictation tests use `.enabled(if: DictationTestPermissions.microphoneGranted)`; never `Issue.record`, which marks the test failed.
- `YEN.xctestplan` sets `YEN_CONFIG_PATH=/tmp/YEN/testing_config.yen` with `working-directory = /tmp/YEN`, so terminal startup does not open a working directory under `~/Documents`.
- Onboarding and the upstream window preferences read `UserDefaults.yen`, which honors `YEN_USER_DEFAULTS_SUITE` in Debug builds only, so a suite keeps onboarding off in the test host.
  The session, tab sidebar, token, wallpaper and notification preferences read `UserDefaults.standard`; no suite isolates them, in any build.
  Two worktrees that run the native lane at the same time therefore write the same `com.yenchat.yen.debug` values, and a test can read back the other host's write (`SettingsWindowLifecycleTests` once read another run's `tabSidebarPresentationMode`); rerun the lane alone before debugging such a read.
- A `quit` that another session sends by bundle identifier ends the `--fast` test host, which shares `com.yenchat.yen.debug`. The run then prints `Restarting after unexpected exit` and fails the tests that were running. The unified log of the host shows `RECEIVED:(aevt,quit)`; rerun the gate instead of debugging those tests.
- `AppDelegate` installs the `yen web`, `yen pane` and build-notification observers only outside XCTest; tests drive those receivers directly.
- Source-scanning suites use the prepared fixture snapshot rather than opening the Documents checkout.
  A host blocked on a checkout read indicates a missing fixture conversion; inspect its stack and source path before requesting access.
- The test host is the Debug bundle `com.yenchat.yen.debug` and shares TCC state with a Debug app launched for E2E work. Answer its prompts before a native run, and `sample` a silent host before calling it a code hang.
- The Debug bundle holds the upstream themes but not the custom theme files or the curated manifest, so its Themes picker is empty and `theme = YEN` reports "not found"; check chrome color there with an explicit `background`.
- Native UI launch checks can pass app preferences as single-dash pairs such as `-com.yenchat.yen.persistentSessions NO`.
  The engine reads terminal options, while AppKit gets the original arguments for its defaults.
  Run `python3 scripts/manual/33-check-native-launch-defaults.py "$YEN_VERIFY_APP"` to check startup, configuration reload, and arguments passed to a child command.
- To see what the engine resolves without launching the app, run `<YEN.app>/Contents/MacOS/yen +show-config --no-pager` with `YEN_CLI_SUPPORT_ACTIONS=1` and with `CFFIXED_USER_HOME`, `HOME` and `XDG_CONFIG_HOME` pointed at scratch directories, so the real `config.yen` is never read.
- A Debug app launched beside the installed one shares its Scratchpad text: `ScratchpadStorage.directoryName` is the fixed `com.yenchat.yen`, not the bundle identifier, so both read and write `~/Library/Application Support/com.yenchat.yen/scratchpad.txt`. Copy that file aside before any Debug E2E run and compare it afterward: the instance loads the text at launch and rewrites the file when it quits, even if the Scratchpad never opened.

**Tests never write the real `config.yen`.** [CRITICAL] `SettingsController` resolves its file through `resolveConfigPath`, which honors `YEN_CONFIG_PATH`.
With no visible Settings window every mutation persists synchronously, so a suite touching `SettingsController.shared` would rewrite the operator's config on every release.
`SettingsConfigPathTests.testHostNeverTargetsRealUserConfig` guards it; suites that need a specific file still call `_testSetConfigPathOverride`.

**Live terminal windows.** Suites that create real `TerminalController` windows spawn login shells.
Close them through the real AppKit close path so `windowWillClose` runs; `orderOut(nil)` leaves `/usr/bin/login` children alive and later runs look frozen.
For docked-sidebar coverage inject plain `NSView` stubs through `TerminalViewContainer(terminalContentView:dockedSidebarHostingViewFactory:)` and keep frame math in `DockedSidebarGeometry` assertions.
XCTest suppresses onboarding and the first terminal window; host detection accepts `XCTestConfigurationFilePath` or `XCTestBundlePath`.
Async settle paths use `Task.sleep`, `Task.yield` and actor gates, never `RunLoop.main.run(until:)` or semaphores.
Singleton- and `UserDefaults`-backed Settings suites run serially.

**Flaky starts.** For LaunchServices `OSStatus -54`, split the run into `build-for-testing` and `test-without-building` with `-parallel-testing-enabled NO`.
If `build-for-testing` reports missing branded files such as `YEN.Error.swift`, use a fresh `-derivedDataPath` before suspecting overlays.

**YENUITests is retired.** It needs an exclusive desktop and runner grants and its failures vary per run, so it can never gate.
It stays in the mirror because removing upstream code would need pbxproj surgery on every fetch; `apply-overlays.sh` disables it in `YEN.xctestplan`, renames the folder, and renames seven harness-measuring cases to `yenDisabled_*`.
Run it by hand only with `TEST_RUNNER_IDE_DISABLED_OS_ACTIVITY_DT_MODE=1`; without it the suite self-skips with `Executed 0 tests`.

**Known-warning baseline: 0.** A clean native run records no test warning, so any warning is a signal.
Build warnings outside `appintentsmetadataprocessor` extraction, the `YENKit` umbrella header, the arm64 `ext.o` ImGui symbols, and upstream's `@Test` macro warning on the non-Sendable `Any?` parameter in `ScriptKeyEventCommandTests` require investigation.
At the macOS 27 deployment target, Xcode also reports deprecations in SwiftUI views and audio capture APIs.
See [11-speech-to-text.md](11-speech-to-text.md) for the audio tap contract.

## zmx Daemon Shutdown

`scripts/manual/36-check-zmx-shutdown.sh [--runs N] [--binary <zmx>]` checks that zmx session daemons exit cleanly when their session ends (`04-security.md` → Bundled Binary Inventory).
It ends N daemons (default 20), alternating `zmx kill` and an attached command that exits, while a counter session started through `zmx attach` stays up and must return with the same shell pid and a higher count.
Each daemon's exit status comes from kqueue `NOTE_EXITSTATUS`, which macOS reports for the daemon although launchd is its parent, so a clean result is a measured `exit=0`, not a missing crash report.
It also counts the `.ips` reports naming each daemon pid, and runs the binary as a uniquely named copy under `/tmp/yzs.*` so those reports are told apart from any other zmx.
The last line is a `SUMMARY` with the counts; `tests/181-zmx-daemon-shutdown.test.ts` runs the same probe with two runs.

## Loopback SSH Peer

`scripts/manual/35-verify-remote-attach-loopback.sh [--old-cli <yen>]` stands in for a second Mac when testing remote attach (`01-architecture.md` → Remote attach).
It needs no Tailscale, no `sudo` and no change to `~/.ssh` or the system sshd.
- An unprivileged `/usr/sbin/sshd -f <config>` listens on 127.0.0.1 at a random high port with a temporary host key, `UsePAM no`, `StrictModes no` and a temporary `authorized_keys`. Its `environment="HOME=..."` option, allowed by `PermitUserEnvironment yes`, gives the login a throwaway home, because sshd otherwise uses the real one.
- The throwaway home holds `Applications/YEN.app/Contents/Resources/bin/yen`, a wrapper that execs this checkout's CLI; a symlink would make the CLI look for its resources beside the link. `YEN_REMOTE_APP` points the remote command at it, because `/Applications/YEN.app` on the test Mac is the real install.
- `YEN_SSH_BIN` is a wrapper that adds `-F <config>`, one config per failure class: empty known hosts, a changed host key, an unauthorized key, and a closed port.
  Four more configs carry settings a user may have: `RemoteCommand`, `RequestTTY force`, a `LocalForward` that cannot bind with `ExitOnForwardFailure yes`, and a `ProxyJump` through the same sshd. Two controls prove the last two matter: plain ssh fails with that forward, and a jump host that refuses the key breaks the listing.
- The session is created with the vendored zmx under `/tmp/yrl.*`, so socket paths stay under 103 bytes, and every `ZMX_*` variable is dropped first.
- `35-remote-attach-probe.py` attaches in a pty, then cuts the link twice: it kills the sshd connection child, and it stops the grandchild that carries the traffic so only the 30-second keepalive notices. Each pass requires the ticks the session prints to keep counting after the reattach.
- The script kills only the sshd it started and the session it created, and removes its directory on exit.

The script is not a gate: it proves the transport against real OpenSSH on this macOS, not on a tailnet.
Against a real second Mac, stage `Contents/Resources/bin/yen`, `bin/zmx`, `lib` and `commands` from this checkout in a folder there and point `YEN_REMOTE_APP` at it, because that Mac's installed YEN may predate remote sessions; without the variable the listing must answer exit 13.
Start the session with that bundle's `zmx run <UUID> -d <command>`, which types the command into a session shell, and give the attaching pty a window size, because a pty with no size wraps the replayed screen.

## Web Quality Baselines

These apply to the homepage, Terms, and the separate blog.

**Accessibility (WCAG AA).**

- Contrast at least 4.5:1 for body text and 3:1 for large text; text on brand orange uses high-contrast tokens; no opacity-reduced body copy.
- Every page has `<a href="#main-content" className="skip-link">`, `<main id="main-content">`, an `h1` → `h2` → `h3` hierarchy, and visible focus rings.
- Every control has an accessible name; toggles expose `aria-pressed`; `aria-controls` targets only IDs in the current DOM; inputs have labels (visible or `sr-only`).
- The Terms link, which includes privacy and cookie policy, stays visible at every breakpoint, never behind `hidden md:flex`.
- [HARD REQUIREMENT] Reduced motion: CSS sets `animation: none` under `prefers-reduced-motion: reduce` for pings, pulses and custom keyframes; JS checks `matchMedia` before typing, recording or looping animations and jumps to the final state. An animation that persists anyway carries an `/* Animation exception: ... */` comment.

**Responsive.** Dense tables scroll horizontally inside wrappers with minimum widths, and header and footer controls keep touch-size targets.
Product-manual tables align text left and body cells to the top; use the existing `min-w-[36rem]` table pattern for dense references.
Mobile footer spacing is part of the layout contract: no desktop `section-padding`, `min-h-screen` or spacer block directly above the footer, and footer groups stack before a link label wraps.
Check every changed public page at about 390x844 for the last-section-to-footer gap, footer height and space after the footer; a zero after-footer gap is not enough if a blank band above it dominates the viewport.

**Embeds.** Every `<iframe>` has `loading="lazy"` and a descriptive `title`.

**SEO and indexing.**

- `https://yen.chat` is canonical; `www` redirects permanently, and every canonical, sitemap, OpenGraph and Twitter URL uses the apex host.
- The main site indexes the homepage and Terms. Both carry canonical, Open Graph, Twitter, and robots metadata.
- Noindex: `/api/*`, `/download`, `/stable/*`, `/cookies`, and 404, with route-level `X-Robots-Tag` where it applies.
- `robots.txt` comes only from `app/robots.ts`: it disallows `/api` and `/stable`, leaves `/download` and `/cookies` crawlable so crawlers see the header or redirect, and allows the major search and AI crawlers.
- `app/manifest.ts` is the only manifest; a static `public/manifest.webmanifest` collides with the route and returns 500 in development.
- `app/sitemap.ts` is deterministic: exact membership, apex host, unique URLs, no `lastModified`, and no deploy-time `new Date()`; `tests/121-seo-guardrails.test.ts` guards it.
- Each HTML page has one stable server-rendered `h1`; animated text never replaces it. Titles and descriptions stay unique and within the lengths `tests/121` enforces.
- `og-image.png` is opaque RGB (`magick og-image.png -alpha off og-image.png`), and its declared size matches the file.
- No `SoftwareApplication` JSON-LD without real review data.
- `public/llms.txt` keeps high-value resources as Markdown links; run the Lighthouse Agentic Browsing audit after editing it.

**CSP.** `bun run build` runs `scripts/44-build-web-csp.ts`: it derives exact per-route hashes from emitted HTML, probes an unknown URL twice for a fresh nonce and authorized error-page scripts, rewrites `lib/csp/generated-inline-script-hashes.ts` when needed, and requires a converged second build.
The committed manifest is a cache: any app change makes it stale, and the production build then rewrites it and builds twice rather than failing.
A local `bun run build` therefore often leaves it modified; commit it with web work that ships, as the release-notes commit does, and restore it with `git checkout --` before a commit that ships no web change.
Vercel builds set a Next build adapter, so Next 16.3.8+ writes prerendered output to `.next/server/route-cache/` there instead of `.next/server/app/`; the CSP build and `scripts/46-scan-bundle-leaks.ts` read both layouts.
A local build has no adapter, so reproduce the Vercel layout with `NEXT_ADAPTER_PATH=<file exporting { name: "noop" }> bun run build`.
`proxy.ts` serves static routes with hash-only CSP, redirects encoded or case-variant aliases to canonical paths, rejects encoded slash and backslash separators before normalization, and uses request nonces for dynamic and unknown routes.
`connect-src` lists only hosts the browser actually fetches; the release manifest is read server-side and downloads are a 302 navigation, so the GitHub release host stays out.

**Analytics.** Vercel Analytics and Speed Insights only, with these custom events: `download_click`, `header_click`, `footer_click` and `theme_toggle`.
The names were Title Case (`Download Click`) before the rename dated in `00-foundation.md` → Timeline, so compare a period that crosses it under both names in the Vercel dashboard.
Every event goes through `trackProductEvent` in `lib/analytics/product-analytics.ts`, whose `ProductEventName` union is the list above; `tests/56-product-analytics.test.ts` fails if any other file imports `track` from `@vercel/analytics`.
Traffic is not part of `/growth`; see `_docs/08-growth.md`.

## Dictation Live Manual Matrix — Runbook + Evidence Template

Owner surface for the Dictation live matrix; run it before shipping any change to dictation capture or insertion.
The headless coordinator/controller harness already covers the `SpeechAnalyzer` control path; what remains can only be proven by speaking into a live local `YEN.app` and observing real target apps, TCC timing, and the per-session structured logs.

Source of truth for expected behavior: `_docs/11-speech-to-text.md` (Session Contract, Insertion, Verification).
This file is the operator checklist + fillable evidence record.
Fill in the `Observed` / `Verdict` blanks during a live run and attach the generated report.

---

### Acceptance criteria

1. Run the live matrix against: one non-YEN target app, one in-terminal target,
   one process-only or confirmed-readable cross-app target, one Secure
   Input/password-field pass, and one failure-sensitive path.
2. Capture structured log evidence for each live case: `stop_cause`,
   `fallback_used`, restart behavior, and revocation teardown timing.

Do not record the matrix as run from headless tests.
This run is human-in-the-loop.

---

### Why this is manual-only, and the environment constraints

Non-obvious facts that will otherwise burn operator time (verified from source):

- **Logs are `print()` to STDOUT, not `os_log`.** `DictationController`,
  `DictationHotKey`, `DictationRecognizer`, and `SpeechAnalyzerRecognizer` all
  log via `print(...)`. `log stream` / Console.app will NOT show them. The only
  capture path is launching the built binary from a terminal and tee-ing stdout.
  The harness does this for you.
- **The test build must be the SOLE running YEN instance.** Dictation installs a
  session-level Option+Space `CGEventTap` unconditionally at launch and only
  releases it on Accessibility-trust loss. "Pause Dictation" does NOT release the
  tap — the resolver consumes Option+Space before the pause check. Two instances
  therefore fight for the global hotkey (`.headInsertEventTap`, newest-at-head
  wins, and either can re-steal head on a tap-disable rebuild) — non-deterministic
  and unfit for a rigorous run.
- **Both builds share one TCC record.** `/Applications/YEN.app` and
  `zig-out/YEN.app` are the same bundle id (`com.yenchat.yen`) + Developer ID
  identity, so the test build inherits the same Accessibility / Microphone /
  Speech Recognition grants. You cannot permission or deny them independently;
  macOS shows one "YEN" entry.
- **`/Applications/YEN.app` frequently hosts the Claude Code / Codex session**
  (`.../MacOS/yen` -> `login` -> `zsh` -> `claude`). Quitting it to clear the tap
  conflict kills that session. Run this matrix from a plain **Terminal.app /
  iTerm2** window instead — a shell NOT hosted by YEN — so quitting the installed
  app is safe.

---

### Environment prep

1. Build (or confirm) the test app:
   `bash scripts/native/01-macos-smoke.sh --build-only`
   -> produces `yen-terminal/ghostty/zig-out/YEN.app`.
2. Open **Terminal.app** or **iTerm2** (NOT a YEN split/window).
3. Quit every other YEN instance so the test build is the sole tap owner:
   - Quit `/Applications/YEN.app` (menu bar / Cmd+Q). If a Claude/Codex session
     lives inside it, save/close that first — it will terminate.
   - Confirm none remain: `pgrep -fl 'YEN.app/Contents/MacOS/yen'` prints nothing.
4. Confirm platform: `sw_vers -productVersion` -> `27.x` or later uses `SpeechAnalyzer`
   when available (no YEN timer; Translate-on-Dictate available). Runtime fallback uses
   `SFSpeechRecognizer` (60s cap; Case 2 expectations differ — see below).
5. Permissions must already be granted (Accessibility, Microphone, Speech
   Recognition). If prompted on first capture, that is itself a valid onboarding
   observation.

---

### Capture + report harness

Capture (launches the sole test instance, streams `Dictation*` events live, saves full stdout under `~/.yen-dictation-matrix/`):

```
bash scripts/native/02-dictation-live-matrix.sh capture
```

Drive the matrix below while it streams.
Press **Ctrl-C** when done (kills the test instance).
Then produce the per-session evidence table:

```
bash scripts/native/02-dictation-live-matrix.sh report      # newest capture log
bash scripts/native/02-dictation-live-matrix.sh report <logfile>
```

The report groups by session UUID and prints `recognizer`, ordered `states`, `stop_cause`, `fallback_used`, `transcript_source`, `insertion_outcome`, `key_up_to_insert_ms`, the `events` seen, and a `VERDICT` of `OK` / `CHECK` / `FAIL`.
It raises `CHECK` (not a hard FAIL) when a normal stop carries fallback text, because that is legitimate when SpeechAnalyzer finalization genuinely fails (`stopMarkedAsFailure`, which is not in the log) — the operator confirms against the spoken phrase whether it was a genuine failure or a real violation.

Structural exit codes (automation-friendly, still not phrase-proof):
- `0` — sessions present, no `FAIL` verdicts, at least one terminal outcome
- `1` — incomplete session(s) or zero terminal insert/stop/block outcomes
- `2` — zero sessions in the log

The harness refuses to launch a second instance when another YEN is running (pass `--force` only if you accept the tap conflict).

---

### Log vocabulary (grounded in source)

Structured line shape: `DictationController: event=<e> session=<uuid> state=<s> recognizer=<r> [stop_cause=<c>] [fallback_used=<b>] [key_up_to_insert_ms=<n>] [insertion_outcome=<o>] [transcript_source=<t>]`

| Field | Values |
|-------|--------|
| `state` | `idle` `starting` `listening` `stopping` `inserting` `failed` |
| `stop_cause` | `hotkeyRelease` `legacyTimeout` `paused` (final-only) · `recognizerError` `watchdog` `forcedReset` (fallback-eligible) |
| `fallback_used` | `true` / `false` |
| `transcript_source` | `final` / `fallback` |
| `insertion_outcome` | `direct-surface-paste` (YEN terminal) · `responder-chain-paste` (YEN non-terminal) · `remote-command-v-paste` (cross-app) · `manual-recovery-required` (Secure Input / synthetic-paste failure) |
| key `event=` names | `start_requested` `start_blocked_permissions` `start_cancelled_on_stop_request` `listening_started` `stop_requested` `stop_completion_ready_for_insert` `stop_completion_without_insert[_finalized]` `stop_completion_ignored` `insert_completed` `insert_manual_recovery_required` `recognizer_error` `force_stop_reset` |

Also emitted: `DictationController: session_state_transition session=<uuid> from=<s> to=<s> reason=<r> recognizer=<r>`.

Policy invariant the run must confirm: on a **normal** stop (`hotkeyRelease` / `legacyTimeout` / `paused`) insertion binds only to the final recognizer result — `fallback_used=false`, `transcript_source=final`.
Fallback is allowed on failure stops (`recognizerError` / `watchdog` / `forcedReset`) and on the one normal-stop exception where SpeechAnalyzer finalization genuinely fails (`transcriptForInsertion` allows fallback on `stopResult.stopMarkedAsFailure`).
That flag is not logged, so a normal stop showing `fallback_used=true` is only a violation if the utterance actually finalized cleanly — confirm against what you said.

---

### Matrix cases (fill in Observed / Verdict)

#### Case 1 — Short utterance
Steps: hold Option+Space, say a brief phrase, keep holding a beat after speech ends, release.
Expected: the layered rainbow waveform responds to speech and stays optically centered beside `Listening...`; the overlay then changes to `Processing...`; final text inserts once; no 5-second hang; no preview-only text on the normal stop.
Expected log: states `starting -> listening -> stopping -> inserting`; `stop_cause=hotkeyRelease`; `fallback_used=false`; `transcript_source=final`; `event=insert_completed`; `key_up_to_insert_ms` present.
- Observed: `________`  key_up_to_insert_ms: `____`  Verdict: `____`

#### Case 2 — Long utterance (past 60s)
Steps: dictate continuously past 60 seconds, then release.
Expected (SpeechAnalyzer active): no forced timeout, no mid-session auto-paste, menu-bar indicator stays visible, final insert only on release.
NO event with `stop_cause=legacyTimeout`.
Expected (legacy recognizer): auto-stops at ~60s with `stop_cause=legacyTimeout` and auto-paste; release+re-press to continue.
- Observed: `________`  saw legacyTimeout? `____`  Verdict: `____`

#### Case 3 — Stop/re-press during finalization
Steps: release, then immediately press+hold again while the first session is still finalizing.
Expected: first session completes once; second session starts cleanly (new session UUID); no stale transcript bleed; no stuck `Processing...`.
Expected log: two distinct `session=` UUIDs; first reaches `insert_completed`; second shows `start_requested` / `listening_started`; may show `stop_completion_ignored` or `start_cancelled_on_stop_request` on the race.
- Observed session UUIDs: `________`  bleed? `____`  Verdict: `____`

#### Case 4 — Forced stop failure / watchdog (failure-sensitive)
Steps: instrument or provoke a wedged stop path so the controller watchdog or a recognizer stop-time failure runs.
Expected: UI exits listening; app returns to idle without relaunch; fallback insert allowed only from the last composed transcript when the stop is marked failed.
Expected log: `stop_cause` in `watchdog` / `forcedReset` / `recognizerError`; `fallback_used=true` permissible; `transcript_source=fallback`; `event=force_stop_reset` or `recognizer_error`.
- Observed: `________`  returned to idle w/o relaunch? `____`  Verdict: `____`

#### Case 5 — Permission revocation while capture/finalization active
Steps: start dictation, revoke Microphone OR Speech Recognition while capture or finalization is active, wait for the permission-monitor tick (~4s interval, 0.6s tolerance).
Expected: active session tears down; menu state -> blocked; recovery guidance + alert (frontmost) or notification (background).
Expected log: `event=force_stop_reset` with `stop_cause=forcedReset` (reason `permission-revoked`).
Record **teardown timing** = wall-clock from the revocation to the `force_stop_reset` line.
- Observed teardown delay: `____ s`  menu blocked? `____`  Verdict: `____`

#### Case 6 — Permission change while idle / during insertion drain
Steps: revoke permissions while no capture is active; then repeat while translation or delayed insertion is still completing after capture ended.
Expected: blocked state updates WITHOUT an unnecessary force reset; a post-capture insertion tail is NOT silently dropped by the unrelated permission change.
Expected log: idle revocation flips menu to blocked with NO `force_stop_reset` (no active session); the in-flight insertion still reaches `insert_completed`.
- Observed: `________`  tail dropped? `____`  Verdict: `____`

---

### Target-app coverage (acceptance criterion 1 — all required)

| # | Target | How | Expected insertion_outcome / behavior | Observed | Verdict |
|---|--------|-----|----------------------------------------|----------|---------|
| A | Non-YEN app | Focus TextEdit / Notes / Safari field, dictate a phrase | `remote-command-v-paste`; text appears at cursor | | |
| B | In-YEN terminal | Focus a YEN terminal surface, dictate | `direct-surface-paste` (not responder-chain into a palette/field) | | |
| C | Cross-app process-only OR readable-focused-element | Dictate into an app that exposes no readable focused element (process-only path) or one that does | process-only allowed on same-PID/frontmost only; readable-field mismatch is fail-closed to recovery | | |
| D | Secure Input / password field | Focus a password field (login window, `sudo` in a terminal, 1Password), dictate | `insert_manual_recovery_required` / `manual-recovery-required`; NO clipboard write; "Blocked by Secure Input" notification; **clipboard unchanged** | | |
| E | Failure-sensitive | Reuse Case 4 or Case 5 | fallback-eligible stop; clean return to idle | | |

[NOTE] For D, confirm the pre-dictation clipboard is intact afterward (copy a sentinel string first, dictate into the secure field, verify the sentinel still pastes elsewhere).

---

### Sign-off

- [ ] Criterion 1: cases A–E all run and recorded above (non-YEN, in-terminal,
      cross-app process-only/readable, Secure Input, failure-sensitive).
- [ ] Criterion 2: `stop_cause`, `fallback_used`, restart behavior (Case 3), and
      revocation teardown timing (Case 5) captured via the report, attached below.
- [ ] No unresolved `CHECK` verdicts from `report` (each normal-stop fallback
      confirmed as a genuine finalization failure, not a policy violation).
- [ ] Report artifact path: `________________`
- [ ] Operator / date: `________________`

A change to dictation capture or insertion ships only when all boxes are checked with real evidence.
