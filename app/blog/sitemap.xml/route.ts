// Sitemap served at https://blog.yen.chat/sitemap.xml; yen.chat keeps its own app/sitemap.ts.
import { BLOG_URL, blogPostUrl, getBlogPosts } from "@/lib/blog";

export const dynamic = "force-static";

function urlEntry(loc: string, lastmod: string): string {
	return `<url><loc>${loc}</loc><lastmod>${lastmod.slice(0, 10)}</lastmod></url>`;
}

export function GET(): Response {
	const posts = getBlogPosts();
	const xml = [
		'<?xml version="1.0" encoding="UTF-8"?>',
		'<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
		urlEntry(`${BLOG_URL}/`, posts[0]?.publishedAt ?? ""),
		...posts.map((post) => urlEntry(blogPostUrl(post.slug), post.publishedAt)),
		"</urlset>",
	].join("\n");
	return new Response(xml, {
		headers: { "Content-Type": "application/xml; charset=utf-8" },
	});
}
