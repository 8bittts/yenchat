import {
	isPublicLibraryPageEligible,
	PUBLIC_LIBRARY_LAST_MODIFIED,
	PUBLIC_LIBRARY_PAGES,
	type PublicLibraryPage,
	SITE_URL,
} from "@/lib/library/public-pages";

export type SeoInventoryFamily = "Core" | "Hub" | "Alternative" | "Use case";

export interface SeoInventoryPage {
	family: SeoInventoryFamily;
	title: string;
	path: string;
	description: string;
	sitemapIncluded: boolean;
	indexable: boolean;
	evidenceScore?: number;
	sourceCount?: number;
	lastModified: Date;
}

const CORE_SEO_PAGES = [
	{
		family: "Core",
		title: "YEN",
		path: "/",
		description: "Primary product page.",
	},
	{
		family: "Core",
		title: "Docs",
		path: "/docs",
		description: "Product documentation and feature proof.",
	},
	{
		family: "Core",
		title: "Terminals and Tunes",
		path: "/tunes",
		description: "Sister music-production project page.",
	},
	{
		family: "Core",
		title: "Whitepaper",
		path: "/whitepaper.pdf",
		description: "Public PDF asset.",
	},
	{
		family: "Core",
		title: "Terms & Privacy",
		path: "/terms",
		description: "Combined terms, privacy, and cookie policy page.",
	},
] as const satisfies readonly Omit<
	SeoInventoryPage,
	"sitemapIncluded" | "indexable" | "lastModified"
>[];

const HUB_SEO_PAGES = [
	{
		family: "Hub",
		title: "Alternatives",
		path: "/alternatives",
		description: "Index for terminal and IDE alternative pages.",
	},
	{
		family: "Hub",
		title: "Use cases",
		path: "/use-cases",
		description: "Index for workflow-oriented terminal use-case pages.",
	},
] as const satisfies readonly Omit<
	SeoInventoryPage,
	"sitemapIncluded" | "indexable" | "lastModified"
>[];

function withPublicStatus(
	page: Omit<
		SeoInventoryPage,
		"sitemapIncluded" | "indexable" | "lastModified"
	>,
): SeoInventoryPage {
	return {
		...page,
		sitemapIncluded: true,
		indexable: true,
		lastModified: PUBLIC_LIBRARY_LAST_MODIFIED,
	};
}

function publicLibraryPageToInventoryPage(
	page: PublicLibraryPage,
): SeoInventoryPage {
	return {
		family: page.kind === "alternative" ? "Alternative" : "Use case",
		title: page.seo.title,
		path: page.path,
		description: page.seo.description,
		sitemapIncluded: true,
		indexable: true,
		evidenceScore: page.evidenceScore,
		sourceCount: page.officialSources.length + page.yenProofPoints.length,
		lastModified: page.lastModified,
	};
}

export function getLibrarySeoInventory() {
	const alternativePages: SeoInventoryPage[] = [];
	const useCasePages: SeoInventoryPage[] = [];

	for (const page of PUBLIC_LIBRARY_PAGES) {
		if (!isPublicLibraryPageEligible(page)) {
			continue;
		}

		const inventoryPage = publicLibraryPageToInventoryPage(page);
		if (page.kind === "alternative") {
			alternativePages.push(inventoryPage);
			continue;
		}

		useCasePages.push(inventoryPage);
	}

	const corePages = CORE_SEO_PAGES.map(withPublicStatus);
	const hubPages = HUB_SEO_PAGES.map(withPublicStatus);
	const sitemapPages = [
		...corePages.slice(0, 3),
		...hubPages,
		...alternativePages,
		...useCasePages,
		...corePages.slice(3),
	];

	return {
		siteUrl: SITE_URL,
		corePages,
		hubPages,
		alternativePages,
		useCasePages,
		sitemapPages,
		privateWorkbench: {
			title: "Page library",
			path: "/library",
			indexable: false,
			sitemapIncluded: false,
		},
	};
}
