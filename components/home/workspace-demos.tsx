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
	"ph-spark-tail-5",
	"ph-spark-tail-6",
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

// The same choices the app offers under Settings > Appearance > Border.
const weights = ["Thin", "Regular", "Thick"] as const;
const sparkSpeeds = ["Slowww", "Slow", "Medium", "Fast", "Fffast"] as const;
const auraPulses = ["Slow", "Medium", "Fast"] as const;
const auraColors = [
	{ name: "Phosphor", id: "phosphor" },
	{ name: "Orange", id: "orange" },
	{ name: "Sky", id: "sky" },
	{ name: "Violet", id: "violet" },
] as const;

type Weight = (typeof weights)[number];
type SparkSpeed = (typeof sparkSpeeds)[number];
type AuraPulse = (typeof auraPulses)[number];
type AuraColor = (typeof auraColors)[number]["id"];

/** One row of the preview's settings: a label and a set of pressed buttons. */
function Choice<T extends string>({
	label,
	options,
	value,
	onChange,
}: {
	label: string;
	options: readonly T[];
	value: T;
	onChange: (value: T) => void;
}) {
	return (
		<fieldset className="ph-setting">
			<legend>{label}</legend>
			<div className="ph-segment">
				{options.map((option) => (
					<button
						key={option}
						type="button"
						aria-pressed={value === option}
						onClick={() => onChange(option)}
					>
						{option}
					</button>
				))}
			</div>
		</fieldset>
	);
}

function Switch({
	label,
	on,
	onChange,
}: {
	label: string;
	on: boolean;
	onChange: (on: boolean) => void;
}) {
	return (
		<div className="ph-setting">
			<span>{label}</span>
			<button
				type="button"
				role="switch"
				aria-checked={on}
				aria-label={label}
				className="ph-switch"
				onClick={() => onChange(!on)}
			>
				<span className="ph-switch-knob" aria-hidden="true" />
			</button>
		</div>
	);
}

export function SplitDemo() {
	const [focus, setFocus] = useState<0 | 1>(0);
	const [compact, setCompact] = useState(false);
	const [weight, setWeight] = useState<Weight>("Regular");
	const [spark, setSpark] = useState(true);
	const [sparkSpeed, setSparkSpeed] = useState<SparkSpeed>("Medium");
	const [aura, setAura] = useState(true);
	const [auraPulse, setAuraPulse] = useState<AuraPulse>("Medium");
	const [auraColor, setAuraColor] = useState<AuraColor>("phosphor");
	const pane = panes[focus];
	const effects = [
		spark ? `Spark ${sparkSpeed}` : null,
		aura ? `Aura ${auraPulse}` : null,
	].filter(Boolean);
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
			<div
				className={`ph-splits ${compact ? "ph-splits-compact" : ""}`}
				data-weight={weight.toLowerCase()}
				data-spark-speed={sparkSpeed.toLowerCase()}
				data-aura-pulse={auraPulse.toLowerCase()}
				data-aura-color={auraColor}
			>
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
			<div className="ph-settings">
				<p className="ph-settings-head">
					Settings › Appearance › Border{" "}
					<span className="ph-settings-version">YEN 1.287</span>
				</p>
				<Choice
					label="Weight"
					options={weights}
					value={weight}
					onChange={setWeight}
				/>
				<Switch label="Spark" on={spark} onChange={setSpark} />
				{spark ? (
					<Choice
						label="Spark Speed"
						options={sparkSpeeds}
						value={sparkSpeed}
						onChange={setSparkSpeed}
					/>
				) : null}
				<Switch label="Aura" on={aura} onChange={setAura} />
				{aura ? (
					<>
						<fieldset className="ph-setting">
							<legend>Aura Color</legend>
							<div className="ph-swatches">
								{auraColors.map((color) => (
									<button
										key={color.id}
										type="button"
										aria-label={color.name}
										aria-pressed={auraColor === color.id}
										data-color={color.id}
										onClick={() => setAuraColor(color.id)}
									/>
								))}
							</div>
						</fieldset>
						<Choice
							label="Aura Pulse"
							options={auraPulses}
							value={auraPulse}
							onChange={setAuraPulse}
						/>
					</>
				) : null}
			</div>
			<div className="ph-drawer" role="status">
				<span>Keyboard focus</span>
				<span>
					<strong>{pane.name}</strong> {pane.path}
				</span>
				<span>Outline</span>
				<span>
					{weight}
					{effects.length > 0 ? ` · ${effects.join(" · ")}` : ""}
				</span>
			</div>
		</div>
	);
}
