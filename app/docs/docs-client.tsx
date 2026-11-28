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

// A short numbered how-to that opens a chapter: one action per step.
function Steps({
	title,
	children,
}: {
	title: string;
	children: React.ReactNode;
}) {
	return (
		<div className="callout-card">
			<h3 className="text-heading-sm mb-3">{title}</h3>
			<ol className="list-decimal list-outside pl-5 space-y-2 text-body">
				{children}
			</ol>
		</div>
	);
}

// A product screenshot with a one-line caption.
function Shot({
	src,
	alt,
	caption,
	width,
	height,
	sizes = "(min-width: 768px) 720px, 100vw",
	className = "w-full h-auto",
}: {
	src: string;
	alt: string;
	caption: string;
	width: number;
	height: number;
	sizes?: string;
	className?: string;
}) {
	return (
		<figure>
			<Image
				src={src}
				alt={alt}
				width={width}
				height={height}
				sizes={sizes}
				className={className}
			/>
			<figcaption className="media-caption">{caption}</figcaption>
		</figure>
	);
}

import { TerminalCodeBlock } from "@/components/docs/terminal-code-block";
import { TerminalPanel } from "@/components/docs/terminal-panel";
import { DOWNLOAD_HREF } from "@/lib/analytics/download-cta";

// Source: yen-terminal/overlays/macos/Sources/Features/Update/UpdateController.swift; public/stable/version.json.
function GetStartedSection() {
	return (
		<DocSection id="install" title="Get Started">
			<Steps title="Install YEN">
				<li>
					<Link href={DOWNLOAD_HREF} className="link-brand underline">
						Download YEN
					</Link>{" "}
					and open the .dmg file.
				</li>
				<li>Drag YEN to Applications.</li>
				<li>Open YEN from Applications.</li>
				<li>
					Choose YEN &gt; Check for Updates to see the update status in a
					window. If the check fails, click Retry. Automatic checks are
					optional.
				</li>
			</Steps>
			<p id="requirements" className="text-body">
				YEN requires macOS 27 or later on Apple silicon. No YEN account is
				required. For an Intel Mac or macOS 13 through 26, download{" "}
				<a
					className="link-brand underline"
					href="https://github.com/8bittts/yenchat/releases/tag/v1.283"
				>
					YEN 1.283
				</a>
				, the last release for those Macs. Dictation needs extra permissions;
				see{" "}
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
			<p className="text-body">
				YEN is a native macOS terminal with IDE tools around it. Windows, tabs,
				and splits come back when you relaunch. With{" "}
				<a href="#persistent-sessions" className="link-brand underline">
					Keep Sessions Running
				</a>{" "}
				on, the programs in your panes keep running too.
			</p>
			<Steps title="Split the window">
				<li>
					Press <code className="inline-code-brand">Cmd + D</code> to split
					right, or <code className="inline-code-brand">Cmd + Shift + D</code>{" "}
					to split down.
				</li>
				<li>
					Press <code className="inline-code-brand">Cmd + Option + Arrow</code>{" "}
					to move between panes.
				</li>
				<li>
					Press <code className="inline-code-brand">Cmd + Shift + Enter</code>{" "}
					to zoom the focused pane. Press it again to restore the layout.
				</li>
				<li>
					For a preset layout, press{" "}
					<code className="inline-code-brand">Cmd + Option + 1-0</code>, or
					choose one from the File menu or the command palette. Single Pane asks
					for a second press before it closes the other panes.
				</li>
			</Steps>
			<Shot
				src="/doc-images/splits.png"
				alt="Three split panes in one tab: Git status on the left, a folder listing top right, and package.json bottom right. Each pane has a header with its folder."
				width={1738}
				height={1314}
				caption="One tab split three ways. The focused pane has the outline."
			/>
			<Steps title="Keep notes in the scratchpad">
				<li>
					Press <code className="inline-code-brand">Cmd + Shift + J</code>.
				</li>
				<li>
					Type. The notes save on your Mac and are the same in every window.
				</li>
				<li>
					Drag the title bar to move the panel, or an edge to resize it. YEN
					remembers the size.
				</li>
			</Steps>
			<Shot
				src="/doc-images/scratchpad.png"
				alt="The Scratchpad panel with a short release checklist and a list of ideas."
				width={1388}
				height={764}
				sizes="(min-width: 768px) 480px, 100vw"
				className="w-full h-auto max-w-md"
				caption="The scratchpad keeps quick notes beside your terminal."
			/>
			<ul className="list-disc list-outside pl-5 space-y-3 text-body">
				<li>
					<strong>Bundled tools:</strong> fd and rg for file-browser search,
					lazygit, btop, and fastfetch. Some IDE commands need tools you
					install; see{" "}
					<a href="#ide-workflows" className="link-brand underline">
						IDE Workflows
					</a>
					.
				</li>
				<li>
					<strong>Shell integration:</strong> bash, zsh, fish, elvish, and
					nushell are detected automatically. YEN command wrappers and
					cd-on-quit are for bash and zsh.
				</li>
			</ul>
			<h3 id="git-drawer" className="text-heading-sm">
				Local Git changes
			</h3>
			<p className="text-body">
				Run <code className="inline-code-brand">yengit</code> for Git. Use the
				command palette for PR review and merge-conflict workspaces.
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
					Dictation demo. Follow the steps below to set it up.
				</p>
			</div>

			<Steps title="Dictate into any app">
				<li>
					Open Settings &gt; Dictation and grant Accessibility, Microphone, and
					Speech Recognition.
				</li>
				<li>Click into a text field in any app.</li>
				<li>
					Hold <code className="inline-code-brand">Option + Space</code>, with
					no other modifier keys, and speak. A dot blinks in the menu bar while
					YEN listens.
				</li>
				<li>Release the keys. YEN pastes the text.</li>
			</Steps>
			<div className="flex items-center gap-3 callout-card">
				<span className="status-indicator" aria-hidden="true">
					<span className="status-indicator-ping" aria-hidden="true" />
					<span className="status-indicator-dot" aria-hidden="true" />
				</span>
				<p className="text-body">
					The recording dot in the menu bar. Release to paste.
				</p>
			</div>
			<ul className="list-disc list-outside pl-5 space-y-3 text-body">
				<li>
					<strong>On your Mac:</strong> Apple&apos;s SpeechAnalyzer transcribes
					on-device once its language assets are installed. Prepare missing
					assets in Settings. YEN receives no audio or transcripts.
				</li>
				<li>
					<strong>Fallback:</strong> when SpeechAnalyzer is unavailable, YEN
					uses Apple&apos;s legacy recognizer. It stops after 60 seconds and may
					use Apple&apos;s service. For longer text, release and press again.
				</li>
				<li>
					<strong>Live transcript and translation:</strong> turn on Show Live
					Transcript to see partial text. Translate Dictation is off by default
					and needs an installed language pair. If translation fails, YEN
					inserts the original text.
				</li>
				<li>
					<strong>Microphone:</strong> System Default follows macOS. If the
					selected device is unavailable, YEN uses System Default. Changing the
					device stops the current recording.
				</li>
				<li>
					<strong>Clipboard:</strong> a paste into YEN restores your previous
					clipboard. A paste into another app leaves the text on the clipboard.
					Secure Input blocks both the paste and the clipboard. If the target
					changes or the paste fails, YEN keeps the text on the clipboard and
					shows a notification.
				</li>
				<li>
					<strong>No window open:</strong> turn on Open YEN at Login in Settings
					&gt; General to dictate without a terminal window.
				</li>
			</ul>
		</DocSection>
	);
}

