# YEN Scripts

Catalog of the automation in `scripts/`; invoke Bun entry points with `bun` and shell entry points with `bash`.
Procedures live in the `/update-yen` skill (`.agents/skills/update-yen/`, vendor phase and release), build rules in `_docs/05-infrastructure.md`, and gate contracts in `_docs/04-security.md`.
Run repo scripts by absolute path; never rely on `cd`.

## Release

| Script                        | Purpose                                                                                                                                                                                                               |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `01-verify-release-target.sh` | Fails before a build when `gh` cannot reach the public release repository or cannot push to it                                                                                                                        |
| `02-sync-versions.sh`         | Copies `public/stable/version.json` into `package.json`, the Xcode project and `YEN-Info.plist`; `build-release.sh` runs it when mirrors drift                                                                        |
| `03-verify-components.sh`     | Pre-build component gate (details below)                                                                                                                                                                              |
| `04-verify-branding.sh`       | Branding gate; 2 declared units, reports `guarded subjects` present/total                                                                                                                                             |
| `05-detect-failures.sh`       | Post-build failure detection (details below)                                                                                                                                                                          |
| `06-verify-download-links.sh` | Download-link parity, called by `05`                                                                                                                                                                                  |
| `07-stage-release.sh`         | Stages `version.json`, `version.sig`, `appcast.xml`, the DMG checksum and `package.json` only                                                                                                                         |
| `gen-release-notes.ts`        | Rebuilds `lib/release-notes/release-notes-data.ts` from `release-notes-copy.ts`, the frozen `lib/release-notes/release-ledger.ts` and `version.json` bump commits; run `bun run build` after it to refresh CSP hashes |

## Vendor

| Script                                         | Purpose                                                                                                                                                                                                             |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `14-vendor.sh`                                 | Checks and updates every vendor; `--check` exits non-zero when any vendor is behind, unknown or missing; `--check --release` accepts a Ghostty `behind` inside the release window; `<vendor> [--force]` targets one |
| `08-check-upstream.sh`, `09-analyze-impact.sh` | Manual Ghostty upstream check and impact analysis; `14-vendor.sh` does not call them                                                                                                                                |
| `10-update-ghostty.sh [ref]`                   | Updates Ghostty and applies overlays                                                                                                                                                                                |
| `11-sync-vendor-audit.sh`                      | Syncs the `_docs/04-security.md` snapshot from the baselines                                                                                                                                                        |
| `12-verify-vendor-audit.sh [--app <YEN.app>]`  | Verifies that doc against the baselines and, with `--app`, the built bundle                                                                                                                                         |
| `13-scan-artifact-fingerprints.sh`             | Scans built payloads for lineage and provenance residue, including the bundled shell CLI and locale catalogs                                                                                                        |
| `40-vendor-parity-snapshot.sh`                 | No-write parity harness around `14-vendor.sh --check` (`--baseline <path>`, then `--verify <path>`)                                                                                                                 |
| `41-lint-swift-view-modifiers.sh`              | Fails on a SwiftUI modifier missing its leading dot                                                                                                                                                                 |
| `42-lint-overlay-recurrence-gates.sh`          | Overlay recurrence baselines: non-DEBUG `print()`, timers without tolerance, god-file line counts, `apply-overlays.sh` heredocs, window-derived controller lookups                                                  |

### Vendor Registry

`scripts/lib/vendor-manifest.sh` is the single roster; this table mirrors it.

| Vendor    | Type                  | Baseline File         | Update Script            |
| --------- | --------------------- | --------------------- | ------------------------ |
| Ghostty   | Source (Zig)          | `.ghostty-baseline`   | `10-update-ghostty.sh`   |
| Yazi      | Binary (pre-built)    | `.yazi-baseline`      | `15-vendor-yazi.sh`      |
| fd        | Binary (pre-built)    | `.fd-baseline`        | `16-vendor-fd.sh`        |
| ripgrep   | Binary (pre-built)    | `.ripgrep-baseline`   | `17-vendor-ripgrep.sh`   |
| lazygit   | Binary (pre-built)    | `.lazygit-baseline`   | `32-vendor-lazygit.sh`   |
| btop      | Binary (source-built) | `.btop-baseline`      | `34-vendor-btop.sh`      |
| fastfetch | Binary (pre-built)    | `.fastfetch-baseline` | `33-vendor-fastfetch.sh` |
| zmx       | Binary (source-built) | `.zmx-baseline`       | `48-vendor-zmx.sh`       |

