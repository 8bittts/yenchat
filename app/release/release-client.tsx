import Link from "next/link";
import type { DocNavItem } from "@/components/docs/doc-nav";
import { DocPageShell } from "@/components/docs/doc-page-shell";
import { DocSection } from "@/components/docs/doc-section";
import { TrackedDownloadLink } from "@/components/shared/tracked-download-link";

import { RELEASE_WEEKS } from "./release-notes-data";

function weekId(iso: string): string {
	return `w-${iso}`;
}

// One nav entry per month keeps the long weekly history easy to scan; each link
// targets the newest release week whose Thursday falls in that month.
const NAV_ITEMS: DocNavItem[] = (() => {
	const seen = new Set<string>();
	const items: DocNavItem[] = [];
	for (const week of RELEASE_WEEKS) {
		const month = week.month;
		if (seen.has(month)) continue;
		seen.add(month);
		items.push({ id: weekId(week.iso), title: month });
	}
	items.push({ id: "try-yen", title: "Ready to try it?" });
	return items;
})();

export function ReleasePageClient() {
	return (
		<DocPageShell
			navItems={NAV_ITEMS}
			hero={
				<header className="space-y-3 max-w-5xl">
					<h1 className="text-heading-lg pb-2 border-b border-border">
						What changed in YEN
					</h1>
					<p className="text-body text-text-muted max-w-4xl">
						The complete build-by-build history of YEN, the free GPU-accelerated
						terminal for macOS — every shipped build, gathered into weekly
						stories from the first signed release to today. Shared by{" "}
						<a
							href="https://twitter.com/yenFTW"
							target="_blank"
							rel="noopener noreferrer"
							className="link-brand"
						>
							@yenFTW
						</a>
						.
					</p>
					<div className="flex flex-wrap items-center gap-x-4 gap-y-2 pt-2">
						<TrackedDownloadLink
							location="release-hero"
							className="btn-primary"
						>
							<span>Download for macOS</span>
							<span className="ml-2" aria-hidden="true">
								↓
							</span>
						</TrackedDownloadLink>
						<span className="text-body-xs text-text-muted">
							Free, signed, and notarized. No account required.
						</span>
					</div>
				</header>
			}
		>
			{RELEASE_WEEKS.map((week) => (
				<DocSection key={week.iso} id={weekId(week.iso)} title={week.label}>
					<p className="text-label text-brand-dark">
						{week.builds} {week.builds === 1 ? "build" : "builds"} shipped
						{" · "}through v{week.latestVersion}
					</p>
					{/* Weekly stories are authored as blank-line-separated paragraphs in
					    release-notes-copy.ts so a long week reads as a few short beats
					    instead of one wall of text. See _docs/10-gtm.md → "Release Notes
					    Page". */}
					<div className="space-y-4">
						{week.summary.split("\n\n").map((paragraph) => (
							<p
								key={`${week.iso}-${paragraph.slice(0, 32)}`}
								className="text-body-sm text-text-muted"
							>
								{paragraph}
							</p>
						))}
					</div>
				</DocSection>
			))}

			<DocSection id="try-yen" title="Ready to try it?">
				<p className="text-body-sm text-text-muted">
					Today's YEN is a fast, GPU-accelerated terminal for macOS with
					built-in speech-to-text, a native browser preview, a file browser, and
					terminal-first IDE workflows. It's free, private, and there's nothing
					to sign up for.
				</p>
				<div className="flex flex-wrap items-center gap-3">
					<TrackedDownloadLink
						location="release-footer"
						className="btn-primary"
					>
						<span>Download YEN for macOS</span>
						<span className="ml-2" aria-hidden="true">
							↓
						</span>
					</TrackedDownloadLink>
					<Link href="/docs" className="btn-secondary">
						Read the docs
					</Link>
				</div>
				<p className="text-body-sm text-text-muted">
					Questions about a release? Reach out on{" "}
					<a
						href="https://twitter.com/yenFTW"
						target="_blank"
						rel="noopener noreferrer"
						className="link-brand"
					>
						@yenFTW
					</a>
					. For data handling, read the{" "}
					<Link href="/terms" className="link-brand">
						privacy policy
					</Link>
					.
				</p>
			</DocSection>
		</DocPageShell>
	);
}
