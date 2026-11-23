import { describe, expect, test } from "bun:test";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import BLOG_SLUGS from "@/content/blog/slugs.json";
import WEEK_COPY from "@/content/blog/weeks.json";
import { BLOG_MEDIA_PATH, getBlogHeadings, getBlogPosts } from "@/lib/blog";
import { getArchiveByMonth } from "@/lib/blog-archive";
import {
	blogNoteHref,
	getAdjacentBlogWeeks,
	getBlogWeekForPost,
	getBlogWeeks,
	mondayOf,
	postDay,
	weekLabel,
} from "@/lib/blog-weeks";
import { routeBlogHostPath } from "@/lib/http/blog-host";
import { RELEASE_WEEKS } from "@/lib/release-notes/release-notes-data";
import { blogSlugIndex } from "@/scripts/gen-blog-slugs";

// The Substack export of blog.yen.chat held 53 published posts; every one must stay on the blog.
const ARCHIVED_POST_COUNT = 53;

const posts = getBlogPosts();
const weeks = getBlogWeeks();

function attributeValues(
	html: string,
	attribute: "href" | "src" | "srcset",
): string[] {
	return [...html.matchAll(new RegExp(`\\s${attribute}="([^"]*)"`, "g"))].map(
		(match) => match[1] ?? "",
	);
}

