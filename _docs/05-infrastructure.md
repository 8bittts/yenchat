# Infrastructure

Desktop toolchain, build loops, overlay rules, signing, DMG, release hosting, Sparkle, versioning, the web release practice, media retention and environment variables for YEN.

The `/update-yen` skill owns the release procedure, and `.agents/skills/update-yen/references/zip-build.md` is the only copy of the build-step list.
Web deploys follow Public Web Release Practice below and never need `/update-yen`.

## Sources of truth

- `yen-terminal/customizations/build-release.sh`, `finalize-build.sh`, `generate-appcast.sh`, `bundle-yen-resources.sh`
- `yen-terminal/apply-overlays.sh`
- `scripts/lib/version-utils.sh`, `signing-constants.sh`, `release-constants.sh`, `sparkle-runtime-floor.sh`
- `public/stable/version.json`
- `ghostty/macos/YEN-Info.plist` and `ghostty/macos/YEN*.entitlements`, both written by `apply-overlays.sh`

## Requirements and Toolchain

YEN requires macOS 27.0 or later on Apple silicon.
The build uses the minimum in `yen-cli/lib/macos-version.sh` for Xcode targets, Launch Services, thumbnail helpers and the standalone CLI.
Direct invocation of the app or a thumbnail helper checks the running OS against the compiled deployment target before entering main.
Before signing metadata or generating the Sparkle feed, the release gate verifies the macOS platform and minimum version in every packaged YEN binary slice.
Libghostty and bundled vendor tools can target earlier systems.

| Tool | Rule |
|------|------|
| Zig | Must equal `.minimum_zig_version` in `ghostty/build.zig.zon`; `build-release.sh` fails fast with a `zigup fetch <version>` hint |
| Xcode | Release on stable Xcode 27.x, which links the macOS 27 SDK. Gates reject beta and RC selections by install path and the `xcodebuild -version` line, never by a trailing letter in `ProductBuildVersion` (GM builds such as `27A266a` end in one). `YEN_ALLOW_PRERELEASE_XCODE=1` is for experiments only |
| Sparkle runtime | Upstream pins the SPM package exactly; `scripts/lib/sparkle-runtime-floor.sh` asserts it stays at or above `SPARKLE_RUNTIME_FLOOR` at vendor time and in the branding gate. Raise the floor and `tests/123` together |
| Sparkle CLI tools | `sign_update`, `generate_appcast`, `BinaryDelta`, `generate_keys` live in `tools/sparkle/`. Refresh on any security release after checking the release-asset SHA-256, and rewrite all four fields of `tools/sparkle/VERSION`, which is a recorded pin and not a gate. The `sparkle-cli` helper no longer exists upstream |
| gettext | `msgfmt` and `msgunfmt` rebrand locale catalogs during bundling |

XcodeBuildMCP (needs Node; it bundles its own AXe, so no Homebrew `axe` is needed) is optional for deeper native automation; `scripts/native/01-macos-smoke.sh` stays the default build entry point.

### Release SDK: macOS 27

Do not make a beta macOS SDK the default `xcode-select` or release path.
On macOS 27, AppKit decides whether a menu item's image is shown and typically hides it.
YEN follows that system default on purpose: `setImageIfDesired` sets the image and leaves `NSMenuItem.preferredImageVisibility` at automatic.
Setting `.visible` is a product decision, not a fix; it would also need every menu icon checked by eye.
On an SDK change, run `scripts/native/01-macos-smoke.sh` (`--fast`); its slice covers menus, the Tab Sidebar and Scratchpad panels, clipboard snapshot and restore, and dictation paste.
The component gate's forced slice (`YEN_COMPONENT_XCODE_REGRESSION_MODE=always`) runs only the command-palette, Settings, keyboard, web-preview and utility-window suites, so it does not replace that run.
Quick Terminal has no suite, so open and close it by hand.

## Local Build Loops

| Command | Use |
|---------|-----|
| `scripts/native/01-macos-smoke.sh` (`--fast`, default) | Reapplies overlays, then runs the targeted `xcodebuild` regression slice; needs a complete `YENKit.xcframework` |
| `scripts/native/01-macos-smoke.sh --browser` | Focused browser command and settings suites |
| `scripts/native/01-macos-smoke.sh --browser-live` | Launches `zig-out/YEN.app` and checks the live `yen web` bridge; non-mutating when any YEN is already running |
| `scripts/native/01-macos-smoke.sh --local` | `build-release.sh --local --skip-vendor` |
| `scripts/native/01-macos-smoke.sh --build-only` | `build-release.sh --build-only --skip-vendor` |
| `build-release.sh` | Full release: clean, build, sign, notarize, DMG, upload |

