"use client";

import Link from "next/link";
import { DOWNLOAD_HREF } from "@/lib/analytics/download-cta";
import { trackProductEvent } from "@/lib/analytics/product-analytics";

interface TrackedDownloadLinkProps {
	/** Funnel label passed straight through to the `download_click` event. */
	location: string;
	className: string;
	children: React.ReactNode;
}

/**
 * Client island for a `/download` CTA that fires a Vercel Analytics event.
 *
 * This exists so a page whose ONLY client behavior is download tracking can
 * stay a Server Component. `/release` previously carried `"use client"` for
 * exactly these two handlers, which shipped the entire `RELEASE_WEEKS` dataset
 * and all of its paragraph splitting to the browser for no other reason.
 *
 * Keep the tracking here rather than in the pages: `track` pulls the analytics
 * runtime into whatever module imports it, so re-inlining it into a page
 * silently re-clientises that page's whole tree.
 */
export function TrackedDownloadLink({
	location,
	className,
	children,
}: TrackedDownloadLinkProps) {
	return (
		<Link
			href={DOWNLOAD_HREF}
			className={className}
			onClick={() => trackProductEvent("download_click", { location })}
		>
			{children}
		</Link>
	);
}
