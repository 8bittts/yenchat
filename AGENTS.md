# YEN Project Rules

Global operator rules apply before this file.
This file contains only YEN-specific constraints.

## Maintenance Mode

YEN is in maintenance mode; `_docs/00-foundation.md` → Decisions owns the decision.

- In scope: vendor updates and desktop releases through `/yen-zip`, dependency updates through `/update-projs`, and fixes for bugs, crashes, security issues and broken builds.
- Out of scope unless the operator asks: new features, redesigns, refactors, performance work, and growth or SEO work.
- `_docs/todos.md` holds only in-scope work; record an out-of-scope finding in the final report, not the backlog.
- Maintenance mode covers the desktop app and the yen.chat website.

## Product Boundaries

- YEN is open source under the MIT License; `LICENSE` also carries Ghostty's MIT notice, which must stay because the overlays carry Ghostty-derived code.
- The desktop app requires no YEN account and sends no terminal content or desktop usage telemetry to YEN.
- YEN does not operate a speech-recognition service.
- Dictation normally uses Apple's on-device `SpeechAnalyzer` on macOS 26 or newer.
- Older systems and runtime fallback use Apple's legacy recognizer, which can use Apple's service when on-device recognition is unavailable.
- `/download` redirects to the current DMG and records nothing; the site measures only through Vercel Web Analytics ([_docs/08-growth.md](_docs/08-growth.md)).

## Public Repository

- This repository is public. Never commit personal identity, home-directory paths, customer data, company records, or credentials; use `$HOME` or a repo-relative path in docs and scripts, and `/Users/dev/...` in test fixtures.
- The pre-open-source history is private and never pushed here; the local `pre-push` hook (`scripts/setup-hooks.ts`) rejects a push containing its root commit.
- Run `gitleaks git --no-banner` before pushing a change that touches scripts, config, or fixtures.

## Documentation

- `_docs/00-docs-map.md` indexes the owner docs under the fleet documentation standard and their audit rules; read the owner doc before non-trivial work in its domain.
- `_docs/todos.md` is the only backlog; no TODOs live anywhere else.
- State each constraint once, in its owner doc, and cite it elsewhere.
- Reference docs carry no history: no changelogs, dated receipts or review notes. Git history and commit messages hold them, and `/release` is the customer-facing history.
- Update public `/docs`, `public/llms.txt`, and the owning internal document when a public feature contract changes.
- Update privacy and terms when a service, data flow, license, or provider changes.

For design or redesign work, read `_docs/02-design-system.md` first for the public design system.
Then read the affected surface owner from `_docs/00-docs-map.md`, with `_docs/02-design-system.md` owning theme behavior and `_docs/13-desktop-features.md` owning desktop interaction surfaces.

## Architecture

- Treat `yen-terminal/ghostty/` as a generated upstream mirror.
- Put YEN changes in `yen-terminal/overlays/`, `yen-terminal/customizations/`, or the patch pipeline.
- Keep the bundled shell CLI at `Contents/Resources/bin/yen` in the release fingerprint scan.
- Prefer native macOS frameworks before adding a bundled binary.
- Keep browser preview state isolated and non-persistent.

## Web

- Use the tokens and shared utilities in `app/globals.css`.
- Reuse `PageShell`, `DocPageShell`, `DocSection`, shared header, and shared footer.
- Every indexable page needs a canonical URL, contextual Open Graph metadata, contextual Twitter metadata, and `index,follow` robots directives.
- Keep `/library` noindex and outside public discovery.
- Regenerate release notes with `bun scripts/gen-release-notes.ts` after editing release copy or version history.
- Run `bun run seo:source-check` after changing public comparison claims.
- Verify public pages at desktop and mobile widths in a real browser.

## Required Gates

Run these gates before commit:

```bash
bun run check
bun run build
bun test
bun run test:policy
bun run test:prod
bunx react-doctor@latest . --verbose --scope changed --base main
```

`bun run check:full` chains `check`, `build` and `test:all` (`bun test`, `test:policy`, `test:prod`); react-doctor stays a separate step.
`lint`, `lint:fix` and the other script names carry the fleet meanings in `8leeai/_docs/13-starter-kit.md` → Script vocabulary.
`.githooks/commit-msg` refuses AI attribution; `bun install` wires it through `prepare` (`scripts/setup-hooks.ts`), and `tests/156-commit-msg-hook.test.ts` proves it.
Verify a native UI finding or fix in a running re-identified `zig-out` copy before reporting it; a code read, a unit test or an offscreen render is not evidence that a control renders or responds ([_docs/09-quality.md](_docs/09-quality.md) → Native Test Suite).
The vendored `Config.zig` and bundled `jq` must exist before the full test suite.
Do not acknowledge a missing vendor tree as a successful verification run.
A `/yen-zip` vendor-phase Zig toolchain preflight failure means Ghostty raised `.minimum_zig_version`; install the required toolchain instead of setting `YEN_VENDOR_SKIP_TOOLCHAIN_PREFLIGHT=1`.

## Infisical

This project's Infisical id is `af507451-0829-4a0f-9362-91209db7f241` (slug `yenchat`); log in with `infisical login` (US cloud).
Infisical is for maintainers only: the website reads no secrets, so contributors need none.
Run `bun run dev:secrets` for local development; it injects Infisical `dev`, and plain `bun run dev` still reads a gitignored `.env.local`.
Production secrets live in Infisical `prod` at `/`, and the `vercel-prod-yenchat` sync copies every change to Vercel production as a Sensitive variable; redeploy production to load it.
[`8leeai/_global/infisical.md`](https://github.com/8bittts/8leeai/blob/main/_global/infisical.md) owns the fleet rules: editing a synced key, retiring one, preview and development variables, and shared keys.

## Release

- `public/stable/version.json` is the public release source.
- `app/release/release-notes-copy.ts` owns customer-facing release prose.
- `app/release/release-notes-data.ts` is generated and must not be edited directly.
- Vercel builds only a commit whose subject carries `[deploy]` (`8leeai/_docs/13-starter-kit.md` → Web stack); `vercel.json`'s `ignoreCommand` matches the subject line only (`head -1`).
- Every desktop release is a GitHub Release tagged `v<version>` on `8bittts/yenchat`; `scripts/01-verify-release-target.sh` fails before a build when the repository is not public or the `gh` session cannot push ([_docs/05-infrastructure.md](_docs/05-infrastructure.md) § Release Hosting).
- `.vercelignore` excludes `scripts/*` behind an allowlist, and `tests/135-static-csp-prerender.test.ts` fails when a script the install or build runs is missing from it (`8leeai/_docs/13-starter-kit.md` → Files to copy).
- Verify the production Vercel target by the pushed commit SHA and `READY` state.
- Verify representative live routes after promotion.