// Source: Settings/{SettingsPanel,SettingsStudioPreview,SettingsStudioPanes,SettingsShortcutsPane,SettingsController,SettingsThemeCatalog}.swift.
function AgentTokenUsageSection() {
	return (
		<DocSection id="agent-token-usage" title="Agent token usage">
			<p className="text-body">
				An experiment that shows how many tokens your local coding agents used
				today. It is off by default.
			</p>
			<Steps title="See today&apos;s token usage">
				<li>
					Open Settings &gt; General &gt; Experimental and turn on Show Token
					Usage.
				</li>
				<li>
					Click the YEN item in the menu bar. Daily counts include cached
					tokens. A tool appears when it recorded tokens today or reports
					positive usage in a displayed plan window.
				</li>
				<li>
					Click the chart button to see the last 7, 30, and 90 days and your
					busiest hours of the week. The first 90-day read can take half a
					minute.
				</li>
				<li>
					Right-click the menu bar item to refresh, check for updates, or quit
					YEN.
				</li>
			</Steps>
			<Shot
				src="/doc-images/agent-token-usage.png"
				alt="Example token menu showing daily counts including cached tokens and weekly plan usage for active tools."
				width={730}
				height={626}
				sizes="(max-width: 360px) 100vw, 320px"
				className="h-auto w-full max-w-xs"
				caption="Daily totals include cached tokens. Each bar shows the last reported usage for its named plan."
			/>
			<ul className="list-disc list-outside pl-5 space-y-3 text-body">
				<li>
					<strong>Links:</strong> click a provider name or a plan label to open
					its official dashboard.
				</li>
				<li>
					<strong>Menu bar text:</strong> click the menu bar button in the panel
					header to cycle through total tokens, the top provider, rotating
					limits (for example 514M · Claude 64%), and the icon alone. The column
					button changes the layout.
				</li>
				<li>
					<strong>Plan bars:</strong> show the percentage used in each named
					pool when a local reading is available: Weekly and Fable weekly for
					Claude, Weekly for Codex, and the subscription pool for Grok Build.
					Claude Code shares its limits only with its statusline, so turn on
					Claude Plan Limits to add a marked block to your statusline script.
					Turning it off removes the block.
				</li>
				<li>
					<strong>Folders:</strong> the panel lists the five folders where
					agents used the most tokens today, and each tab in the tab sidebar
					shows today&apos;s tokens for its folder.
				</li>
				<li>
					<strong>Limit alerts:</strong> on by default under Show Token Usage. A
					plan pool that reaches 80% and then 95% sends one notification each
					per window, with JP the Cat&apos;s meow. Settings &gt; Notifications
					&gt; Usage Limits changes the sound.
				</li>
				<li>
					<strong>Terminal:</strong> run{" "}
					<code className="inline-code-brand">yen usage</code> for today&apos;s
					counts, limits, and top folders;{" "}
					<code className="inline-code-brand">yen usage --json</code> prints
					them for scripts and agents, and{" "}
					<code className="inline-code-brand">yen usage --here</code> shows the
					current folder.
				</li>
				<li>
					<strong>Readings:</strong> an asterisk marks a partial total. A
					readable source can be idle. OpenCode appears in the overview only
					after it records tokens that day.
				</li>
			</ul>
			<details>
				<summary className="text-body cursor-pointer focus-ring">
					What each tool counts
				</summary>
				<ul className="list-disc list-outside pl-5 space-y-2 text-body">
					<li>
						<strong>Claude Code:</strong> input, output, cache reads, and cache
						writes. Streamed copies of a reply count once.
					</li>
					<li>
						<strong>Codex:</strong> changes in rollout totals. Input already
						includes cached tokens, and output includes reasoning.
					</li>
					<li>
						<strong>Grok Build:</strong> completed turns, including each model
						in a turn, plus each finished request of a turn still running.
					</li>
					<li>
						<strong>OpenCode:</strong> assistant usage across gateways in its
						local database. With only session counters, usage belongs to the day
						the session started. Older installations can supply a usage log
						instead.
					</li>
				</ul>
			</details>
			<p className="text-body">
				YEN reads these records on your Mac, keeps each finished day&apos;s
				total there, and makes no network request for these numbers. Turn the
				switch off to stop and remove the menu item.
			</p>
		</DocSection>
	);
}

