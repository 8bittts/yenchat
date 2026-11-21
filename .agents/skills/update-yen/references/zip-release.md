# Release Phase (Steps 8-12)

## Step 8: Commit

### 8a. Review Staged Changes
```bash
git -C $HOME/Documents/yenchat diff --cached --stat
git -C $HOME/Documents/yenchat diff --cached
```

Verify only release artifacts are staged. Never `git add .` or `git add -A`.

### 8b. Commit
```bash
git -C $HOME/Documents/yenchat commit -m "v<version>: <description> [deploy]"
```

Commit message rules:
- Format: `v<version>: <concise description> [deploy]`
- Version matches `public/stable/version.json`
- No AI/Claude attribution (per global rules)
- Description summarizes what changed in this release
- `[deploy]` is required because `/update-yen` always stages `public/stable/*`, which Vercel serves

## Step 9: Verify the GitHub Release Upload

Confirm the DMG is accessible:
```bash
curl -sIL -o /dev/null -w '%{http_code} %{size_download}\n' "$(jq -r .url public/stable/version.json)"
```

Expected: HTTP 200 after GitHub's redirect to its asset host.
The DMG must be accessible before pushing, because Sparkle update checks resolve immediately after push.
On a 404, check `finalize-build.sh` output for upload errors and re-run it.

## Step 10: Push

```bash
git -C $HOME/Documents/yenchat push origin main
```

Claude Code runners must pass `dangerouslyDisableSandbox: true` on this Bash call. Its sandbox heuristic can block default-branch pushes even when broad permissions are enabled.
Keep the push on its own Bash call: a guard hook refuses any line that carries a ` -f` argument after the push, so a following `cut -f1` on the same line fails the call.

Only push after:
1. Commit is clean (Step 8)
2. DMG is accessible (Step 9)
3. All verification passed (Steps 6-7)
4. The release commit includes `[deploy]` so Vercel rebuilds `yen.chat/stable/*`

## Step 11: Publish Release Notes + Feature Documentation

**Release notes — REQUIRED on every `/update-yen`, never "if applicable":**

The public release notes voice (blog.yen.chat/releases) comes from the hand-curated `lib/release-notes/release-notes-copy.ts` (`RELEASE_COPY`), merged by `scripts/gen-release-notes.ts` over the terse commit line. The ship date comes from this release's `version.json` bump commit (Step 8), so notes ship as a short follow-up commit right after the release. Builds from before the open-source history come from the frozen `lib/release-notes/release-ledger.ts`, so a regeneration must still report every earlier week; a run that prints far fewer weeks than `/release` shows is the ledger not being read, and `tests/161` fails on it. A maintenance build with no user-facing change goes in `RELEASE_EXCLUDE` instead of `RELEASE_COPY`. See `_docs/10-gtm.md` -> "Release Notes".

1. Add the factual customer-facing line for `v<version>` to `RELEASE_COPY`, then create or refresh the current Monday-start `RELEASE_WEEK_COPY` story in `lib/release-notes/release-notes-copy.ts`. Write the weekly story for the person considering the updates: establish the meaningful theme or user situation, name the most important concrete improvements, and close on why YEN is better to use or worth downloading. Break the story into blank-line-separated paragraphs (a literal `\n\n` in the string) — the page renders one `<p>` per paragraph, so a missing break ships a wall of text; target 2-3 paragraphs for a substantial week, 1-2 for a thin one. Write it so the reader wants to try it: lead with the change a person would feel, address them in the second person, and prefer one concrete detail over a category. Keep it specific and proportional to the evidence; do not concatenate every build into a feature inventory. No invented benefits, emojis, hype, exclamation-mark marketing, upstream engine name, or retired runtimes. Missing copy in either layer fails generation; do not weaken that gate.
2. From repo root: `bun scripts/gen-release-notes.ts` then `bun run build` (refreshes CSP inline-script hashes). The generator prints curated/fallback counts and warns on typo'd keys; confirm the new version uses curated copy.
**Push the release-notes commit ALONE.** `vercel.json`'s `ignoreCommand` evaluates only the **HEAD commit of a push**, not every commit in it. If any commit without `[deploy]` lands on top of the notes commit in the same push, Vercel cancels the build and the regenerated `release-notes-data.ts` never reaches production — `/release` keeps serving the previous version while `version.json` and the appcast already show the new one. This is silent: the notes commit shows `[deploy]`, the push succeeds, and only the live page is wrong. It happened on v1.160, where a `vendor:` commit was pushed alongside the notes. If it does happen, the fix is an empty `[deploy]` commit to re-trigger.

