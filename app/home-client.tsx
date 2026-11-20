"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { PageShell } from "@/components/shared/page-shell";
import { TypewriterHeading } from "@/components/shared/typewriter-heading";
import { DOWNLOAD_HREF } from "@/lib/analytics/download-cta";
import { trackProductEvent } from "@/lib/analytics/product-analytics";
import { useTypewriter } from "@/lib/hooks/use-typewriter";
import { getVersionFilename } from "@/lib/version-format";

interface HomeClientProps {
	version: string;
}

const HERO_TITLE = "Quit, crash, update. Your terminal keeps running.";
const PLACEHOLDER_TEXT = "Enable speech-to-text";
const TERMINAL_DEMO_TEXT = "Speech-to-text in any app. No AI required.";

function useTerminalDemo() {
	const [phase, setPhase] = useState<"idle" | "recording" | "typing" | "done">(
		"idle",
	);
	const [typedText, setTypedText] = useState("");

	// Same typewriter pattern as useTypewriter (lib/hooks/use-typewriter.ts); suppression rationale lives there.
	// react-doctor-disable-next-line react-doctor/effect-needs-cleanup
	// react-doctor-disable-next-line react-doctor/no-cascading-set-state
	useEffect(() => {
		const prefersReducedMotion = window.matchMedia(
			"(prefers-reduced-motion: reduce)",
		).matches;

		if (prefersReducedMotion) {
			setTypedText(TERMINAL_DEMO_TEXT);
			setPhase("done");
			return;
		}

		let timeoutId: ReturnType<typeof setTimeout>;
		let intervalId: ReturnType<typeof setInterval>;
		let typedLength = 0;

		const runAnimation = () => {
			setPhase("idle");
			setTypedText("");
			typedLength = 0;

			// Start after 6s (after hero animation completes)
			timeoutId = setTimeout(() => {
				setPhase("recording");

				timeoutId = setTimeout(() => {
					setPhase("typing");

					intervalId = setInterval(() => {
						if (typedLength >= TERMINAL_DEMO_TEXT.length) {
							clearInterval(intervalId);
							// Play once (matches the hero animation) instead of
							// looping every 4s, which repainted the idle page forever.
							timeoutId = setTimeout(() => {
								setPhase("done");
							}, 500);
							return;
						}
						typedLength += 1;
						setTypedText(TERMINAL_DEMO_TEXT.slice(0, typedLength));
					}, 50);
				}, 500);
			}, 6000);
		};

		runAnimation();

		return () => {
			clearTimeout(timeoutId);
			clearInterval(intervalId);
		};
	}, []);

	return { phase, typedText };
}

