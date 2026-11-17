// RSS feed served at https://blog.yen.chat/feed (the address Substack used), so readers keep their subscription.
import {
	BLOG_DESCRIPTION,
	BLOG_TITLE,
	BLOG_URL,
	blogPostUrl,
	getBlogPosts,
} from "@/lib/blog";

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

export function GET(): Response {
	const posts = getBlogPosts();
	const items = posts.map((post) =>
		[
			"<item>",
			`<title>${escapeXml(post.title)}</title>`,
			`<description>${escapeXml(post.subtitle)}</description>`,
			`<link>${blogPostUrl(post.slug)}</link>`,
			`<guid isPermaLink="true">${blogPostUrl(post.slug)}</guid>`,
			`<pubDate>${new Date(post.publishedAt).toUTCString()}</pubDate>`,
			`<content:encoded>${cdata(absolutizeLinks(post.html))}</content:encoded>`,
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
		`<lastBuildDate>${new Date(posts[0]?.publishedAt ?? 0).toUTCString()}</lastBuildDate>`,
		...items,
		"</channel>",
		"</rss>",
	].join("\n");
	return new Response(xml, {
		headers: { "Content-Type": "application/rss+xml; charset=utf-8" },
	});
}
