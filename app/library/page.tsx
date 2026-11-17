import type { Metadata } from "next";
import { getLibrarySeoInventory } from "@/lib/library/seo-inventory";
import { NOINDEX_ROBOTS } from "@/lib/seo";
import { LibraryClient } from "./library-client";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
	title: "YEN Page Library",
	description: "A direct list of YEN pages.",
	robots: NOINDEX_ROBOTS,
};

export default async function LibraryPage() {
	const inventory = getLibrarySeoInventory();

	return (
		<LibraryClient
			sections={[
				{
					id: "core-pages",
					title: "Core pages",
					pages: [
						...inventory.corePages.filter(
							(page) => page.path !== "/whitepaper.pdf",
						),
						...inventory.hubPages,
					],
				},
				{
					id: "alternative-pages",
					title: "Alternative pages",
					pages: inventory.alternativePages,
				},
				{
					id: "use-case-pages",
					title: "Use-case pages",
					pages: inventory.useCasePages,
				},
			]}
		/>
	);
}
