# YEN Documentation Map

Open-source (MIT) macOS terminal, in maintenance mode ([00-foundation.md](00-foundation.md) → Decisions), built on a vendored Ghostty mirror with YEN overlays, a native browser, a file browser, on-device dictation, and the public website at `yen.chat` with its [public manual](https://yen.chat/#guide).
Agent routing lives in `AGENTS.md`; this index follows the fleet documentation standard that `/docs` audits against.

## Owner docs

| Doc                          | Owns                                                                                                                    |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `00-docs-map.md`             | Document inventory, ownership, authority order, and audit rules |
| `00-foundation.md`           | History, decisions, and the index of design assets                                                                      |
| `01-architecture.md`         | Component boundaries, persistent sessions, remote attach, and native input                                  |
| `02-design-system.md`        | Themes and the generated catalog, the public web design system, Phosphor typography                                     |
| `04-security.md`             | Upstream overlap, fail-closed vendor gate contracts, the bundled binary inventory, the remote attach threat model        |
| `05-infrastructure.md`       | Desktop toolchain, build guardrails, signing, DMG, release hosting, Sparkle, versioning, web release practice, media retention, environment variables |
| `07-email.md`                | The support mailbox and mail authentication                                                                             |
| `08-growth.md`               | Measurement limits, public discovery                                                                          |
| `09-quality.md`              | Gates, the native test suite, remote session checks, web quality baselines, and the dictation manual matrix                                   |
| `10-gtm.md`                  | Public accuracy and legal copy, blog.yen.chat and its release notes, content voice                                      |
| `11-speech-to-text.md`       | Dictation                                                                                                               |
| `12-commands.md`             | `yen` CLI, shell integration, shortcuts, palette actions, automation, `yen ide` contract                                |
| `13-desktop-features.md`     | Native desktop features: window rules, Settings, sounds and notifications, workspace panels, terminal behavior          |
| `14-file-browser.md`         | Yazi file browser                                                                                                       |
| `15-browser.md`              | Native WebKit browser                                                                                                   |
| `todos.md`                   | The only backlog; active work only                                                                                      |

## Not applicable

- `03-data.md`: YEN has no hosted database.
  The disposable local token index belongs to `01-architecture.md` and the theme catalog belongs to `02-design-system.md`.
- `06-payments.md`: the app is free and sells nothing.

## Other surfaces

| Path                                                                  | Notes                                                                                            |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `AGENTS.md`                                                           | Enforceable project rules, loaded by Claude Code and Codex                                      |
| `README.md`                                                           | Repository overview; points here                                                                 |
| `LICENSE`, `CONTRIBUTING.md`                                          | MIT License with Ghostty's notice, and the contributor guide                                     |
| `scripts/00-scripts-readme.md`, `tests/00-tests-readme.md`, `yen-cli/00-core-readme.md` | Script catalog, test lanes, CLI internals                                     |
| `.agents/skills/update-yen/`, `.claude/commands/`                        | Procedures; they cite owner docs and never restate them                                         |
| `.claude/README.md`                                                   | Slash-command index                                                                              |
| `public/README.md`, `public/skills.md`                                | Note on the deployed `public/` tree, and a served article                                        |
| `yen-pdfthumb/`, `yen-svgthumb/`, `yen-vidthumb/` (`README.md` each)  | Native thumbnail helpers for the file browser                                                    |
| `yen-terminal/customizations/dmg-resources/README.md`                 | DMG background art; the layout rules are in `05-infrastructure.md`                               |
| `yen-terminal/archive/gui-settings-2025-12/README.md`                 | Archived GUI Settings code; not documentation                                                    |
| `_docs/_design/`                                                      | Design assets, indexed by `00-foundation.md`; not documentation                                  |
| `content/blog/`                                                       | The published blog.yen.chat posts and proxy slug index ([10-gtm.md](10-gtm.md#blog-blogyenchat)) |
| `8leeai/_global/` (separate repo)                                     | Operator configuration backups; its `README.md` owns the mappings                                |

## Authority order

Code, scripts and tests, then the owner doc, then `AGENTS.md`, then `README.md`.

### Audit rules

Checked by `/docs`:

- Each constraint lives once, in its owner; everywhere else cites it.
- Reference docs carry no history: no dated receipts, review labels, changelogs or "previously" narration; `00-foundation.md` is the one place dates are evidence.
- Boundaries: `10` holds no implementation detail, `01` no release checklist, `05` no marketing, `08` no desktop build steps, and the environment section of `05` no secret values.
- Counts are recomputed from source, never copied: themes (curated manifest), bundled binaries (`scripts/lib/required-app-bins.sh`), gate units (`scripts/lib/units/`), overlay pairs (`yen-terminal/.overlay-upstream-pairs.txt`).
- Machine-maintained sections: the `04` snapshot block and overlap sentence (`11-sync-vendor-audit.sh`, `12-verify-vendor-audit.sh`) and the `02` theme catalog.
- Tests pin some doc text; change a pinned string and its test in the same commit.

Sync rules:

- A command or shortcut change updates `12`, `KeybindRegistry`, `app/docs/docs-client.tsx` and `public/llms.txt`.
- A service, data-flow or provider change updates `08`, the environment section of `05`, and the combined `/terms` page (privacy lives there; `/privacy` redirects).

Audit the homepage and its manual, Terms, the blog, discovery files, and redirects for retired pages against the SEO baseline in `09`.

## Known doc drift

None.
