# Dependency Update (Steps D1 to D6)

The deps phase keeps YEN's Bun packages and the vendored Sparkle framework current.
It runs first in full mode, before the vendor phase, and it is the only updater for them: `/update-projs` does not cover yenchat.
It never touches `yen-terminal/ghostty/` or anything in `scripts/lib/vendor-manifest.sh`; those belong to the vendor phase.

Run `eval-phase.sh begin yen-deps` once, at Step D1.
Save every detection output under `tmp/skill-telemetry/`, so each eval reads the file instead of re-running the command.

```bash
R=$HOME/Documents/yenchat
T=$R/tmp/skill-telemetry
mkdir -p "$T"
```

## Step D1. Pre-flight

```bash
cd "$R" && pwd && git rev-parse --show-toplevel && git branch --show-current
git status --porcelain
git worktree list
lock_key=$(printf '%s\n' "$R" | cksum | awk '{print $1}')
ls -d "${TMPDIR:-/tmp}/yen-workflow-${lock_key}.lock" "${TMPDIR:-/tmp}/yen-vendor-${lock_key}.lock" 2>/dev/null
git fetch origin main && git rev-list --left-right --count HEAD...origin/main
```

- Work in the canonical checkout on `main`, never a worktree; the release scripts assume it.
- A lock at this repo's key means another YEN workflow owns the tree. Read its `pid`, check it with `command ps -p <pid> -o pid=,command=`, and stop while it is alive.
- A dirty tree may be another agent's live work. Date the files with `stat -f '%Sm %N' -t '%m-%d %H:%M'`; edits a few minutes old, or edits under `yen-terminal/overlays/`, mean stop and ask.
- Otherwise stash with `git stash push -u -m "pre-update stash" -- <paths>`. Name only the real work: a path listed by `git worktree list` is a live checkout and is never stashed.
- A clean tree that is behind fast-forwards with `git merge --ff-only origin/main`. A tree that is ahead is unpushed work: stop and ask.
- Run `bun install --frozen-lockfile`. A commit pulled from another checkout can leave a declared package missing, and every later gate then fails on `Cannot find module`.

## Step D2. Detect

```bash
bun --version
bunx npm-check-updates > "$T/yen-deps-ncu.out" 2>&1; echo "$?" > "$T/yen-deps-ncu.out.code"
bun audit > "$T/yen-deps-audit.out" 2>&1; echo "$?" > "$T/yen-deps-audit.out.code"
grep '^sparkle_version=' tools/sparkle/VERSION
gh api repos/sparkle-project/Sparkle/releases/latest --jq '.tag_name'
```

- `packageManager` in `package.json` must equal `bun@<bun --version>`. Drift counts as an update; fix it with the Edit tool.
- Ignore the `bun` row in the ncu output; it is the `packageManager` field.
- `ncu` reads only declared dependencies, so `bun audit` is the receipt for the whole tree. Any finding counts as an update.
- A `FetchError`, `ECONNRESET` or `ConnectionRefused` line makes that output incomplete even at exit 0. Re-run it before calling the result current.
- Print `Sparkle: local=<ver> latest=<ver>`. An empty `latest` is lost coverage, never "already latest". Use `releases/latest`, which excludes prereleases; a beta tag is never a target.
- `yen-cli/fixtures/**/package.json` are test fixtures and `workstreams/**` are nested checkouts; neither is a manifest to update.

**No-update path.** When nothing is outdated, the audit is clean, `packageManager` matches and Sparkle is current, record DP-01 to DP-03, skip Steps D3 to D6, and go to Step V1.

## Step D3. Breaking-change review

The phase runs on autopilot: majors and minors apply by default. For each major (`pkg@old -> pkg@new`):

1. Group the updates with `bunx npm-check-updates --format group`.
2. Read the changelog or release notes and summarize the breaking changes.
3. Compare against the newest stable on the pin's own major line, not only `latest`:

```bash
npm view <pkg> versions --json | jq -r '[.[] | select(startswith("<major>.")) | select(test("-")|not)] | .[-1]'
```

Then apply it: run its codemod or migration and fix every call site the changelog names before Step D5.
Stop and ask only for a dangerous case: a Sparkle `2.x -> 3.x` major (it changes how every installed copy updates), a fix that would weaken or delete a gate or test, a change to what users see, or an advisory with no patched release.
`next` is not held; update it like any other dependency.

## Step D4. Apply

```bash
bunx npm-check-updates -u --reject bun
bun install
```

