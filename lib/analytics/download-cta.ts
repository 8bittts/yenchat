/**
 * The one on-site download URL. `/download` redirects to the current DMG on GitHub
 * Releases; downloads are not recorded.
 *
 * Client-safe: imported by client components, so it must stay free of server-only imports.
 */
export const DOWNLOAD_HREF = "/download";

export function isDownloadHref(href: string): boolean {
	return href === DOWNLOAD_HREF || href.startsWith(`${DOWNLOAD_HREF}?`);
}