`build-release.sh` retains argument handling and locks, then sources six ordered phases from `scripts/lib/build-release-phases/`.
Missing build phases fail before sourcing, and exit traps preserve build failures and interrupt status.
Cleanup removes DerivedData only when its `WorkspacePath` matches the current checkout's Xcode project.
`finalize-build.sh` sources eight ordered phases from `scripts/lib/finalize-build-phases/`, retaining signing, notarization, upload, and appcast checks.
Its staging cleanup preserves failure and interrupt status while releasing the workflow lock.
`bundle-yen-resources.sh` sources six ordered phases from `scripts/lib/bundle-resource-phases/` for themes, CLI resources, binaries, Yazi, shell integration, and locale verification.
Missing bundling phases fail before sourcing, including after theme cleanup installs its exit trap.
Locale verification requires at least one compiled catalog and reports the number checked.
`--local` keeps caches and never ships; `--build-only` cleans but skips packaging.
Both refresh an ad-hoc signature so `open yen-terminal/ghostty/zig-out/YEN.app` launches, which is why `05-detect-failures.sh` needs a full Developer ID build.
`--skip-vendor` skips only `14-vendor.sh --check`; the vendor-audit doc check still runs before and after the build.
`14-vendor.sh --check --release` is the `/update-yen` Step 1 form: `scripts/lib/release-vendor-window.sh` accepts a Ghostty `behind` when the committed baseline was pushed by a `vendor:` commit within 24h, the vendor files are clean, and the commit is on `origin/main`; nothing else that is behind, unknown, or missing is accepted, and the window is a constant rather than an env override.
`scripts/lib/zig-toolchain.sh` is the one comparison of `zig version` against `.minimum_zig_version`; `14-vendor.sh` and `validate-environment.sh` both call it with their own bypass variables.
`YEN_PREBUILD_COMPONENT_GATE_MODE=off|report|enforce` controls the pre-build `03-verify-components.sh` run; turn it off only when the caller already ran it.
`YEN_VERBOSE_OVERLAYS=1` shows every overlay patch line.

A fresh git worktree has no `yen-terminal/ghostty/`, because it is gitignored and regenerated.
To run `xcodebuild` there without a Zig build, copy the canonical tree in as real files: `yen-terminal/ghostty/` without `.zig-cache`, `.yen-zig-global-cache`, `zig-out` and `macos/build`, then `zig-out/` without `YEN.app`.
Without `zig-out/share`, the build fails on missing `terminfo`, `zsh` and `yen` folder references.
The unit suite also needs the ignored `src/config/Config.zig`, `macos/YEN.xcodeproj`, each synchronized-group source folder, and the vendored `zmx` (`tests/164`, `tests/165`).
Copy those prerequisites into a fresh worktree before starting the suite.

## Overlay Rules

`apply-overlays.sh` runs eight ordered shell phases under `scripts/lib/overlay-phases/` in one shell.
The phase order preserves branding, renames, project settings, icons, emoji removal, copying, patching, and verification.
`overlay-data/` declares bulk URL substitutions, required hooks, and retired files; fixtures exercise each reader and its failure cases.
Native change detection and shell recurrence checks include the extracted phases and helpers.
AppleScript verification watches the extracted branding, rename, copy, and verification paths.
`overlay-plist.sh` owns plist add/set/delete operations, and `overlay-rename-preflight.sh` checks the renamed layout and AppleScript resources.
Fixture tests call those helpers directly.
`overlay-branding.sh` owns bulk rewrite filtering, URL restoration, and project-file configuration.
`overlay-verification.sh` owns wrapper conformance removal, Shift+Enter payload checks, and AppDelegate hook and method checks.
`overlay-patch-plan.json` declares each patch target and its arguments.
The patch phases call named operations in their required order, and `overlay-patch-plan.py` loads those arguments into the existing patch utility without a second subprocess.
`overlay-patch-runtime.sh` owns patch execution and applied/skipped tallies for both the orchestrator and fixture tests.
`overlay-patch-targets.txt` lists required post-branding targets; `overlay-patch-preflight.sh` validates every target and rejects missing or empty manifests and duplicate entries.

- Edit only `yen-terminal/overlays/` and `yen-terminal/customizations/`; `yen-terminal/ghostty/` is regenerated.
- New overlay `.swift` files compile without a pbxproj edit, because `macos/Sources` is a synchronized root group.
- Never delete an overlay file mid-refactor: `cp -Rp` only adds and overwrites, so the deletion never reaches the build tree.
- Code behind `#if DEBUG` also needs a `--build-only` Release compile.
- The four bulk `sed` passes in the overlay phases run through `rewrite_files_containing`, because an unconditional `sed -i ''` bumps every mtime and turns each `--fast` run into a full recompile. Its filter must stay the exact union of that pass's `sed` left-hand sides, the list must stay NUL-delimited with `--null` (BSD `grep` ignores `-Z`), and an empty candidate list fails.
- Branding and URL scans exclude `.zig-cache/` and `zig-pkg/` so incremental builds cannot rewrite cached or fetched dependencies.
- Branding never touches `build.zig.zon` (its `.name = .ghostty` builds dependency paths) or `build.zig.zon.json` (pinned upstream URLs); branding them fails the build with `yen/pkg/zlib: FileNotFound`.
- A cross-file parity guard fails overlay apply when a non-`AppDelegate` file calls an `appDelegate` method the `AppDelegate*.swift` overlays no longer define.
- A helper in `Resources/bin/` with a sibling `<binary>.entitlements` file is signed with those entitlements.

