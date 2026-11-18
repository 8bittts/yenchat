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
	getBlogPostsByMonth,
} from "@/lib/blog";
import { buildPublicPageMetadata, SITE_URL } from "@/lib/seo";

// Served at https://blog.yen.chat/ by proxy.ts; /blog on yen.chat redirects there.
export const metadata: Metadata = buildPublicPageMetadata({
	title: `${BLOG_TITLE} — the YEN blog`,
	description: `${BLOG_DESCRIPTION}. Long-form notes on building YEN, the free GPU-accelerated terminal for macOS.`,
	url: `${BLOG_URL}/`,
	imageAlt: `${BLOG_TITLE}, the YEN blog`,
});

const MONTHS = getBlogPostsByMonth();
const NAV_ITEMS: DocNavItem[] = MONTHS.map((month) => ({
	id: month.id,
	title: month.label,
}));

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
						{BLOG_DESCRIPTION}. Every post on building YEN, the free
						GPU-accelerated terminal for macOS, newest first.
					</p>
				</header>
			}
		>
			{MONTHS.map((month) => (
				<DocSection key={month.id} id={month.id} title={month.label}>
					{month.posts.map((post) => (
						<article key={post.slug} className="space-y-1">
							<p className="eyebrow-text">
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
					))}
				</DocSection>
			))}
		</DocPageShell>
	);
}
