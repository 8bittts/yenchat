/**
 * Host routing for blog.yen.chat, applied by proxy.ts.
 *
 * The blog lives under app/blog/ and is served at the root of its own host:
 * `https://blog.yen.chat/skills` renders `/blog/skills`. Substack's
 * `/p/<slug>` addresses redirect to `/<slug>`, Substack-only pages redirect to
 * the blog index, and any other page path belongs to yen.chat.
 */

import BLOG_SLUGS from "@/content/blog/slugs.json";

export const BLOG_HOST = "blog.yen.chat";
const BLOG_ORIGIN = `https://${BLOG_HOST}`;
const MAIN_ORIGIN = "https://yen.chat";

const SLUGS: ReadonlySet<string> = new Set(BLOG_SLUGS);

/** Pages rendered as HTML, which need the route's CSP. */
const BLOG_PAGE_ROUTES: Readonly<Record<string, string>> = { "/": "/blog" };

/** Route handlers (feed, sitemap, robots) served without page CSP. */
const BLOG_FILE_ROUTES: Readonly<Record<string, string>> = {
	"/feed": "/blog/feed",
	"/sitemap.xml": "/blog/sitemap.xml",
	"/robots.txt": "/blog/robots.txt",
};

/** Substack-only pages that have no equivalent; they land on the blog index. */
const SUBSTACK_PAGE_PATTERN =
	/^\/(?:archive|about|subscribe|podcast|recommendations|leaderboard|notes|account|welcome|s|t)(?:\/.*)?$/;

/** Shared assets and infrastructure paths the blog pages load from their own host. */
const ASSET_PATH_PATTERN =
	/^\/(?:_next|_vercel|api|blog-media|favicons|doc-images|mascot|stable)(?:\/|$)|\/[^/]+\.[a-z0-9]+$/i;

export type BlogHostRoute =
	| { kind: "page"; pathname: string }
	| { kind: "file"; pathname: string }
	| { kind: "redirect"; url: string }
	| { kind: "asset" };

export function routeBlogHostPath(pathname: string): BlogHostRoute {
	const page = BLOG_PAGE_ROUTES[pathname];
	if (page) return { kind: "page", pathname: page };
	const file = BLOG_FILE_ROUTES[pathname];
	if (file) return { kind: "file", pathname: file };

	const slug = pathname.match(/^\/([^/]+)\/?$/)?.[1];
	if (slug && SLUGS.has(slug)) {
		return pathname.endsWith("/")
			? { kind: "redirect", url: `${BLOG_ORIGIN}/${slug}` }
			: { kind: "page", pathname: `/blog/${slug}` };
	}

	const legacySlug = pathname.match(/^\/p\/([^/]+)/)?.[1];
	if (legacySlug) {
		return {
			kind: "redirect",
			url: SLUGS.has(legacySlug)
				? `${BLOG_ORIGIN}/${legacySlug}`
				: `${BLOG_ORIGIN}/`,
		};
	}
	if (SUBSTACK_PAGE_PATTERN.test(pathname)) {
		return { kind: "redirect", url: `${BLOG_ORIGIN}/` };
	}
	if (ASSET_PATH_PATTERN.test(pathname)) return { kind: "asset" };
	// Any other page path, such as a typed /docs, is a yen.chat page.
	return { kind: "redirect", url: `${MAIN_ORIGIN}${pathname}` };
}

/** On yen.chat, /blog and /blog/<path> move to blog.yen.chat. */
export function blogUrlForMainHostPath(pathname: string): string | null {
	if (pathname === "/blog" || pathname === "/blog/") return `${BLOG_ORIGIN}/`;
	const rest = pathname.match(/^\/blog\/(.+)$/)?.[1];
	return rest ? `${BLOG_ORIGIN}/${rest}` : null;
}
