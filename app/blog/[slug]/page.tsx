import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { PageShell } from "@/components/shared/page-shell";
import {
	BLOG_TITLE,
	blogPostUrl,
	formatBlogDate,
	getAdjacentBlogPosts,
	getBlogHeadings,
	getBlogPost,
	getBlogPosts,
} from "@/lib/blog";
import {
	getReleaseWeekForPost,
	RELEASES_PATH,
	releaseWeekHref,
} from "@/lib/blog-archive";
import { buildPublicPageMetadata, SITE_URL } from "@/lib/seo";

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
	const releaseWeek = getReleaseWeekForPost(post);
	const headings = getBlogHeadings(post);
	return (
		<PageShell siteOrigin={SITE_URL} mainClassName="ed-page">
			<div className="ph-wrap ed-story">
				<header className="ed-story-head">
					<Link className="ed-label" href="/">
						← {BLOG_TITLE}
					</Link>
					<h1>{post.title}</h1>
					<p className="ed-deck">{post.subtitle}</p>
					<p className="ed-byline">
						8BIT <span> / </span>{" "}
						<time dateTime={post.publishedAt}>
							{formatBlogDate(post.publishedAt)}
						</time>
					</p>
				</header>
				<div className="ed-reading">
					{headings.length > 0 && (
						<aside>
							<details className="ed-index">
								<summary>In this field note</summary>
								<nav aria-label="Article sections">
									{headings.map((h) => (
										<a key={h.id} href={`#${h.id}`}>
											{h.title}
										</a>
									))}
								</nav>
							</details>
						</aside>
					)}
					<div>
						{/* The importer sanitizes this repository-owned article before publication. */}
						{/* react-doctor-disable-next-line react/no-danger, react-doctor/dangerous-html-sink */}
						<article
							className="blog-prose"
							dangerouslySetInnerHTML={{ __html: post.html }}
						/>
						<section className="ed-next" id="more-posts">
							<h2>More field notes</h2>
							{newer && (
								<Link href={`/${newer.slug}`}>Newer · {newer.title} ↗</Link>
							)}
							{older && (
								<Link href={`/${older.slug}`}>Older · {older.title} ↗</Link>
							)}
							<Link
								href={
									releaseWeek ? releaseWeekHref(releaseWeek) : RELEASES_PATH
								}
							>
								{releaseWeek ? releaseWeek.label : "All release notes"} ↗
							</Link>
							<Link href="/">All posts ↗</Link>
						</section>
					</div>
				</div>
			</div>
		</PageShell>
	);
}
