# YEN Project Rules

Global operator rules apply before this file.
This file contains only YEN-specific constraints.

## Maintenance Mode

YEN is in maintenance mode; `_docs/00-foundation.md` → Decisions owns the decision.

- In scope: dependency updates, vendor updates and desktop releases through `/update-yen` (`/update-projs` does not cover this repo), and fixes for bugs, crashes, security issues and broken builds.
- Also in scope: the always-on sessions feature in `_docs/todos.md` (persistent panes, Tailscale remote attach, and its window-chrome and split design pass).
- The opt-in token menu, the built-in experimental moving wallpaper and the window border effects (Spark and Aura) are also operator-approved; see `_docs/13-desktop-features.md`.
- Out of scope unless the operator asks: other new features, redesigns, refactors, performance work, and growth or SEO work.
- `_docs/todos.md` holds only in-scope work; record an out-of-scope finding in the final report, not the backlog.
- Maintenance mode covers the desktop app and the yen.chat website.

## Product Boundaries

- YEN is open source under the MIT License; `LICENSE` also carries Ghostty's MIT notice, which must stay because the overlays carry Ghostty-derived code.
- The desktop app requires no YEN account and sends no terminal content or desktop usage telemetry to YEN.
- Remote sessions run the system `ssh` from the user's Mac to the user's other Macs and nothing else: YEN opens no listener, runs no relay, never relaxes host-key checking, and looks for Macs only while the user has asked for hosts ([_docs/04-security.md](_docs/04-security.md) → Remote Attach Threat Model).
- YEN does not operate a speech-recognition service.
- Dictation normally uses Apple's on-device `SpeechAnalyzer`.
- Runtime fallback uses Apple's legacy recognizer, which can use Apple's service when on-device recognition is unavailable.
- `/download` redirects to the current DMG and records nothing; the site measures only through Vercel Web Analytics ([_docs/08-growth.md](_docs/08-growth.md)).

## Public Repository

- This repository is public. Never commit personal identity, home-directory paths, customer data, company records, or credentials; use `$HOME` or a repo-relative path in docs and scripts, and `/Users/dev/...` in test fixtures.
- The pre-open-source history is private and never pushed here; the local `pre-push` hook (`scripts/setup-hooks.ts`) rejects a push containing its root commit.
- Run `gitleaks git --no-banner` before pushing a change that touches scripts, config, or fixtures.

## Documentation

- `_docs/00-docs-map.md` indexes the owner docs under the fleet documentation standard and their audit rules; read the owner doc before non-trivial work in its domain.
- `_docs/todos.md` is the only backlog; no TODOs live anywhere else.
- State each constraint once, in its owner doc, and cite it elsewhere.
- Reference docs carry no history: no changelogs, dated receipts or review notes. Git history and commit messages hold them, and blog.yen.chat/releases is the customer-facing history.
- Update the public manual at `/#guide`, `public/llms.txt`, and the owning internal document when a public feature contract changes.
- Update privacy and terms when a service, data flow, license, or provider changes.

For design or redesign work, read `_docs/02-design-system.md` first for the public design system.
Then read the affected surface owner from `_docs/00-docs-map.md`, with `_docs/02-design-system.md` owning theme behavior and `_docs/13-desktop-features.md` owning desktop interaction surfaces.

## Architecture

- Treat `yen-terminal/ghostty/` as a generated upstream mirror.
- Put YEN changes in `yen-terminal/overlays/`, `yen-terminal/customizations/`, or the patch pipeline.
- Keep the bundled shell CLI at `Contents/Resources/bin/yen` in the release fingerprint scan.
- Prefer native macOS frameworks before adding a bundled binary.
- Every bundled binary is arm64-only, because YEN requires macOS 27; vendor only what a caller inside YEN fails without ([_docs/04-security.md](_docs/04-security.md) → Bundled Binary Inventory).
- Every vendored component needs its license notice in `yen-terminal/customizations/notices/`; the engine's is `TerminalEngine.txt`, because a bundle path must not carry the upstream name ([_docs/04-security.md](_docs/04-security.md) → Third-Party License Notices).
- Keep browser preview state isolated and non-persistent.