## Build Ownership and Toolchain Guardrails

- `build-release.sh` owns `YENKit.xcframework` recreation and every Zig/Xcode workaround. Never substitute raw `zig build`, and never read a missing xcframework as a test regression.
- The build passes `-Dxcframework-target=native`, so `YENKit.xcframework` holds one arm64 engine library. The universal target compiles a second, x86_64 copy that the arm64-only app never links; `tests/123-release-script-hardening.test.ts` fails if it returns.
- `03-verify-components.sh` skips its `xcodebuild` slice when the xcframework is incomplete, or when `YEN_COMPONENT_XCODE_REGRESSION_MODE=auto` finds no native macOS change since the latest `[deploy]` release; `always` forces it and `off` skips it.
- The component gate declares 17 pre-build units in `scripts/lib/units/03-verify-components.units` and ends in `RECEIPT gate=03-verify-components ... result=PASS`, after one `RAN|` or `SKIP|` line per unit. The native slice reports `RAN|xcode-regression|suites=<n> executed=<N>` from `xcodebuild`'s own output.
- Before every `zig build`, a three-valued SDK link probe (`pass`, `fail`, `inconclusive`) decides the synthetic-sysroot workaround; `pass` overrides the SDK `targets:` heuristic, and only `undefined symbol` output is `fail`. The probe imports no `std`, so it cannot fail at compile time and be misread as a linker failure (`tests/138-zig-sdk-probe.test.ts`). Bypass: `YEN_SKIP_ZIG_SDK_WORKAROUND=1`.
- `overlays/src/build/LibtoolStep.zig` extracts `.o` members from input archives before `libtool -static`; passing archives directly drops `vt.o`, `zig_macos.o` and `spirv_cross_c.o`.
- `WebPreviewCommandTests` runs as its own single `xcodebuild` invocation after the combined suites. Re-merging it causes an order-dependent host crash; never add a retry, because the past launch crash was a deterministic over-release fixed in `BrowserTestSupport`.
- `build-release.sh`, `finalize-build.sh` and `14-vendor.sh` share `$TMPDIR/yen-workflow-<cksum>.lock` plus a per-script lock. Remove a lock only when it is stale and no workflow PID is alive.
- Finder-prone clean targets go through `remove_dir_robust`, which sweeps `.DS_Store` and retries; a plain `rm -rf` of `zig-out` races Finder and aborts under `set -e`.
- `scripts/manual/12-check-recent-crashes.sh --days 3` blocks a release while recent `yen` crash reports exist: macOS `.ips` reports and the bundled reporter's `~/.local/state/yen/crash/*.yencrash` files whose main executable is `/Applications/YEN.app`. A framework abort, such as an AttributeGraph precondition, writes only the `.yencrash`, so the `.ips` scan alone misses it. It also counts `zmx*.ips` reports whose `slice_uuid` is a UUID of the installed `Contents/Resources/bin/zmx` (`dwarfdump --uuid`), which covers the per-session `zmx-<digest>` copies; the report path is redacted, and local zmx builds have other UUIDs. Installing a new release changes that UUID, so the previous build's reports stop counting (guard: `tests/151-recent-crash-gate.test.ts`). Override only with `YEN_ALLOW_RECENT_CRASHES=1` after triage.
- Release cost model: the clean compile and notarization are irreducible. The shipping artifact never reuses a prior build, the SDK probe is never cached, and the release tree runs its own native slice in `/update-yen` Step 4 even when the vendor phase's VB-05 ran it on the same sources minutes earlier.

[CRITICAL] Test `zig-out/YEN.app`, and never quit or kill `/Applications/YEN.app` during a build, test or release.
The agent session and the running `/update-yen` are often hosted inside it, so killing it kills them (`exit 137`).
If versions conflict, run `yen-terminal/customizations/clear-app-cache.sh`.

**Release-push ordering.** `vercel.json`'s `ignoreCommand` reads only the HEAD commit of a push, so push the `[deploy]` release-notes commit by itself.
`07-stage-release.sh` does not stage baselines, `VENDOR_INFO.txt` or `_docs/04-security.md`; commit a vendor bump before `/update-yen` starts.

