# Foundation

History and decisions for YEN; every other doc describes the code as it is.

## Timeline

Dates are the evidence in this doc; the owner docs carry none.

- 2025-11-06: the initial commit of the desktop terminal, built on a vendored Ghostty mirror with YEN overlays.
- 2025-11-10: the Ghostty update checklist becomes the canonical reference for upstream syncs, with a mandatory exception review step.
- 2025-11-25: the first end-to-end rebrand cycle completes and YEN v0.1.0 is the first official release.
- 2025-11-28: the baseline-plus-diff vendoring strategy ships, so upstream changes are applied as patches over the mirror.
- 2025-12: v0.3.x releases land, the Sparkle updater is paused behind a welcome banner, and the `/release` notes adopt one entry per week.
- 2026-10-18: the macOS 27 SDK cutover closes with v1.228, following AppKit's default menu-image visibility.
- 2026-10-22: the custom analytics events move from Title Case (`Download Click`) to snake_case (`download_click`) ([09-quality.md](09-quality.md)).
- 2026-11-16: YEN enters maintenance mode, and `/yen-vendor` is folded into `/yen-zip` as its vendor phase, so one command updates vendors and ships.
  Superlogical, the company Ghostty's creator started in July 2026, began public testing of its Rex terminal on 2026-10-05; it is free, funded, and built on the same engine.
- 2026-11-17: the source goes public under the MIT license as a fresh repository with a new root commit, because the old history held company records and operator-private files.
- 2026-11-18: the yen.chat `/release` page is retired; its weekly release notes move to blog.yen.chat/releases, and the blog index lists them beside the creator's posts.
  The same change moves release downloads from Supabase Storage to GitHub Releases and removes the download database, the owner daily report, and the `yen-tunes/` music pipeline.
  The Supabase project, its `auth.yen.chat` DNS record, and every web environment variable in Infisical and Vercel were deleted the same day.
- 2026-11-19: the operator lifts maintenance mode for one feature, always-on sessions: panes that outlive the app and attach from another Mac over Tailscale, plus the window-chrome and split design work around them.
- 2026-11-21: `/yen-zip` becomes `/update-yen`, which adds a deps phase (Bun packages and Sparkle) ahead of the vendor phase and the release cut; `/update-projs` stops covering yenchat, so one command owns every YEN update.

- 2026-11-21: the operator approves an opt-in local token menu and built-in MovingPaper controls on supported Macs.

## Decisions

- **Maintenance mode.** YEN gets vendor updates, dependency updates, desktop releases, and fixes for bugs, crashes, security issues and broken builds.
  New features, redesigns, refactors, performance work, and growth or SEO work wait for an explicit operator request, because a solo project cannot compete with a funded team on the same engine (Timeline, 2026-11-16).
  `AGENTS.md` → Maintenance Mode carries the rule; `_docs/todos.md` holds only work inside it.
- **Approved feature work.** Persistent panes with Tailscale remote attach are the feature the operator judged missing to make YEN their default terminal, so it and its design pass are in scope (Timeline, 2026-11-19); the plan lives in `_docs/todos.md`.
  The local token menu and experimental desktop wallpaper also have explicit operator approval.
- **zmx is the session backend.** zmx (MIT, Zig 0.17, built on libghostty-vt) owns each pane's PTY in its own process group, so a pane survives the app quitting and replays its screen and scrollback on reattach.
  A spike proved it in a re-identified copy of the shipping app: a pane whose `command` was `zmx attach` kept its counter running through an AppleScript quit and showed the whole history after relaunch.
  No macOS framework keeps a PTY and its screen state alive after the app exits, so the native-first rule allows this bundled binary.
  Rejected: a YEN-owned daemon, which would rebuild zmx on the same library; shpool, which is Linux-first with a single client per session; abduco and dtach, which replay no screen state; and tmux control mode, which needs a tmux install and whose upstream viewer has no macOS interface.
- **YEN is open source under MIT.** The repository starts from a fresh root commit; the pre-open-source history is private and never pushed to the public repository (`AGENTS.md` → Public Repository).
  Ghostty's MIT notice stays in `LICENSE` because the overlays carry Ghostty-derived code.
- **No account, no telemetry.** The desktop app requires no YEN account and sends no terminal content or usage telemetry; dictation runs on-device through Apple's `SpeechAnalyzer` when available ([11-speech-to-text.md](11-speech-to-text.md)).
- **Ghostty is a generated upstream mirror.** YEN changes live in overlays, customizations and the patch pipeline, never in the mirror ([01-architecture.md](01-architecture.md), [04-security.md](04-security.md)).
- **Native frameworks before bundled binaries.** Every bundled binary is pinned, inventoried and verified by the vendor audit ([04-security.md](04-security.md)).
- **Deploy by subject marker.** Vercel builds only `[deploy]` in the commit subject; a marker written in a commit body once launched an unintended build ([05-infrastructure.md](05-infrastructure.md)).
- **Releases live on GitHub Releases.** Each version is a release tagged `v<version>` on the public repository, holding the DMG, its checksum and the Sparkle deltas ([05-infrastructure.md](05-infrastructure.md)).
- **The release cost model is settled.** Reusing a prior build for the shipping artifact, caching the SDK probe, and skipping `/update-yen` Step 4's native slice after the vendor phase's VB-05 were each rejected as determinism hazards ([05-infrastructure.md](05-infrastructure.md)).
- **Gate receipts account for every unit.** The unit contract replaced per-incident skip markers ([04-security.md](04-security.md)).
- **Native UI findings are verified in a running build.** The shortcut list once stayed one update behind in the running app, which no test showed because the suites exercised the derived-state model and never the view path that fed it ([09-quality.md](09-quality.md)).
- **No download tracking.** The download database and the owner report were removed when the source went public; the site keeps Vercel Web Analytics only ([08-growth.md](08-growth.md)).
- **Tests never hold a live credential.** A Monday test run once sent a real owner email and burned that day's idempotency key, so `tests/01-preload.ts` strips credential-shaped variables ([09-quality.md](09-quality.md)).
- **Dictation microphone options are seeded eagerly.** Two releases shipped the Microphone row with no reachable UI while it waited on its own `.onAppear` ([11-speech-to-text.md](11-speech-to-text.md)).

## Records

- `_design/`: logo masters, vectors and the Open Graph screenshot set.