## Web

- Use the tokens and shared utilities in `app/globals.css`.
- Reuse `PageShell`, `DocSection`, shared header, and shared footer.
- Every indexable page needs a canonical URL, contextual Open Graph metadata, contextual Twitter metadata, and `index,follow` robots directives.
- Keep the former `/library` URL redirected and outside public discovery.
- Route blog.yen.chat only in `proxy.ts` (`lib/http/blog-host.ts`); a `next.config.ts` host rewrite would serve the static blog pages a nonce CSP and break hydration ([_docs/10-gtm.md](_docs/10-gtm.md#blog-blogyenchat)).
- Regenerate release notes with `bun scripts/gen-release-notes.ts` after editing release copy or version history.
- Verify public pages at desktop and mobile widths in a real browser.

## Required Gates

Run these gates before commit:

```bash
bun run check
bun run build
bun run test
bun run test:policy
bun run test:prod
bunx react-doctor@latest . --verbose --scope changed --base main
```

`bun run check:full` chains `check`, `build` and `test:all` (`test`, `test:policy`, `test:prod`); react-doctor stays a separate step.
`bun run test` is `bun test --parallel=8`: each test file runs in one of eight worker processes, so a file must not depend on state another file leaves behind.
`lint`, `lint:fix` and the other script names carry the fleet meanings in `8leeai/_docs/13-starter-kit.md` → Script vocabulary.
`.githooks/commit-msg` refuses AI attribution; `bun install` wires it through `prepare` (`scripts/setup-hooks.ts`), and `tests/156-commit-msg-hook.test.ts` proves it.
Verify a native UI finding or fix in a running re-identified `zig-out` copy before reporting it; a code read, a unit test or an offscreen render is not evidence that a control renders or responds ([_docs/09-quality.md](_docs/09-quality.md) → Native Test Suite).
The vendored `Config.zig` and `zmx` must exist before the full test suite.
Do not acknowledge a missing vendor tree as a successful verification run.
A `/update-yen` vendor-phase Zig toolchain preflight failure means Ghostty raised `.minimum_zig_version`; install the required toolchain instead of setting `YEN_VENDOR_SKIP_TOOLCHAIN_PREFLIGHT=1`.

## Infisical

This project's Infisical id is `af507451-0829-4a0f-9362-91209db7f241` (slug `yenchat`); log in with `infisical login` (US cloud).
Infisical is for maintainers only: the website reads no secrets, so contributors need none.
Run `bun run dev:secrets` for local development; it injects Infisical `dev`, and plain `bun run dev` still reads a gitignored `.env.local`.
Infisical `prod` and `dev` hold no web key today; a future key lives in `prod` at `/`, and the `vercel-prod-yenchat` sync copies it to Vercel production as a Sensitive variable; redeploy production to load it.
[`8leeai/_global/infisical.md`](https://github.com/8bittts/8leeai/blob/main/_global/infisical.md) owns the fleet rules: editing a synced key, retiring one, preview and development variables, and shared keys.

## Release

- `public/stable/version.json` is the public release source.
- `lib/release-notes/release-notes-copy.ts` owns customer-facing release prose.
- `lib/release-notes/release-notes-data.ts` is generated and must not be edited directly.
- Vercel builds only a commit whose subject carries `[deploy]` (`8leeai/_docs/13-starter-kit.md` → Web stack); `vercel.json`'s `ignoreCommand` matches the subject line only (`head -1`).
- Every desktop release is a GitHub Release tagged `v<version>` on `8bittts/yenchat`; `scripts/01-verify-release-target.sh` fails before a build when the repository is not public or the `gh` session cannot push ([_docs/05-infrastructure.md](_docs/05-infrastructure.md) § Release Hosting).
- `.vercelignore` excludes `scripts/*` behind an allowlist, and `tests/135-static-csp-prerender.test.ts` fails when a script the install or build runs is missing from it (`8leeai/_docs/13-starter-kit.md` → Files to copy).
- Verify the production Vercel target by the pushed commit SHA and `READY` state.
- Verify representative live routes after promotion.

## Rule enforcement

| Rule | Enforced by |
|------|-------------|
| Never edit `yen-terminal/ghostty/`; change it through overlays or patches | `.gitignore` (the mirror is untracked, so a direct edit cannot be committed) and `scripts/lib/overlay-phases/07-patches.sh` (fail-closed anchors) |
| No AI attribution in commits | `.githooks/commit-msg`, proven by `tests/156-commit-msg-hook.test.ts` |
| Never push the pre-open-source history | `pre-push` hook from `scripts/setup-hooks.ts`, proven by `tests/157-pre-push-hook.test.ts` |
| Vercel builds only a `[deploy]` subject | `vercel.json` `ignoreCommand` |
| `.vercelignore` keeps every script the build runs | `tests/135-static-csp-prerender.test.ts` |
| Releases go only to the public repository | `scripts/01-verify-release-target.sh` |
| The vendored engine tree must exist before the full suite | `tests/45-overlay-patching.test.ts` and `tests/119-vendor-process-guardrails.test.ts` (fail unless `YEN_ALLOW_MISSING_VENDOR_TREE=1`) |
| Indexable pages carry canonical and social metadata | `tests/121-seo-guardrails.test.ts` |
| `/library` redirects and stays outside discovery | `tests/121-seo-guardrails.test.ts` |
| Route blog.yen.chat only in `proxy.ts` | `tests/159-blog-host-routing.test.ts` |
| Do not edit `lib/release-notes/release-notes-data.ts` by hand | none (prose) |
| Run `gitleaks` before pushing scripts, config or fixtures | none (prose) |
| No personal identity or home paths in the public repository | none (prose) |
| Verify native UI in a running copy before reporting it | none (prose) |
| Keep work and backlog entries within the approved maintenance scope | none (prose) |
| Preserve the MIT notices and the desktop account, privacy and dictation boundaries | none (prose) |
| Remote sessions use only the system `ssh`, with fixed options and no relaxed host-key check, and discover Macs only on request | `tests/176-cli-sessions-remote-contract.test.ts` (ssh options), `RemoteHostsPaletteContractTests` and `TabSidebarHostsSectionTests` (discovery), `tests/154-documentation-contracts.policy.ts` (public statements) |
| Serve the current GitHub DMG from the download route | `tests/10-production.prod.ts` |
| Keep owner documents current, use one backlog, and align public documentation and legal copy | `tests/154-documentation-contracts.policy.ts` covers named public contracts. Other changes require manual review. |
| Ship a license notice for the engine and each vendored tool | `scripts/lib/third-party-notices.sh` in `scripts/03-verify-components.sh` and `scripts/05-detect-failures.sh`, proven by `tests/171-third-party-notices.test.ts` |
| Bundled binaries are arm64-only | `assert_arm64_only_binary` in `scripts/05-detect-failures.sh`, `scripts/12-verify-vendor-audit.sh` and `scripts/lib/vendor-binary.sh`, proven by `tests/123-release-script-hardening.test.ts` and `tests/162-vendor-build-input-id.test.ts` |
| Scan the bundled shell CLI before release | `scripts/13-scan-artifact-fingerprints.sh`, proven by `tests/46-artifact-fingerprint-gate.test.ts` |
| Isolate browser preview state | `yen-terminal/overlays/macos/Tests/Browser/WebPreviewRepresentableTests.swift` |
| Use the shared web design system and verify layouts at desktop and mobile widths | `tests/55-web-ui-dom.test.tsx` checks shared shell behavior. Visual verification requires a browser. |
| Regenerate public release notes when they change | `scripts/gen-release-notes.ts` generates the public data. Invocation is manual. |
| Run the declared gates before commit with the vendored zmx and the required Zig toolchain | `package.json` defines the lanes and `scripts/lib/zig-toolchain.sh` checks the compiler. Precommit invocation is manual. |
| Verify the serving commit and run live checks after promotion | `tests/10-production.prod.ts` checks live routes. The ship workflow verifies the serving commit. |
