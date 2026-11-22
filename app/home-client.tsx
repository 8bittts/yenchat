import Image from "next/image";
import Link from "next/link";
import { OperatorGuide } from "@/components/home/operator-guide";
import { SessionDemo, SplitDemo } from "@/components/home/workspace-demos";
import { PageShell } from "@/components/shared/page-shell";
import { TrackedDownloadLink } from "@/components/shared/tracked-download-link";
import { getVersionFilename } from "@/lib/version-format";

import stable from "@/public/stable/version.json";

const releaseNotes = "https://blog.yen.chat/releases";
const repository = "https://github.com/8bittts/yenchat";
const milestones = [
	[
		"1.283",
		"Today’s agent usage, one click away.",
		"An optional menu bar counter reads local agent records. Moving Wallpaper brings video behind the desktop icons on macOS 27.",
	],
	[
		"1.282",
		"An outline all the way around.",
		"The active border follows the header and both bottom corners. Rounded gutters and a compact divider give you two ways to separate panes.",
	],
	[
		"1.279",
		"Move the pane by its name.",
		"Drag a split by its header. Click the pencil to call it “server” and keep that name as you rearrange the window.",
	],
	[
		"1.277",
		"An update can find the old shell.",
		"Each session records which backend started it. A newer YEN can reconnect to a shell still running under the previous build.",
	],
	[
		"1.275",
		"Quitting detaches the shell.",
		"Ordinary panes keep running by default. When YEN opens again, a restored pane reattaches with its screen and scrollback.",
	],
];

