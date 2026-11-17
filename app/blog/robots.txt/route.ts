// robots.txt served at https://blog.yen.chat/robots.txt; yen.chat keeps its own app/robots.ts.
import { BLOG_URL } from "@/lib/blog";

export const dynamic = "force-static";

export function GET(): Response {
	return new Response(
		`User-agent: *\nAllow: /\n\nSitemap: ${BLOG_URL}/sitemap.xml\n`,
		{ headers: { "Content-Type": "text/plain; charset=utf-8" } },
	);
}
