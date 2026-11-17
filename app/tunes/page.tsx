import { buildPublicPageMetadata, PUBLIC_PAGE_SEO } from "@/lib/seo";
import { TunesClient } from "./tunes-client";

export const metadata = buildPublicPageMetadata(PUBLIC_PAGE_SEO.tunes);

export default function TunesPage() {
	return <TunesClient />;
}
