/**
 * blog.yen.chat — the self-hosted Digital Onigiri blog.
 *
 * Notes are static JSON files in `content/blog/posts/`: the creator's posts,
 * written once by `scripts/47-import-substack-blog.ts` from the Substack
 * export, and notes written for the site since. Their media
 * lives in `public/blog-media/` and is served same-origin. Every blog route is
 * prerendered at build time, so these reads never run at request time; the
 * node:fs import keeps this module out of client bundles.
 *
 * These are the notes the weekly issues in `lib/blog-weeks.ts` are built
 * from; `proxy.ts` serves the issues at the root of blog.yen.chat
 * (`/blog/2026-03-06` answers `https://blog.yen.chat/2026-03-06`).
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

/** Who wrote a note: the creator by hand, or an agent from the week's changes. */
export type BlogAuthor = "creator" | "agent";

export interface BlogPost {
	slug: string;
	postId: string;
	author: BlogAuthor;
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
 * aria-level so the note's outline starts at `firstLevel` and never skips,
 * and code blocks become focusable so keyboard users can scroll them.
 * A note sits under its own title inside a weekly issue, so the issue page
 * passes the level below that title. The visual tags stay the same, so the
 * article styles do not change.
 */
export function accessibleArticleHtml(html: string, firstLevel = 2): string {
	const levels = [...html.matchAll(/<h([1-6])\b/g)].map((match) =>
		Number(match[1]),
	);
	const ranks = [...new Set(levels)].sort((a, b) => a - b);
	let previous = firstLevel - 1;
	return html
		.replace(/<pre>/g, '<pre tabindex="0">')
		.replace(
			/<a href="([^"]*)">(<img\b[^>]*\balt=""[^>]*>)<\/a>/g,
			`<a href="$1" aria-label="${FULL_SIZE_IMAGE_LABEL}">$2</a>`,
		)
		.replace(/<h([1-6])\b/g, (tag, level: string) => {
			const outline = Math.min(
				ranks.indexOf(Number(level)) + firstLevel,
				previous + 1,
			);
			previous = outline;
			return outline === Number(level) ? tag : `${tag} aria-level="${outline}"`;
		});
}

/**
 * Every note, newest first, with its stored markup. Pages render a note
 * through `accessibleArticleHtml` at the level it sits under.
 */
export function getBlogPosts(): readonly BlogPost[] {
	if (!cachedPosts) {
		cachedPosts = readdirSync(POSTS_DIR)
			.filter((name) => name.endsWith(".json"))
			.map(
				(name) =>
					JSON.parse(
						readFileSync(path.join(POSTS_DIR, name), "utf8"),
					) as BlogPost,
			)
			.sort((a, b) => b.publishedAt.localeCompare(a.publishedAt));
	}
	return cachedPosts;
}

export function getBlogPost(slug: string): BlogPost | null {
	return getBlogPosts().find((post) => post.slug === slug) ?? null;
}

export function formatBlogDate(iso: string): string {
	return DATE_LABEL.format(new Date(iso));
}

/** The h2/h3 section anchors the importer added to a note's markup. */
export function getBlogHeadings(html: string): BlogHeading[] {
	return [
		...html.matchAll(/<h[23]\b[^>]*\bid="([^"]+)"[^>]*>([\s\S]*?)<\/h[23]>/g),
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