## Signing and Notarization

Identity and team come from `scripts/lib/signing-constants.sh`; the notary profile is `YEN-Notarization` in the keychain.
Sign bottom-up: vendored binaries, then every nested Sparkle binary, `.app` and XPC service, then the framework, then the main app with `--entitlements`.
Never use `--deep`, which re-signs nested code with the wrong entitlements.
Without `--entitlements` on the main app, the microphone and speech prompts never appear.

`finalize-build.sh` then verifies that `audio-input`, `speech-recognition` and `apple-events` are embedded, and that every Mach-O found with BSD `find -perm +111` (never GNU `/111`) has a Developer ID signature with the right team.
That scan misses dylibs without the executable bit; add any such file to the signing loop explicitly.
It also asserts `REPO_ROOT` is the repo root before packaging.

**Release credential preflight.** Before the Zig build, `build-release.sh` checks signing access and requires successful, non-empty `notarytool history` output.
It runs `scripts/01-verify-release-target.sh`, which fails when `gh` is missing, the release repository is unreachable or not public, or the session cannot push to it.
`finalize-build.sh` repeats the notarization check as a backstop.

**Entitlements.** `YEN.entitlements` (Release), `YENDebug.entitlements` and `YENReleaseLocal.entitlements` carry `com.apple.security.device.audio-input`, `com.apple.security.personal-information.speech-recognition`, `com.apple.security.personal-information.photos-library` and `com.apple.security.automation.apple-events`.
The hardened runtime denies a protected resource without its entitlement and shows no prompt, so Shuffle from Photos needs the Photos entry.
The Debug and ReleaseLocal files also carry `com.apple.security.cs.disable-library-validation`; the Release file does not.
`apply-overlays.sh` strips every other `personal-information.*` entitlement.

**Info.plist.**

| Key | Rule |
|-----|------|
| `SUFeedURL` | `https://yen.chat/stable/appcast.xml` |
| `SUPublicEDKey` | EdDSA public key; updates fail without it |
| `SUEnableInstallerLauncherService` | `true`; installs fail silently without it |
| `SUEnableAutomaticChecks` | Deleted, so Sparkle asks on first launch; `false` would silently disable checks |
| `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` | Required for dictation prompts |
| `NSPhotoLibraryUsageDescription` | Required for the Shuffle from Photos prompt |
| `NSScreenCaptureUsageDescription` | Must stay absent; screenshots capture only YEN's own window and need no Screen Recording grant |

`YEN-Info.plist` owns the three usage strings above.
`plist_set_usage_description` writes each one and deletes the matching `INFOPLIST_KEY_*` build setting, because a build setting overrides the file and ships upstream's generic prompt text.

`INFOPLIST_PREPROCESS = NO` must stay set, because the preprocessor treats `//` in `https://` as a comment and truncates `SUFeedURL`.

**New machine.** Import Apple's `DeveloperIDG2CA.cer` into the login keychain, then `xcrun notarytool store-credentials "YEN-Notarization" --apple-id <id> --team-id GRNGR33Z8A --password <app-specific>`.

## DMG

Frozen installer layout, enforced by `scripts/manual/14-verify-dmg-layout.sh`:

- Icon view with toolbar and status bar hidden, arrangement `not arranged`, window `600x660`.
- Icon size `108`, label size `12`.
- `YEN.app {300,241}`, `Applications {300,420}`; `.background {300,760}` and `.fseventsd {300,800}` parked below the frame.
- `background.png` (600x600) and `background@2x.png` (1200x1200) from `public/dmg-frame.png`, with no baked labels. The recipe lives in `yen-terminal/customizations/dmg-resources/README.md`.
- Finder draws icon labels in the system text color (black in Light Mode, white in Dark Mode), and a DMG cannot change it. The art puts a mid-gray pill under each label so both stay readable; without a backing, Light Mode labels vanish on the dark art.
- An `/Applications` symlink for drag install.

Packaging rules:

- Backgrounds must be opaque RGB. With RGBA, Finder's `set background picture` exits 0 but stores a background color instead of the image.
- Hide `.background`, scrub `.fseventsd`, and remove `.metadata_never_index` from the mounted image before Finder layout, or Finder shifts the icon column.
- Strip any `Icon\r` custom-icon override from the staged `YEN.app`.
- Survive `/Volumes/YEN 1` name collisions, and fail visibly when Finder scripting fails instead of shipping the default layout.
- `scripts/lib/mount-utils.sh` detaches stale `/Volumes/YEN*` mounts.

