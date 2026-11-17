# Contributing to YEN

Contributions are welcome: bug reports, crash reports, fixes, and pull requests.

## Before you start

- Read [`AGENTS.md`](AGENTS.md).
  It is the enforceable contract for this repository, and its rules name the tests that guard them.
- YEN is in maintenance mode: bug, crash, security, and build fixes are in scope.
  Open an issue before a feature or a large change, so the approach can be agreed before you write it.
- Put desktop changes in `yen-terminal/overlays/`, `yen-terminal/customizations/`, or the patch pipeline.
  `yen-terminal/ghostty/` is a generated upstream mirror and is never edited by hand.
- For any visual change, read [`_docs/02-design-system.md`](_docs/02-design-system.md) and use the existing design.

## Hard rules

- The desktop app sends no terminal content and no usage telemetry, and it needs no account.
- Never commit secrets, tokens, signing keys, notarization credentials, or local credential state.
- Never commit a DMG, a Sparkle delta, or the generated Ghostty mirror.

## Run the gates

Run each line from the repository root:

```sh
bun install
bun run check                           # lint + typecheck
bun test                                # unit, contract, and fixture tests
bun scripts/44-build-web-csp.ts         # website build
scripts/native/01-macos-smoke.sh --fast # native build and tests; needs Xcode, Zig, and the vendor tree
```

`bun run build` also runs the bundle secret scan, which fails closed when no deploy credentials are present, so it is a maintainer gate.
Fetch the Ghostty mirror and the bundled tools with `scripts/14-vendor.sh` before the native build.
Use Bun for all JavaScript package work.
Add or update tests for the behavior you change, and keep the gates green.

## Pull requests

- Keep each pull request to one topic.
- Describe what changed and how you verified it, including a screenshot for visible UI work.
- Write commit subjects in plain user language.

Releases, signing, notarization, and deploys need owner credentials, so the maintainer runs them.

## License

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
The YEN name and logo are not covered by that license.
