"use client";

import { TerminalPanel } from "@/components/docs/terminal-panel";
import { PageShell } from "@/components/shared/page-shell";
import { TypewriterHeading } from "@/components/shared/typewriter-heading";
import { trackProductEvent } from "@/lib/analytics/product-analytics";
import { useTypewriter } from "@/lib/hooks/use-typewriter";

const HERO_TITLE =
	"Music for coding, focus, and the beautifully quiet hours between builds.";
const PLACEHOLDER_TEXT = "Press play for focus";

type Platform = "youtube" | "spotify" | "apple" | "amazon";

const PLATFORM_LINKS: Array<{
	key: Platform;
	label: string;
}> = [
	{
		key: "spotify",
		label: "Spotify",
	},
	{
		key: "apple",
		label: "Apple Music",
	},
	{
		key: "amazon",
		label: "Amazon Music",
	},
];

const YOUTUBE_VIDEO_ID = "AyTMFhww7uo";

function PlatformIcon({ platform }: { platform: Platform }) {
	if (platform === "youtube") {
		return (
			<svg
				aria-hidden="true"
				className="size-5"
				fill="currentColor"
				viewBox="0 0 24 24"
			>
				<path d="M23.5 6.2a3 3 0 0 0-2.1-2.1C19.5 3.6 12 3.6 12 3.6s-7.5 0-9.4.5A3 3 0 0 0 .5 6.2 31 31 0 0 0 0 12a31 31 0 0 0 .5 5.8 3 3 0 0 0 2.1 2.1c1.9.5 9.4.5 9.4.5s7.5 0 9.4-.5a3 3 0 0 0 2.1-2.1A31 31 0 0 0 24 12a31 31 0 0 0-.5-5.8ZM9.6 15.6V8.4L15.9 12l-6.3 3.6Z" />
			</svg>
		);
	}

	if (platform === "spotify") {
		return (
			<svg
				aria-hidden="true"
				className="size-5"
				fill="currentColor"
				viewBox="0 0 24 24"
			>
				<path d="M12 0a12 12 0 1 0 0 24 12 12 0 0 0 0-24Zm5.5 17.3a.8.8 0 0 1-1.1.3c-3-1.8-6.8-2.2-11.3-1.2a.8.8 0 1 1-.4-1.6c4.9-1.1 9.1-.6 12.5 1.5.4.2.5.7.3 1Zm1.5-3.2a1 1 0 0 1-1.3.3c-3.4-2.1-8.5-2.7-12.5-1.5a1 1 0 1 1-.6-1.9c4.6-1.4 10.4-.7 14.3 1.7.4.3.6.9.1 1.4Zm.2-3.4c-4-2.4-10.7-2.7-14.6-1.5a1.2 1.2 0 1 1-.7-2.3c4.5-1.4 12-1.1 16.5 1.6a1.2 1.2 0 0 1-1.2 2.2Z" />
			</svg>
		);
	}

	if (platform === "apple") {
		return (
			<svg
				aria-hidden="true"
				className="size-5"
				fill="currentColor"
				viewBox="0 0 24 24"
			>
				<path d="M18.7 13.1c0-2.5 2-3.7 2.1-3.8-1.2-1.7-3-1.9-3.6-2-1.5-.2-3 .9-3.8.9-.8 0-2-.9-3.3-.9-1.7 0-3.3 1-4.2 2.5-1.8 3.1-.5 7.7 1.3 10.2.9 1.2 1.9 2.6 3.2 2.5 1.3-.1 1.8-.8 3.4-.8s2 .8 3.4.8c1.4 0 2.3-1.2 3.1-2.5 1-1.5 1.4-2.9 1.4-3-.1 0-2.9-1.1-3-3.9ZM16.2 5.7c.7-.8 1.1-1.9 1-3-.9 0-2 .6-2.7 1.4-.6.7-1.2 1.9-1 2.9 1 .1 2-.5 2.7-1.3Z" />
			</svg>
		);
	}

	return (
		<svg
			aria-hidden="true"
			className="size-5"
			fill="none"
			stroke="currentColor"
			strokeLinecap="round"
			strokeLinejoin="round"
			strokeWidth="1.8"
			viewBox="0 0 24 24"
		>
			<path d="M9 18V5l10-2v13" />
			<circle cx="6" cy="18" r="3" />
			<circle cx="16" cy="16" r="3" />
		</svg>
	);
}

export function TunesClient() {
	const { phase: heroPhase, typedText: typedTitle } = useTypewriter(HERO_TITLE);

	return (
		<PageShell currentPage="tunes">
			<section className="pt-20 pb-6 md:py-28">
				<div className="container-page grid-two-cols-divider">
					<div className="space-y-6 pb-6 lg:pb-0">
						<header className="space-y-4 max-w-5xl">
							<p className="eyebrow-text text-brand-dark">
								Terminals and Tunes
							</p>

							<div className="space-y-3">
								<TypewriterHeading
									title={HERO_TITLE}
									placeholder={PLACEHOLDER_TEXT}
									phase={heroPhase}
									typedText={typedTitle}
								/>

								<p className="text-body text-text-muted max-w-4xl">
									YEN would not exist if it weren&apos;t for music. Every line
									of code was written with a sound in the backdrop. And, like
									you, I&apos;m simply more productive and happier with beats in
									my brain. I hope you enjoy my creations.
								</p>
							</div>

							<div className="flex flex-wrap gap-3">
								<a
									href="https://www.youtube.com/watch?v=AyTMFhww7uo"
									target="_blank"
									rel="noopener noreferrer"
									aria-label="Listen on YouTube"
									className="btn-primary gap-2"
									onClick={() =>
										trackProductEvent("tunes_platform_click", {
											platform: "youtube",
										})
									}
								>
									<span>Listen Now</span>
									<PlatformIcon platform="youtube" />
								</a>
								<nav
									className="flex items-center gap-2"
									aria-label="Music platforms"
								>
									{PLATFORM_LINKS.map((platform) => (
										<button
											key={platform.key}
											type="button"
											aria-label={`${platform.label} is not available yet`}
											title={`${platform.label} — coming soon`}
											className="btn-secondary inline-flex size-11 cursor-not-allowed items-center justify-center p-0 opacity-50"
											disabled
										>
											<PlatformIcon platform={platform.key} />
										</button>
									))}
								</nav>
								<p className="w-full text-body-xs text-text-muted">
									More platforms coming soon.
								</p>
							</div>
						</header>
					</div>

					<div className="hidden lg:block bg-border" aria-hidden="true" />

					<div className="w-full pt-6 lg:pt-0 lg:pl-6 border-t border-border lg:border-t-0">
						<TerminalPanel
							title="Terminals & Tunes"
							contentClassName="bg-card-content p-3 md:p-4"
						>
							<div className="aspect-video overflow-hidden rounded-md border border-border bg-code-bg">
								<iframe
									className="h-full w-full"
									src={`https://www.youtube-nocookie.com/embed/${YOUTUBE_VIDEO_ID}?rel=0&modestbranding=1`}
									title="YEN Terminals and Tunes video"
									loading="lazy"
									allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
									referrerPolicy="strict-origin-when-cross-origin"
									// allow-same-origin is required: without it the YouTube player never builds (proven via prod A/B). CSP frame-src pins the host.
									sandbox="allow-scripts allow-same-origin allow-presentation allow-popups allow-popups-to-escape-sandbox"
									allowFullScreen
								/>
							</div>
						</TerminalPanel>
					</div>
				</div>
			</section>
		</PageShell>
	);
}
