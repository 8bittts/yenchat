/**
 * Writes content/blog/slugs.json, the route index proxy.ts bundles for
 * blog.yen.chat: the published weekly issues, and each note's issue so an
 * old note address can 308 to its place inside that issue.
 *
 * Run after adding a week to content/blog/weeks.json or a note to
 * content/blog/posts/: bun scripts/gen-blog-slugs.ts
 * tests/158-blog-archive.test.ts fails when the file is stale.
 */

import { writeFileSync } from "node:fs";
import path from "node:path";
import { getBlogPosts } from "@/lib/blog";
import { getBlogWeekForPost, getBlogWeeks } from "@/lib/blog-weeks";

export function blogSlugIndex(): {
	weeks: string[];
	notes: Record<string, string>;
} {
	const notes: Record<string, string> = {};
	for (const post of [...getBlogPosts()].sort((a, b) =>
		a.slug.localeCompare(b.slug),
	)) {
		const week = getBlogWeekForPost(post);
		if (week) notes[post.slug] = week.slug;
	}
	return { weeks: getBlogWeeks().map((week) => week.slug), notes };
}

if (import.meta.main) {
	const file = path.join(process.cwd(), "content", "blog", "slugs.json");
	writeFileSync(file, `${JSON.stringify(blogSlugIndex(), null, "\t")}\n`);
	console.log(`RAN|gen-blog-slugs|file=${path.relative(process.cwd(), file)}`);
}
