import Image from "next/image";
import Link from "next/link";

function DocSection({
	id,
	title,
	children,
}: {
	id: string;
	title: string;
	children: React.ReactNode;
}) {
	return (
		<details id={id} className="ph-manual-chapter">
			<summary>
				{title}
				<span className="ph-disclosure" aria-hidden="true" />
			</summary>
			<div className="space-y-6">{children}</div>
		</details>
	);
}

import { TerminalCodeBlock } from "@/components/docs/terminal-code-block";
import { TerminalPanel } from "@/components/docs/terminal-panel";
import { DOWNLOAD_HREF } from "@/lib/analytics/download-cta";

// Source: yen-terminal/overlays/macos/Sources/Features/Update/UpdateController.swift; public/stable/version.json.
function GetStartedSection() {
	return (
		<DocSection id="install" title="Get Started">
			<TerminalPanel className="mb-6">
				<table className="w-full text-body table-fixed">
					<thead>
						<tr className="border-b border-border bg-card-header">
							<th
								scope="col"
								className="text-left py-3 pl-4 pr-4 font-bold text-text-primary"
							>
								Step
							</th>
							<th
								scope="col"
								className="text-left py-3 pr-4 font-bold text-text-primary"
							>
								Action
							</th>
						</tr>
					</thead>
					<tbody className="text-body bg-card">
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								1.{" "}
								<Link href={DOWNLOAD_HREF} className="link-brand underline">
									Download
								</Link>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Open the .dmg file
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">2. Install</td>
							<td className="align-top py-2 pr-4 text-left">
								Drag YEN to Applications
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">3. First launch</td>
							<td className="align-top py-2 pr-4 text-left">
								Open YEN from Applications
							</td>
						</tr>
						<tr>
							<td className="align-top py-2 pl-4 pr-4">4. Updates</td>
							<td className="align-top py-2 pr-4 text-left">
								Choose Check for Updates in YEN; automatic checks are optional
							</td>
						</tr>
					</tbody>
				</table>
			</TerminalPanel>
			<p id="requirements" className="text-body">
				YEN 1.284 requires macOS 27.0 or later on Apple silicon. For an Intel
				Mac or macOS 13 through 26, download{" "}
				<a
					className="link-brand underline"
					href="https://github.com/8bittts/yenchat/releases/tag/v1.283"
				>
					YEN 1.283
				</a>
				. In 1.283, YEN’s actions in Apple Shortcuts require macOS 14 or later.
				On macOS 13 through 15, dictation uses the legacy recognizer and
				dictation translation is unavailable. No YEN account is required.
				Dictation needs Accessibility, Microphone, and Speech Recognition
				permissions; see{" "}
				<a href="#voice-dictation" className="link-brand underline">
					dictation setup
				</a>
				.
			</p>
		</DocSection>
	);
}

// Source: terminal engine src/renderer/Metal.zig and src/config/Config.zig; Settings/LayoutTemplate.swift; Scratchpad/ScratchpadStorage.swift.
function TerminalIDESection() {
	return (
		<DocSection id="terminal-ide" title="Workspace">
			<p className="text-body mb-4">
				YEN starts with a native macOS terminal and layers IDE workflows around
				it. Settings and workspace panels use native macOS UI; browser preview
				uses Apple WebKit. Editor commands can open your configured external
				editor.
			</p>

			<p className="text-body mb-4">
				The terminal renders with Metal. Windows, tabs, split layouts, and
				positions restore on relaunch. With{" "}
				<a href="#persistent-sessions" className="link-brand underline">
					Keep Sessions Running
				</a>{" "}
				enabled, restored shell panes also reconnect to their live processes.
				Use the{" "}
				<a href="#commands" className="link-brand underline">
					shortcut reference
				</a>{" "}
				for tabs, splits, Quick Terminal, and window screenshots.
			</p>
			<ul className="list-disc list-outside pl-5 space-y-3 text-body mb-6">
				<li>
					<strong>Scratchpad:</strong> one locally saved notes buffer shared
					across windows. The panel opens in the center of the terminal. Drag
					its title bar to move it or an edge to resize it. YEN remembers the
					size. It supports copy, paste, and copy-on-select when enabled.
				</li>
				<li>
					<strong>Layouts:</strong> ten presets from the File menu, the command
					palette, or{" "}
					<code className="inline-code-brand">Cmd + Option + 1-0</code>. Single
					Pane requires a second invocation to confirm closing other panes.
				</li>
				<li>
					<strong>Bundled tools:</strong> fd, rg, fzf, zoxide, bat, jq, and
					other terminal helpers. IDE integrations can require additional tools;
					see{" "}
					<a href="#ide-workflows" className="link-brand underline">
						IDE Workflows
					</a>
					.
				</li>
				<li>
					<strong>Shell integration:</strong> automatic detection supports bash,
					zsh, fish, elvish, and nushell. YEN command wrappers and cd-on-quit
					are supplied for bash and zsh.
				</li>
			</ul>

			<h3 id="git-drawer" className="text-heading-sm mb-3">
				Local Git changes
			</h3>
			<p className="text-body">
				YEN 1.283 removed the bottom Git drawer and its shortcut. Run{" "}
				<code className="inline-code-brand">yengit</code> for Git operations, or
				the command palette for PR review and merge-conflict workspaces.
			</p>
		</DocSection>
	);
}

// Source: yen-terminal/overlays/macos/Tests/Terminal/TerminalClipboardShortcutTests.swift; Helpers/CopyOnSelectClipboard.swift; yen-terminal/apply-overlays.sh.
function ClipboardSection() {
	return (
		<DocSection id="clipboard" title="Clipboard & Paste">
			<p className="text-body mb-4">
				With the default bindings,{" "}
				<code className="inline-code-brand">Cmd + C</code> copies the terminal
				selection and <code className="inline-code-brand">Cmd + V</code> uses
				the native paste action, including in terminal applications. Custom
				bindings are respected; applications still control how pasted text is
				handled.
			</p>

			<TerminalPanel className="mb-6">
				<table className="w-full min-w-[36rem] text-body table-fixed">
					<thead>
						<tr className="border-b border-border bg-card-header">
							<th
								scope="col"
								className="text-left py-3 pl-4 pr-4 font-bold text-text-primary"
							>
								Action
							</th>
							<th
								scope="col"
								className="text-left py-3 pr-4 font-bold text-text-primary"
							>
								What YEN does
							</th>
						</tr>
					</thead>
					<tbody className="text-body bg-card">
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">Cmd + C</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Copies the selection. With copy-on-select on (default),
								releasing the mouse already copies — hold{" "}
								<code className="inline-code-brand">Shift</code> to select
								inside TUIs that capture mouse events.
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">Cmd + V</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Uses the native paste action when bound to paste. A custom
								non-paste binding is not overridden.
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								Paste an image (screenshot, copied picture)
							</td>
							<td className="align-top py-2 pr-4 text-left">
								YEN materializes it as a temp file in a private, auto-pruned
								directory and pastes the path — ready to{" "}
								<code className="inline-code-brand">cat</code>,{" "}
								<code className="inline-code-brand">cp</code>, or hand to your
								editor.
							</td>
						</tr>
						<tr>
							<td className="align-top py-2 pl-4 pr-4">
								Right-click in a terminal
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Native macOS context menu with Copy / Paste / Paste as Plain
								Text / Paste from Selection.
							</td>
						</tr>
					</tbody>
				</table>
			</TerminalPanel>

			<p className="text-body">
				Copy on Select can be disabled in Settings &gt; General. File URLs paste
				as paths; image-only clipboards become temporary image files.
			</p>
		</DocSection>
	);
}

