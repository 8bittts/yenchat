import type { Metadata } from "next";
import { PublicLibraryHub } from "@/components/library/public-library-hub";
import { getPublicLibraryPagesByKind } from "@/lib/library/public-pages";
import { buildLibraryHubMetadata } from "@/lib/library/slug-route";
import { PUBLIC_PAGE_SEO } from "@/lib/seo";

export const metadata: Metadata = buildLibraryHubMetadata(
	PUBLIC_PAGE_SEO.alternatives,
);

export default function AlternativesPage() {
	return (
		<PublicLibraryHub
			kind="alternative"
			title="YEN terminal alternatives"
			description="Research-backed alternative pages for developers comparing YEN against terminal apps, AI terminals, and IDE-centered workflows."
			pages={getPublicLibraryPagesByKind("alternative")}
		/>
	);
}
