import { describe, expect, test } from "bun:test";
import { JSDOM } from "jsdom";
import { getBlogHeadings, getBlogPosts } from "@/lib/blog";

// Article bodies render below the page h1. Screen readers need a named link
// for every image link, an outline without skipped levels, and keyboard
// access to code blocks that scroll sideways on a phone.

const posts = getBlogPosts();

function articleBody(html: string): Element {
	return new JSDOM(`<article>${html}</article>`).window.document.querySelector(
		"article",
	) as Element;
}

function linkName(link: Element): string {
	const imageAlt = [...link.querySelectorAll("img")]
		.map((img) => img.getAttribute("alt") ?? "")
		.join(" ");
	return [
		link.getAttribute("aria-label") ?? "",
		link.textContent ?? "",
		imageAlt,
	]
		.join(" ")
		.trim();
}

function outlineLevel(heading: Element): number {
	return Number(heading.getAttribute("aria-level") ?? heading.tagName.slice(1));
}

describe("blog article accessibility", () => {
	test("posts load", () => {
		expect(posts.length).toBeGreaterThan(0);
	});

	test("every link in every article has an accessible name", () => {
		const unnamed = posts.flatMap((post) =>
			[...articleBody(post.html).querySelectorAll("a[href]")]
				.filter((link) => linkName(link) === "")
				.map((link) => `${post.slug}: ${link.getAttribute("href")}`),
		);
		expect(unnamed).toEqual([]);
	});

	test("article outlines start at level 2 and never skip a level", () => {
		const broken = posts.flatMap((post) => {
			const levels = [
				...articleBody(post.html).querySelectorAll("h1, h2, h3, h4, h5, h6"),
			].map(outlineLevel);
			const skips = levels.filter(
				(level, index) =>
					level > (index === 0 ? 2 : (levels[index - 1] ?? 2) + 1),
			);
			return skips.length > 0 ? [`${post.slug}: ${levels.join(",")}`] : [];
		});
		expect(broken).toEqual([]);
	});

	test("code blocks are keyboard focusable", () => {
		const unfocusable = posts.flatMap((post) =>
			[...articleBody(post.html).querySelectorAll("pre")]
				.filter((pre) => pre.getAttribute("tabindex") !== "0")
				.map(() => post.slug),
		);
		expect(unfocusable).toEqual([]);
	});

	test("section index still lists every h2 and h3 anchor", () => {
		for (const post of posts) {
			const anchors = articleBody(post.html).querySelectorAll(
				"h2[id], h3[id]",
			).length;
			expect(getBlogHeadings(post).length, post.slug).toBe(anchors);
		}
	});
});