// Static documentation content (capability table + quick-start codeblock). Length is content, not behavior — splitting further would fragment a single conceptual section.
// Source: yen-cli/commands/core/ide; yen-cli/lib/ide/{debug-targets,lsp,ast,share,workflow-quality}.sh; yen-cli/commands/core/agents.
// react-doctor-disable-next-line react-doctor/no-giant-component
function IDEWorkflowsSection() {
	return (
		<DocSection id="ide-workflows" title="IDE Workflows">
			<p className="text-body mb-4">
				Run <code className="inline-code-brand">yen ide --help</code> for the
				full command reference. Start with the status commands below, then grant
				trust only for the capabilities you need.
			</p>

			<div className="callout-card mb-6">
				<h3 className="text-heading-sm mb-3">Before you start</h3>
				<p className="text-body">
					Run commands from your project directory. Trust is granted per project
					and capability; a status command does not grant it. LSP and AST tools
					need Python 3 and the relevant language server or compiler. Debugging
					needs Python, Node, or LLDB. Devcontainers need the devcontainer CLI
					and a container runtime. Sharing needs upterm or tmate and OpenSSL.
					GitHub review needs an authenticated GitHub CLI; agent adapters need
					the corresponding Claude or Codex CLI and its own authentication.
				</p>
			</div>

			<h3 className="text-heading-sm mb-3">Start with project status:</h3>
			<TerminalCodeBlock
				title="Terminal"
				showPrompt
				code={`yen ide doctor
yen ide trust status
yen ide test status
yen ide workflow discover
yen ide lsp status
yen ide --help`}
			/>
			<details>
				<summary className="text-body cursor-pointer focus-ring">
					Workflow commands and requirements
				</summary>

				<TerminalPanel className="mb-6">
					<table className="w-full min-w-[36rem] text-body table-fixed">
						<thead>
							<tr className="border-b border-border bg-card-header">
								<th
									scope="col"
									className="text-left py-3 pl-4 pr-4 font-bold text-text-primary"
								>
									Command
								</th>
								<th
									scope="col"
									className="text-left py-3 pr-4 font-bold text-text-primary"
								>
									What you get
								</th>
							</tr>
						</thead>
						<tbody className="text-body bg-card">
							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">yen ide doctor</code>
								</td>
								<td className="align-top py-2 pr-4 text-left">
									Aggregated repo health: blockers, warnings, verify / security
									/ debugger readiness, with remediation copy in text / JSON /
									env
								</td>
							</tr>
							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">yen ide debug</code>
								</td>
								<td className="align-top py-2 pr-4 text-left">
									Trust-gated Python pdb, Node inspect, and LLDB sessions,
									locally or over SSH. Node starts at entry; LLDB requires an
									executable. Attach-to-process and direct TypeScript debugging
									are not supported.
								</td>
							</tr>

							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">yen ide search</code>
								</td>
								<td className="align-top py-2 pr-4 text-left">
									Project-scoped search across files, symbols, content, history,
									diagnostics, and actions; powers the macOS{" "}
									<code className="inline-code-brand">Cmd + Shift + P</code>{" "}
									palette and adds CODEOWNERS / git-history routing hints in
									repo-backed CLI search
								</td>
							</tr>
							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">yen ide lsp</code>
								</td>
								<td className="align-top py-2 pr-4 text-left">
									Local LSP lifecycle plus hover, definition, references, code
									actions, rename, and grouped diagnostics with freshness state
								</td>
							</tr>
							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">yen ide ast</code>
								</td>
								<td className="align-top py-2 pr-4 text-left">
									Polyglot AST fallback for Python, JS / TS, Go, and Swift with
									parser-labeled engines; explicit no-fallback guidance for Rust
									/ Zig
								</td>
							</tr>
							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">
										yen ide devcontainer / vscode
									</code>
								</td>
								<td className="align-top py-2 pr-4 text-left">
									Local + remote devcontainer control and deterministic VS Code
									inventory / import with dry-run diffs and migration-report
									artifacts
								</td>
							</tr>
							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">yen ide share</code>
								</td>
								<td className="align-top py-2 pr-4 text-left">
									Terminal sharing over upterm / tmate with a
									passphrase-encrypted join token, read-only or interactive
									mode, expiry, and revoke
								</td>
							</tr>
							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">yen ide explain</code> (
									<code className="inline-code-brand">??</code>)
								</td>
								<td className="align-top py-2 pr-4 text-left">
									Failed-command explanation with project-aware hints
								</td>
							</tr>
							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">
										yen ide verify / gate
									</code>
								</td>
								<td className="align-top py-2 pr-4 text-left">
									Verification reports, evidence bundles, and approval
									checkpoints. Security scans need their external tools; missing
									tools are reported.
								</td>
							</tr>
							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">
										yen ide format / lint / fix
									</code>
								</td>
								<td className="align-top py-2 pr-4 text-left">
									Repo-native quality baseline with dry-run planning,
									changed-file scoping, and approval gating
								</td>
							</tr>
							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">yen ide workflow</code>
								</td>
								<td className="align-top py-2 pr-4 text-left">
									Repo-native task discovery + execution over package, make,
									just, and task sources, local or remote (
									<code className="inline-code-brand">ssh://...</code>)
								</td>
							</tr>
							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">
										yen ide test status / run
									</code>
								</td>
								<td className="align-top py-2 pr-4 text-left">
									Local runner discovery, failed-test replay, and watch-mode
									loops with explicit runner selection
								</td>
							</tr>
							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">
										yen ide trust status / revoke / reset
									</code>
								</td>
								<td className="align-top py-2 pr-4 text-left">
									Workspace trust records, share approvals, and local reset
									controls for trusted project state
								</td>
							</tr>
							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">yen agents</code>
								</td>
								<td className="align-top py-2 pr-4 text-left">
									Adapter board for separately installed Claude / Codex sessions
									with workspace timeline, handoff notes, and Markdown / JSON
									evidence export linked to local verify, test, and PR-review
									artifacts
								</td>
							</tr>
							<tr className="border-b border-border-light">
								<td className="align-top py-2 pl-4 pr-4">
									<code className="inline-code-brand">yen ide pr-review</code>
								</td>
								{/* biome-ignore format: keep "with raw selectable previews" contiguous on one line for the tests/154 documentation contract */}
								<td className="align-top py-2 pr-4 text-left">
								Focused PR diffs, hunk navigation, inline comments, and a desktop workspace launched from <code className="inline-code-brand">Cmd + Shift + P</code> with raw selectable previews and posting + decision actions
							</td>
							</tr>
						</tbody>
					</table>
				</TerminalPanel>
			</details>

			<details className="mb-6">
				<summary className="text-body cursor-pointer focus-ring">
					Optional local test and workflow examples
				</summary>
				<p className="text-body my-3">
					These commands run project code. Use them only in a project you trust,
					with the named runner or package script available. Review each
					command&apos;s help and grant the requested trust first.
				</p>
				<TerminalCodeBlock
					title="Terminal"
					showPrompt
					code={`yen ide test run --runner node-test --watch --watch-interval 0.5 --max-runs 3
yen ide workflow run --native package.json:test --dry-run
yen ide workflow run --native package.json:test --watch --watch-interval 0.5 --max-runs 2`}
				/>
			</details>

			<p className="text-body mt-4 mb-3">
				On macOS, <code className="inline-code-brand">Cmd + Shift + P</code>{" "}
				opens the command palette for actions and project search. It can jump
				straight to matching files and lines, and in trusted local repos it also
				launches dedicated PR review and merge-conflict workspaces.
			</p>
			<p className="text-body mb-3">
				Remote targets are supported by detect, doctor, trust status, verify
				status, workflow, devcontainer, debug, and share. Use{" "}
				<code className="inline-code-brand">ssh://user@host/absolute/path</code>{" "}
				and check the command&apos;s help for supported options. SSH probes need
				Python 3 on the remote host. Local-only options such as{" "}
				<code className="inline-code-brand">--watch</code> remain blocked
				instead of silently degrading.
			</p>
		</DocSection>
	);
}

