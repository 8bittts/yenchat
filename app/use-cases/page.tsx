import type { Metadata } from "next";
import { PublicLibraryHub } from "@/components/library/public-library-hub";
import { getPublicLibraryPagesByKind } from "@/lib/library/public-pages";
import { buildLibraryHubMetadata } from "@/lib/library/slug-route";
import { PUBLIC_PAGE_SEO } from "@/lib/seo";

export const metadata: Metadata = buildLibraryHubMetadata(
	PUBLIC_PAGE_SEO.useCases,
);

export default function UseCasesPage() {
	return (
		<PublicLibraryHub
			kind="use-case"
			title="YEN terminal use cases"
			description="Focused pages for developers evaluating YEN around speech-to-text, browser preview, Git review, local IDE workflows, privacy, and GPU terminal work."
			pages={getPublicLibraryPagesByKind("use-case")}
		/>
	);
}