function SettingsSection() {
	return (
		<DocSection id="settings" title="Settings">
			<Steps title="Change a setting">
				<li>
					Press <code className="inline-code-brand">Cmd + ,</code>.
				</li>
				<li>
					Choose a pane: Appearance, General, Notifications, Dictation, or
					Shortcuts.
				</li>
				<li>
					Change the setting. The terminal preview shows it at once. Background
					opacity applies the next time you open YEN.
				</li>
			</Steps>
			<Shot
				src="/doc-images/settings-appearance.png"
				alt="YEN Settings on the Appearance pane: a live terminal preview on the left, the theme dock below it, and the Appearance controls in a glass panel on the right."
				width={2200}
				height={1380}
				caption="Appearance: the preview shows each change as you make it."
			/>
			<div className="grid gap-4 sm:grid-cols-2">
				<Shot
					src="/doc-images/settings-appearance-light.png"
					alt="The same Settings window after picking a light theme from the dock: the preview and the Settings panel switch to the light colors."
					width={2200}
					height={1380}
					sizes="(min-width: 768px) 360px, 100vw"
					caption="Pick a theme from the dock to preview it."
				/>
				<Shot
					src="/doc-images/settings-shortcuts.png"
					alt="The Shortcuts pane: shortcut groups across the top and each shortcut as a button you click to record new keys."
					width={2200}
					height={1380}
					sizes="(min-width: 768px) 360px, 100vw"
					caption="Shortcuts: click a shortcut, then press the new keys."
				/>
			</div>
			<ul className="list-disc pl-6 space-y-3 text-body">
				<li>
					<strong>Appearance:</strong> the theme, font, cursor, opacity,
					padding, a PNG or JPEG background image, and a border. To outline the
					active split, turn on Border and choose Focused Pane under Outline.
					Spark sends a light around that outline, and Spark Speed sets how fast
					it travels, from Slowww to Fffast. Aura adds a soft glow that pulses
					in the color and at the speed you pick.
				</li>
				<li>
					<strong>General:</strong> open at login, copy on select, the scroll
					bar, the tab sidebar, panes, and how terminal links open. Under
					Experimental, you can turn on{" "}
					<a href="#agent-token-usage" className="link-brand underline">
						agent token usage
					</a>{" "}
					and{" "}
					<a href="#moving-wallpaper" className="link-brand underline">
						moving wallpaper
					</a>
					.
				</li>
				<li>
					<strong>Notifications:</strong> command-finish alerts, one sound each
					for General, Build, and Usage Limits alerts (a macOS sound or JP the
					Cat), and what happens while YEN is active.
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
			<Steps title="Set a moving wallpaper">
				<li>
					Open Settings &gt; General &gt; Experimental and turn on Moving
					Wallpaper.
				</li>
				<li>
					Click Demo to try a sample video. Click it again for another one.
				</li>
				<li>
					Or click Choose File, YouTube URL, From Photos, or Shuffle Photos to
					use your own video or GIF.
				</li>
				<li>
					For a different wallpaper on each desktop, turn on Wallpaper per
					Desktop.
				</li>
			</Steps>
			<p className="text-body">
				Playback starts muted. The Pause, Sound, and Remove buttons control the
				wallpaper. Demo downloads each sample from yen.chat the first time it
				plays. A YouTube link downloads at up to 1080p with its sound, and
				Shuffle from Photos can ask for access to your library. With Wallpaper
				per Desktop, a per-desktop wallpaper on an external display comes back
				when you plug the display in again, even though macOS gives that display
				new desktops.
			</p>
			<p className="text-body">
				YEN draws behind your desktop icons and keeps your Mac&apos;s own
				wallpaper. Turn the feature off to see it again at once. YEN keeps your
				choices for next time. Standalone MovingPaper takes priority while it
				runs.
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
			<Steps title="Use the tab sidebar">
				<li>
					Press <code className="inline-code-brand">Cmd + Shift + B</code>.
				</li>
				<li>Click a row to switch to that tab.</li>
				<li>Click a row&apos;s terminal icon to give the tab a color.</li>
				<li>
					To rename a tab, right-click its row and choose Change Title. Custom
					titles come back when you relaunch.
				</li>
				<li>
					Click the pin button to keep the sidebar docked. Unpinned, it closes
					when you press Esc.
				</li>
			</Steps>
			<Shot
				src="/doc-images/tab-sidebar.png"
				alt="The docked tab sidebar with three tabs named acme-web, dev server, and tests. Each row shows the folder, the Git branch, and its Command-number shortcut. A collapsed Hosts section sits below."
				width={1440}
				height={760}
				caption="Each row shows the tab&apos;s folder, Git state, and shortcut."
			/>
			<p className="text-body">
				Each row shows the focused split&apos;s folder, Git state, and recent
				task status. Untrusted local paths, remote sessions, and multiplexers
				can leave the folder and Git details blank. A globe icon marks a tab
				attached to another Mac, and stacked rectangles mark a tab whose panes
				keep running when YEN quits. Hover an icon to read what it means. The
				Hosts section below the tabs lists your other Macs; see{" "}
				<a href="#remote-sessions" className="link-brand underline">
					Remote sessions
				</a>
				.
			</p>
			<p className="text-body">
				In native fullscreen, the sidebar button in the upper left opens a rail
				for that window, and the arrows beside it exit fullscreen. Quick
				Terminal cannot dock the sidebar. The gear opens General settings, and
				New Tab opens a tab. Tabs share the titlebar by default; set{" "}
				<code className="inline-code-brand">
					macos-titlebar-style = transparent
				</code>{" "}
				to put them below it.
			</p>
		</DocSection>
	);
}

