import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import type { DocNavItem } from "@/components/docs/doc-nav";
import { DocPageShell } from "@/components/docs/doc-page-shell";
import { DocSection } from "@/components/docs/doc-section";
import {
	BLOG_TITLE,
	blogPostUrl,
	formatBlogDate,
	getAdjacentBlogPosts,
	getBlogHeadings,
	getBlogPost,
	getBlogPosts,
} from "@/lib/blog";
import { buildPublicPageMetadata } from "@/lib/seo";

// Served at https://blog.yen.chat/<slug> by proxy.ts; /p/<slug> redirects here.
interface BlogPostRouteProps {
	params: Promise<{ slug: string }>;
}

export const dynamicParams = false;

export function generateStaticParams() {
	return getBlogPosts().map((post) => ({ slug: post.slug }));
}

export async function generateMetadata({
	params,
}: BlogPostRouteProps): Promise<Metadata> {
	const post = getBlogPost((await params).slug);
	if (!post) return {};
	const metadata = buildPublicPageMetadata({
		title: `${post.title} — ${BLOG_TITLE}`,
		description: post.subtitle || post.title,
		url: blogPostUrl(post.slug),
		imageAlt: post.title,
		...(post.coverImage
			? {
					image: {
						url: post.coverImage.src,
						width: post.coverImage.width,
						height: post.coverImage.height,
					},
				}
			: {}),
	});
	return {
		...metadata,
		openGraph: {
			...metadata.openGraph,
			type: "article",
			publishedTime: post.publishedAt,
		},
	};
}

export default async function BlogPostPage({ params }: BlogPostRouteProps) {
	const post = getBlogPost((await params).slug);
	if (!post) notFound();
	const { newer, older } = getAdjacentBlogPosts(post.slug);
	const navItems: DocNavItem[] = [
		...getBlogHeadings(post),
		{ id: "more-posts", title: "More posts" },
	];

	return (
		<DocPageShell
			variant="guide"
			navItems={navItems}
			hero={
				<header className="space-y-3">
					<p className="eyebrow-text">
						<Link href="/" className="link-brand">
							{BLOG_TITLE}
						</Link>
						{" · "}
						<time dateTime={post.publishedAt}>
							{formatBlogDate(post.publishedAt)}
						</time>
					</p>
					<h1 className="text-heading-md pb-2 border-b border-border">
						{post.title}
					</h1>
					{post.subtitle ? (
						<p className="text-body text-text-muted">{post.subtitle}</p>
					) : null}
				</header>
			}
		>
			{/* Post HTML is a repo-owned static file sanitized by scripts/47-import-substack-blog.ts. */}
			{/* react-doctor-disable-next-line react/no-danger, react-doctor/dangerous-html-sink */}
			<article
				className="blog-prose"
				dangerouslySetInnerHTML={{ __html: post.html }}
			/>

			<DocSection id="more-posts" title="More posts">
				<ul className="space-y-3">
					{newer ? (
						<li className="text-body-sm">
							<span className="text-text-muted">Newer: </span>
							<Link href={`/${newer.slug}`} className="link-brand">
								{newer.title}
							</Link>
						</li>
					) : null}
					{older ? (
						<li className="text-body-sm">
							<span className="text-text-muted">Older: </span>
							<Link href={`/${older.slug}`} className="link-brand">
								{older.title}
							</Link>
						</li>
					) : null}
					<li className="text-body-sm">
						<Link href="/" className="link-brand">
							All posts
						</Link>
					</li>
				</ul>
			</DocSection>
		</DocPageShell>
	);
}
