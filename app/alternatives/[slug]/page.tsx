import type { Metadata } from "next";
import {
	getAlternativePage,
	getPublicLibraryPagesByKind,
} from "@/lib/library/public-pages";
import {
	buildLibrarySlugMetadata,
	type LibrarySlugParams,
	renderLibrarySlugPage,
} from "@/lib/library/slug-route";

interface AlternativeRouteProps {
	params: LibrarySlugParams;
}

export const dynamicParams = false;

export function generateStaticParams() {
	return getPublicLibraryPagesByKind("alternative").map((page) => ({
		slug: page.slug,
	}));
}

export function generateMetadata({
	params,
}: AlternativeRouteProps): Promise<Metadata> {
	return buildLibrarySlugMetadata(getAlternativePage, params);
}

export default function AlternativePage({ params }: AlternativeRouteProps) {
	return renderLibrarySlugPage(getAlternativePage, params);
}