// Source: Splits/{TerminalSplitTreeView,SplitPaneLabelState}.swift; Settings/WorkspaceSettingsStore.swift.
function SplitPaneLabelsSection() {
	return (
		<DocSection id="split-pane-labels" title="Split Pane Labels">
			<p className="text-body">
				Each split has a header with its icon and name. Pane Labels is on by
				default in Settings &gt; General &gt; Panes.
			</p>
			<Shot
				src="/doc-images/split-headers.png"
				alt="Claude Code and Codex in adjacent panes. Each pane header shows its own icon and title."
				width={1600}
				height={258}
				caption="Two split panes, each with its own header."
			/>
			<Steps title="Work with split headers">
				<li>Click a header to focus its pane.</li>
				<li>Drag a header to a highlighted edge to move the pane.</li>
				<li>
					Click the pencil to rename the pane. Clear the name to go back to
					automatic naming. You can also run{" "}
					<code className="inline-code-brand">Rename Split Label</code> from the
					command palette.
				</li>
			</Steps>
			<ul className="list-disc list-outside pl-5 space-y-3 text-body">
				<li>
					<strong>Pane style:</strong> Comfortable gives each split a rounded
					border and space around it. Compact puts panes edge to edge with a
					thin divider. To outline the active pane, set the border to Focused
					Pane in Appearance.
				</li>
				<li>
					<strong>Worktree names:</strong> turn on Name Panes After Their
					Worktree to name a pane after its worktree folder or branch. An agent
					can report its folder with{" "}
					<code className="inline-code-brand">yen pane cwd</code>. A custom name
					wins over automatic naming and survives session restore.
				</li>
				<li>
					<strong>Tabs:</strong> a tab with splits shows its pane count on the
					right. Hold Command to see each tab&apos;s Cmd + 1-9 shortcut. Headers
					hide in small or zoomed panes.
				</li>
			</ul>
		</DocSection>
	);
}

