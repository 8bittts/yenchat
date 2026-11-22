import type { Metadata } from "next";
import Link from "next/link";
import { DocSection } from "@/components/docs/doc-section";
import { PageShell } from "@/components/shared/page-shell";
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
	imageAlt: "The YEN weekly build log",
	image: { url: `${SITE_URL}/social/releases.png`, width: 1200, height: 630 },
});

// One nav entry per month keeps the long weekly history easy to scan; each link
// targets the newest release week whose Thursday falls in that month.
const NAV_ITEMS = (() => {
	const seen = new Set<string>();
	const items: { id: string; title: string }[] = [];
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
		<PageShell siteOrigin={SITE_URL} mainClassName="ed-page">
			<header className="ed-cover">
				<div className="ph-wrap ed-release-head">
					<Link className="ph-kicker" href="/">
						← {BLOG_TITLE}
					</Link>
					<h1>
						What changed in <em>YEN</em>
					</h1>
					<p className="ph-hero-lede">
						The build log, one week at a time. See when a feature landed and
						follow the field notes behind it.
					</p>
					<div className="ph-actions">
						<TrackedDownloadLink
							location="release-hero"
							className="ph-download"
							siteOrigin={SITE_URL}
						>
							Download for macOS ↓
						</TrackedDownloadLink>
						<a className="ed-night-link" href="#release-log">
							Read the log ↓
						</a>
					</div>
				</div>
			</header>
			<div className="ph-wrap ed-sheet" id="release-log">
				<details className="ed-index">
					<summary>Jump to a release month</summary>
					<nav aria-label="Release months">
						{NAV_ITEMS.map((item) => (
							<a href={`#${item.id}`} key={item.id}>
								{item.title}
							</a>
						))}
					</nav>
				</details>
				<div className="ed-log">
					{RELEASE_WEEKS.map((week) => {
						const posts = getPostsForReleaseWeek(week);
						return (
							<DocSection
								key={week.iso}
								id={releaseWeekId(week)}
								title={week.label}
							>
								<p className="ed-label">{describeReleaseWeek(week)}</p>
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
							Quit YEN and an ordinary shell can keep its port, its process, and
							its scrollback. Open the field guide for setup, split controls,
							and the optional local agent token counter.
						</p>
						<div className="flex flex-wrap items-center gap-3">
							<TrackedDownloadLink
								location="release-footer"
								className="ph-download"
								siteOrigin={SITE_URL}
							>
								<span>Download YEN for macOS</span>
								<span className="ml-2" aria-hidden="true">
									↓
								</span>
							</TrackedDownloadLink>
							<Link href={`${SITE_URL}/#guide`} className="ed-text-link">
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
				</div>
			</div>
		</PageShell>
	);
}
