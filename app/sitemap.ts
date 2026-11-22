import type { MetadataRoute } from "next";
import {
	PUBLIC_LIBRARY_LAST_MODIFIED,
	SITE_URL,
} from "@/lib/library/public-pages";

export default function sitemap(): MetadataRoute.Sitemap {
	return [
		{
			url: SITE_URL,
			lastModified: PUBLIC_LIBRARY_LAST_MODIFIED,
			changeFrequency: "weekly",
			priority: 1.0,
		},
		{
			url: `${SITE_URL}/terms`,
			lastModified: PUBLIC_LIBRARY_LAST_MODIFIED,
			changeFrequency: "yearly",
			priority: 0.3,
		},
	];
}