// Source: Dictation/{DictationController,SpeechAnalyzerRecognizer,DictationTranslationProcessing}.swift; Settings/SettingsStudioPanes.swift.
function VoiceDictationSection() {
	return (
		<DocSection id="voice-dictation" title="Speech-to-Text">
			{/* Speech-to-Text Video */}
			<div className="w-full">
				<div className="aspect-video">
					<iframe
						src="https://www.youtube-nocookie.com/embed/lrdKV8-L10I?rel=0"
						title="YEN speech-to-text demo"
						allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
						allowFullScreen
						loading="lazy"
						referrerPolicy="strict-origin-when-cross-origin"
						// allow-same-origin is required: without it the YouTube player never builds (proven via prod A/B). CSP frame-src pins the host.
						sandbox="allow-scripts allow-same-origin allow-presentation allow-popups allow-popups-to-escape-sandbox"
						className="w-full h-full media-border"
					/>
				</div>
				<p className="media-caption">
					Recorded dictation demonstration. Use the setup instructions below for
					current permissions and platform requirements.
				</p>
			</div>

			<p className="text-body">
				In Settings &gt; Dictation &gt; Permissions, grant Accessibility,
				Microphone, and Speech Recognition. Focus a text field, hold
				<code className="inline-code-brand"> Option + Space</code>, speak, and
				release to paste. Use no extra modifiers.
			</p>
			<p className="text-body">
				Apple&apos;s SpeechAnalyzer transcribes on-device after language assets
				are installed. Prepare missing assets in Settings. YEN imposes no
				60-second timer on this path, but system or input errors can end a
				session. Runtime fallback uses Apple&apos;s legacy recognizer: it stops
				after 60 seconds and may use Apple&apos;s service when on-device
				recognition is unavailable. YEN receives no audio or transcripts.
			</p>
			<p className="text-body">
				Turn on Show Live Transcript in Settings &gt; Dictation to see partial
				text. Translate Dictation is off by default and requires an installed
				language pair. A translation failure inserts the original transcript.
			</p>
			<p className="text-body">
				Successful in-app paste restores the previous clipboard; cross-app paste
				leaves the transcript there.
			</p>

			{/* Recording Indicator Preview */}
			<div className="flex items-center gap-3 callout-card mb-6">
				<span className="status-indicator" aria-hidden="true">
					<span className="status-indicator-ping" aria-hidden="true" />
					<span className="status-indicator-dot" aria-hidden="true" />
				</span>
				<div>
					<h3 className="text-heading-sm mb-3">Recording indicator</h3>
					<p className="text-body">
						A recording dot blinks in the menu bar while listening. Release to
						paste.
					</p>
				</div>
			</div>

			<p className="text-body mb-4">
				Choose a microphone in Settings &gt; Dictation. System Default follows
				macOS; an unavailable selected device falls back to it. A change during
				recording stops that capture; select a device before restarting.
			</p>
			<p className="text-body mb-4">
				Secure Input blocks both clipboard writes and automatic insertion. If
				the target changes or automatic paste fails, YEN leaves the transcript
				on the clipboard for manual paste and shows a recovery notification.
			</p>

			<p className="text-body">
				<strong>Pro tip:</strong> With the fallback recognizer, release and
				press again for longer content. Enable{" "}
				<code className="inline-code-brand">Open YEN at Login</code> in Settings
				{">"} General for dictation without a terminal window open.
			</p>
		</DocSection>
	);
}

