import type { Metadata } from "next";
import Link from "next/link";
import type { DocNavItem } from "@/components/docs/doc-nav";
import { DocPageShell } from "@/components/docs/doc-page-shell";
import { DocSection } from "@/components/docs/doc-section";
import { TrackedDownloadLink } from "@/components/shared/tracked-download-link";
import { BLOG_TITLE, BLOG_URL } from "@/lib/blog";
import {
	describeReleaseWeek,
	getPostsForReleaseWeek,
	RELEASES_PATH,
	releaseWeekId,
} from "@/lib/blog-archive";
import { RELEASE_WEEKS } from "@/lib/release-notes/release-notes-data";
import { buildPublicPageMetadata, SITE_URL } from "@/lib/seo";

// Served at https://blog.yen.chat/releases by proxy.ts; yen.chat/release redirects here.
export const metadata: Metadata = buildPublicPageMetadata({
	title: `YEN Release Notes — ${BLOG_TITLE}`,
	description:
		"What changed in YEN, the free GPU-accelerated macOS terminal, week by week — every shipped build from the first signed release to today.",
	url: `${BLOG_URL}${RELEASES_PATH}`,
	imageAlt: "YEN release notes, week by week",
});

// One nav entry per month keeps the long weekly history easy to scan; each link
// targets the newest release week whose Thursday falls in that month.
const NAV_ITEMS: DocNavItem[] = (() => {
	const seen = new Set<string>();
	const items: DocNavItem[] = [];
	for (const week of RELEASE_WEEKS) {
		if (seen.has(week.month)) continue;
		seen.add(week.month);
		items.push({ id: releaseWeekId(week), title: week.month });
	}
	items.push({ id: "try-yen", title: "Ready to try it?" });
	return items;
})();

export default function ReleaseNotesPage() {
	return (
		<DocPageShell
			siteOrigin={SITE_URL}
			navItems={NAV_ITEMS}
			hero={
				<header className="space-y-3 max-w-5xl">
					<p className="eyebrow-text">
						<Link href="/" className="link-brand">
							{BLOG_TITLE}
						</Link>
						{" · "}Release notes
					</p>
					<h1 className="text-heading-lg pb-2 border-b border-border">
						What changed in YEN
					</h1>
					<p className="text-body text-text-muted max-w-4xl">
						The release notes for YEN, the free GPU-accelerated terminal for
						macOS: every shipped build, gathered into one short story per week,
						from the first signed release to today. For the longer notes on why
						and how YEN is built, read the{" "}
						<Link href="/" className="link-brand">
							posts from the creator
						</Link>
						.
					</p>
					<div className="flex flex-wrap items-center gap-x-4 gap-y-2 pt-2">
						<TrackedDownloadLink
							location="release-hero"
							className="btn-primary"
							siteOrigin={SITE_URL}
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
			{RELEASE_WEEKS.map((week) => {
				const posts = getPostsForReleaseWeek(week);
				return (
					<DocSection
						key={week.iso}
						id={releaseWeekId(week)}
						title={week.label}
					>
						<p className="text-label text-brand-dark">
							{describeReleaseWeek(week)}
						</p>
						{/* Weekly stories are authored as blank-line-separated paragraphs in
						    lib/release-notes/release-notes-copy.ts so a long week reads as a
						    few short beats. See _docs/10-gtm.md → "Release Notes". */}
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
						{posts.length > 0 ? (
							<p className="text-body-sm text-text-muted">
								From the creator this week:{" "}
								{posts.map((post, index) => (
									<span key={post.slug}>
										{index > 0 ? "; " : null}
										<Link href={`/${post.slug}`} className="link-brand">
											{post.title}
										</Link>
									</span>
								))}
							</p>
						) : null}
					</DocSection>
				);
			})}

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
						siteOrigin={SITE_URL}
					>
						<span>Download YEN for macOS</span>
						<span className="ml-2" aria-hidden="true">
							↓
						</span>
					</TrackedDownloadLink>
					<Link href={`${SITE_URL}/docs`} className="btn-secondary">
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
					<Link href={`${SITE_URL}/terms`} className="link-brand">
						privacy policy
					</Link>
					.
				</p>
			</DocSection>
		</DocPageShell>
	);
}
