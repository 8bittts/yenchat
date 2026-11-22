# YEN

**Quit the app. Keep the shell.**

![YEN Terminal](https://yen.chat/doc-images/_yen-0.png)

YEN is a free, open-source, GPU-accelerated terminal for macOS that just works.
Your panes keep running through quits, crashes and updates, you can talk to any app on your Mac, and nothing needs configuring before it is useful.
It is built on [Ghostty](https://github.com/ghostty-org/ghostty) and released under the [MIT License](LICENSE).

[Download for macOS](https://yen.chat) · [Docs](https://yen.chat/#guide) · [Release notes](https://blog.yen.chat/releases)

## Why YEN

### Leave a server running

Quit YEN, let it update, or watch it crash: your shell sessions keep running.
Open it again and each restored session reattaches with its screen and scrollback, right where you left it.
A build finishes, a dev server keeps its port, and an SSH connection stays up while YEN is closed.

There is nothing to set up: no tmux config, no session names, no extra commands.
It is on by default.
Settings > General shows how many sessions are running and stops them all with one button, and `yen sessions` lists, attaches and ends them from any shell.
Closing a pane still ends what runs in it.

### Speech-to-text in any app

Press `Option + Space`, talk, and your words land in the terminal or in any other macOS app.
Dictation runs on Apple's on-device `SpeechAnalyzer` after language assets install.
YEN never receives your audio or transcripts.

### Paste anything

`Cmd + V` knows what is on your clipboard.
Paste a screenshot or a copied picture and YEN saves it to a private, auto-pruned folder and pastes its path, ready for your editor or coding agent.

### A terminal-first IDE

- A native file browser, command palette, tab sidebar and scratchpad, all one shortcut away.
- A built-in WebKit browser for docs and local dev servers, in a window or a split.
- Project detection, trust, diagnostics, test runs, review and automation through the bundled `yen` command.
- 20 curated themes, previewed live in Settings.
- A focused outline around the pane that receives the next keystroke, with a choice of comfortable gutters or compact dividers.

### A menu bar for your agents

The [agent token usage experiment](https://yen.chat/#agent-token-usage) shows daily counts for Claude Code, Codex, Grok Build and OpenCode in the menu bar.
The breakdown follows your Mac’s local day, including activity outside YEN.

### A moving desktop

On macOS 27 or later, Experimental > Moving Wallpaper plays video behind your desktop icons.
Choose a local clip, a GIF, YouTube, or Photos, and assign a different selection to each desktop.
Token counting and wallpaper both start switched off.

### Private by default

No YEN account.
No desktop usage telemetry sent to YEN.
No terminal content is sent to YEN.

## Requirements

- Builds after 1.283 require macOS 27.0 or later on Apple silicon.
- YEN 1.283 supports macOS 13.0 and later.
- Accessibility, Microphone, and Speech Recognition permissions for dictation.

When SpeechAnalyzer is unavailable, YEN requests on-device recognition when Apple reports support.
Apple's legacy recognizer can use Apple's service when on-device recognition is unavailable.

## Install

1. Download YEN from [yen.chat](https://yen.chat) or the [latest GitHub Release](https://github.com/8bittts/yenchat/releases/latest).
2. Open the DMG and drag YEN to Applications.
3. Open YEN from Applications.

YEN updates itself.
See the [public documentation](https://yen.chat/#guide) for every feature and command.

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

## License

YEN is released under the [MIT License](LICENSE).
YEN is built on Ghostty, which is also MIT licensed; its notice is included in [LICENSE](LICENSE).
Persistent sessions use [zmx](https://github.com/neurosnap/zmx), which is MIT licensed.
Bundled third-party tools keep their own licenses.
The YEN name and logo are not covered by the MIT License.