// Source: Settings/{SettingsPanel,SettingsStudioPreview,SettingsStudioPanes,SettingsShortcutsPane,SettingsController,SettingsThemeCatalog}.swift.
function AgentTokenUsageSection() {
	return (
		<DocSection id="agent-token-usage" title="Agent token usage">
			<p className="text-body">
				This experiment shows how many tokens your local coding agents used
				today. Open Settings → General → Menu Bar and turn on Show Token Usage.
				The switch is off by default.
			</p>
			<p className="text-body">
				Click the YEN icon to see each tool’s exact daily count and share.
				Provider links open the official dashboards. Use the column button to
				change the layout. Click the footer display button to cycle through
				total tokens, the top provider, rotating plan limits, and the icon
				alone.
			</p>
			<figure>
				<Image
					src="/doc-images/agent-token-usage.png"
					alt="Example token menu with 10,000 daily tokens, inline provider counts and separate Grok, Cursor and Grok Bot plan bars."
					width={730}
					height={1072}
					sizes="(max-width: 360px) 100vw, 320px"
					className="h-auto w-full max-w-xs"
				/>
				<figcaption className="media-caption">
					Example readings. Each provider’s top bar shows its share of today’s
					tokens. The smaller bars show usage within each named plan window.
				</figcaption>
			</figure>
			<ul className="list-disc space-y-2 pl-5 text-body">
				<li>
					<strong>Claude Code</strong> counts input, output, cache reads and
					cache writes. Streamed copies of a reply count once.
				</li>
				<li>
					<strong>Codex</strong> counts changes in rollout totals. Its input
					already includes cached tokens, and its output includes reasoning.
				</li>
				<li>
					<strong>Grok Build</strong> counts completed turns, including each
					model in a turn. An active turn appears after Grok records its
					completion.
				</li>
				<li>
					<strong>OpenCode</strong> counts assistant usage across gateways in
					its local database. If only session counters are available, usage
					belongs to the day the session started. Older installations can supply
					a usage log instead.
				</li>
			</ul>
			<p className="text-body">
				Plan bars show the percentage used in each named pool. For Cursor and
				Grok Bot, open the connection button and enter a personal Cursor API
				key, or use existing local plan readings from JPtheCat. Disconnect there
				to remove the key from your Mac’s Keychain. Claude, Codex, and Grok
				Build show current plan readings when their local tools record them.
			</p>
			<p className="text-body">
				An asterisk marks a partial total. Unavailable means the source could
				not be read. Zero means it was readable and recorded no tokens today.
				YEN reads these records locally. Turn the switch off to stop collection
				and remove the menu item.
			</p>
		</DocSection>
	);
}

function SettingsSection() {
	return (
		<DocSection id="settings" title="Settings">
			<p className="text-body">
				Press <code className="inline-code-brand">Cmd + ,</code>. The window is
				a live terminal preview: every appearance change shows in it at once.
				Five panes float beside it. Changes apply immediately except background
				opacity, which applies the next time you open YEN.
			</p>
			<figure>
				<Image
					src="/doc-images/settings-appearance.png"
					alt="YEN Settings on the Appearance pane: a live terminal preview on the left, the theme dock below it, and the Appearance controls in a glass panel on the right."
					width={2200}
					height={1380}
					sizes="(min-width: 768px) 720px, 100vw"
					className="w-full h-auto"
				/>
				<figcaption className="media-caption">
					Appearance: the preview shows each change as you make it.
				</figcaption>
			</figure>
			<div className="grid gap-4 sm:grid-cols-2">
				<figure>
					<Image
						src="/doc-images/settings-appearance-light.png"
						alt="The same Settings window after picking a light theme from the dock: the preview switches to the light colors."
						width={2200}
						height={1380}
						sizes="(min-width: 768px) 360px, 100vw"
						className="w-full h-auto"
					/>
					<figcaption className="media-caption">
						Pick a theme from the dock to preview it.
					</figcaption>
				</figure>
				<figure>
					<Image
						src="/doc-images/settings-shortcuts.png"
						alt="The Shortcuts pane: shortcut groups across the top and each shortcut as a button you click to record new keys."
						width={2200}
						height={1380}
						sizes="(min-width: 768px) 360px, 100vw"
						className="w-full h-auto"
					/>
					<figcaption className="media-caption">
						Shortcuts: click a shortcut, then press the new keys.
					</figcaption>
				</figure>
			</div>
			<ul className="list-disc pl-6 space-y-3 text-body">
				<li>
					<strong>Appearance:</strong> pick one of the bundled themes from the
					theme dock, then set the font, cursor, opacity, padding, a PNG or JPEG
					background image, and a border. To follow the active split, turn on
					Border and choose Focused Pane under Outline.
				</li>
				<li>
					<strong>General:</strong> open at login, copy on select, the scroll
					bar, the tab sidebar, pane labels, the scratchpad, and how terminal
					links open. Under Menu Bar, you can enable{" "}
					<a href="#agent-token-usage" className="link-brand underline">
						experimental agent token usage
					</a>
					.
				</li>
				<li>
					<strong>Notifications:</strong> command-finish alerts, one alert sound
					each for General and Build notifications, and what happens while YEN
					is active.
				</li>
				<li>
					<strong>Dictation:</strong> permissions, the microphone, the live
					transcript, and translation.
				</li>
				<li>
					<strong>Shortcuts:</strong> click a shortcut, then press the new keys.
					Conflicts with macOS and other apps show under the row. Fixed
					shortcuts are locked.
				</li>
			</ul>
			<h3 id="moving-wallpaper" className="text-heading-sm">
				Experimental moving wallpaper
			</h3>
			<p className="text-body">
				On macOS 27 or later, open General, then Experimental. Turn on Moving
				Wallpaper and click Wallpaper Controls. Choose a video or GIF, paste a
				YouTube link, pick a video from Photos, or shuffle from Photos. Use
				Wallpaper per Desktop to choose separate assignments. The same menu
				controls pause, sound, and removal.
			</p>
			<p className="text-body">
				Playback starts muted. YEN draws behind desktop icons and preserves your
				Mac’s wallpaper. Switch the feature off to reveal it immediately. YEN
				keeps your selections for next time. Standalone MovingPaper takes
				priority while it runs. Moving Wallpaper is off by default.
			</p>
			<p className="text-body">
				Reset All Settings in General restores every setting and shortcut;
				Restore Default Shortcuts in Shortcuts restores only shortcuts.
			</p>
			<details>
				<summary className="text-body cursor-pointer focus-ring">
					Advanced configuration
				</summary>
				<TerminalCodeBlock
					title="Config file"
					wrap
					code="~/Library/Application Support/com.yenchat.yen/config.yen"
				/>
				<p className="text-body">
					This file does not hold every Settings preference. Window border,
					workspace, notification, and dictation choices are stored in macOS
					preferences for YEN.
				</p>
			</details>
		</DocSection>
	);
}

// Source: yen-terminal/overlays/macos/Sources/Features/TabSidebar/; Settings/WorkspaceSettingsStore.swift.
function TabSidebarSection() {
	return (
		<DocSection id="tab-sidebar" title="Tab Sidebar">
			<p className="text-body">
				Tabs share the titlebar by default. Set{" "}
				<code className="inline-code-brand">
					macos-titlebar-style = transparent
				</code>{" "}
				to place them below it.
			</p>
			<p className="text-body">
				Press <code className="inline-code-brand">Cmd + Shift + B</code> to open
				the sidebar. Click a row to switch tabs. Click its terminal icon or
				color swatch to choose a color. To rename a tab, right-click its row and
				choose Change Title. Custom titles restore on relaunch. Press Esc to
				dismiss the transient sidebar when not editing.
			</p>
			<p className="text-body">
				The pin button switches between a transient overlay and a docked rail.
				In native fullscreen, the upper-left sidebar button opens a rail for
				that tab group. The adjacent arrows exit fullscreen. Your windowed
				sidebar preference resumes when you leave fullscreen. Quick Terminal
				does not support docking. The gear opens General settings, and New Tab
				opens another tab.
			</p>
			<p className="text-body">
				Rows show the focused split&apos;s directory, Git state, and recent task
				status when available. Untrusted local paths, remote sessions, and
				multiplexers can leave directory and Git details blank.
			</p>
		</DocSection>
	);
}

