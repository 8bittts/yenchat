import type { ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import stable from "../../../public/stable/version.json";

const manualUrl = "https://yen.chat/docs";
const github = "https://github.com/8bittts/yenchat";
const notes = "https://blog.yen.chat/releases";
const concepts = [
	{
		slug: "phosphor",
		name: "Phosphor",
		pitch: "A dark, hands-on introduction to persistent sessions.",
	},
	{
		slug: "field-manual",
		name: "Field Manual",
		pitch: "An illustrated operator’s guide that doubles as the homepage.",
	},
	{
		slug: "workshop",
		name: "Workshop",
		pitch: "A solo engineer’s journal, told through the details that shipped.",
	},
] as const;
function Brand() {
	return (
		<a href="/" className="brand" aria-label="YEN concept index">
			<img src="/assets/mark.png" width="30" height="30" alt="" />
			YEN
		</a>
	);
}
function Nav({ name }: { name: string }) {
	return (
		<header>
			<Brand />
			<span className="edition mono">{name}</span>
			<nav aria-label="Page navigation">
				<a href="#guide">Guide</a>
				<a href="#releases">Releases</a>
				<a className="index-link" href="/">
					Concepts <span>↗</span>
				</a>
			</nav>
		</header>
	);
}
function Download({ children }: { children?: ReactNode }) {
	return (
		<a className="download" href="https://yen.chat/download">
			{children ?? "Download for Mac"} <span aria-hidden="true">↓</span>
		</a>
	);
}
function Footer({ next }: { next: 0 | 1 | 2 }) {
	return (
		<footer>
			<div className="footer-inner">
				<div>
					<Brand />
					<p>A solo-built macOS terminal, open source under MIT.</p>
				</div>
				<div>
					<Download />
					<a className="next" href={"/" + concepts[next].slug}>
						Next concept · {concepts[next].name} →
					</a>
				</div>
			</div>
		</footer>
	);
}
const topics = [
	{
		name: "Install on your Mac",
		slug: "install",
		hint: "macOS 13+",
		detail:
			"Open the DMG, drag YEN into Applications, and launch it from there. Apple silicon and Intel Macs are supported. You can start an ordinary shell immediately, without a YEN account.",
		ref: "Get started",
	},
	{
		name: "Keep a session running",
		slug: "persistent-sessions",
		hint: "yen sessions",
		detail:
			"Start a dev server in an ordinary shell pane. Quit YEN with ⌘Q. Reopen it on the same Mac. The server keeps its port, and the pane reattaches with its screen and scrollback. This is on by default under Settings → General → Keep Sessions Running. Close the pane or its window to end the session. Restarting the Mac ends it too.",
		ref: "Session lifecycle",
	},
	{
		name: "Find the active split",
		slug: "split-pane-labels",
		hint: "⌘D",
		detail:
			"Split right with ⌘D or split down with ⇧⌘D. In Settings → Appearance, enable Border and choose Focused Pane. The outline follows the entire pane, including its header. Move focus with ⌥⌘ and an arrow. Drag a header to move its pane.",
		ref: "Split pane labels",
	},
	{
		name: "Inspect the current repository",
		slug: "git-drawer",
		hint: "⇧⌘G",
		detail:
			"Open the read-only Git drawer with ⇧⌘G. Switch to a split in another repository and the drawer follows its directory. Review the branch, changed files, stashes, and diffs. Open yengit when you want to stage a change.",
		ref: "Git drawer",
	},
	{
		name: "Browse, then land in a directory",
		slug: "file-browser",
		hint: "y",
		detail:
			"In a YEN bash or zsh shell, type y to open the bundled file browser. Navigate to a directory and press q. Your shell lands there. Use browse when you want to return to the starting directory.",
		ref: "File browser",
	},
	{
		name: "Keep a note between windows",
		slug: "terminal-ide",
		hint: "⇧⌘J",
		detail:
			"Open Scratchpad with ⇧⌘J. Paste a command, a path, or the stack trace you keep needing. Every YEN window on this Mac shares the same locally saved buffer.",
		ref: "Workspace guide",
	},
];
function Guide({
	title,
	intro,
	open = 1,
}: {
	title: string;
	intro: string;
	open?: number;
}) {
	return (
		<section id="guide" className="guide section">
			<div className="guide-heading">
				<p className="kicker">Operator’s guide</p>
				<h2>{title}</h2>
				<p>{intro}</p>
				<a className="under" href={manualUrl}>
					Complete manual ↗
				</a>
			</div>
			<div className="topics">
				{topics.map((t, i) => (
					<details key={t.slug} open={i === open} id={"guide-" + t.slug}>
						<summary>
							{t.name}
							<code>{t.hint}</code>
							<span className="toggle" aria-hidden="true" />
						</summary>
						<p>{t.detail}</p>
						{t.slug === "persistent-sessions" && (
							<>
								<p>
									After a crash, YEN can reopen up to eight detached sessions
									that window restore missed. List sessions with{" "}
									<code>yen sessions</code> and reconnect with{" "}
									<code>yen sessions attach &lt;id&gt;</code>.
								</p>
								<p>
									Turning the setting off applies to new panes. Panes launched
									with an explicit command are temporary.
								</p>
							</>
						)}
						<a href={manualUrl + "#" + t.slug}>{t.ref} ↗</a>
					</details>
				))}
			</div>
		</section>
	);
}
const releases = [
	[
		"1.282",
		"An outline that reaches the corners",
		"The focused pane’s border follows the header and both bottom corners. Choose rounded gutters or a compact divider.",
	],
	[
		"1.279",
		"A handle for every split",
		"Drag a pane by its header. Rename it in place so “server” still means server after you rearrange the window.",
	],
	[
		"1.277",
		"Recovery across updates",
		"Each session remembers the backend build that started it. An update can reconnect to a shell running under the previous build.",
	],
	[
		"1.275",
		"Shells that outlive the app",
		"Keep Sessions Running ships on by default. Quitting detaches ordinary shell panes and reopening YEN reattaches them.",
	],
];
function Releases({ title }: { title: string }) {
	return (
		<section id="releases" className="section releases">
			<div className="section-heading">
				<div>
					<p className="kicker">From the release log</p>
					<h2>{title}</h2>
				</div>
				<a className="under" href={notes}>
					All releases ↗
				</a>
			</div>
			<div>
				{releases.map(([v, t, s]) => (
					<article className="release" key={v}>
						<a className="mono" href={github + "/releases/tag/v" + v}>
							v{v} ↗
						</a>
						<h3>{t}</h3>
						<p>{s}</p>
					</article>
				))}
			</div>
		</section>
	);
}
function Monitor() {
	return (
		<figure className="machine">
			<div className="crt">
				<div className="crt-face">
					<img
						src="/assets/phosphor.png"
						width="512"
						height="512"
						alt="YEN’s green phosphor mark"
					/>
					<span className="screen-label">YEN TERMINAL</span>
				</div>
				<div className="crt-bezel" aria-hidden="true">
					<i />
					YEN <b>▥▥▥▥▥▥▥</b>
				</div>
			</div>
			<figcaption className="mono">
				<span>Fig. 01</span> The phosphor mark
			</figcaption>
		</figure>
	);
}
function SessionDemo() {
	return (
		<section className="section demo-section" id="demo">
			<div>
				<p className="kicker">Interactive walkthrough</p>
				<h2>Watch the port.</h2>
				<p>
					This simulated server counts requests on port 4321. Quit YEN, send a
					request while the app is closed, then reopen it to see the request in
					your scrollback.
				</p>
			</div>
			<div className="simulator">
				<div className="sim-title mono">
					<span>Session preview</span>
					<span className="alive">● Process running</span>
				</div>
				<div className="sim-screen">
					<code className="terminal-log">
						$ bun run dev
						<br />
						<span>Listening on localhost:4321</span>
						<br />
						<span id="request-log">GET / 200 · request 1</span>
						<br />
						<b>▍</b>
					</code>
					<p className="detached" hidden>
						YEN is closed.
						<br />
						<small>The server still owns port 4321.</small>
					</p>
				</div>
				<div className="sim-control">
					<button type="button" id="session-toggle">
						Quit YEN <span>⌘Q</span>
					</button>
					<button type="button" id="make-request">
						Send request
					</button>
					<span id="session-status" role="status">
						Attached · port 4321
					</span>
				</div>
			</div>
		</section>
	);
}
function Phosphor() {
	return (
		<>
			<Nav name="Terminal for macOS" />
			<main id="main">
				<section className="night-hero">
					<div className="night-copy">
						<p className="kicker">
							<i /> Native macOS terminal
						</p>
						<h1>
							Quit the app.
							<br />
							<em>Keep the shell.</em>
						</h1>
						<p className="lede">
							Your dev server keeps its port. Your shell keeps its history.
							Reopen YEN and pick up at the same prompt.
						</p>
						<div className="actions">
							<Download />
							<a href="#demo">Try the session demo ↓</a>
						</div>
					</div>
					<Monitor />
				</section>
				<div className="status-strip mono">
					<span>YEN / v{stable.version}</span>
					<span>Ghostty engine · Metal renderer</span>
					<span>Solo-built · MIT</span>
				</div>
				<SessionDemo />
				<Guide
					title="A few keys to keep."
					intro="Start a session, split the window, and keep the tools for that project within reach."
				/>
				<Releases title="What shipped." />
			</main>
			<Footer next={1} />
		</>
	);
}
function PaneDiagram() {
	return (
		<figure className="drawing">
			<div className="plate-meta mono">
				<span>Plate A</span> <span>Split assembly</span>
			</div>
			<div className="draft-grid">
				<div className="dimension mono">Window bounds</div>
				<div className="schematic">
					<div className="drawing-bar">
						• • • <span>~/project</span>
					</div>
					<div className="pane-pair">
						{["Editor", "Server"].map((s, i) => (
							<button
								key={s}
								type="button"
								data-pane={s}
								aria-pressed={i === 0}
							>
								<span className="pane-label">{s}</span>
								<span className="lines" aria-hidden="true" />
								<strong>{i === 0 ? "A" : "B"}</strong>
							</button>
						))}
					</div>
				</div>
			</div>
			<figcaption>
				<span className="mono">Fig. A</span>{" "}
				<span id="pane-caption" role="status">
					Editor has focus. Select Server to move the outline.
				</span>
			</figcaption>
		</figure>
	);
}
function FieldManual() {
	return (
		<>
			<Nav name="Field Manual" />
			<main id="main">
				<section className="manual-hero">
					<div>
						<p className="kicker">YEN / Operator’s edition</p>
						<h1>
							Field
							<br />
							<em>Manual.</em>
						</h1>
						<p className="lede">
							One engineer’s guide to a native Mac terminal. Start with two panes and
							the line that tells you where your next command goes.
						</p>
						<div className="actions">
							<Download />
							<a href="#guide">Open the guide ↓</a>
						</div>
					</div>
					<PaneDiagram />
				</section>
				<section className="instruction-strip">
					<span className="mono">Default behavior</span>
					<h2>Quitting keeps the shell running.</h2>
					<p>
						When you reopen YEN, an ordinary pane reconnects to its process on
						this Mac, complete with screen and scrollback.
					</p>
				</section>
				<Guide
					title="At the keyboard."
					intro="Six tasks from the manual. Open one and try it in your own shell."
					open={2}
				/>
				<Releases title="Revision history." />
			</main>
			<Footer next={2} />
		</>
	);
}
const stories = [
	{
		tab: "The session",
		ver: "1.275",
		title: "The pane worth keeping.",
		text: "Closing an app is a habit. Restarting a dev server, finding its port, and scrolling back to the error shouldn’t be. YEN lets you quit and come back to the same running shell.",
		caption: "The app detaches. The shell and its server stay on the Mac.",
		link: "persistent-sessions",
	},
	{
		tab: "The outline",
		ver: "1.282",
		title: "Where the next key goes.",
		text: "Two panes can look almost identical. The focused pane gets one continuous outline, from the top of its header to both bottom corners. You can see where a command will land before you type it.",
		caption: "A single outline includes the pane label and terminal surface.",
		link: "split-pane-labels",
	},
	{
		tab: "The drawer",
		ver: "1.262",
		title: "The diff follows the shell.",
		text: "Two repos in two splits used to mean checking which directory you were reading. YEN’s Git drawer follows the focused split. Change panes and the branch, files, and diff follow along.",
		caption: "The Git drawer reads the repository of the focused split.",
		link: "git-drawer",
	},
];
function StoryArt({ index }: { index: number }) {
	if (index === 1)
		return (
			<div className="story-art art-split">
				<img
					src="/assets/splits.png"
					alt="YEN split headers with an outlined pane"
				/>
			</div>
		);
	if (index === 2)
		return (
			<div className="story-art proof-diff">
				<div className="proof-bar">
					Git drawer <span>~/project</span>
				</div>
				<code>
					main <b>· 1 changed file</b>
					<br />
					<br />
					M　src/server.ts
					<br />
					<br />
					<span>+ listen(PORT)</span>
				</code>
			</div>
		);
	return (
		<div className="story-art lifecycle">
			<div className="timeline">
				<span>01 / Before quit</span>
				<span>02 / After reopen</span>
			</div>
			<div className="trace">
				<i />
				<b>4321</b>
				<i />
			</div>
			<div className="trace-key mono">Same process · same port</div>
		</div>
	);
}
function Workshop() {
	return (
		<>
			<Nav name="Engineering journal" />
			<main id="main">
				<section className="journal-mast">
					<p className="kicker">An independent macOS terminal</p>
					<h1>
						YEN <em>Workshop</em>
					</h1>
					<div className="journal-meta mono">
						<span>Engineering notes</span>
						<span>Built on Ghostty</span>
						<span>Est. 2025</span>
					</div>
				</section>
				<section className="journal-cover" aria-label="Feature stories">
					<div className="story-picker">
						<span className="kicker">In this edition</span>
						{stories.map((s, i) => (
							<button
								key={s.tab}
								type="button"
								data-story={i}
								aria-pressed={i === 0}
							>
								{s.tab}
							</button>
						))}
					</div>
					{stories.map((s, i) => (
						<article
							className="story"
							key={s.tab}
							data-article={i}
							hidden={i !== 0}
						>
							<div>
								<p className="kicker">Shipped in v{s.ver}</p>
								<h2>{s.title}</h2>
								<p>{s.text}</p>
								<a className="under" href={"#guide-" + s.link}>
									Try it in YEN ↓
								</a>
							</div>
							<figure>
								<StoryArt index={i} />
								<figcaption>
									<span className="mono">Fig. {i + 1}</span>
									{s.caption}
								</figcaption>
							</figure>
						</article>
					))}
				</section>
				<div className="journal-deck">
					<p>
						One engineer builds YEN for daily use on the Mac. The work shows up
						in details you can try in a single afternoon.
					</p>
					<Download />
				</div>
				<Releases title="From the workbench." />
				<Guide
					title="The desk reference."
					intro="Keep these commands close. Each entry explains one small piece of the workspace."
				/>
			</main>
			<Footer next={0} />
		</>
	);
}
function Gallery() {
	return (
		<main id="main" className="gallery-page">
			<div className="gallery-top">
				<Brand />
				<span className="mono">Local design review</span>
			</div>
			<div className="gallery-head">
				<p className="kicker">YEN / Homepage studies</p>
				<h1>Three ways into YEN.</h1>
				<p>
					Choose a homepage to explore its demo, guide, and release history.
				</p>
			</div>
			<div className="covers">
				{concepts.map((c, i) => (
					<a className={"cover c" + i} key={c.slug} href={"/" + c.slug}>
						<div className="thumbnail">
							<img src={"/assets/cover-" + i + ".webp"} alt="" />
						</div>
						<div className="cover-text">
							<h2>
								{c.name} <span>↗</span>
							</h2>
							<p>{c.pitch}</p>
						</div>
					</a>
				))}
			</div>
		</main>
	);
}
export function page(path: string) {
	const item = concepts.find((c) => "/" + c.slug === path);
	const content =
		path === "/phosphor" ? (
			<Phosphor />
		) : path === "/field-manual" ? (
			<FieldManual />
		) : path === "/workshop" ? (
			<Workshop />
		) : (
			<Gallery />
		);
	return (
		"<!doctype html>" +
		renderToStaticMarkup(
			<html lang="en">
				<head>
					<meta charSet="utf-8" />
					<meta name="viewport" content="width=device-width, initial-scale=1" />
					<meta name="robots" content="noindex,nofollow" />
					<title>{(item?.name ?? "Homepage studies") + " · YEN"}</title>
					<link rel="icon" href="/assets/mark.png" />
					<link rel="stylesheet" href="/style.css" />
					<script src="/interactions.js" defer />
				</head>
				<body className={item?.slug ?? "index"}>
					<a className="skip" href="#main">
						Skip to content
					</a>
					{content}
				</body>
			</html>,
		)
	);
}
