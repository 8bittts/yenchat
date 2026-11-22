/**
 * blog.yen.chat — the self-hosted Digital Onigiri blog.
 *
 * Posts are static JSON files in `content/blog/posts/`, written once by
 * `scripts/47-import-substack-blog.ts` from the Substack export. Their media
 * lives in `public/blog-media/` and is served same-origin. Every blog route is
 * prerendered at build time, so these reads never run at request time; the
 * node:fs import keeps this module out of client bundles.
 *
 * `proxy.ts` serves the routes under `app/blog/` at the root of blog.yen.chat
 * (`/blog/skills` answers `https://blog.yen.chat/skills`).
 */

import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

export const BLOG_URL = "https://blog.yen.chat";
export const BLOG_TITLE = "Digital Onigiri";
export const BLOG_DESCRIPTION = "On Building YEN: A Terminal App";
/** Public path of the post media in `public/blog-media/`. */
export const BLOG_MEDIA_PATH = "/blog-media/";

const POSTS_DIR = path.join(process.cwd(), "content", "blog", "posts");

/** Post dates read as they did on Substack, in the author's timezone. */
const DATE_LABEL = new Intl.DateTimeFormat("en-US", {
	day: "numeric",
	month: "long",
	timeZone: "America/Los_Angeles",
	year: "numeric",
});

export interface BlogImage {
	src: string;
	width: number;
	height: number;
}

export interface BlogPost {
	slug: string;
	postId: string;
	title: string;
	subtitle: string;
	publishedAt: string;
	coverImage: BlogImage | null;
	wordCount: number;
	html: string;
}

export interface BlogHeading {
	id: string;
	title: string;
}

let cachedPosts: readonly BlogPost[] | null = null;

const FULL_SIZE_IMAGE_LABEL = "Open full-size image";

/**
 * Imported Substack markup needs three accessibility repairs before render:
 * image links whose image has empty alt text get a name, headings get an
 * aria-level so the outline under the page h1 starts at 2 and never skips,
 * and code blocks become focusable so keyboard users can scroll them.
 * The visual tags stay the same, so the article styles do not change.
 */
export function accessibleArticleHtml(html: string): string {
	const levels = [...html.matchAll(/<h([1-6])\b/g)].map((match) =>
		Number(match[1]),
	);
	const ranks = [...new Set(levels)].sort((a, b) => a - b);
	let previous = 1;
	return html
		.replace(/<pre>/g, '<pre tabindex="0">')
		.replace(
			/<a href="([^"]*)">(<img\b[^>]*\balt=""[^>]*>)<\/a>/g,
			`<a href="$1" aria-label="${FULL_SIZE_IMAGE_LABEL}">$2</a>`,
		)
		.replace(/<h([1-6])\b/g, (tag, level: string) => {
			const outline = Math.min(ranks.indexOf(Number(level)) + 2, previous + 1);
			previous = outline;
			return outline === Number(level) ? tag : `${tag} aria-level="${outline}"`;
		});
}

function withAccessibleArticleHtml(post: BlogPost): BlogPost {
	return { ...post, html: accessibleArticleHtml(post.html) };
}

/** Every post, newest first. */
export function getBlogPosts(): readonly BlogPost[] {
	if (!cachedPosts) {
		cachedPosts = readdirSync(POSTS_DIR)
			.filter((name) => name.endsWith(".json"))
			.map((name) =>
				withAccessibleArticleHtml(
					JSON.parse(
						readFileSync(path.join(POSTS_DIR, name), "utf8"),
					) as BlogPost,
				),
			)
			.sort((a, b) => b.publishedAt.localeCompare(a.publishedAt));
	}
	return cachedPosts;
}

export function getBlogPost(slug: string): BlogPost | null {
	return getBlogPosts().find((post) => post.slug === slug) ?? null;
}

export function blogPostUrl(slug: string): string {
	return `${BLOG_URL}/${slug}`;
}

export function formatBlogDate(iso: string): string {
	return DATE_LABEL.format(new Date(iso));
}

/** The posts immediately newer and older than `slug`. */
export function getAdjacentBlogPosts(slug: string): {
	newer: BlogPost | null;
	older: BlogPost | null;
} {
	const posts = getBlogPosts();
	const index = posts.findIndex((post) => post.slug === slug);
	if (index < 0) return { newer: null, older: null };
	return { newer: posts[index - 1] ?? null, older: posts[index + 1] ?? null };
}

/** The h2/h3 section anchors the importer added to a post. */
export function getBlogHeadings(post: BlogPost): BlogHeading[] {
	return [
		...post.html.matchAll(
			/<h[23]\b[^>]*\bid="([^"]+)"[^>]*>([\s\S]*?)<\/h[23]>/g,
		),
	].map((match) => ({
		id: match[1] ?? "",
		title: (match[2] ?? "")
			.replace(/<[^>]+>/g, "")
			.replace(/&amp;/g, "&")
			.replace(/&lt;/g, "<")
			.replace(/&gt;/g, ">")
			.replace(/&quot;/g, '"')
			.replace(/&#39;/g, "'")
			.trim(),
	}));
}