// Source: Splits/{TerminalSplitTreeView,SplitPaneLabelState}.swift; Settings/WorkspaceSettingsStore.swift.
function SplitPaneLabelsSection() {
	return (
		<DocSection id="split-pane-labels" title="Split Pane Labels">
			<p className="text-body">
				In YEN 1.282, open Settings &gt; General &gt; Panes. Comfortable gives
				each split a rounded border and space around it. Choose Compact for
				edge-to-edge panes with a thin divider. Pane Labels works with either
				style. In Appearance, set the border scope to Focused Pane to outline
				the active pane and its header.
			</p>
			<p className="text-body">
				Horizontal tabs line up on the right and expand to the left. Comfortable
				keeps the same gap below the tabs when you add the first split.
			</p>
			<p className="text-body">
				In YEN 1.277 and 1.278, enable Settings &gt; General &gt; Pane Labels to
				show a name above each split. Run{" "}
				<code className="inline-code-brand">Rename Split Label</code> to set a
				custom name. Clear it to return to automatic naming.
			</p>
			<p className="text-body">
				Turn on Name Panes After Worktree to use the worktree folder or branch.
				An agent can report its directory with{" "}
				<code className="inline-code-brand">yen pane cwd</code>. Your shell and
				new splits keep their working directory. A custom label overrides
				automatic naming and survives session restore.
			</p>
			<p className="text-body">
				Starting in YEN 1.279, split headers are on by default. Click the icon,
				name, or empty header space to focus a pane. Drag it to a highlighted
				edge to move it, or click the pencil to rename it. Headers hide in small
				or zoomed panes.
			</p>
			<p className="text-body">
				Horizontal tabs show up to three pane icons and a count for additional
				panes. The icons follow the foreground tool or terminal title. When a
				tab gets narrow, the icons hide to leave room for its name.
			</p>
			<figure>
				<Image
					src="/doc-images/split-headers.png"
					alt="Claude Code and Codex in adjacent panes. Each pane has its own icon and title, and both icons appear together in the selected tab."
					width={1600}
					height={330}
					sizes="(min-width: 768px) 720px, 100vw"
					className="w-full h-auto"
				/>
				<figcaption className="media-caption">
					The selected tab shows the two tools running in its split panes.
				</figcaption>
			</figure>
		</DocSection>
	);
}

// Source: Sessions/{PersistentSessions,PersistentSessionReaper}.swift; yen-cli/commands/core/sessions; _docs/01-architecture.md → Persistent sessions.
function PersistentSessionsSection() {
	return (
		<DocSection id="persistent-sessions" title="Persistent Sessions">
			<p className="text-body">
				With Settings &gt; General &gt; Keep Sessions Running on, the default,
				ordinary shell panes keep running when you quit YEN, when it updates, or
				if it crashes. Reopen YEN and a restored session reattaches with its
				screen and scrollback, so a build, a server, or an SSH connection
				carries on where you left it. Panes opened for an explicit command and
				panes whose session socket path exceeds 103 bytes run without
				persistence.
			</p>
			<p className="text-body">
				Quitting no longer stops what runs in your panes: a dev server keeps its
				port. Close a pane or its window to end its session. Settings &gt;
				General shows how many sessions run and has End All Sessions to stop
				them at once. In a shell,{" "}
				<code className="inline-code-brand">yen sessions</code> lists sessions
				and{" "}
				<code className="inline-code-brand">yen sessions kill &lt;id&gt;</code>{" "}
				ends one. Turning the setting off affects new panes only.
			</p>
			<p className="text-body">
				Sessions stay on your Mac and end when it restarts. With Keep Sessions
				Running on, YEN can reopen up to eight detached sessions that window
				restore missed. Use{" "}
				<code className="inline-code-brand">yen sessions</code> to find the
				others. A detached session that no window holds ends after YEN has
				watched it continuously for a day.
			</p>
		</DocSection>
	);
}

// Source: yen-terminal/customizations/yazi-config/{keymap,yazi}.toml; customizations/shell-integration/{bash,zsh}/; AppDelegate+FileBrowser.swift.
function FileBrowserSection() {
	return (
		<DocSection id="file-browser" title="File Browser">
			<p className="text-body mb-4">
				Press <code className="inline-code-brand">Cmd + Shift + O</code> to open
				the file browser in the active terminal. It does not open as a floating
				window or global sidebar, and it will not steal focus from another
				window. Browse directories, preview files, and manage the project
				without leaving the terminal.
			</p>

			<div className="callout-card mb-6">
				<h3 className="text-heading-sm mb-3">
					Terminal-native with cd-on-quit
				</h3>
				<p className="text-body">
					Launch with the shortcut or{" "}
					<code className="inline-code-brand">y</code> in a YEN bash or zsh
					shell. Press <code className="inline-code-brand">q</code> to exit and
					your shell follows the last directory you visited. The{" "}
					<code className="inline-code-brand">browse</code> command opens the
					same browser without changing the shell directory. Press{" "}
					<code className="inline-code-brand">Enter</code> on a code file for a
					colorized read-only preview, or{" "}
					<code className="inline-code-brand">O</code> for open-with.
				</p>
			</div>

			{/* File browser features table */}
			<TerminalPanel className="mb-6">
				<table className="w-full min-w-[36rem] text-body table-fixed">
					<thead>
						<tr className="border-b border-border bg-card-header">
							<th
								scope="col"
								className="text-left py-3 pl-4 pr-4 font-bold text-text-primary"
							>
								Feature
							</th>
							<th
								scope="col"
								className="text-left py-3 pr-4 font-bold text-text-primary"
							>
								Details
							</th>
						</tr>
					</thead>
					<tbody className="text-body bg-card">
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">File previews</td>
							<td className="align-top py-2 pr-4 text-left">
								Syntax-highlighted code, images, archive listings, and video /
								PDF thumbnails
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Quick Look</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Space</code> for native
								macOS preview
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								Search and fuzzy find
							</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">/</code> to find in the
								current directory, <code className="inline-code-brand">z</code>{" "}
								for fuzzy file / directory search, and{" "}
								<code className="inline-code-brand">Z</code> for frequent
								directories
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">File operations</td>
							<td className="align-top py-2 pr-4 text-left">
								Copy, move, trash or delete, bulk rename, archive extract
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								Vim + mouse navigation
							</td>
							<td className="align-top py-2 pr-4 text-left">
								h / j / k / l, visual selection, click, scroll
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								Git status indicators
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Modified, staged, untracked icons inline
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">cd-on-quit</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">q</code> to exit; shell
								follows to last directory
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								Open in editor / Finder
							</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">e</code> for $EDITOR,{" "}
								<code className="inline-code-brand">g r</code> for Finder
							</td>
						</tr>
						<tr>
							<td className="align-top py-2 pl-4 pr-4">
								Full shortcut reference
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Press <code className="inline-code-brand">?</code> inside the
								file browser
							</td>
						</tr>
					</tbody>
				</table>
			</TerminalPanel>
		</DocSection>
	);
}