export function HomeClient({ version }: HomeClientProps) {
	const { phase: heroPhase, typedText: typedTitle } = useTypewriter(HERO_TITLE);
	const { phase: terminalPhase, typedText } = useTerminalDemo();
	const versionFilename = getVersionFilename(version);

	return (
		<PageShell currentPage="home">
			<section className="pt-20 pb-6 md:py-28">
				<div className="container-page grid-two-cols-divider">
					<div className="space-y-6 pb-6 lg:pb-0">
						{/* Animated Hero */}
						<header className="space-y-4 max-w-5xl">
							<p className="eyebrow-text text-brand-dark">GPU Terminal</p>

							<div className="space-y-3">
								<TypewriterHeading
									title={HERO_TITLE}
									placeholder={PLACEHOLDER_TEXT}
									phase={heroPhase}
									typedText={typedTitle}
								/>
								{/* LOCKED COPY — Do not modify this text without explicit user request.
									    This is hand-crafted marketing copy approved by the founder. */}
								<p className="text-body text-text-muted max-w-4xl">
									Every pane keeps running when YEN quits, crashes, or updates,
									then reattaches right where you left it. Plus native
									speech-to-text, clipboard-aware Cmd + V image/file paste, 20
									curated stylish themes, custom notifications, power dev tools,
									and more! Built on Metal for 60FPS+ rendering. LFG.
								</p>
							</div>

							<div className="flex flex-wrap gap-3">
								<Link
									href={DOWNLOAD_HREF}
									className="btn-primary"
									onClick={() =>
										trackProductEvent("download_click", { location: "hero" })
									}
								>
									<span>Download for macOS</span>
									<span className="ml-2" aria-hidden="true">
										↓
									</span>
								</Link>
								<span className="inline-flex items-center rounded-lg border border-border px-4 py-2 text-sm text-text-muted">
									v{version}
								</span>
								<Link href="/docs" className="btn-secondary">
									Docs
								</Link>
							</div>
						</header>

						<div className="space-y-1 text-body-xs text-text-muted">
							<p>
								<strong className="text-text-primary">Start:</strong> Download,
								open DMG, drag to Applications, enjoy!
							</p>
							<p>
								<strong className="text-text-primary">Launch:</strong>{" "}
								Right-click YEN.app and click "Open" to bypass Gatekeeper.
							</p>
							<p>
								<strong className="text-text-primary">Verify:</strong> Review
								the{" "}
								<a
									href={`/stable/yen-${versionFilename}.dmg.sha256`}
									className="link-brand"
								>
									SHA256
								</a>{" "}
								for authenticity.
							</p>
						</div>
					</div>

					{/* Vertical divider - centered between columns */}
					<div className="hidden lg:block bg-border" aria-hidden="true" />

					{/* Static terminal vignette to show the UI chrome without runtime cost */}
					<div className="w-full pt-6 lg:pt-0 lg:pl-6 border-t border-border lg:border-t-0">
						<div className="terminal-window">
							<div className="terminal-header">
								<div className="terminal-dots" aria-hidden="true">
									<div className="terminal-dot bg-terminal-dot-red" />
									<div className="terminal-dot bg-terminal-dot-yellow" />
									<div className="terminal-dot bg-terminal-dot-green" />
								</div>
							</div>
							<div className="terminal-content">
								<div className="mb-4 md:mb-6 overflow-x-auto">
									<pre
										className="leading-none text-xl md:text-2xl font-mono overflow-x-auto"
										aria-hidden="true"
									>
										<span className="text-brand">
											{`┓┏┏┓┳┓
┗┫┣ ┃┃
┗┛┗┛┛┗`}
										</span>
									</pre>
								</div>
								<div className="mb-6">
									<p className="text-terminal-text">
										GPU-Accelerated Terminal for macOS
									</p>
									<p className="text-terminal-text-muted text-xs mt-1">
										No required account. No desktop telemetry.
									</p>
								</div>

								{/* Voice demo animation */}
								<div className="pt-4 border-t border-border-light">
									<div className="flex items-center gap-2 mb-2">
										{(terminalPhase === "recording" ||
											terminalPhase === "typing") && (
											<div className="status-indicator">
												<span className="status-indicator-ping" />
												<span className="status-indicator-dot" />
											</div>
										)}
										<span className="text-terminal-text-muted text-xs">
											{terminalPhase === "idle" && "Option + Space"}
											{terminalPhase === "recording" && "Recording..."}
											{terminalPhase === "typing" && "Option + Space"}
											{terminalPhase === "done" && "Option + Space"}
										</span>
									</div>
									<div className="relative">
										<p
											className="text-terminal-text invisible"
											aria-hidden="true"
											data-layout-reserve="terminal-demo"
										>
											Speech-to-text in any app. No AI required.
										</p>
										{typedText && (
											<p className="text-terminal-text absolute inset-x-0 top-0">
												{typedText}
												{terminalPhase !== "done" && (
													<span className="cursor-blink bg-terminal-text" />
												)}
											</p>
										)}
									</div>
								</div>
							</div>
						</div>
					</div>
				</div>
			</section>
		</PageShell>
	);
}
