import { describe, expect, test } from "bun:test";
import { JSDOM } from "jsdom";
import { getBlogHeadings } from "@/lib/blog";
import { getBlogWeeks, renderWeekNotes } from "@/lib/blog-weeks";

// Notes render inside a weekly issue: issue h1 > section h2 > note title h3,
// so a note's own headings start at level 4. Screen readers need a named link
// for every image link, an outline without skipped levels, keyboard access to
// code blocks that scroll sideways on a phone, and ids that are unique on the
// whole issue page.

const NOTE_FIRST_LEVEL = 4;
const issues = getBlogWeeks().map((week) => ({
	week,
	notes: renderWeekNotes([...week.features, ...week.notes], NOTE_FIRST_LEVEL),
}));
const notes = issues.flatMap((issue) => issue.notes);

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

describe("blog issue accessibility", () => {
	test("issues and notes load", () => {
		expect(issues.length).toBeGreaterThan(0);
		expect(notes.length).toBeGreaterThan(0);
	});

	test("every link in every note has an accessible name", () => {
		const unnamed = notes.flatMap((note) =>
			[...articleBody(note.html).querySelectorAll("a[href]")]
				.filter((link) => linkName(link) === "")
				.map((link) => `${note.post.slug}: ${link.getAttribute("href")}`),
		);
		expect(unnamed).toEqual([]);
	});

	test("note outlines start under the note title and never skip a level", () => {
		const broken = notes.flatMap((note) => {
			const levels = [
				...articleBody(note.html).querySelectorAll("h1, h2, h3, h4, h5, h6"),
			].map(outlineLevel);
			const skips = levels.filter(
				(level, index) =>
					level < NOTE_FIRST_LEVEL ||
					level >
						(index === 0
							? NOTE_FIRST_LEVEL
							: (levels[index - 1] ?? NOTE_FIRST_LEVEL) + 1),
			);
			return skips.length > 0 ? [`${note.post.slug}: ${levels.join(",")}`] : [];
		});
		expect(broken).toEqual([]);
	});

	test("code blocks are keyboard focusable", () => {
		const unfocusable = notes.flatMap((note) =>
			[...articleBody(note.html).querySelectorAll("pre")]
				.filter((pre) => pre.getAttribute("tabindex") !== "0")
				.map(() => note.post.slug),
		);
		expect(unfocusable).toEqual([]);
	});

	test("every id on an issue page is unique, and in-note links follow renamed ids", () => {
		for (const issue of issues) {
			const ids = [
				"technical-updates",
				"notes-from-the-creator",
				...issue.notes.flatMap((note) => [
					note.post.slug,
					...[...articleBody(note.html).querySelectorAll("[id]")].map(
						(element) => element.id,
					),
				]),
			];
			expect(ids.length, issue.week.slug).toBe(new Set(ids).size);
			for (const note of issue.notes) {
				const body = articleBody(note.html);
				for (const link of body.querySelectorAll('a[href^="#"]')) {
					const target = link.getAttribute("href")?.slice(1) ?? "";
					expect(ids, `${note.post.slug} -> #${target}`).toContain(target);
				}
			}
		}
	});

	test("section index still lists every h2 and h3 anchor of a note", () => {
		for (const note of notes) {
			const anchors = articleBody(note.html).querySelectorAll(
				"h2[id], h3[id]",
			).length;
			expect(getBlogHeadings(note.html).length, note.post.slug).toBe(anchors);
		}
	});
});
