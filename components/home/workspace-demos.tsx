"use client";

import { useState } from "react";

export function SessionDemo() {
	const [attached, setAttached] = useState(true);
	const [requests, setRequests] = useState(1);
	const [status, setStatus] = useState("Shell attached.");
	const recentRequests = Array.from(
		{ length: Math.min(requests, 4) },
		(_, i) => requests - Math.min(requests, 4) + i + 1,
	);

	function toggleApp() {
		setAttached(!attached);
		setStatus(
			attached
				? "App closed. The server still owns port 4321."
				: "Shell reattached. Your scrollback is back.",
		);
	}
	function sendRequest() {
		setRequests(requests + 1);
		setStatus(
			`Request ${requests + 1} returned 200 OK${attached ? "." : " while YEN was closed."}`,
		);
	}

	return (
		<div className="ph-demo">
			<div className="ph-demo-bar">
				<span>Session simulator</span>
				<span className="ph-signal">Server running</span>
			</div>
			<div className="ph-screen">
				{attached ? (
					<div>
						<p className="ph-cwd">
							~/project <span>on main</span>
						</p>
						<p>$ bun run dev</p>
						<p className="ph-output">Listening on localhost:4321</p>
						<div className="ph-requests">
							{recentRequests.map((n) => (
								<p key={n}>
									<span>GET /</span>
									<span>200 OK</span>
									<small>#{String(n).padStart(2, "0")}</small>
								</p>
							))}
						</div>
					</div>
				) : (
					<div className="ph-detached">
						<span aria-hidden="true">⌘ Q</span>
						<strong>YEN is closed.</strong>
						<p>You can still send the server a request.</p>
					</div>
				)}
			</div>
			<div className="ph-controls">
				<button type="button" className="ph-primary" onClick={toggleApp}>
					{attached ? "Quit YEN" : "Reopen YEN"}
				</button>
				<button type="button" className="ph-secondary" onClick={sendRequest}>
					Send request
				</button>
			</div>
			<p className="ph-live" role="status">
				{status}
			</p>
		</div>
	);
}

const panes = [
	{
		name: "Editor",
		path: "~/project/web",
		command: "git status --short",
		output: " M src/app.tsx",
	},
	{
		name: "Server",
		path: "~/project/api",
		command: "bun run dev",
		output: "Listening on :4321",
	},
] as const;

// Strokes that share one head. Each is shorter and brighter than the last,
// so together they draw a tail that fades.
const sparkStrokes = [
	"ph-spark-glow",
	"ph-spark-tail-1",
	"ph-spark-tail-2",
	"ph-spark-tail-3",
	"ph-spark-tail-4",
	"ph-spark-head",
] as const;

/** The light that travels around the focused pane: a glowing head and a fading tail. */
function Spark() {
	return (
		<svg className="ph-spark" aria-hidden="true" focusable="false">
			{sparkStrokes.map((stroke) => (
				<rect key={stroke} className={stroke} pathLength={100} />
			))}
		</svg>
	);
}

export function SplitDemo() {
	const [focus, setFocus] = useState<0 | 1>(0);
	const [compact, setCompact] = useState(false);
	const [spark, setSpark] = useState(true);
	const [aura, setAura] = useState(true);
	const pane = panes[focus];
	return (
		<div className="ph-demo">
			<div className="ph-demo-bar">
				<span>Split preview</span>
				<fieldset className="ph-segment">
					<legend className="sr-only">Split appearance</legend>
					{["Comfortable", "Compact"].map((style, i) => (
						<button
							key={style}
							type="button"
							aria-pressed={compact === (i === 1)}
							onClick={() => setCompact(i === 1)}
						>
							{style}
						</button>
					))}
				</fieldset>
			</div>
			<div className={`ph-splits ${compact ? "ph-splits-compact" : ""}`}>
				{panes.map((p, i) => (
					<div
						key={p.name}
						className={`ph-pane-slot ${focus === i && aura ? "ph-aura" : ""}`}
					>
						<button
							type="button"
							aria-label={`Focus ${p.name} pane`}
							className="ph-pane"
							aria-pressed={focus === i}
							onClick={() => setFocus(i === 0 ? 0 : 1)}
						>
							<span className="ph-pane-title">
								<strong>{p.name}</strong>
								<span>{focus === i ? "Focused" : "Idle"}</span>
							</span>
							<span className="ph-pane-code">
								<small>{p.path}</small>
								<span>$ {p.command}</span>
								<span>{p.output}</span>
							</span>
						</button>
						{focus === i && spark ? <Spark /> : null}
					</div>
				))}
			</div>
			<div className="ph-demo-bar ph-effects-bar">
				<span>Outline effects · YEN 1.285</span>
				<fieldset className="ph-segment">
					<legend className="sr-only">Outline effects</legend>
					<button
						type="button"
						aria-pressed={spark}
						onClick={() => setSpark(!spark)}
					>
						Spark
					</button>
					<button
						type="button"
						aria-pressed={aura}
						onClick={() => setAura(!aura)}
					>
						Aura
					</button>
				</fieldset>
			</div>
			<div className="ph-drawer" role="status">
				<span>Keyboard focus</span>
				<strong>{pane.name}</strong>
				<span>{pane.path}</span>
			</div>
		</div>
	);
}
