import type { Metadata } from "next";
import Link from "next/link";
import type { DocNavItem } from "@/components/docs/doc-nav";
import { DocPageShell } from "@/components/docs/doc-page-shell";
import { DocSection } from "@/components/docs/doc-section";
import {
	BLOG_DESCRIPTION,
	BLOG_TITLE,
	BLOG_URL,
	formatBlogDate,
} from "@/lib/blog";
import {
	type ArchiveEntry,
	describeReleaseWeek,
	getArchiveByMonth,
	RELEASES_PATH,
	releaseWeekHref,
} from "@/lib/blog-archive";
import { buildPublicPageMetadata, SITE_URL } from "@/lib/seo";

// Served at https://blog.yen.chat/ by proxy.ts; /blog on yen.chat redirects there.
export const metadata: Metadata = buildPublicPageMetadata({
	title: `${BLOG_TITLE} — the YEN blog`,
	description: `${BLOG_DESCRIPTION}. Long-form posts from the creator of YEN, the free GPU-accelerated terminal for macOS, alongside its weekly release notes.`,
	url: `${BLOG_URL}/`,
	imageAlt: `${BLOG_TITLE}, the YEN blog`,
});

const MONTHS = getArchiveByMonth();
const NAV_ITEMS: DocNavItem[] = MONTHS.map((month) => ({
	id: month.id,
	title: month.label,
}));

function ArchiveItem({ entry }: { entry: ArchiveEntry }) {
	if (entry.kind === "release") {
		return (
			// A week is the short record, so it sits one step below a post.
			<article className="space-y-1">
				<p className="eyebrow-text">Release notes</p>
				<p className="text-body-sm text-text-muted">
					<Link href={releaseWeekHref(entry.week)} className="link-brand">
						{entry.week.label}
					</Link>
					{" · "}
					{describeReleaseWeek(entry.week)}
				</p>
			</article>
		);
	}
	const { post } = entry;
	return (
		<article className="space-y-1">
			<p className="eyebrow-text">
				From the creator ·{" "}
				<time dateTime={post.publishedAt}>
					{formatBlogDate(post.publishedAt)}
				</time>
			</p>
			<h3 className="text-heading-sm">
				<Link href={`/${post.slug}`} className="link-brand">
					{post.title}
				</Link>
			</h3>
			{post.subtitle ? (
				<p className="text-body-sm text-text-muted">{post.subtitle}</p>
			) : null}
		</article>
	);
}

export default function BlogIndexPage() {
	return (
		<DocPageShell
			siteOrigin={SITE_URL}
			navItems={NAV_ITEMS}
			hero={
				<header className="space-y-3 max-w-5xl">
					<h1 className="text-heading-lg pb-2 border-b border-border">
						{BLOG_TITLE}
					</h1>
					<p className="text-body text-text-muted max-w-4xl">
						{BLOG_DESCRIPTION}. Two kinds of writing about YEN, the free
						GPU-accelerated terminal for macOS, newest first.
					</p>
					<ul className="space-y-2 text-body-sm text-text-muted max-w-4xl">
						<li>
							<span className="text-text-primary">From the creator</span>:
							long-form posts on why and how YEN is built.
						</li>
						<li>
							<span className="text-text-primary">Release notes</span>: what
							changed in each week's builds, so you can see what an update
							brings.{" "}
							<Link href={RELEASES_PATH} className="link-brand">
								Read the release notes
							</Link>
						</li>
					</ul>
				</header>
			}
		>
			{MONTHS.map((month) => (
				<DocSection key={month.id} id={month.id} title={month.label}>
					{month.entries.map((entry) => (
						<ArchiveItem
							key={
								entry.kind === "post" ? entry.post.slug : `w-${entry.week.iso}`
							}
							entry={entry}
						/>
					))}
				</DocSection>
			))}
		</DocPageShell>
	);
}
