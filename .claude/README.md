# YEN Slash Commands

| Command | Source | Purpose |
|---------|--------|---------|
| `/update-yen` | `.agents/skills/update-yen/` | Update every vendored dependency, then build, sign, notarize and ship the desktop app |
| `/docs` | `.claude/commands/docs.md` → global `docs` skill | Documentation audit; YEN scope lives in `_docs/00-docs-map.md` |

`/update-yen` is a global command (`~/.claude/commands/update-yen.md`) that points at the repo skill so it runs from any directory; Codex reaches the same skill through the `~/.codex/skills/update-yen` symlink.
The retired `/yen-vendor` is its vendor phase and has no command, link or backup left.
`/update-yen` deliberately has no `~/.claude/skills/` link, which would list them twice in this repo's picker.
Shared global commands (`/ship`, `/check`, `/fix`, `/vercel`, ...) and their backups are owned by the operator's global configuration in `8leeai/_global/`; `/vercel` audits and never deploys.

To reset YEN app data, run `yen-terminal/customizations/clear-app-cache.sh` (`--fresh` for a first-launch state); its header lists every category it clears and how `config.yen` is backed up.
