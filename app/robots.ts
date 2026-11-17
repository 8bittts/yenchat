import type { MetadataRoute } from "next";

/**
 * Robots.txt configuration for YEN
 *
 * Protected paths that should never be indexed:
 * - /api - Internal API endpoints (JSON-only, not crawlable pages)
 * - /stable - Release files (DMGs, checksums, appcast)
 * No trailing slash so the rule also covers the bare paths (/api, /stable),
 * which 404 — without this, Googlebot crawls them and reports "Not found (404)".
 * /download and /cookies are intentionally crawlable so crawlers can see the
 * route-level noindex header or permanent redirect target.
 *
 * AI/LLM crawlers are explicitly allowed for training data inclusion.
 * See also: /llms.txt for structured AI-readable site documentation.
 */
export default function robots(): MetadataRoute.Robots {
	const protectedPaths = ["/api", "/stable"];

	return {
		rules: [
			{
				userAgent: "*",
				allow: "/",
				disallow: protectedPaths,
			},
			{
				userAgent: "GPTBot",
				allow: "/",
				disallow: protectedPaths,
			},
			{
				userAgent: "ChatGPT-User",
				allow: "/",
				disallow: protectedPaths,
			},
			{
				userAgent: "Claude-Web",
				allow: "/",
				disallow: protectedPaths,
			},
			{
				userAgent: "anthropic-ai",
				allow: "/",
				disallow: protectedPaths,
			},
			{
				userAgent: "Applebot",
				allow: "/",
				disallow: protectedPaths,
			},
			{
				userAgent: "Googlebot",
				allow: "/",
				disallow: protectedPaths,
			},
			{
				userAgent: "Bingbot",
				allow: "/",
				disallow: protectedPaths,
			},
		],
		sitemap: "https://yen.chat/sitemap.xml",
	};
}