`05-detect-failures.sh` requires `version.json.url` to match the version's GitHub Release asset URL, both checksums to match the DMG, and `hdiutil verify`, `spctl -a -t open --context context:primary-signature` and `xcrun stapler validate` to pass.
It runs the layout verifier as the authoritative gate; `YEN_DMG_LAYOUT_GATE_MODE` is `enforce` by default, and any other mode also needs `YEN_ALLOW_GATE_DOWNGRADE=1`.
`YEN_DMG_LAYOUT_SKIP_FINDER_CHECK=1` is an emergency structure-only override for when Finder readback is unavailable.
Before shipping, open the DMG on Retina and non-Retina displays, check both labels, drag-install once, and reopen to confirm the layout holds.

## Branding and Automation Gates

`04-verify-branding.sh` reports `guarded subjects` present/total; its checks live in the script, and every upstream path it guards is declared in `scripts/lib/ghostty-paths.sh`.
`05-detect-failures.sh` checks the tiered `+action` policy and App Intents allowlists on the built binary; their contracts are in `_docs/12-commands.md`.

**AppleScript smoke gate.** `scripts/manual/16-verify-applescript-if-needed.sh` runs the verifier when AppleScript or workspace contract paths changed in the worktree or since the commit stamped in `yen-terminal/.applescript-verified`, or when the stamp is missing.
Judge it by `RAN|verifier|` versus `SKIP|verifier|`, never by the exit code; a clean pass on a clean tree advances the stamp.
It verifies absolute-path launch, `new window`, `new tab`, `split`, `YEN_SURFACE_ID` against the AppleScript terminal `id`, working directories, counts, and the `perform action` allowlist.
`--keep-open` leaves the split scenario up for the physical `Cmd + Option + 2` check; scripted keys and computer-use input cannot reach the app-wide layout-shortcut monitor.
The verifier refuses to run while another YEN process holds an older config.

#### Validating the local `zig-out` build without quitting your own YEN.app

Launching `zig-out/YEN.app` by hand can activate the installed app because both use `com.yenchat.yen`.
When the operator's session must stay up, give the build its own identity:

```bash
bash $HOME/Documents/yenchat/scripts/manual/18-make-verify-copy.sh
APP=$HOME/.local/state/yen/verify/YENVerify.app
bash $HOME/Documents/yenchat/scripts/manual/16-verify-applescript-if-needed.sh --app "$APP" --keep-open
```

`18-make-verify-copy.sh` writes one copy at a fixed path, with the bundle identifier `com.yenchat.yenverify`, the executable `yenverify`, and the release Developer ID signature plus the build's entitlements.
Always use it; never build the copy by hand in a `mktemp` folder, re-sign it ad hoc, or invent another name or identifier.
macOS keys an Accessibility or Automation grant to the code requirement, so an ad-hoc copy asked the operator for access on every build, and a deleted temp copy left System Settings with no row to toggle.
The fixed identifier and Team ID let one grant cover every later copy; the script refuses while a copy is running.
The builder checks for a running `yenverify` and for processes using the destination executable, including a copy relaunched as `yen`.
Wait for the session that owns the running copy.
When two sessions verify at once, give each its own folder with `YEN_VERIFY_DIR`: the grant follows the identifier and Team ID, not the path, while one shared path lets a later build replace an earlier session's copy in the middle of its test.
Identify the scripted window by its scratch-directory tab titles and confirm it with `lsappinfo`.
The verifier overwrites both `config.yen` locations and restores them on exit from a backup inside its temp directory, so copy any live config first.

For a manual or scripted UI pass, launch the same copy with a scratch config instead of running the verifier:

```bash
SCRATCH=$(mktemp -d)
defaults export com.yenchat.yenverify "$SCRATCH/yenverify-defaults.plist"
defaults write com.yenchat.yenverify com.yenchat.yen.hasCompletedSetup -bool true
open -n -a "$HOME/.local/state/yen/verify/YENVerify.app" --env YEN_CONFIG_PATH="$SCRATCH/config.yen"
```

