# YEN

![YEN Terminal](https://yen.chat/doc-images/_yen-0.png)

YEN is a free, open-source, GPU-accelerated terminal for macOS, built on [Ghostty](https://github.com/ghostty-org/ghostty).
It is released under the [MIT License](LICENSE).

## Product

- Native Metal rendering.
- Apple Speech dictation in YEN and other macOS apps.
- A built-in file browser, Git drawer, command palette, browser preview, tab sidebar, and scratchpad.
- Local terminal-first IDE workflows for project detection, trust, diagnostics, testing, review, and automation.
- A curated theme catalog and native macOS settings.
- No required YEN account and no desktop usage telemetry sent to YEN.

Dictation uses Apple's on-device `SpeechAnalyzer` on macOS 26 or newer.
On older systems or runtime fallback, YEN requests on-device recognition when Apple reports support.
Apple's legacy recognizer can use Apple's service when on-device recognition is unavailable.
YEN does not receive dictation audio or transcripts.

## Requirements

- macOS 13 Ventura or newer.
- Apple silicon or Intel Mac.
- Accessibility, Microphone, and Speech Recognition permissions for dictation.

## Install

1. Download YEN from [yen.chat](https://yen.chat) or the [latest GitHub Release](https://github.com/8bittts/yenchat/releases/latest).
2. Open the DMG and drag YEN to Applications.
3. Open YEN from Applications.

See the [public documentation](https://yen.chat/docs) for current features and commands.

## Development

Use Bun for all package operations: `bun install`, then `bun run dev` for the website on port 8987.
The website needs no environment variables.
The required gates are listed in [AGENTS.md](AGENTS.md); the default native loop is `scripts/native/01-macos-smoke.sh`, which needs Xcode and the Zig version pinned by Ghostty.
`yen-terminal/ghostty/` and the bundled tool binaries are not in the repository: `scripts/14-vendor.sh` downloads and verifies them.
See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
[`_docs/00-docs-map.md`](_docs/00-docs-map.md) indexes the internal documentation, and [`_docs/05-infrastructure.md`](_docs/05-infrastructure.md) covers desktop builds, releases, and environment variables.

## Structure

| Path | Purpose |
|------|---------|
| `app/`, `components/`, `lib/` | Public Next.js website |
| `yen-terminal/ghostty/` | Generated upstream terminal mirror |
| `yen-terminal/overlays/` | YEN-owned native overlays |
| `yen-terminal/customizations/` | Desktop assets and integration files |
| `yen-cli/` | Bundled `yen` command |
| `public/stable/` | Public release metadata and checksums |
| `scripts/` | Build, vendor, verification, and release automation |
| `_docs/` | Owner documentation for maintainers |

## Links

- Website: [yen.chat](https://yen.chat)
- Documentation: [yen.chat/docs](https://yen.chat/docs)
- Release notes: [yen.chat/release](https://yen.chat/release)
- Blog: [blog.yen.chat](https://blog.yen.chat/)

## License

YEN is released under the [MIT License](LICENSE).
YEN is built on Ghostty, which is also MIT licensed; its notice is included in [LICENSE](LICENSE).
Bundled third-party tools keep their own licenses.
The YEN name and logo are not covered by the MIT License.