// Source: WebPreview/{WebPreviewURLPolicy,BrowserCommandService,WebPreviewRepresentable}.swift; yen-cli/commands/core/web.
function BrowserPreviewSection() {
	return (
		<DocSection id="browser-preview" title="Browser Preview">
			<p className="text-body mb-4">
				Open the command palette with{" "}
				<code className="inline-code-brand">Cmd + Shift + P</code>, search{" "}
				<code className="inline-code-brand">Browser</code>,{" "}
				<code className="inline-code-brand">web preview</code>,{" "}
				<code className="inline-code-brand">localhost</code>, or{" "}
				<code className="inline-code-brand">dev server</code>, and press Enter.
				Search <code className="inline-code-brand">terminal browser</code> for{" "}
				<code className="inline-code-brand">Browser Split</code>. YEN opens a
				native WebKit window or explicit split for docs, HTTPS pages, and
				localhost/loopback development servers.
			</p>

			<div className="callout-card mb-6">
				<h3 className="text-heading-sm mb-3">Native and isolated</h3>
				<p className="text-body">
					WebKit connects directly to each site you open, and YEN does not
					receive that browsing activity. The browser uses a non-persistent
					WebKit data store. <code className="inline-code-brand">yen web</code>{" "}
					can open, navigate, reload, close, and report status, with explicit
					window, split, automatic, or focused targets for stateful commands.
					When the CLI can identify the intended app copy, status confirms the
					executable that answered. Terminal link capture is off by default,
					explicit-activation only, and controlled from Settings &gt; General
					&gt; Links. There is no bundled browser runtime.
				</p>
			</div>

			<div className="mb-6">
				<TerminalCodeBlock
					title="Terminal"
					code={`yen web open https://yen.chat/#guide
yen web open --split http://localhost:3000
yen web reload --target window
yen web status
yen web close`}
				/>
			</div>

			<TerminalPanel className="mb-6">
				<table className="w-full min-w-[36rem] text-body table-fixed">
					<thead>
						<tr className="border-b border-border bg-card-header">
							<th
								scope="col"
								className="text-left py-3 pl-4 pr-4 font-bold text-text-primary"
							>
								URL
							</th>
							<th
								scope="col"
								className="text-left py-3 pr-4 font-bold text-text-primary"
							>
								Behavior
							</th>
						</tr>
					</thead>
					<tbody className="text-body bg-card">
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">https://...</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">Opens in YEN</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">http://localhost</code>,{" "}
								<code className="inline-code-brand">127.0.0.1</code>,{" "}
								<code className="inline-code-brand">::1</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">Opens in YEN</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">mailto:</code>,{" "}
								<code className="inline-code-brand">tel:</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Hands off direct links to macOS; blocked in embedded frames
							</td>
						</tr>
						<tr>
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">file:</code>,{" "}
								<code className="inline-code-brand">data:</code>,{" "}
								<code className="inline-code-brand">javascript:</code>,
								<code className="inline-code-brand">blob:</code>, unknown
								schemes, non-local{" "}
								<code className="inline-code-brand">http:</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">Blocked</td>
						</tr>
					</tbody>
				</table>
			</TerminalPanel>
		</DocSection>
	);
}

// Source: the generated macOS app's YEN.sdef; Features/App Intents/; terminal engine src/config/Config.zig.
function AutomationSection() {
	return (
		<DocSection id="automation" title="macOS Automation">
			<p className="text-body mb-4">
				YEN also exposes actions in Apple Shortcuts. The
				<code className="inline-code-brand"> macos-shortcuts</code> config
				accepts
				<code className="inline-code-brand"> ask</code>,
				<code className="inline-code-brand"> allow</code>, or
				<code className="inline-code-brand"> deny</code>. The default asks for
				permission by action scope. Action invocation is limited to YEN&apos;s
				approved command catalog.
			</p>
			<p className="text-body mb-4">
				YEN ships a branded AppleScript dictionary for local macOS automation.
				It is enabled by default and can be disabled in{" "}
				<code className="inline-code-brand">config.yen</code> with{" "}
				<code className="inline-code-brand">macos-applescript = false</code>.
				Target YEN by absolute bundle path when scripting a specific build.
			</p>

			<TerminalPanel className="mb-6">
				<table className="w-full min-w-[36rem] text-body table-fixed">
					<thead>
						<tr className="border-b border-border bg-card-header">
							<th
								scope="col"
								className="text-left py-3 pl-4 pr-4 font-bold text-text-primary"
							>
								Surface
							</th>
							<th
								scope="col"
								className="text-left py-3 pr-4 font-bold text-text-primary"
							>
								AppleScript boundary
							</th>
						</tr>
					</thead>
					<tbody className="text-body bg-card">
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">windows</code>,{" "}
								<code className="inline-code-brand">tabs</code>,{" "}
								<code className="inline-code-brand">terminals</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Address live terminal surfaces
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">new window</code>,{" "}
								<code className="inline-code-brand">new tab</code>,{" "}
								<code className="inline-code-brand">split</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Create project workspaces with surface configuration
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">input text</code>,{" "}
								<code className="inline-code-brand">send key</code>,{" "}
								<code className="inline-code-brand">send mouse button</code>,{" "}
								<code className="inline-code-brand">send mouse position</code>,{" "}
								<code className="inline-code-brand">send mouse scroll</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Inject local input after macOS automation permission
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">pid</code>,{" "}
								<code className="inline-code-brand">tty</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Read foreground process ID and PTY path
							</td>
						</tr>
						<tr>
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">perform action</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Allowlisted command-catalog actions only
							</td>
						</tr>
					</tbody>
				</table>
			</TerminalPanel>

			<p className="text-body mb-4">
				AppleScript can create windows, tabs, and splits with an initial working
				directory and input. YEN-native overlays such as layout presets,
				scratchpad, tab sidebar, and PR review workspaces remain command-palette
				or config-driven instead of being cloned into a second scripting model.
			</p>

			<p className="text-body mb-4">
				<code className="inline-code-brand">send key</code> does not derive text
				from your active keyboard layout. Use{" "}
				<code className="inline-code-brand">input text</code> to send literal
				text.
			</p>

			<TerminalCodeBlock
				title="AppleScript"
				code={`on yenNewWindow(appPath, surfaceConfig)
	tell application appPath
		return «event GhstNWin» given «class GNwS»:surfaceConfig
	end tell
end yenNewWindow

set appPath to "/Applications/YEN.app"
set projectRoot to "/absolute/path/to/project"
set windowRef to yenNewWindow(appPath, {initial working directory:projectRoot, initial input:"git status" & linefeed})

tell application appPath
	get tty of terminal 1 of windowRef
end tell`}
			/>
		</DocSection>
	);
}