describe("blog.yen.chat archive", () => {
	test("keeps every published Substack post as a creator note, and the proxy slug index is current", () => {
		const imported = posts.filter((post) => /^\d+$/.test(post.postId));
		expect(imported).toHaveLength(ARCHIVED_POST_COUNT);
		// Substack posts are the creator's own; a post written for the site is
		// marked by who wrote it, never guessed from its id.
		for (const post of imported) expect(post.author).toBe("creator");
		for (const post of posts) {
			expect(post.author === "creator" || post.author === "agent").toBe(true);
		}
		expect(new Set(posts.map((post) => post.postId)).size).toBe(posts.length);
		const files = readdirSync("content/blog/posts").map((name) =>
			name.replace(/\.json$/, ""),
		);
		expect(files.sort()).toEqual(posts.map((post) => post.slug).sort());
		// bun scripts/gen-blog-slugs.ts rewrites the index proxy.ts bundles.
		expect(BLOG_SLUGS as ReturnType<typeof blogSlugIndex>).toEqual(
			blogSlugIndex(),
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

	test("leaves no Substack link, and every internal note link reaches a published issue", () => {
		const problems = posts.flatMap((post) =>
			attributeValues(post.html, "href")
				.filter((href) => {
					if (/substack\.com|blog\.yen\.chat\/p\//i.test(href)) return true;
					if (!href.startsWith("/") || href === "/") return false;
					if (href.startsWith(BLOG_MEDIA_PATH)) return false;
					const target = posts.find((other) => `/${other.slug}` === href);
					return !target || !blogNoteHref(target);
				})
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

	test("publishes one issue per week, on that week's Friday, newest first", () => {
		expect(weeks.length).toBe(WEEK_COPY.length);
		expect(new Set(weeks.map((week) => week.week)).size).toBe(weeks.length);
		for (const week of weeks) {
			const friday = new Date(`${week.slug}T00:00:00Z`);
			expect(friday.getUTCDay(), week.slug).toBe(5);
			expect(mondayOf(week.slug)).toBe(week.week);
			expect(week.publishedAt.slice(0, 10)).toBe(week.slug);
			if (week.release) expect(week.label).toBe(week.release.label);
			else expect(week.label).toBe(weekLabel(week.week));
		}
		const slugs = weeks.map((week) => week.slug);
		expect(slugs).toEqual([...slugs].sort().reverse());
	});

	test("every release week and every note belongs to exactly one published issue", () => {
		// Weeks whose Friday has not come yet are still open; everything older is published.
		const newest = weeks[0]?.week ?? "";
		for (const release of RELEASE_WEEKS) {
			if (release.iso > newest) continue;
			expect(
				weeks.filter((week) => week.release === release),
				release.iso,
			).toHaveLength(1);
		}
		for (const post of posts) {
			if (mondayOf(postDay(post)) > newest) continue;
			const holders = weeks.filter(
				(week) => week.notes.includes(post) || week.features.includes(post),
			);
			expect(holders, post.slug).toHaveLength(1);
			expect(holders[0]?.week).toBe(mondayOf(postDay(post)));
		}
	});

	test("a week with a creator note is a personal issue led by that note; any other week is an update", () => {
		for (const week of weeks) {
			const creator = week.notes.filter((post) => post.author === "creator");
			expect(creator).toEqual(week.notes);
			expect(week.features.every((post) => post.author === "agent")).toBe(true);
			if (week.notes.length > 0) {
				expect(week.kind, week.slug).toBe("personal");
				expect(week.title).toBe(week.notes[0]?.title ?? "");
			} else {
				expect(week.kind, week.slug).toBe("update");
			}
		}
		// The two notes written for the site in November are agent feature notes.
		const november = weeks.find((week) => week.slug === "2026-11-20");
		expect(november?.kind).toBe("update");
		expect(november?.features.map((post) => post.slug).sort()).toEqual([
			"agent-plans-in-the-menu-bar",
			"room-for-the-terminal",
		]);
	});

	test("every issue has its own social image on disk", () => {
		for (const week of weeks) {
			expect(existsSync(path.join("public", week.image.src)), week.slug).toBe(
				true,
			);
			expect(week.imageAlt.length).toBeGreaterThan(0);
		}
	});

	test("an old note address redirects into its issue, and an issue address is a page", () => {
		const skills = posts.find((post) => post.slug === "skills");
		const issue = skills ? getBlogWeekForPost(skills) : null;
		expect(issue?.slug).toBe("2026-03-06");
		expect(routeBlogHostPath("/skills")).toEqual({
			kind: "redirect",
			url: "https://blog.yen.chat/2026-03-06#skills",
		});
		expect(routeBlogHostPath("/p/skills")).toEqual({
			kind: "redirect",
			url: "https://blog.yen.chat/2026-03-06#skills",
		});
		expect(routeBlogHostPath("/2026-03-06")).toEqual({
			kind: "page",
			pathname: "/blog/2026-03-06",
		});
		for (const post of posts) {
			const route = routeBlogHostPath(`/${post.slug}`);
			expect(route.kind, post.slug).toBe("redirect");
		}
	});

	test("links neighbor issues and exposes note section headings", () => {
		const [first, second, third] = weeks;
		if (!first || !second || !third) throw new Error("archive too small");
		expect(getAdjacentBlogWeeks(second.slug)).toEqual({
			newer: first,
			older: third,
		});
		expect(getAdjacentBlogWeeks(first.slug).newer).toBeNull();
		const skills = posts.find((post) => post.slug === "skills");
		expect(skills && getBlogHeadings(skills.html).length).toBeGreaterThan(0);
	});

	test("no issue or note slug collides with a blog page route", () => {
		for (const reserved of ["releases", "feed", "sitemap.xml", "robots.txt"]) {
			expect(BLOG_SLUGS.weeks).not.toContain(reserved);
			expect(Object.keys(BLOG_SLUGS.notes)).not.toContain(reserved);
		}
	});

	test("the index groups every issue once by the month of its Friday", () => {
		const months = getArchiveByMonth();
		const listed = months.flatMap((month) =>
			month.weeks.map((week) => week.slug),
		);
		expect(listed).toEqual(weeks.map((week) => week.slug));
		expect(new Set(months.map((month) => month.id)).size).toBe(months.length);
		for (const month of months) {
			for (const week of month.weeks) {
				expect(week.slug.slice(0, 7)).toBe(
					new Date(`${month.label} 1 UTC`).toISOString().slice(0, 7),
				);
			}
		}
	});

	test("the release notes link each week to its issue", () => {
		const page = readFileSync("app/blog/releases/page.tsx", "utf8");
		expect(page).toContain("getBlogWeekForRelease");
		expect(page).not.toContain("getPostsForReleaseWeek");
	});
});