Baselines are git-tracked; vendor artifacts are gitignored.
Every vendored binary is arm64-only, because YEN requires macOS 27 and that runs only on Apple silicon.
Pre-built vendors are thin wrappers over `vendor_binary()` in `scripts/lib/vendor-binary.sh`, which downloads the arm64 asset; `fastfetch` ships one universal asset, so its arm64 slice is kept and the rest dropped.
`btop` builds from source through `vendor_source_build()` (CMake) because upstream ships no macOS binary; `zmx` builds the same way with Zig against the vendored engine (`_docs/04-security.md`).

### Verification Pipeline (vendor-binary.sh)

| Stage        | Check                                                                                                                                | Severity                                                                              |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| Download     | Published checksum verification (8 filename patterns tried, including underscore variants) plus GitHub release-asset digest metadata | Fatal on mismatch; trust-on-first-use is recorded when upstream publishes no checksum |
| Install      | `vendor_install_arm64` copies a thin arm64 binary or keeps the arm64 slice of a fat one; no arm64 slice fails                        | Fatal                                                                                 |
| Post-install | `assert_arm64_only_binary` (`lipo -archs` prints exactly `arm64`), before any baseline write                                         | Fatal                                                                                 |
| Post-create  | `--version`, `-V` or `version` answers                                                                                               | Fatal                                                                                 |
| No-op run    | Source-built vendors revalidate the bundled output against `output_sha256`                                                           | Fatal                                                                                 |
| Orchestrator | Baseline has `upstream_version=` before any read                                                                                     | Fatal                                                                                 |

### Adding a Vendor

Reference: `scripts/17-vendor-ripgrep.sh` for a pre-built vendor and `scripts/34-vendor-btop.sh` for a source build.

1. Create `scripts/NN-vendor-<name>.sh` (next free number) over `vendor_binary()`, or a source build when upstream ships no macOS arm64 asset.
2. Append one record to `scripts/lib/vendor-manifest.sh` (`key|type|title|subtitle|repo|binary|script|companion|require_companion`); `14-vendor.sh`, `11-sync-vendor-audit.sh` and `12-verify-vendor-audit.sh` iterate it.
3. Never hand-write the baseline; the first run writes it with the integrity fields the gates read back.
4. Wire `.gitignore`, `bundle-yen-resources.sh`, `finalize-build.sh` signing, `05-detect-failures.sh`, `scripts/lib/required-app-bins.sh`, the `13-scan-artifact-fingerprints.sh` scope, shell-integration `PATH`, this table, and `_docs/04-security.md`.
   Add the tool's license file at the vendored version as `yen-terminal/customizations/notices/<key>.txt`; `03-verify-components.sh` fails while a baseline has no notice.
5. Commit the baseline.

## Gate Details

### `03-verify-components.sh`

Runs before every build with 17 declared units in `scripts/lib/units/03-verify-components.units`, ending in a `RECEIPT` line: shell compatibility, `version.json`, CLI syntax, terminal prerequisites, native helper sources, Lua plugin syntax, Yazi flavor assets, Yazi launch surface, the removed `gh` guard, regression tests, the targeted `xcodebuild` slice, privileged-action surface drift, the non-concurrency allowlist, the weather-removal guard, the curated theme manifest, SwiftUI view-modifier hygiene, and Overlay recurrence gates.
The regression unit runs `tests/35`, `45` and `51` plus the guardrail suites.
`YEN_COMPONENT_XCODE_REGRESSION_MODE=auto` runs the `xcodebuild` slice only when native macOS inputs changed since the latest `[deploy]` release; set `always` to force it or `off` to skip it.

### `05-detect-failures.sh`

Post-build checks in seven categories:

1. Artifacts: main binary architecture and macOS floor, arm64-only bundled binaries, plist keys, bundled CLI, DMG and checksum, signed metadata, shell integration; DMG URL and SHA-256 parity, `hdiutil verify`, `spctl` and `stapler validate`.
   The built binary must resolve `copy-on-select = true` to `both`, and the bundle must hold every tracked license notice unchanged.
2. Security: hardened runtime, timestamps, Sparkle and app signatures, `codesign --verify --strict` on every required `Resources/bin` binary, and the audio-input entitlement.
3. Critical files present and non-empty.
4. Consistency: download links and well-formed appcast XML.
5. Artifact credential and URL scan (`YEN_ARTIFACT_URL_SCAN_GATE_MODE`, default `enforce`; allowlist `YEN_ARTIFACT_URL_ALLOWLIST_FILE`).
6. Artifact fingerprint scan (`YEN_FINGERPRINT_GATE_MODE`, default `enforce`), which force-scans the bundled shell CLI at `Contents/Resources/bin/yen` even though it is not Mach-O; local ad-hoc scans may pass `--skip-codesig`.
7. Git state, informational only.

