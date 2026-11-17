import { buildPublicPageMetadata, PUBLIC_PAGE_SEO } from "@/lib/seo";
import { YeniClient } from "./yeni-client";

/**
 * Unlisted YENI character bible, served at https://yen.chat/yeni.
 *
 * Intentionally NOT added to app/sitemap.ts and NOT robots-blocked (per owner):
 * reachable by direct URL, but undiscoverable via listings/sitemap and unlinked
 * from the rest of the site. A normal app-router page (reuses Header/Footer/
 * DocNav/DocSection) — no special robots override, so it inherits the layout's
 * default indexable robots the same way the prior raw-HTML route did.
 *
 * Social cards must be page-local: without buildPublicPageMetadata here, crawlers
 * inherit the root layout homepage OG/Twitter tags (terminal product card).
 */
export const metadata = buildPublicPageMetadata(PUBLIC_PAGE_SEO.yeni);

export default function YeniPage() {
	return <YeniClient />;
}