- Confirm the process before the first observation: its start time, the `txt` mapping from `lsof -p`, and `lsappinfo info -app com.yenchat.yenverify`.
- Settings in the copy reads and writes only the scratch config, and its preferences live in the `com.yenchat.yenverify` domain. Restore that domain with `defaults delete` followed by `defaults import`, because import alone merges.
- [CRITICAL] The copy still shares `~/Library/Application Support/com.yenchat.yen/` with the installed app, because `TerminalBackgroundImageStore.appSupportRootURL` and `ScratchpadStorage.directoryName` are fixed strings. Never use Reset All Settings, the background image buttons or the Scratchpad in the copy; the reset path calls `cleanupManagedImages` on the operator's images. Hash the installed `config.yen`, `backgrounds/` and `scratchpad.txt` before and after the pass.
- Do not toggle Launch at Login, which registers the scratch bundle as a login item, or pick a notification sound, which plays aloud.
- Every YEN process owns its own Moving Wallpaper switch: the installed app, each verify copy and the Debug test host read different preference domains. A copy with the switch on covers the operator's desktop while their own Settings show it off. Leave the copy's switch off when the pass ends, delete the `com.yenchat.yen.movingWallpaper.*` keys you wrote, and never write `enabled` again for a copy the operator may have switched off.
- Launching the copy or activating it with `open -a` takes keyboard focus, and the operator's keystrokes then land in its terminal. Tell the operator before the pass and keep activations few.
- A launch can put a `UserNotificationCenter` alert and then System Settings in front of the copy. Neither shows in an app-filtered screenshot, so read `lsappinfo front` when input stops landing.
- `18-make-verify-copy.sh` takes a Release `zig-out` app. A Debug build from `--fast` keeps `Contents/MacOS/yen.debug.dylib` under its old signature, and dyld aborts the copy at launch with "different Team IDs". To check a Debug build, launch that build itself: its identifier is already `com.yenchat.yen.debug`.
- Address every System Events element through `first process whose unix id is <pid>` in the same expression. A reference saved in a variable resolves again by the process name `yen` and reaches the installed app.
- System Events reads only `AXDescription`. SwiftUI buttons inside a grid expose their name as `AXAttributedDescription`, so read names with `AXUIElementCopyAttributeValue` before reporting a button unnamed. Grid cells outside the visible part of the scroll area are not in the tree until they are scrolled into view.
- Synthetic Escape does not reach the copy: neither a computer-use key press nor `System Events` `key code 53` cancelled the shortcut recorder, whose Esc handling ships and is unit-tested. Judge Esc behavior only from a real key press.
- Leave 2 seconds between synthetic clicks; a click within about 1.5 seconds of the previous one was dropped repeatedly.
- For a pass isolated from the operator's files, add `--env CFFIXED_USER_HOME="$SCRATCH/home"`. The engine then reads `$SCRATCH/home/Library/Application Support/com.yenchat.yen/config.yen`, sessions go to `$SCRATCH/home/.local/state/yen/zmx`, and the token readers see only that home's tool records. A `theme` line in that config changes the terminal and the app appearance, where the same line in a `YEN_CONFIG_PATH` file does not.
  The preferences domain and the window restore state do not move. `UserDefaults.standard` still reads and writes the real `com.yenchat.yenverify` domain, and macOS restores the windows saved for the bundle identifier.
  Export the domain before the pass and restore it afterwards, and set `window-save-state = never` in the scratch config when the pass must start with no restored window.
- A pass that starts a persistent pane always uses `CFFIXED_USER_HOME`, with a short home such as `/tmp/<name>`, because a socket path over 103 bytes keeps the pane ephemeral. Without it the copy starts its sessions in the operator's `~/.local/state/yen/zmx`. Turn `com.yenchat.yen.persistentSessions` on in the copy's domain for the pass only, end every session the pass started, and delete the key afterwards.
  Write it with `defaults write … -bool YES`: `PersistentSessions.isEnabled` accepts only a stored Boolean, so the launch argument `-com.yenchat.yen.persistentSessions YES` leaves sessions off in a copy.
- When another session may run a copy with the same identifier, address the instance by process identifier, for example `osascript -l JavaScript -e 'Application(<pid>).quit()'`. `tell application id` can reach the other session's instance.
- A status-item panel can be checked without taking focus: launch with `open -g`, press the menu bar item through the Accessibility API (`AXExtrasMenuBar`, `AXPress`), and capture the panel by window id with `screencapture -x -o -l <id>`.
- Prove the engine applied the scratch config with a visible canary before judging a config-driven behavior. `working-directory`, `window-theme` and `window-padding-x` from a scratch file have shown no effect in the copy's terminals while Settings read and wrote the same file.
- The Settings preview always draws the focused outline, so a border effect can be checked in a background copy; a terminal window shows Spark and Aura only while the app is active and its window is key.
- `tell application "<path>" to new window` sometimes activates the copy and sometimes does not. Put `command = /bin/sleep 3600` in the scratch config so stray keystrokes run nothing, send an explicit `activate` when a check needs focus, capture at once, and return focus to the app that had it.
- `System Events` can resize the Settings window in the background (`set size of window 1`), which shows the rows below the fold without a scroll.
- The Settings accessibility tree is empty to `System Events`, so drive it from screenshots. Claude Code's computer-use tools accept the copy by bundle identifier and refuse a click that would land on another app's window.
- Quit the copy through AppleScript by its path (`tell application "$APP" to quit`), never with a signal sent by name. Every session's copy shares the bundle identifier, so `tell application id` also reaches a copy another session is running; a copy here received a quit its own session never sent.

## Release Hosting

