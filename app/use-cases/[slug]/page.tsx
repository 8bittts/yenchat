import type { Metadata } from "next";
import {
	getPublicLibraryPagesByKind,
	getUseCasePage,
} from "@/lib/library/public-pages";
import {
	buildLibrarySlugMetadata,
	type LibrarySlugParams,
	renderLibrarySlugPage,
} from "@/lib/library/slug-route";

interface UseCaseRouteProps {
	params: LibrarySlugParams;
}

export const dynamicParams = false;

export function generateStaticParams() {
	return getPublicLibraryPagesByKind("use-case").map((page) => ({
		slug: page.slug,
	}));
}

export function generateMetadata({
	params,
}: UseCaseRouteProps): Promise<Metadata> {
	return buildLibrarySlugMetadata(getUseCasePage, params);
}

export default function UseCasePage({ params }: UseCaseRouteProps) {
	return renderLibrarySlugPage(getUseCasePage, params);
}
