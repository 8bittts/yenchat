// RSS feed served at https://blog.yen.chat/feed (the address Substack used), so readers keep their subscription.
// One item per weekly issue; an old note guid no longer appears, so readers get each issue once.
import { BLOG_DESCRIPTION, BLOG_TITLE, BLOG_URL } from "@/lib/blog";
import {
	type BlogWeek,
	blogWeekUrl,
	getBlogWeeks,
	renderWeekNotes,
	weekKindLabel,
} from "@/lib/blog-weeks";

export const dynamic = "force-static";

function escapeXml(value: string): string {
	return value
		.replace(/&/g, "&amp;")
		.replace(/</g, "&lt;")
		.replace(/>/g, "&gt;")
		.replace(/"/g, "&quot;");
}

function cdata(value: string): string {
	return `<![CDATA[${value.replaceAll("]]>", "]]]]><![CDATA[>")}]]>`;
}

/** Root-relative post links and media resolve against the blog host for feed readers. */
function absolutizeLinks(html: string): string {
	return html
		.replace(/(href|src)="\/([^"]*)"/g, `$1="${BLOG_URL}/$2"`)
		.replace(/, \/blog-media\//g, `, ${BLOG_URL}/blog-media/`)
		.replace(/srcset="\/blog-media\//g, `srcset="${BLOG_URL}/blog-media/`);
}

/** The whole issue as feed HTML: technical updates, then the creator's notes. */
function issueHtml(week: BlogWeek): string {
	const updates = week.release
		? week.release.summary
				.split("\n\n")
				.map((paragraph) => `<p>${escapeXml(paragraph)}</p>`)
				.join("")
		: "<p>No build shipped this week.</p>";
	const notes = (title: string, posts: BlogWeek["notes"]) =>
		posts.length === 0
			? ""
			: `<h2>${title}</h2>${renderWeekNotes(posts, 4)
					.map(
						(note) =>
							`<h3 id="${note.post.slug}">${escapeXml(note.post.title)}</h3>${note.html}`,
					)
					.join("")}`;
	return `<h2>Technical updates</h2>${updates}${notes("Feature notes", week.features)}${notes("Notes from the creator", week.notes)}`;
}

export function GET(): Response {
	const weeks = getBlogWeeks();
	const items = weeks.map((week) =>
		[
			"<item>",
			`<title>${escapeXml(week.title)}</title>`,
			`<description>${escapeXml(week.deck)}</description>`,
			`<category>${escapeXml(weekKindLabel(week))}</category>`,
			`<link>${blogWeekUrl(week)}</link>`,
			`<guid isPermaLink="true">${blogWeekUrl(week)}</guid>`,
			`<pubDate>${new Date(week.publishedAt).toUTCString()}</pubDate>`,
			`<content:encoded>${cdata(absolutizeLinks(issueHtml(week)))}</content:encoded>`,
			"</item>",
		].join(""),
	);
	const xml = [
		'<?xml version="1.0" encoding="UTF-8"?>',
		'<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:atom="http://www.w3.org/2005/Atom">',
		"<channel>",
		`<title>${escapeXml(BLOG_TITLE)}</title>`,
		`<description>${escapeXml(BLOG_DESCRIPTION)}</description>`,
		`<link>${BLOG_URL}</link>`,
		`<atom:link href="${BLOG_URL}/feed" rel="self" type="application/rss+xml"/>`,
		`<lastBuildDate>${new Date(weeks[0]?.publishedAt ?? 0).toUTCString()}</lastBuildDate>`,
		...items,
		"</channel>",
		"</rss>",
	].join("\n");
	return new Response(xml, {
		headers: { "Content-Type": "application/rss+xml; charset=utf-8" },
	});
}