Every desktop release is a GitHub Release on the public `8bittts/yenchat` repository, tagged `v<version>` (for example `v1.272`).
`scripts/lib/release-constants.sh` owns the repository and the URL shape, and `lib/release-host.ts` mirrors it for the `/download` allowlist.
The release holds `yen-<v>.dmg`, `yen-<v>.dmg.sha256`, and that release's Sparkle deltas; nothing is pruned, because older DMGs are the delta sources.
`finalize-build.sh` creates the release when it is missing, with its tag on the default branch tip, and uploads with `gh release upload --clobber`, retrying only network and server errors.
It then verifies the public URL and the byte size of each asset, following GitHub's redirect to its asset host.
The status probe retries up to `YEN_RELEASE_URL_VERIFY_ATTEMPTS` times (default 18, `YEN_RELEASE_URL_VERIFY_DELAY_SECONDS` apart, default 10, so about three minutes), because the asset host can answer 404 for a short time after an upload, then fails closed.
A private repository would make every download and update fail, so the release-target preflight rejects one.

## Sparkle Updates

YEN uses `SPUUpdater` with one public feed, `/stable/appcast.xml`.
Explicit `auto-update = check|download|off` overrides Sparkle's stored choice in `AppDelegate.yenConfigDidChange`.
With a terminal open, Check for Updates brings the current check or result forward in one Software Update window.
Retry acknowledges a failed session before another check starts.
Without a terminal window, Sparkle supplies its standard interface.
YENVerify can check the public feed; its update delegate refuses the production build.
The [verify-copy builder](../scripts/manual/18-make-verify-copy.sh) also removes Sparkle’s installer before signing, including when copying a build that predates the delegate guard.
Rebuild historical QA copies with that helper before opening them.
An install in an old, unprotected copy can relaunch a second production identity and restore the installed app’s windows, even with a scratch home.
If panes look wrong after a test relaunch, compare both PIDs and executable paths, bring the installed instance forward, and confirm its layout before touching saved state.
Quit only the identified test process after confirming its sessions can close.
With the default `tabs` titlebar style, the update status leads the titlebar beside the window buttons as a glass capsule in the row of workspace tabs (`UpdateTitlebarStatus`), and the tabs start after it.
It is placed in the toolbar's view like the tab bar, not added as a toolbar item, because NSToolbar moves its items into the overflow menu once the tab bar fills the toolbar.
An explicit `native` or `transparent` style keeps Ghostty's titlebar status at the right edge.
Native full screen and a hidden titlebar have no titlebar row to hold it, so the same item draws over the top-left corner of the terminal instead.

Delta updates: `generate-appcast.sh` downloads the DMGs of up to five prior GitHub Releases, runs the vendored `generate_appcast` in a scratch directory, and splices only `<sparkle:deltas>` into YEN's hand-built appcast item.
Every delta step is non-fatal and falls back to a full-DMG update.
Sparkle may emit multiple items when the minimum macOS version changes.
Select only the item matching the target build and copy its signed patches into the release directory.
To exercise installation mechanics, run `bash scripts/manual/17-verify-sparkle-delta-dryrun.sh <new-version> <old-version>`.
It applies a generated delta to a disposable copy from two published DMGs and verifies the result without launching either app.
`appcast.xml` generation fails closed on an invalid `minOS`, and `05-detect-failures.sh` verifies `sparkle:edSignature` against the DMG.

Release notes are a required release step owned by `_docs/10-gtm.md` → Release Notes.

## Version Management

`public/stable/version.json` is the only version source, in `X.XXX` form; `0.999` is followed by `1.000`.
`scripts/lib/version-utils.sh` alone derives `CFBundleVersion`, `sparkle:version`, the DMG and checksum file names; never strip dots by hand.
Non-shell mirrors such as `lib/version.ts` must fail closed on an invalid version and stay under runtime parity tests.
`02-sync-versions.sh` writes `package.json`, the Xcode project and `YEN-Info.plist`; it must accept any numeric shape, because a vendor bump resets the pbxproj to upstream values.
`finalize-build.sh` writes `version.sig`, an Ed25519 signature over `version.json` that `yen update` verifies with the bundled `SUPublicEDKey`.
The homepage, `yen version`, the welcome banner and the shell's `TERM_PROGRAM_VERSION` read `version.json` at build or run time and need no sync.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Wrong version or old UI | Confirm the running bundle (`09-quality.md` → Native Test Suite), then `clear-app-cache.sh` |
| `ProcessInfoPlistFile` fails or "Update Error!" | `INFOPLIST_PREPROCESS` was re-enabled or `SUFeedURL` is wrong |
| Repeated update checks after a timeout | Inspect the running process’s Sparkle log for a feed timeout and an active session. Retry in Software Update. If an older app cannot retry, use the signed DMG from `/download` when ready to quit. |
| Zig dependency fetch fails (`HttpConnectionClosing`, `TlsInitializationFailed`, transient `FileNotFound`) | `build-release.sh` retries three times with cache cleanup; then check `deps.files.ghostty.org` |
| Undefined `vt.o`, `zig_macos.o` or `spirv_cross_c.o` symbols | `LibtoolStep.zig` stopped flattening archives; reapply overlays and use `build-release.sh` |
| Build fails with a fingerprint | Copy the fingerprint from the error into `build.zig.zon` |
| `v0.0.0` in About | Run `scripts/02-sync-versions.sh` and rebuild |
| "Improperly signed" update | `scripts/manual/11-verify-sparkle-signing.sh` |
| Install flickers and fails | The DMG must be notarized and stapled |
| No microphone prompt | `--entitlements` missing from main-app signing; check `codesign -d --entitlements -` |
| Vendor check shows UNKNOWN (403) | Rate limit; retry, or `14-vendor.sh <vendor> --force` for an urgent local build |
| Swift concurrency error after a vendor bump | Fix the overlay source, not the build tree: mark helpers `nonisolated static`, read `UserDefaults` directly, and keep `.main` observers synchronous with `MainActor.assumeIsolated {}` instead of a `Task { @MainActor }` hop |
| `covariant 'Self' type cannot be referenced from a stored property initializer` | Use the explicit type name, or set the value in `init` |
| SourceKit "Cannot find type" in an overlay file | IDE noise; overlays sit outside the Xcode project until applied |

