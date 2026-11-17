# yen-cli

Source of the `yen` command bundled at `YEN.app/Contents/Resources/bin/yen`.
The user-facing command contract is `_docs/12-commands.md`; this file covers layout and development.

## Layout

```
bin/yen                 # Entry point: help, routing, suggestions
commands/core/          # One script per subcommand
  config help web pane reload update agents
  ide                   # Router for detect/doctor/env/lsp/share/ast/devcontainer/vscode and the other ide families
lib/common.sh           # Colors, prompts, formatting
lib/ide/                # Sourced IDE modules behind commands/core/ide
```

The build copies `commands/` and `lib/` into `YEN.app/Contents/Resources/`.
The CLI reads its version from the bundled `yen/version.json`, or `public/stable/version.json` in development; it needs no version sync.

## Examples

```bash
yen web open --split http://localhost:3000
yen pane cwd --hook
yen ide detect
yen ide doctor
yen ide trust status
yen ide lsp status
yen ide lsp diagnostics
yen ide share host --read-only --ttl-minutes 30
yen ide test status
yen ide test run --runner node-test --watch --watch-interval 0.5 --max-runs 3
yen ide workflow run --native package.json:test --watch --watch-interval 0.5 --max-runs 2
yen ide verify --quick
yen ide pr-review 123 --evidence
yen agents timeline --format json
```

## Development

```bash
export PATH="$HOME/Documents/yenchat/yen-cli/bin:$PATH"
export YEN_LIB="$HOME/Documents/yenchat/yen-cli/lib"
yen help
```

## Adding Commands

Add an executable script under `commands/core/` that sources `${YEN_LIB}/common.sh`, then follow the registration checklist in `_docs/12-commands.md` → Adding New Commands.
`commands/core/ide` stays a thin router: extend an existing `lib/ide/` module when the capability fits its family, and add a new module only for a genuinely new boundary.
