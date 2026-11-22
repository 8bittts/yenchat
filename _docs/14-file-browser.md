# File Browser (Yazi)

Owns YEN View: the vendored Yazi browser, its launch paths, bundled config and plugins, and Yazi update checks.

## Sources of truth

- `yen-terminal/customizations/bin/browse`, `yen-quicklook`, `yen-yazi-edit`
- `yen-terminal/customizations/yazi-config/` (`yazi.toml`, `init.lua`, `theme.toml`, `keymap.toml`, `flavors/`, `plugins/`)
- `y()` in `yen-terminal/customizations/shell-integration/{zsh,bash}/`
- `yen-terminal/customizations/vendor/yazi/` (gitignored `yazi` and `ya`)
- `AppDelegate+FileBrowser.swift` and `TerminalSurfaceCommandLauncher.swift`

## Launch

| Entry | Behavior |
|-------|----------|
| `Cmd + Shift + O`, palette action | The launcher resolves the focused terminal surface, sends `Ctrl + C` as a command boundary, then `y` and Enter as key events (never `sendText`); with no terminal surface it fails closed |
| `y` | Shell function in YEN-launched bash and zsh shells only; runs bundled `browse --cwd-file` and `cd`s to the last directory on quit |
| `browse` (`files`, `fm`, `yen browse`) | Works anywhere, no cd-on-quit; sets the static `YAZI_CONFIG_HOME` and puts the bundle's `bin` first on `PATH` |

`y()` delegates to `browse` so every path resolves the same bundled helpers.
`yen init` does not define `y`; inside YEN, "command not found: y" means the bundled integration is broken, so fix the build rather than dotfiles.

## Configuration

Yazi is customized only through the bundled config directory, never by patching the binary.
`yazi.toml` sets `show_hidden`, `sort_by = "natural"` and `sort_dir_first`; the `YEN: <cwd>` title comes from an `ind-app-title` subscriber in `init.lua`, because Yazi removed the static `title_format` key.
Visuals are static: `theme.toml` with the bundled Catppuccin flavors; there is no runtime theme generator.
`bundle-yen-resources.sh` copies the config to `Resources/yazi-config/` and the wrappers to `Resources/bin/`, and fails if the binary, config or wrapper is missing; `05-detect-failures.sh` re-checks the bundle.

Keymap additions in `keymap.toml`: `Enter` opens a read-only view of text in the system `less`, `O` opens the open-with menu, `e` edits through `yen-yazi-edit`, `Space` is Quick Look, `g r` reveals in Finder, `g o` opens in the default app, `Tab` selects.
Yazi defaults cover the rest: `h j k l` navigate, `/` finds in the current list, `s` searches names with the bundled `fd`, `S` searches contents with the bundled `rg`, and `Y` or `X` clears the yank selection.
`z` (fzf) and `Z` (zoxide) work only when the user has those tools on `PATH`; YEN bundles neither ([04-security.md](04-security.md) → Bundled Binary Inventory).
File operations are copy, move, trash, permanent delete and rename; there is no file-operation undo contract.
`q` changes the shell directory only when launched through `y`.

`yen-yazi-edit` routes a single target through `yen-cli/lib/ide/editor-handoff.sh`, the same `path:line[:col]` launcher as `yen ide open`.
It keeps quoted `$EDITOR` argv, resolves dash-prefixed names to absolute paths, falls back from `nvr` to `nvim` with no server, and fails when the target or launcher is missing.
For `micro` it adds `-ruler false -softwrap true -wordwrap true` so copy-on-select never captures gutter numbers; `tests/35-yazi-config.test.ts`, `03-verify-components.sh` and `05-detect-failures.sh` fail if those flags drift.

## Plugins

| Plugin | Role | Bounds and failure behavior |
|--------|------|-----------------------------|
| `code-guard.yazi` | Wraps upstream `code` preview | Files over 1 MB or minified fall back to plain wrapped text (64 KB sample, decision cache by path+length+mtime, 64-entry line cache) |
| `git.yazi` | Git status column | At most 2048 tracked directories with per-scope refcounted pruning; a failed git call degrades without breaking init |
| `archive-native.yazi` | Archive listing through macOS `bsdtar` | 128-entry cache, 5000 indexed entries, visible slice only; renders `(empty archive)` or an error widget |
| `extract-native.yazi` | Extraction | Temp directory and tidy pass, strips `__MACOSX`, cleans up on failure |
| `video-native.yazi`, `pdf-native.yazi` | Thumbnails through `yen-vidthumb` and `yen-pdfthumb` | 512-entry metadata caches, preload-owned rendering, honors `image_delay` and preview bounds; a helper failure never breaks the session |
| `svg-native.yazi` | SVG thumbnails through `yen-svgthumb`, which inflates `.svgz` itself (64 MB cap) | A failed render logs `ya.err` and shows an error widget |

Each plugin keeps upstream's `peek`/`preload`/`seek` shape and changes only its backend; `image_quality` is unapplied because the helpers emit PNG.
The SVG rules sit above the archive rules in `prepend_previewers`, because a `.svgz` file has the mime type `application/gzip` and the first matching rule wins.
`fs.cha` takes a `Url`: a plugin that passes a string or a `Path` raises a Lua error in the preview pane, so wrap the path as `Url(tostring(path))`.
The archive plugin intentionally omits upstream's compressed-tar re-entry and size column, which `bsdtar` cannot list cheaply.

## Known Limitations

- Encrypted archive extraction is blocked: `bsdtar` takes passphrases only as arguments, visible in `ps`. `YEN_ALLOW_INSECURE_ARCHIVE_PASSPHRASE=1` opts in.
- `qlmanage` can abort on audio and video, so `yen-quicklook` sends `public.movie`, `public.video` and `public.audio` to `open`.

## Verification

```bash
bun test tests/35-yazi-config.test.ts
for f in yen-terminal/customizations/yazi-config/plugins/*/*.lua; do luac -p "$f"; done
yen-terminal/customizations/vendor/yazi/yazi --version
./scripts/manual/28-run-file-browser-preview-benchmark.sh
```

## Vendor Watch

The `/update-yen` vendor phase carries the Yazi checks in `.agents/skills/update-yen/references/vendor-audit.md`; when Yazi updates, confirm:

- `theme.toml` still matches the schema (`[tabs]`, `[indicator]`, `[cmp]`, `[icon].{prepend,append}_globs`, `filetype.rules` with `url`); `tests/35-yazi-config.test.ts` guards it.
- Flavor fields still validate.
- `init.lua` still receives `ind-app-title`.
- Every preview type still renders in a running copy: text, JSON, SVG, `.svgz`, PDF, video, `.zip` and `.tar.gz`. A Lua stub cannot show a changed Yazi API; `tests/35-yazi-config.test.ts` rejects only the argument types already known to fail.
- A native `<S-Enter>` binding does not collide with YEN's Shift + Enter mapping (`\r`).