It also runs the DMG layout gate (`YEN_DMG_LAYOUT_GATE_MODE`, default `enforce`); any non-`enforce` mode needs `YEN_ALLOW_GATE_DOWNGRADE=1`.

## Other Scripts

| Script                                                                                     | Purpose                                                                                                                                                                                                                                 |
| ------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `native/01-macos-smoke.sh`                                                                 | Native build and test loops (`_docs/05-infrastructure.md` → Local Build Loops)                                                                                                                                                          |
| `native/source-fixtures.py`                                                                | Byte-verified native source-test inputs outside protected folders (`_docs/09-quality.md`)                                                                                                                                               |
| `native/02-dictation-live-matrix.sh`                                                       | Dictation live matrix capture and report (`_docs/09-quality.md`)                                                                                                                                                                        |
| `30-eval-svgthumb.sh`, `31-soak-svgthumb.sh`                                               | Self-validating eval and fail-closed soak for the SVG helper                                                                                                                                                                            |
| `36-eval-pdfthumb.sh`, `37-soak-pdfthumb.sh`, `38-eval-vidthumb.sh`, `39-soak-vidthumb.sh` | Self-validating evals and fail-closed soaks for the PDF and video helpers                                                                                                                                                               |
| `44-build-web-csp.ts`                                                                      | Web build with converged CSP hashes (`bun run build`)                                                                                                                                                                                   |
| `46-scan-bundle-leaks.ts`                                                                  | Last step of `bun run build`: byte-scans browser artifacts for every server credential value in raw, JSON, RSC, JS-escape, HTML-entity, URI and base64 forms; reports names and paths only; fails on zero credentials or zero artifacts |
| `run-pinned-bun.cjs`                                                                       | Vercel install and build entry point in `vercel.json`: bootstraps the `packageManager` Bun and verifies it                                                                                                                              |
| `setup-hooks.ts`                                                                           | `prepare` step of `bun install`: points `core.hooksPath` at `.githooks` (`tests/156-commit-msg-hook.test.ts`)                                                                                                                           |
| `theme-contrast.js`                                                                        | Theme contrast math for `bundle-yen-resources.sh` and `tests/76-theme-contrast-gates.test.ts`                                                                                                                                         |

Manual utilities, outside the release and vendor gates:

| Script                                                                         | Purpose                                                          |
| ------------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| `manual/08-check-notification-names.sh`                                        | Notification names stay in sync across Swift and the build hook  |
| `manual/11-verify-sparkle-signing.sh`                                          | Sparkle signing and key consistency against the DMG and appcast  |
| `manual/12-check-recent-crashes.sh --days 3`                                   | Blocks shipping on recent `yen` or installed-`zmx` crash reports |
| `manual/14-verify-dmg-layout.sh [--skip-finder-check]`                         | DMG structure, backgrounds and Finder geometry                   |
| `manual/15-verify-applescript.sh`, `manual/16-verify-applescript-if-needed.sh` | AppleScript and workspace verifier, and its stamp-driven wrapper |
| `manual/17-verify-sparkle-delta-dryrun.sh`                                     | Delta generation against the live DMGs, with no writes           |
| `manual/18-make-verify-copy.sh`                                                | Signed `YENVerify.app` copy of the local build at a fixed path   |
| `manual/26-sync-theme-catalog.sh`                                              | Regenerates the catalog in `_docs/02-design-system.md`           |
| `manual/27-run-settings-memory-benchmark.sh`                                   | Settings memory benchmark, retain versus release                 |
| `manual/28-run-file-browser-preview-benchmark.sh`                              | File-browser preview benchmark                                   |
| `manual/29-run-settings-hitch-benchmark.sh`                                    | Settings hitch benchmark (`_docs/13-desktop-features.md`)        |
| `manual/30-check-outline-corners.py`                                           | Check both lower outline arcs in a shadowless window capture     |
| `manual/31-check-pane-top.py`                                                  | Compare the top outline in single-pane and split-pane captures   |
| `manual/32-check-pane-clearance.py`                                            | Check terminal grid corners against a thick pane outline         |
| `manual/33-check-native-launch-defaults.py`                                    | Verify app defaults, config reload, and child arguments on macOS |
| `manual/34-measure-key-latency.swift`                                          | Key-to-frame latency of a running copy (`_docs/09-quality.md`)   |
| `manual/35-verify-remote-attach-loopback.sh`                                   | Remote attach against a loopback sshd (`_docs/09-quality.md`)    |
| `manual/36-check-zmx-shutdown.sh [--runs N]`                                   | zmx daemons exit cleanly at session end (`_docs/09-quality.md`)  |