// Static documentation content (multiple shortcut tables). Length is content, not behavior — splitting further would fragment a single conceptual section.
// Source: Settings/KeybindRegistry.swift; AppDelegate.swift; yen-cli/bin/yen show_init and route_command; yen-cli/commands/core/.
// react-doctor-disable-next-line react-doctor/no-giant-component
function CommandsSection() {
	return (
		<DocSection id="commands" title="Commands & Shortcuts">
			<p className="text-body mb-4">
				Default shortcuts are listed below. Editable bindings can change in
				Settings &gt; Shortcuts.
			</p>
			<h3 className="text-heading-sm mb-3">Keyboard shortcuts:</h3>
			<TerminalPanel className="mb-6">
				<table className="w-full min-w-[36rem] text-body table-fixed">
					<thead>
						<tr className="border-b border-border bg-card-header">
							<th
								scope="col"
								className="text-left py-3 pl-4 pr-4 font-bold text-text-primary"
							>
								Action
							</th>
							<th
								scope="col"
								className="text-left py-3 pr-4 font-bold text-text-primary"
							>
								Key
							</th>
						</tr>
					</thead>
					<tbody className="text-body bg-card">
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Command palette</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + Shift + P</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Browser preview</td>
							<td className="align-top py-2 pr-4 text-left">
								Command palette &rarr; Browser / Browser Split
								<span className="block text-body">
									search web preview, localhost, or terminal browser
								</span>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Settings</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + ,</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">File browser</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + Shift + O</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Speech-to-text</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Option + Space</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Split layout presets</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + Option + 1-0</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Split in a direction</td>
							<td className="align-top py-2 pr-4 text-left">
								Hold <code className="inline-code-brand">← / → / ↑ / ↓</code>,
								then press <code className="inline-code-brand">Cmd + D</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Split right / down</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + D</code> /{" "}
								<code className="inline-code-brand">Cmd + Shift + D</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">New tab / window</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + T</code> /{" "}
								<code className="inline-code-brand">Cmd + N</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Close tab / pane</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + W</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Quick Terminal</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Ctrl + `</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								Window screenshot to file and clipboard
							</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + Shift + S</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Tab sidebar</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + Shift + B</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Scratchpad</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + Shift + J</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								Copy screen file path
							</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">
									Cmd + Ctrl + Shift + U
								</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								Paste screen file path
							</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + Shift + U</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Open screen file</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">
									Cmd + Option + Shift + U
								</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Copy-on-select</td>
							<td className="align-top py-2 pr-4 text-left">
								Select text; hold{" "}
								<code className="inline-code-brand">Shift</code> in TUI apps
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Find terminal text</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + F</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Focus adjacent split</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + Option + Arrow</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Zoom focused split</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + Shift + Enter</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Font size +/-</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + +</code> /{" "}
								<code className="inline-code-brand">Cmd + -</code>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">Toggle fullscreen</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">Cmd + Enter</code>
							</td>
						</tr>
						<tr>
							<td className="align-top py-2 pl-4 pr-4">Rename split label</td>
							<td className="align-top py-2 pr-4 text-left">
								Command palette &rarr; Rename Split Label
							</td>
						</tr>
					</tbody>
				</table>
			</TerminalPanel>

			<h3 className="text-heading-sm mb-3">CLI commands:</h3>
			<p id="shell-setup" className="text-body mb-4">
				YEN-launched bash and zsh shells include command wrappers. In an
				external shell, run{" "}
				<code className="inline-code-brand">yen init zsh</code> or{" "}
				<code className="inline-code-brand">yen init bash</code> to print setup
				code. Review and add that output to your shell startup file (
				<code className="inline-code-brand">~/.zshrc</code>, or{" "}
				<code className="inline-code-brand">~/.bashrc</code> /{" "}
				<code className="inline-code-brand">~/.bash_profile</code>), then
				restart the shell. The command does not edit those files. If yen is not
				on PATH, invoke{" "}
				<code className="inline-code-brand">
					/Applications/YEN.app/Contents/Resources/bin/yen
				</code>
				.
			</p>

			<TerminalPanel className="mb-6">
				<table className="w-full min-w-[36rem] text-body table-fixed">
					<thead>
						<tr className="border-b border-border bg-card-header">
							<th
								scope="col"
								className="text-left py-3 pl-4 pr-4 font-bold text-text-primary"
							>
								Command
							</th>
							<th
								scope="col"
								className="text-left py-3 pr-4 font-bold text-text-primary"
							>
								Description
							</th>
						</tr>
					</thead>
					<tbody className="text-body bg-card">
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">btop</code> (
								<code className="inline-code-brand">monitor</code>,{" "}
								<code className="inline-code-brand">resources</code>)
							</td>
							<td className="align-top py-2 pr-4 text-left">
								System monitor TUI (bundled btop)
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">fastfetch</code> (
								<code className="inline-code-brand">fetch</code>)
							</td>
							<td className="align-top py-2 pr-4 text-left">
								System info snapshot (bundled fastfetch)
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">bios</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								System info snapshot with YEN BIOS branding
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">browse</code> (
								<code className="inline-code-brand">files</code>,{" "}
								<code className="inline-code-brand">fm</code>)
							</td>
							<td className="align-top py-2 pr-4 text-left">File browser</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">web</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Native browser controls and optional split target
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">y</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								File browser with cd-on-quit
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">yengit</code> (
								<code className="inline-code-brand">lazygit</code>,{" "}
								<code className="inline-code-brand">gitlazy</code>,{" "}
								<code className="inline-code-brand">gityen</code>)
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Git TUI (bundled lazygit)
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">yen help</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Full command reference and aliases
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">yen ide --help</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								See{" "}
								<a href="#ide-workflows" className="link-brand underline">
									IDE Workflows
								</a>{" "}
								for capabilities and prerequisites
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">yen agents --help</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Claude / Codex adapter help; see{" "}
								<a href="#ide-workflows" className="link-brand underline">
									IDE Workflows
								</a>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">
									yen pane cwd &lt;directory&gt;
								</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Report an agent worktree from an agent or hook; use{" "}
								<code className="inline-code-brand">yen pane --help</code> for
								hook setup and clearing a report. The next shell prompt clears
								it.
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">yen sessions</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								List persistent sessions;{" "}
								<code className="inline-code-brand">attach &lt;id&gt;</code> and{" "}
								<code className="inline-code-brand">kill &lt;id&gt;</code> reach
								or end one; see{" "}
								<a href="#persistent-sessions" className="link-brand underline">
									Persistent Sessions
								</a>
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">yen +list-themes</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								List curated bundled themes
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">yen +edit-config</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Open config in $EDITOR
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">yen init zsh</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Print shell setup for external zsh
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">yen init bash</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Print shell setup for external bash
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">yen update</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Check signed release metadata (requires OpenSSL 3); install
								updates through YEN
							</td>
						</tr>
						<tr className="border-b border-border-light">
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">yen config / reload</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">
								Show the config location / reload terminal configuration
							</td>
						</tr>
						<tr>
							<td className="align-top py-2 pl-4 pr-4">
								<code className="inline-code-brand">yen --version</code>
							</td>
							<td className="align-top py-2 pr-4 text-left">Show version</td>
						</tr>
					</tbody>
				</table>
			</TerminalPanel>

			<p className="text-body mb-4">
				Need the complete command + alias reference? Run{" "}
				<code className="inline-code-brand">yen help</code>. For full file
				browser shortcuts, press <code className="inline-code-brand">?</code>{" "}
				inside the file browser.
			</p>

			<h3 className="text-heading-sm mb-3">Custom keybindings:</h3>
			<p className="text-body mb-4">
				Shortcut editing lives in <strong>Settings {">"} Shortcuts</strong>. For
				advanced changes, edit the config file directly.
			</p>
		</DocSection>
	);
}

// Source: Dictation/DictationController.swift; Settings/{SettingsController,SettingsStudioPanes,LayoutShortcutController}.swift; yen-cli/bin/yen show_init.
function TroubleshootingSection() {
	return (
		<DocSection id="troubleshooting" title="Troubleshooting">
			<ul className="list-disc list-outside pl-5 space-y-3 text-body mb-6">
				<li>
					<strong>App won&apos;t open:</strong> Right-click YEN.app, then Open,
					or allow in System Settings &gt; Privacy & Security.
				</li>
				<li>
					<strong>Commands not found:</strong> Follow the{" "}
					<a href="#shell-setup" className="link-brand underline">
						shell setup instructions
					</a>
					. In YEN, check that shell integration is enabled. Bare command
					wrappers and <code className="inline-code-brand">y</code> require bash
					or zsh.
				</li>
				<li>
					<strong>Speech-to-text not working:</strong> Grant Accessibility,
					Microphone, and Speech Recognition permissions in System Settings &gt;
					Privacy & Security. Dictation listens to exact{" "}
					<code className="inline-code-brand">Option + Space</code> only (no
					Cmd/Ctrl/Shift). Click the YEN menu bar extra (a template waveform
					when idle, or the recording-dot status item while dictation is active)
					for blocked-state recovery actions, or open Settings &gt; Dictation,
					where the permission status refreshes while the pane is open.
				</li>
				<li>
					<strong>Option + Space conflicts:</strong> Check for conflicts with
					input source, Spotlight, Alfred, or Raycast shortcuts. Use Settings
					&gt; Shortcuts for fixed-shortcut conflict guidance.
				</li>
				<li>
					<strong>Layout shortcut not firing:</strong> Use exact{" "}
					<code className="inline-code-brand">Cmd + Option + 1-0</code> with no
					extra modifiers and click a terminal window first. Layout presets are
					intentionally ignored while Settings or another utility window is key.
				</li>
				<li>
					<strong>Cursor style / blink not previewing:</strong> Changes are
					applied, but preview appears after you refocus a terminal window
					(unfocused terminals show a hollow block cursor).
				</li>
				<li>
					<strong>Opacity slider looks unchanged:</strong> Background opacity
					applies after app restart. Use Window Border for an immediate focus
					cue.
				</li>

				<li>
					<strong>File browser not opening:</strong> Verify the terminal window
					is focused, not the Settings panel or another window.
				</li>
				<li>
					<strong>Browser preview blocks a URL:</strong> Use HTTPS for remote
					pages or localhost / loopback HTTP for local development servers.
					File, data, JavaScript, blob, unknown-scheme, and non-local HTTP URLs
					are intentionally blocked.
				</li>
				<li>
					<strong>&quot;command not found: y&quot;:</strong> The cd-on-quit
					wrapper is supplied only in YEN-launched bash and zsh shells. External
					shells can use <code className="inline-code-brand">yen browse</code>,
					which does not change the shell directory.
				</li>
				<li>
					<strong>btop / fastfetch runs a system command:</strong> Check the
					<a href="#shell-setup" className="link-brand underline">
						{" "}
						shell setup
					</a>{" "}
					and restart the shell. YEN&apos;s wrappers should resolve the bundled
					tools.
				</li>
			</ul>

			<h3 className="text-heading-sm mb-3">
				Back up config.yen before resetting terminal settings:
			</h3>
			<TerminalCodeBlock
				code={
					'mv "$HOME/Library/Application Support/com.yenchat.yen/config.yen" "$HOME/Library/Application Support/com.yenchat.yen/config.yen.backup-$(date +%s)"'
				}
				title="Terminal"
				showPrompt
			/>
			<p className="text-body mt-2">
				Quit YEN before moving the file, then reopen it. This removes the
				overrides stored in{" "}
				<code className="inline-code-brand">config.yen</code> (font, cursor,
				background opacity, padding, theme, keyboard overrides). Preferences
				kept in macOS UserDefaults — Window Border, workspace and link toggles,
				dictation preview and translation state, and notification routing —
				survive this. To restore every in-app preference, open Settings (
				<code className="inline-code-brand">Cmd + ,</code>) &gt; General and use{" "}
				<strong>Reset All Settings</strong>.
			</p>
		</DocSection>
	);
}

export function ManualChapters() {
	return (
		<>
			<GetStartedSection />
			<TerminalIDESection />
			<TabSidebarSection />
			<SplitPaneLabelsSection />
			<PersistentSessionsSection />
			<ClipboardSection />
			<IDEWorkflowsSection />
			<AgentTokenUsageSection />
			<VoiceDictationSection />
			<SettingsSection />
			<FileBrowserSection />
			<BrowserPreviewSection />
			<AutomationSection />
			<CommandsSection />
			<TroubleshootingSection />
		</>
	);
}
