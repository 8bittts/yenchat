import { buildPublicPageMetadata, PUBLIC_PAGE_SEO } from "@/lib/seo";
import { getVersion } from "@/lib/version";
import { HomeClient } from "./home-client";

export const metadata = buildPublicPageMetadata(PUBLIC_PAGE_SEO.home);

export default function Home() {
	const version = getVersion();

	return <HomeClient version={version} />;
}
