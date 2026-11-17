import { describe, expect, test } from "bun:test";
import { existsSync, readdirSync } from "node:fs";
import path from "node:path";
import BLOG_SLUGS from "@/content/blog/slugs.json";
import {
	BLOG_MEDIA_PATH,
	getAdjacentBlogPosts,
	getBlogHeadings,
	getBlogPost,
	getBlogPosts,
} from "@/lib/blog";

// The Substack export of blog.yen.chat held 53 published posts; every one must stay on the blog.
const ARCHIVED_POST_COUNT = 53;

const posts = getBlogPosts();

function attributeValues(
	html: string,
	attribute: "href" | "src" | "srcset",
): string[] {
	return [...html.matchAll(new RegExp(`\\s${attribute}="([^"]*)"`, "g"))].map(
		(match) => match[1] ?? "",
	);
}

describe("blog.yen.chat archive", () => {
	test("keeps every published Substack post, and the proxy slug index matches the post files", () => {
		expect(posts).toHaveLength(ARCHIVED_POST_COUNT);
		expect(new Set(posts.map((post) => post.postId)).size).toBe(
			ARCHIVED_POST_COUNT,
		);
		const files = readdirSync("content/blog/posts").map((name) =>
			name.replace(/\.json$/, ""),
		);
		expect([...BLOG_SLUGS].sort()).toEqual(files.sort());
		expect([...BLOG_SLUGS].sort()).toEqual(
			posts.map((post) => post.slug).sort(),
		);
	});

	test("gives every post a URL-safe slug, a title, and a valid date, newest first", () => {
		for (const post of posts) {
			expect(post.slug).toMatch(/^[a-z0-9][a-z0-9-]*$/);
			expect(post.title.length).toBeGreaterThan(0);
			expect(Number.isNaN(Date.parse(post.publishedAt))).toBe(false);
		}
		const dates = posts.map((post) => post.publishedAt);
		expect(dates).toEqual([...dates].sort().reverse());
	});

	test("serves post media only from public/blog-media or YouTube, and every file exists", () => {
		const offHost = posts.flatMap((post) => {
			const sources = [
				...attributeValues(post.html, "src"),
				...attributeValues(post.html, "srcset").flatMap((set) =>
					set.split(", ").map((entry) => entry.split(" ")[0] ?? ""),
				),
			];
			return sources
				.filter(
					(src) =>
						!src.startsWith(BLOG_MEDIA_PATH) &&
						!src.startsWith("https://www.youtube-nocookie.com/embed/"),
				)
				.map((src) => `${post.slug}: ${src}`);
		});
		expect(offHost).toEqual([]);
		const missing = posts.flatMap((post) =>
			attributeValues(post.html, "src")
				.filter((src) => src.startsWith(BLOG_MEDIA_PATH))
				.filter((src) => !existsSync(path.join("public", src)))
				.map((src) => `${post.slug}: ${src}`),
		);
		expect(missing).toEqual([]);
		for (const post of posts) {
			if (post.coverImage)
				expect(post.coverImage.src.startsWith(BLOG_MEDIA_PATH)).toBe(true);
		}
	});

	test("leaves no Substack link and resolves every internal post link", () => {
		const problems = posts.flatMap((post) =>
			attributeValues(post.html, "href")
				.filter(
					(href) =>
						/substack\.com|blog\.yen\.chat\/p\//i.test(href) ||
						(href.startsWith("/") &&
							!href.startsWith(BLOG_MEDIA_PATH) &&
							href !== "/" &&
							!getBlogPost(href.slice(1))),
				)
				.map((href) => `${post.slug}: ${href}`),
		);
		expect(problems).toEqual([]);
	});

	test("keeps post HTML inside the sanitized subset", () => {
		for (const post of posts) {
			expect(post.html.length).toBeGreaterThan(0);
			expect(post.html).not.toMatch(
				/<(script|style|form|input|button|svg|picture|source)\b/i,
			);
			expect(post.html).not.toMatch(/\son[a-z]+=/i);
		}
	});

	test("links neighbors and exposes section headings", () => {
		const [first, second, third] = posts;
		if (!first || !second || !third) throw new Error("archive too small");
		expect(getAdjacentBlogPosts(second.slug)).toEqual({
			newer: first,
			older: third,
		});
		expect(getAdjacentBlogPosts(first.slug).newer).toBeNull();
		const skills = getBlogPost("skills");
		expect(skills && getBlogHeadings(skills).length).toBeGreaterThan(0);
	});
});