// Source: Sessions/{PersistentSessions,PersistentSessionReaper,TailscalePeers,RemoteSessions,RemotePanes}.swift; yen-cli/commands/core/sessions; yen-cli/lib/sessions-remote.sh; _docs/01-architecture.md → Persistent sessions.
function PersistentSessionsSection() {
	return (
		<DocSection id="persistent-sessions" title="Persistent Sessions">
			<p className="text-body">
				Your shell panes keep running when you quit YEN, when it updates, or if
				it crashes. Reopen YEN and each pane comes back with its screen and
				scrollback, so a build, a dev server, or an SSH connection carries on.
				Keep Sessions Running in Settings &gt; General is on by default.
			</p>
			<Steps title="Manage running sessions">
				<li>
					To end one session, close its pane or window. Quitting YEN does not
					end it.
				</li>
				<li>
					To see what runs, open Settings &gt; General, or run{" "}
					<code className="inline-code-brand">yen sessions</code> in a shell.
				</li>
				<li>
					To end sessions, click End All Sessions in Settings &gt; General, or
					run{" "}
					<code className="inline-code-brand">
						yen sessions kill &lt;id&gt;
					</code>
					.
				</li>
			</Steps>
			<p className="text-body">
				A tab whose panes all run in sessions shows a stacked-rectangles icon,
				labeled Live session: keeps running when YEN quits. Panes opened for an
				explicit command, and panes whose session socket path exceeds 103 bytes,
				do not persist. Turning the setting off affects new panes only.
			</p>
			<p className="text-body">
				Sessions stay on your Mac and end when it restarts. YEN can reopen up to
				eight detached sessions that window restore missed; use{" "}
				<code className="inline-code-brand">yen sessions</code> to find the
				others. A detached session that no window holds ends after YEN has
				watched it for a day.
			</p>
			<h3 id="remote-sessions" className="text-heading-sm">
				Remote sessions
			</h3>
			<p className="text-body">
				Attach to a persistent session that runs on another of your Macs. YEN
				connects with the system <code className="inline-code-brand">ssh</code>{" "}
				over your Tailscale network. It runs no relay, needs no YEN account, and
				sends nothing to YEN.
			</p>
			<Steps title="Attach to a session on another Mac">
				<li>Sign in to the same Tailscale account on both Macs.</li>
				<li>
					On the other Mac, turn on Remote Login in System Settings &gt; General
					&gt; Sharing, and keep Keep Sessions Running on.
				</li>
				<li>
					Press <code className="inline-code-brand">Cmd + Shift + P</code> and
					type <code className="inline-code-brand">hosts</code>.
				</li>
				<li>
					Select a session. YEN opens it in a new tab, or focuses the pane that
					already shows it.
				</li>
			</Steps>
			<ul className="list-disc pl-5 space-y-2 text-body">
				<li>
					<strong>Both Macs:</strong> YEN, and Tailscale signed in to the same
					Tailscale account. YEN lists only your own Macs that run the Tailscale
					app or daemon, not devices shared with you, devices whose Tailscale
					key expired, or Tailscale nodes that other apps embed.
				</li>
				<li>
					<strong>The other Mac:</strong> Keep Sessions Running on, and an SSH
					server. On a Mac with the Tailscale app from the App Store or the
					Tailscale website, turn on Remote Login in System Settings &gt;
					General &gt; Sharing. Those Tailscale apps cannot act as a Tailscale
					SSH server; the open-source command-line Tailscale can. With Tailscale
					SSH on the other Mac, a remote pane that cannot attach shows the
					reason from that Mac and closes when you press Return.
				</li>
				<li>
					<strong>Sign-in:</strong> YEN lists sessions without prompting, so
					signing in must work without a password, for example with an SSH key.
					Your Tailscale access rules must also let this Mac reach the other
					Mac.
				</li>
			</ul>
			<p className="text-body">
				When you type <code className="inline-code-brand">hosts</code>, YEN
				checks your Tailscale network and lists each Mac with its sessions. YEN
				connects to a Mac by its Tailscale name when that name resolves on this
				Mac to that Mac&apos;s Tailscale address, and by its Tailscale address
				otherwise, so the first-connection step may name the address. Sessions
				come first, newest first, then Macs that need a step from you, then Macs
				that are offline or out of reach. YEN looks for your Macs and their
				sessions only while you have asked for hosts, and Hosts: Refresh Remote
				Sessions checks again. A remote pane stays connected to its own Mac.
			</p>
			<p className="text-body">
				The tab sidebar has a Hosts section below your tabs, with the same rows
				as Hosts in the palette. It starts collapsed. YEN looks for your Macs
				only while the section is expanded and the sidebar is on screen; a
				background tab, a minimized window, or another Space does not count. A
				tab with a pane attached to a session on another Mac shows a globe icon,
				and its tooltip names that Mac, as in Remote session on studio. Detached
				sessions, which no tab shows, appear only in Hosts.
			</p>
			<p className="text-body">
				The first time, the palette asks you to trust the other Mac&apos;s host
				key. Select <strong>Trust the Host Key of &lt;Mac&gt;</strong> to type{" "}
				<code className="inline-code-brand">ssh &lt;Mac&gt;</code> at your
				prompt, then run it and confirm the key. If the other Mac asks for a
				password, select <strong>Set Up Key Sign-In for &lt;Mac&gt;</strong> to
				type <code className="inline-code-brand">ssh-copy-id &lt;Mac&gt;</code>,
				and run it once. If Tailscale asks you to approve a sign-in, select{" "}
				<strong>Approve &lt;Mac&gt; in Tailscale</strong> to type{" "}
				<code className="inline-code-brand">ssh &lt;Mac&gt;</code>, run it, and
				open the link it shows. An attach pane also shows the approval link. The
				approval lasts for your tailnet&apos;s check period. Leave the pane open
				while you approve the sign-in. The same pane connects after approval. If
				the other Mac&apos;s host key changes, YEN stops connecting to it until
				you fix <code className="inline-code-brand">~/.ssh/known_hosts</code>.
			</p>
			<p className="text-body">
				A remote pane&apos;s tab title starts with the other Mac&apos;s name, as
				in <code className="inline-code-brand">studio · zsh</code>, and its
				split header shows that name instead of a local folder. A split or tab
				you open from a remote pane is a local shell. If the connection drops,
				YEN reconnects after 1, 2, 4, 8, 16, then every 30 seconds until you
				press <code className="inline-code-brand">Ctrl + C</code>. The session
				keeps running on the other Mac, and its screen comes back when YEN
				reattaches. Quit YEN and a restored remote pane reattaches at the next
				launch, waiting for the network if it is not up yet. When the session
				ends, its pane closes; if YEN cannot attach, the pane shows why until
				you press Return. Closing a remote pane, tab, or window only detaches:
				YEN does not ask, and the session keeps running on the other Mac.
			</p>
			<p className="text-body">
				While YEN reconnects a remote tab to its Mac, the tab&apos;s globe icon
				is struck through, and its tooltip reads Reconnecting to &lt;Mac&gt;.
				The pane shows when the next attempt runs, and the icon returns to the
				plain globe as soon as the session is back. Press{" "}
				<code className="inline-code-brand">Ctrl + C</code> in the pane to stop
				trying; the session keeps running on the other Mac. With{" "}
				<code className="inline-code-brand">progress-style = false</code> in
				config.yen, no tab shows this marker.
			</p>
			<TerminalCodeBlock
				title="Terminal"
				showPrompt
				code={`yen sessions list --host studio
yen sessions attach --host studio <id>`}
			/>
			<p className="text-body">
				In a shell, <code className="inline-code-brand">--host</code> takes the
				other Mac&apos;s Tailscale name or address, with an optional{" "}
				<code className="inline-code-brand">user@</code>.{" "}
				<code className="inline-code-brand">yen sessions kill</code> only ends
				sessions on this Mac; end a remote session from a shell inside it. Run{" "}
				<code className="inline-code-brand">yen sessions --help</code> for the
				exit codes.
			</p>
		</DocSection>
	);
}

