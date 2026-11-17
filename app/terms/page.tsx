import { LEGAL_LAST_UPDATED } from "@/lib/legal";
import { LEGAL_COMBINED_NAV_ITEMS } from "@/lib/legal-nav";
import { buildPublicPageMetadata, PUBLIC_PAGE_SEO } from "@/lib/seo";
import { TermsPageClient } from "./terms-client";

export const metadata = buildPublicPageMetadata(PUBLIC_PAGE_SEO.terms);

export default function TermsPage() {
	return (
		<TermsPageClient
			navItems={LEGAL_COMBINED_NAV_ITEMS}
			lastUpdated={LEGAL_LAST_UPDATED}
		/>
	);
}
