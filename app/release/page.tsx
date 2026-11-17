import { buildPublicPageMetadata, PUBLIC_PAGE_SEO } from "@/lib/seo";
import { ReleasePageClient } from "./release-client";

export const metadata = buildPublicPageMetadata(PUBLIC_PAGE_SEO.release);

export default function ReleasePage() {
	return <ReleasePageClient />;
}
