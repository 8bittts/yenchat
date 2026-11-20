# Vendor Commit (Step V5)

Commit only after Step V4 passed: the compile gate, the project gates, and the eval checks. Never commit a vendor bump that did not build.

## Stage Explicitly

Stage what changed, by name. Baselines are the run's output; overlays, the pair manifest, and any repair edits are its source of truth and must land in the same commit, or a later `git checkout --` silently reverts the port.

```bash
git -C $HOME/Documents/yenchat status --porcelain
git -C $HOME/Documents/yenchat add -- ':(glob)yen-terminal/.*-baseline' yen-terminal/VENDOR_INFO.txt yen-terminal/.overlay-upstream-pairs.txt yen-terminal/overlays _docs/04-security.md
# plus every file a repair touched (apply-overlays.sh, scripts/lib/patches/, tests/, docs)
git -C $HOME/Documents/yenchat diff --cached --name-status
```

Confirm no sensitive files are staged (`.env*`, keys, credentials) and that `git status --porcelain` shows nothing left behind.
Step V4's `bun run build` gate often rewrites `lib/csp/generated-inline-script-hashes.ts`; a vendor bump ships no web change, so restore it with `git -C $HOME/Documents/yenchat checkout -- lib/csp/generated-inline-script-hashes.ts` before VK-02 ([01-gtm](../../../../_docs/10-gtm.md) § Web Quality Baselines, CSP).

## Commit and Push

Subject: `vendor: update <vendor-list> to <versions>` — for example `vendor: update ghostty to e8aa0986` or `vendor: update ghostty, yazi, fd to latest`. Body bullets name the upstream range, any overlay repair, and the gates that ran with their positive results. No AI attribution. Never put `[deploy]` in the subject; a vendor bump is native-only.

```bash
git -C $HOME/Documents/yenchat commit -F <message-file>
git -C $HOME/Documents/yenchat fetch -q origin && git -C $HOME/Documents/yenchat merge-base --is-ancestor origin/main HEAD
git -C $HOME/Documents/yenchat push origin main
```

On Claude Code the push to `main` needs `dangerouslyDisableSandbox: true` on that one Bash call (per-call override only); on Codex under `--yolo` it needs nothing. Verify with `git ls-remote origin refs/heads/main` equal to `git rev-parse HEAD`, in a separate Bash call: the push guard hook refuses any line that carries a ` -f` argument after the push, and `cut -f1` on the same call trips it.

## Vendor Summary

Keep a summary for the final `/yen-zip` report. All 14 vendors get a row every run — a vendor missing from the table reads as "not checked". Read the real values from `yen-terminal/.*-baseline`; the versions below are illustrative.

```
## Vendor Summary

| Vendor | Status | From | To |
|--------|--------|------|----|
| Ghostty | Updated | 8af6897c | e8aa0986 (4 commits) |
| Yazi | Current | v26.8.15 | — |
| fd | Current | v10.5.0 | — |
| ripgrep | Current | 15.2.0 | — |
| fzf | Current | v0.74.3 | — |
| zoxide | Current | v0.10.0 | — |
| bat | Current | v0.26.1 | — |
| jq | Current | jq-1.8.2 | — |
| lazygit | Current | v0.64.1 | — |
| delta | Current | 0.19.2 | — |
| resvg | Current | v0.48.1 | — |
| btop | Current | v1.4.7 | — |
| fastfetch | Current | 2.67.1 | — |
| zmx | Current | v1.0.1 | — |
```

For Ghostty, also state: commits ahead; whether overlays applied cleanly and what was repaired or retired; the compile gate used and its result; every `RECEIPT gate=... result=PASS` line with its unit counts (a result is read from a positive field, never from a missing string); whether `manual/16-verify-applescript-if-needed.sh` ran; new Xcode targets or embedded bundles.

## Upstream Changelog

Then report every upstream change in the range, per commit for Ghostty (`https://api.github.com/repos/ghostty-org/ghostty/compare/<old>...<new>`) and per release for binary vendors (GitHub release notes): a table with Commit/Version, Summary, and Impact on YEN (NONE / LOW / MEDIUM / HIGH with one clause), followed by counts of fixes, features, and refactors and a list of anything touching an overlay anchor or customization.

## Eval Summary

After the commit checks, run `bash $HOME/Documents/yenchat/.agents/skills/yen-zip/scripts/eval-phase.sh summary yen-vendor` and quote its `Result: PASS` line before the release starts at Step 0.

## Eval Checks

| Check ID | Description | Command |
|----------|-------------|---------|
| VK-01 | No untracked baselines | `[ "$(git -C $HOME/Documents/yenchat ls-files --others --exclude-standard -- 'yen-terminal/.*-baseline' \| wc -l \| tr -d ' ')" -eq 0 ]` |
| VK-02 | Tracked tree clean | `[ "$(git -C $HOME/Documents/yenchat status --porcelain \| /usr/bin/grep -v '^??' \| wc -l \| tr -d ' ')" -eq 0 ]` |
| VK-03 | Pushed | `[ "$(git -C $HOME/Documents/yenchat ls-remote origin refs/heads/main \| cut -f1)" = "$(git -C $HOME/Documents/yenchat rev-parse HEAD)" ]` |