The Release build compiles arm64 only. Patterns it has rejected:

- Call `private static` methods with an explicit `Self.` from instance context.
- `deinit` is nonisolated, so cleanup it calls must be `nonisolated`, even as a no-op.
- Annotate closure parameter and return types in `compactMap`, `sorted` and `map` chains.

## Environment Variables

The web app reads no environment variable beyond `NODE_ENV`; contributors need no secrets to run `bun run dev`.
`next dev` appends a `nextjs-agent-rules` block to `AGENTS.md` on every start (`node_modules/next/dist/server/lib/generate-agent-files.js`); restore the file before committing.
The Vercel project holds no environment variable, and the project's Infisical `dev` and `prod` hold no web key; a stale gitignored `.env.local` is harmless because nothing reads it.
Add a variable only with the code that reads it, through Infisical, which auto-syncs to Vercel Production as a Sensitive variable; this file then lists its name and reason, never a value.
The rules for changing a value are in [AGENTS.md](../AGENTS.md#infisical).

### Vercel Behavior

- Bun and Node are pinned the way the fleet stack table says (`8leeai/_docs/13-starter-kit.md` → Web stack).
- Functions read the env snapshot of their deployment: a new or rotated variable takes effect only after the next `[deploy]` build.
- blog.yen.chat is a domain on the same Vercel project; its Cloudflare record is a DNS-only CNAME to the target Vercel assigns, so Vercel terminates TLS. `proxy.ts` routes it ([10-gtm.md](10-gtm.md#blog-blogyenchat)).

### Bundle Secret Scan

`scripts/46-scan-bundle-leaks.ts` fails closed when no credential value resolves.
On Vercel it always has one: the project's OIDC federation is on, so every build carries `VERCEL_OIDC_TOKEN`, which the scan list includes.
A contributor build with no credentials fails that last step by design, so `bun run build` is a maintainer gate (`CONTRIBUTING.md`).

## Public Web Release Practice

Web, SEO and legal changes ship separately from `/update-yen`:

1. Verify the edited route, `lib/seo.ts`, `app/sitemap.ts`, `app/robots.ts`, `public/llms.txt` and the owning docs.
2. Run `tests/121-seo-guardrails.test.ts` and the blog archive and host-routing tests.
3. Run the required gates in `AGENTS.md`.
4. Render the touched routes at desktop and 390x844: one `h1`, skip link, `main#main-content`, named controls, visible legal links, no band after the footer, no horizontal overflow.
5. Ship with a `[deploy]` subject, verify production by commit SHA and `READY`, then live-check representative URLs, `/sitemap.xml`, `/robots.txt` and the retired route redirects.

`.vercelignore` keeps local-only workspaces out of the upload.

## Public Media Retention

[HARD REQUIREMENT] Never delete a `public/` asset because nothing references it.
`public/mascot/` and `public/doc-images/` are kept as backup material; a sweep may report unreferenced media, but removal is the operator's call.
Keep the `public/mascot/*.mp4` entry in `outputFileTracingExcludes` and `/mascot` in `HEADER_BYPASS_PREFIXES`; they keep that media out of the serverless bundle.
`public/blog-media/` holds every blog.yen.chat image and video, has the same tracing exclude and bypass entry, and is rewritten only by `scripts/47-import-substack-blog.ts` ([10-gtm.md](10-gtm.md#blog-blogyenchat)).