function Monitor() {
	return (
		<figure className="ph-machine">
			<div className="ph-crt">
				<div className="ph-face">
					<Image
						src="/yen-logo-square-512.png"
						width={512}
						height={512}
						sizes="(max-width: 700px) 65vw, 440px"
						alt="YEN’s green phosphor mark on a CRT screen"
						loading="eager"
					/>
					<span aria-hidden="true">YEN TERMINAL</span>
				</div>
				<div className="ph-bezel" aria-hidden="true">
					<i /> YEN <b />
				</div>
			</div>
		</figure>
	);
}
function Download({ location }: { location: string }) {
	return (
		<TrackedDownloadLink className="ph-download" location={location}>
			Download for macOS <span aria-hidden="true">↓</span>
		</TrackedDownloadLink>
	);
}
export function HomeClient({ version }: { version: string }) {
	return (
		<div className="ph-site">
			<PageShell currentPage="home">
				<section className="ph-hero">
					<div className="ph-wrap ph-hero-grid">
						<div>
							<p className="ph-kicker">
								<i />
								Native macOS terminal
							</p>
							<h1>
								Quit the app.
								<br /> <em>Keep the shell.</em>
							</h1>
							<p className="ph-hero-lede">
								Your dev server keeps its port. Your shell keeps its scrollback.
								Reopen YEN and you’re back in the same running session.
							</p>
							<div className="ph-actions">
								<Download location="hero" />
								<Link className="ph-text-link" href="#sessions">
									Try the session demo ↓
								</Link>
							</div>
							<p className="ph-requirements">
								Free · macOS {Number.parseInt(stable.minOS, 10)}+ ·{" "}
								{Number.parseInt(stable.minOS, 10) >= 27
									? "Apple silicon"
									: "Apple silicon and Intel"}
							</p>
						</div>
						<Monitor />
					</div>
				</section>
				<div className="ph-instrument">
					<div className="ph-wrap">
						<Link href="#releases">YEN / v{version}</Link>
						<span>Ghostty engine · Metal renderer</span>
						<span>Solo-built · MIT</span>
					</div>
				</div>
				<nav aria-label="On this page" className="ph-chapters">
					<div className="ph-wrap">
						<Link href="#sessions">Sessions</Link>
						<Link href="#splits">Split panes</Link>
						<Link href="#experiments">Experiments</Link>
						<Link href="#guide">Field guide</Link>
						<Link href="#releases">Release log</Link>
					</div>
				</nav>
				<section className="ph-section ph-dark" id="sessions">
					<div className="ph-wrap ph-feature-grid">
						<div>
							<p className="ph-kicker">Persistent sessions</p>
							<h2>Watch the port.</h2>
							<p className="ph-lede">
								A dev server shouldn’t need a restart because its terminal quit.
								YEN keeps the process running on your Mac, even through an app
								update.
							</p>
							<p className="ph-instruction">
								Try it here. Quit the simulated app, send a request, then reopen
								YEN. Look for that request in your scrollback.
							</p>
						</div>
						<SessionDemo />
					</div>
				</section>
				<section className="ph-section ph-dark ph-split-section" id="splits">
					<div className="ph-wrap ph-feature-grid">
						<div>
							<p className="ph-kicker">Focused split panes</p>
							<h2>Know where the next key goes.</h2>
							<p className="ph-lede">
								Two shells can look alike. A continuous outline wraps the active
								pane, right around its header. A named split keeps its label
								when you drag it to another position.
							</p>
							<p className="ph-instruction">
								Select a pane in the preview. Watch the outline follow your
								focus. Switch to Compact to trade the gutter for a thin divider.
							</p>
						</div>
						<SplitDemo />
					</div>
				</section>
				<section
					className="ph-section ph-native"
					aria-labelledby="native-title"
				>
					<div className="ph-wrap ph-native-grid">
						<figure>
							<a
								href="/doc-images/settings-appearance.png"
								aria-label="Open full-size YEN Appearance screenshot"
							>
								<Image
									src="/doc-images/settings-appearance.png"
									width={2200}
									height={1380}
									sizes="(max-width: 700px) 88vw, 52vw"
									alt="YEN Appearance settings over a live terminal with the theme dock below and native controls to the right"
								/>
							</a>
							<figcaption>
								Appearance in YEN{" "}
								<a href="/doc-images/settings-appearance.png">
									View full size ↗
								</a>
							</figcaption>
						</figure>
						<div>
							<p className="ph-kicker">Inside the Mac app</p>
							<h2 id="native-title">A real terminal in Settings.</h2>
							<p className="ph-lede">
								Pick a theme and see it on a running terminal. Adjust the font,
								padding, or border against the same glyphs you’ll read all day.
							</p>
							<p className="ph-instruction">
								Ghostty renders the terminal with Metal. Native macOS controls
								handle the settings. The desktop app sends no terminal content
								or usage telemetry to YEN.
							</p>
							<Link className="ph-text-link" href="#settings">
								Explore the settings →
							</Link>
						</div>
					</div>
				</section>
				<section id="experiments" className="ph-section ph-dark">
					<div className="ph-wrap ph-feature-grid">
						<div>
							<p className="ph-kicker">Experiments / Menu bar</p>
							<h2>What did your agents use today?</h2>
							<p className="ph-lede">
								Run Claude Code in one pane and Codex in another. Open the YEN
								menu to see their token counts for the day, including work you
								did outside YEN.
							</p>
							<a className="ph-text-link" href="#agent-token-usage">
								See how each tool counts →
							</a>
						</div>
						<figure className="ph-token-figure">
							<Image
								src="/doc-images/agent-token-usage.png"
								width={640}
								height={848}
								sizes="(max-width: 700px) 70vw, 320px"
								alt="YEN’s menu bar breakdown with the Codex token count expanded"
							/>
							<figcaption>
								Local usage records · Four supported tools
							</figcaption>
						</figure>
					</div>
					<div className="ph-wrap ph-wallpaper">
						<div>
							<p className="ph-kicker">Experiments / macOS 27+</p>
							<h3>A moving desktop between builds.</h3>
						</div>
						<div>
							<p>
								Choose a video, GIF, YouTube link, or a clip from Photos. YEN
								plays it behind the desktop icons, muted at first. Give each
								desktop its own selection, or switch it off to return to your
								wallpaper.
							</p>
							<a className="ph-text-link" href="#moving-wallpaper">
								Open the wallpaper controls guide →
							</a>
						</div>
					</div>
				</section>
				<OperatorGuide />
				<section id="releases" className="ph-section ph-releases">
					<div className="ph-wrap">
						<div className="ph-log-head">
							<div>
								<p className="ph-kicker">Independent development</p>
								<h2>What one engineer shipped.</h2>
							</div>
							<a className="ph-text-link" href={releaseNotes}>
								All release notes ↗
							</a>
						</div>
						<p className="ph-log-intro">
							YEN started in 2025. Follow the releases from persistent shell
							processes to focused split outlines and local agent usage.
						</p>
						<ol>
							{milestones.map(([v, title, body]) => (
								<li key={v}>
									<a href={`${repository}/releases/tag/v${v}`}>v{v} ↗</a>
									<h3>{title}</h3>
									<p>{body}</p>
								</li>
							))}
						</ol>
					</div>
				</section>
				<section className="ph-final">
					<div className="ph-wrap">
						<div>
							<p className="ph-kicker">YEN for macOS</p>
							<h2>Try it on your Mac.</h2>
							<p>Start a server. Split the window. Quit and come back.</p>
						</div>
						<div>
							<Download location="home-footer" />
							<div className="ph-verify">
								<a
									href={`/stable/yen-${getVersionFilename(version)}.dmg.sha256`}
								>
									SHA256
								</a>
								<span>·</span>
								<Link href="#install">Install guide</Link>
								<span>·</span>
								<a href={repository}>Source ↗</a>
							</div>
						</div>
					</div>
				</section>
			</PageShell>
		</div>
	);
}
