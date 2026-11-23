// Sitemap served at https://blog.yen.chat/sitemap.xml; yen.chat keeps its own app/sitemap.ts.
import { BLOG_URL } from "@/lib/blog";
import { RELEASES_PATH } from "@/lib/blog-archive";
import { blogWeekUrl, getBlogWeeks } from "@/lib/blog-weeks";
import { RELEASE_WEEKS } from "@/lib/release-notes/release-notes-data";

export const dynamic = "force-static";

function urlEntry(loc: string, lastmod: string): string {
	return `<url><loc>${loc}</loc><lastmod>${lastmod.slice(0, 10)}</lastmod></url>`;
}

// Old note addresses 308 into their issue, so the sitemap lists issues only.
export function GET(): Response {
	const weeks = getBlogWeeks();
	const xml = [
		'<?xml version="1.0" encoding="UTF-8"?>',
		'<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
		urlEntry(`${BLOG_URL}/`, weeks[0]?.publishedAt ?? ""),
		urlEntry(
			`${BLOG_URL}${RELEASES_PATH}`,
			RELEASE_WEEKS[0]?.versions[0]?.shippedOn ?? "",
		),
		...weeks.map((week) => urlEntry(blogWeekUrl(week), week.publishedAt)),
		"</urlset>",
	].join("\n");
	return new Response(xml, {
		headers: { "Content-Type": "application/xml; charset=utf-8" },
	});
}