- Add a `--reject <pkg>` only for a major held at Step D5.
- Read the whole `overrides` block in `package.json` before installing. Each entry must equal its declared version or be a documented security pin in `_docs/04-security.md`; remove any other pin.
- When `bun audit` still reports a finding, run `bun audit fix`, then `bun audit` again until it prints `No vulnerabilities found`. Confirm with `git diff package.json bun.lock`: it can also rewrite an exact pin. Never run `bun audit fix --latest`.
- If `@biomejs/biome` moved, run `bunx biome migrate --write`, then `bunx biome format --write .` until a pass changes nothing.

**Sparkle 2.x patch or minor.**

1. Download `Sparkle-<version>.tar.xz` from the GitHub release, never a SwiftPM artifact.
2. Replace `tools/sparkle/Sparkle.framework` and `tools/sparkle/bin/`. Copy the whole `Versions/B/` tree, including `Updater.app`, `Autoupdate` and both `XPCServices/*.xpc`, and restore the top-level framework symlinks onto `Versions/Current/<name>`.
3. Refresh every field in `tools/sparkle/VERSION`; `sparkle_binary_sha256` is `shasum -a 256 tools/sparkle/Sparkle.framework/Versions/B/Sparkle`.
4. Confirm each `required_paths` entry in `VERSION` exists. The release cut's Step 5 build is the compile gate for the new framework.

## Step D5. Gates

Run the repo `AGENTS.md` Required Gates, with the full output in a file:

```bash
( bun run check:full > "$T/yen-deps-gates.out" 2>&1; echo "exit=$?" >> "$T/yen-deps-gates.out" )
```

- The vendored `Config.zig` and `zmx` must exist first; a missing vendor tree is not a verified run, and `YEN_ALLOW_MISSING_VENDOR_TREE` is never set here.
- A web build that passes locally but fails on Vercel is reproduced with Vercel's build-adapter layout (`_docs/09-quality.md`). Fix the build script; never pin `next` to avoid it.
- The generated CSP hash manifest is specific to the `next` version, so commit the one the final build writes.
- On a failure, baseline it: stash the update, run the failing gate at HEAD, then pop. The same failure at HEAD is pre-existing; report it and keep the update.
- A pass at HEAD is a regression: fix the code for the new API first. Only after a genuine fix attempt, hold that one package (`--reject <pkg>`), keep every other update, and name the hold and its failing receipt in the final summary.

## Step D6. Commit and push

- Stage only the files this phase changed (`package.json`, `bun.lock`, the CSP manifest, `tools/sparkle/`, formatter output), never `git add .`.
- Commit as `deps: <summary of moved packages>`, with no `[deploy]` marker. The release cut ships the website with its own `[deploy]` commits.
- Push to `origin main`. Claude Code needs `dangerouslyDisableSandbox: true` on that Bash call.
- Restore the D1 stash. `git stash list` must show no workflow stash, and `git status --porcelain` must match what was stashed.

## Eval Checks

| Check ID | Description | Command |
|----------|-------------|---------|
| DP-01 | Pre-flight left a clean `main` that is not behind origin | `cd $HOME/Documents/yenchat && [ "$(git branch --show-current)" = main ] && test -z "$(git status --porcelain)" && [ "$(git rev-list --count HEAD..origin/main)" -eq 0 ]` |
| DP-02 | Detection ran in this run and its outputs are complete | `T=$HOME/Documents/yenchat/tmp/skill-telemetry; test "$T/yen-deps-ncu.out" -nt "$T/yen-deps-eval-run.id" && test "$T/yen-deps-audit.out" -nt "$T/yen-deps-eval-run.id" && ! grep -q -e FetchError -e ECONNRESET -e ConnectionRefused "$T/yen-deps-ncu.out" "$T/yen-deps-audit.out"` |
| DP-03 | `packageManager` matches the installed Bun | `cd $HOME/Documents/yenchat && grep -q "\"packageManager\": \"bun@$(bun --version)\"" package.json` |
| DP-04 | The audit is clean after the update | `T=$HOME/Documents/yenchat/tmp/skill-telemetry; cd $HOME/Documents/yenchat && bun audit > "$T/yen-deps-audit-final.out" 2>&1; grep -q 'No vulnerabilities found' "$T/yen-deps-audit-final.out"` |
| DP-05 | Required gates passed in this run | `G=$HOME/Documents/yenchat/tmp/skill-telemetry/yen-deps-gates.out; test "$G" -nt $HOME/Documents/yenchat/tmp/skill-telemetry/yen-deps-eval-run.id && grep -qx 'exit=0' "$G"` |
| DP-06 | The `deps:` commit is pushed and the tree is clean | `cd $HOME/Documents/yenchat && test -n "$(git log --format=%s -E --grep='^deps: ' HEAD^!)" && [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && test -z "$(git status --porcelain)"` |

The no-update path records DP-01 to DP-03 only. Run `summary yen-deps` after Step D6, or after DP-03 on the no-update path, and require `Result: PASS` before Step V1.