3. Commit + push `lib/release-notes/release-notes-copy.ts`, `lib/release-notes/release-notes-data.ts`, and `lib/csp/generated-inline-script-hashes.ts` as `docs: publish v<version> release notes [deploy]`, with the same push rule as Step 10.

**Feature documentation (if applicable):** if this release also includes new user-facing features or vendor updates:
- Update `_docs/05-infrastructure.md` (desktop build workflow / overlay rules)
- Update `_docs/04-security.md` (vendor overlap + bundled inventory)
- Update `_docs/12-commands.md` and `_docs/13-desktop-features.md` when command surfaces or UX changed
- Update user-facing docs at yen.chat/docs when public behavior changed
- Update `scripts/04-verify-branding.sh` and matching doc check counts when new release checks are added

Skip only the feature-docs subsection for a bugfix-only release; the release-notes subsection is never skipped.

**Trace every claim.** Each sentence in `RELEASE_COPY` and the week story must trace to a commit message or diff in the release range; for a vendor bump, read the upstream compare range, not the vendor commit subject. Drop any clause that adds a benefit the change does not state (for example a bug the change never mentions fixing). Check the generated `/release` page for the new text after production is READY.

## Step 11b: Verify Production

The notes commit is the HEAD of the last push, so it is the deploy that must reach production. Verify it by exact SHA, never by the latest deployment:

```bash
S=$(git -C $HOME/Documents/yenchat rev-parse HEAD)
gh api repos/8bittts/yenchat/commits/$S/status --jq '[.statuses[] | "\(.context)=\(.state)"] | join(" ")'
```

Poll until `Vercel=success`; `pending` is a build still running, and `failure` or `error` stops the release for a build-log review. A cancelled build (the `ignoreCommand` saw a HEAD without `[deploy]`) shows no `Vercel=success` for that SHA and needs an empty `[deploy]` commit.
Then read representative live routes: `https://blog.yen.chat/releases` carries the new week text, `/stable/version.json` reports the new version, `/stable/appcast.xml` and `/docs` return 200. `/download` returns 302 by design, and a local run must never click it because it writes to production.

---

## Step 12: Release Summary

**Always end `/update-yen` with a clear summary table.** Include the vendor phase's Vendor Summary and Upstream Changelog (`references/vendor-commit.md`) when it updated anything.

```text
## Release Summary: v<version> [deploy]

| Category | Details |
|----------|---------|
| Version | <version> |
| DMG Size | XXM |
| Build Time | Xm XXs |
| Vendors Updated | [list or "None"] |
| Changes | [bullet list of what's in this release] |
```

If vendors were updated, include a sub-table:

```text
### Vendor Updates

| Vendor | From | To | Commits/Notes |
|--------|------|----|---------------|
| Ghostty | abc123 | def456 | 10 commits |
```

## Release Artifacts

On the `v<version>` GitHub Release of `8bittts/yenchat` (nothing is pruned; older DMGs are delta sources): `yen-<v>.dmg` (signed DMG), `yen-<v>.dmg.sha256`, and `YENXXXX-YYYY.delta` Sparkle binary-delta patches from version YYYY to XXXX (up to 5 per release when history is available). In git under `public/stable/`: the DMG checksum, `version.json` (URL points to the GitHub Release asset), `version.sig` (Ed25519 signature for `version.json`), and `appcast.xml` (Sparkle feed).

## Eval Checks

RL-01 binds its match to the version in `public/stable/version.json`; a release commit from history cannot satisfy it. RL-03 is a read-only publication assertion after Step 10.

It must not push a second time.

| Check ID | Description | Command |
|----------|-------------|---------|
| RL-01 | The release commit for this version carries the deploy suffix | `v="$(jq -r .version $HOME/Documents/yenchat/public/stable/version.json)"; git -C $HOME/Documents/yenchat log --extended-regexp --grep="^v${v}: .*\\[deploy\\]$" -1 --format=%s \| /usr/bin/grep -qE "^v${v}: .*\\[deploy\\]$"` (binds the match to `version.json`'s version, so an older release commit cannot satisfy it; the newest match is still read after the required notes follow-up, without an early-closing pipe) |
| RL-02 | DMG served with HTTP 200 | `test "$(curl -sIL -o /dev/null -w '%{http_code}' "$(jq -r .url $HOME/Documents/yenchat/public/stable/version.json)")" = 200` |
| RL-03 | Published remote matches local HEAD | `test "$(git -C $HOME/Documents/yenchat rev-parse HEAD)" = "$(git -C $HOME/Documents/yenchat ls-remote origin refs/heads/main \| awk 'NR == 1 {print $1}')"` |

## Local Mode

For `/update-yen local`, this phase is skipped entirely. Local builds:
- Do not commit
- Do not upload
- Do not push
- Are never shipped to users