// Source: yen-terminal/customizations/yazi-config/{keymap,yazi}.toml; customizations/shell-integration/{bash,zsh}/; AppDelegate+FileBrowser.swift.
function FileBrowserSection() {
	return (
		<DocSection id="file-browser" title="File Browser">
			<Steps title="Browse files">
				<li>
					Press <code className="inline-code-brand">Cmd + Shift + O</code>, or
					type <code className="inline-code-brand">y</code> in a bash or zsh
					pane. The browser opens inside the active terminal.
				</li>
				<li>
					Move with the arrow keys, h / j / k / l, or the mouse. The right
					column previews the selected file.
				</li>
				<li>
					Press <code className="inline-code-brand">Enter</code> on a code file
					to read it, <code className="inline-code-brand">e</code> to edit it,
					or <code className="inline-code-brand">Space</code> for Quick Look.
				</li>
				<li>
					Press <code className="inline-code-brand">q</code> to quit. Your shell
					moves to the last folder you visited.
				</li>
			</Steps>
			<Shot
				src="/doc-images/file-browser.png"
				alt="The file browser in a terminal pane: the folder list on the left, the files in the middle, and a syntax-highlighted preview of cart.tsx on the right."
				width={1736}
				height={1312}
				caption="Folders on the left, files in the middle, and a preview on the right."
			/>
			<p className="text-body">
				The <code className="inline-code-brand">browse</code> command opens the
				same browser without changing your shell&apos;s folder. Press{" "}
				<code className="inline-code-brand">O</code> to open a file with another
				app.
			</p>
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
							<td className="align-top py-2 pl-4 pr-4">Search</td>
							<td className="align-top py-2 pr-4 text-left">
								<code className="inline-code-brand">/</code> to find in the
								current directory, <code className="inline-code-brand">s</code>{" "}
								to search by name, and{" "}
								<code className="inline-code-brand">S</code> to search file
								contents. <code className="inline-code-brand">z</code> opens
								fuzzy search and <code className="inline-code-brand">Z</code>{" "}
								lists frequent directories; these two need fzf and zoxide
								installed
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
			<Steps title="Preview a page beside your terminal">
				<li>
					Press <code className="inline-code-brand">Cmd + Shift + P</code>.
				</li>
				<li>
					Type <code className="inline-code-brand">Browser Split</code> to open
					the page in a split, or{" "}
					<code className="inline-code-brand">Browser</code> for a window.
					Searching <code className="inline-code-brand">localhost</code>,{" "}
					<code className="inline-code-brand">dev server</code>, or{" "}
					<code className="inline-code-brand">web preview</code> finds them too.
				</li>
				<li>Press Enter, then type an HTTPS or localhost address.</li>
			</Steps>
			<Shot
				src="/doc-images/command-palette.png"
				alt="The command palette open over a terminal, with Browser and Browser Split at the top of the list."
				width={1160}
				height={580}
				sizes="(min-width: 768px) 560px, 100vw"
				className="w-full h-auto max-w-xl"
				caption="Browser and Browser Split in the command palette."
			/>
			<p className="text-body">
				From a shell,{" "}
				<code className="inline-code-brand">
					yen web open --split http://localhost:3000
				</code>{" "}
				does the same. YEN opens docs, HTTPS pages, and localhost or loopback
				development servers in a native WebKit window or split.
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
				<code className="inline-code-brand">send key</code> translates each key
				once through your active keyboard layout, and a dead key does not
				combine with the next key. Use{" "}
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
								<code className="inline-code-brand">fetch</code>,{" "}
								<code className="inline-code-brand">fast</code>)
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
								. <code className="inline-code-brand">--host &lt;mac&gt;</code>{" "}
								lists and attaches sessions on another Mac; see{" "}
								<a href="#remote-sessions" className="link-brand underline">
									Remote sessions
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
					<strong>App won&apos;t open:</strong> Open System Settings &gt;
					Privacy & Security and click Open Anyway.
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
