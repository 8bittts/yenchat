import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { PublicLibraryPage } from "@/components/library/public-library-page";
import {
	getPublicLibraryPageByPath,
	isPublicLibraryPageEligible,
	type PublicLibraryPage as PublicLibraryPageModel,
	SITE_URL,
} from "@/lib/library/public-pages";
import { buildPublicPageMetadata } from "@/lib/seo";

/**
 * Shared implementation for the pSEO library routes (alternatives, use-cases) —
 * both the `[slug]` detail routes and the hub index pages. Each page is a thin
 * binding that supplies its kind-specific lookup / SEO entry.
 */
export type LibrarySlugParams = Promise<{ slug: string }>;

type LibraryHubSeo = {
	title: string;
	description: string;
	url: string;
	imageAlt: string;
};

export function buildLibraryHubMetadata(seo: LibraryHubSeo): Metadata {
	return buildPublicPageMetadata(seo);
}
type LibraryPageLookup = (slug: string) => PublicLibraryPageModel | undefined;

export async function buildLibrarySlugMetadata(
	lookup: LibraryPageLookup,
	params: LibrarySlugParams,
): Promise<Metadata> {
	const { slug } = await params;
	const page = lookup(slug);

	if (!page || !isPublicLibraryPageEligible(page)) {
		return {};
	}

	const url = `${SITE_URL}${page.path}`;

	return buildPublicPageMetadata({
		title: page.seo.title,
		description: page.seo.description,
		url,
		imageAlt: page.seo.imageAlt,
	});
}

export async function renderLibrarySlugPage(
	lookup: LibraryPageLookup,
	params: LibrarySlugParams,
) {
	const { slug } = await params;
	const page = lookup(slug);

	if (!page || !isPublicLibraryPageEligible(page)) {
		notFound();
	}

	const relatedPages = page.relatedPaths
		.map((path) => getPublicLibraryPageByPath(path))
		.filter((relatedPage): relatedPage is PublicLibraryPageModel =>
			Boolean(relatedPage && isPublicLibraryPageEligible(relatedPage)),
		);

	return <PublicLibraryPage page={page} relatedPages={relatedPages} />;
}