## Shared Library (`scripts/lib/`)

`overlay-phases/`, `build-release-phases/`, `bundle-resource-phases/`, and `finalize-build-phases/` hold the ordered pipeline steps.
Their orchestrators and shared-state contracts are described in `_docs/05-infrastructure.md`.

| File                                                                                                                                                | Role                                                                                                                                 |
| --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `vendor-manifest.sh`, `vendor-binary.sh`, `required-app-bins.sh`                                                                                    | Vendor roster, download and build helpers, required `Resources/bin` list                                                             |
| `upstream.sh`                                                                                                                                       | Every Ghostty upstream URL and the forge adapter                                                                                     |
| `ghostty-paths.sh`                                                                                                                                  | Upstream paths the branding gate depends on                                                                                          |
| `sparkle-runtime-floor.sh`                                                                                                                          | `SPARKLE_RUNTIME_FLOOR` and its assertion                                                                                            |
| `zig-sdk-workaround.sh`                                                                                                                             | Probe-gated synthetic sysroot for Zig on Xcode 26.4+                                                                                 |
| `zig-toolchain.sh`                                                                                                                                  | The one `zig version` versus `.minimum_zig_version` comparison, shared by `14-vendor.sh` and `validate-environment.sh`               |
| `release-vendor-window.sh`                                                                                                                          | `/update-yen` Step 1 rule that accepts a Ghostty `behind` for a recent, published `vendor:` baseline                                 |
| `gate-receipt.sh`, `gate-roster.txt`, `units/`                                                                                                      | Gate receipt contract                                                                                                                |
| `copy-on-select-compat.sh`                                                                                                                          | Asks a built binary what `copy-on-select = true` resolves to, in a temporary home                                                    |
| `third-party-notices.sh`                                                                                                                            | Requires a license notice per vendor baseline, and each notice in the built app                                                      |
| `patch-file.py`, `patches/`                                                                                                                         | Fail-closed source patches for `apply-overlays.sh`                                                                                   |
| `apple-script-action-policy.py`, `native-fullscreen-helper.py`, `remove-wrapper-sendable.py`, `rewrite-pbxproj-membership-exclusions.py`            | `apply-overlays.sh` patchers: AppleScript action policy, fullscreen transition state, wrapper `Sendable` removal, pbxproj membership |
| `xcode-policy.sh`                                                                                                                                   | Stable-Xcode release gate by install path and version line                                                                           |
| `workflow-lock.sh`                                                                                                                                  | The shared vendor, build-release and finalize-build lock described below                                                             |
| `non-concurrency-utils.sh`, `privileged-surface-utils.sh`                                                                                           | Warning-allowlist metadata validation and the privileged-action surface diff for the component gates                                 |
| `verify-signed-file.sh`, `zip-notify.sh`                                                                                                            | Signature check on a release file; `/update-yen` milestone notifications                                                             |
| `web-build-id.ts`                                                                                                                                   | Content-derived Next build ID for `next.config.ts`                                                                                   |
| `version-utils.sh`                                                                                                                                  | The only source of derived version values                                                                                            |
| `signing-constants.sh`, `signature-utils.sh`, `release-constants.sh`, `mount-utils.sh`                                                              | Signing identity, Ed25519 and arm64-only checks, release URLs, stale DMG mounts                                                      |
| `json-utils.py`, `python-utils.sh`, `yen-cli-resolve.sh`, `build-thumb.sh`                                                                          | JSON edits, Python discovery, `yen` CLI resolution, thumbnail helper builds                                                          |
| `fingerprint-allowlist.txt`, `artifact-url-domain-allowlist.txt`, `non-concurrency-warning-allowlist.txt`, `privileged-action-surface-baseline.txt` | Gate allowlists and baselines                                                                                                        |

`build-release.sh`, `finalize-build.sh` and `14-vendor.sh` share `$TMPDIR/yen-workflow-<cksum>.lock` plus per-script locks; remove a lock only when it is stale and no workflow PID is alive.

## Web performance budgets

`bun run check:perf-budget` checks `perf-budget.json` after CSP compilation and before the final browser-secret scan.
It compares uncompressed first-load JavaScript bytes and manifest rendering classes, failing closed on missing or malformed inputs.
Fallback routes without generated examples use `on-demand`; their regeneration interval is not present in the manifest.
Review intended changes before running `bun scripts/perf-budget.ts --baseline` after a clean build.
The canonical logic lives in 8leeai's `scripts/perf-budget.ts`.
The build script remains allowed through `.vercelignore`.

Nested `bun` commands resolve through a temporary alias to the verified executable, including pinned downloads named `bun.exe`.
