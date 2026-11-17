import type { MetadataRoute } from "next";
import {
	getPublicLibrarySitemapEntries,
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
			url: `${SITE_URL}/docs`,
			lastModified: PUBLIC_LIBRARY_LAST_MODIFIED,
			changeFrequency: "weekly",
			priority: 0.9,
		},
		{
			url: `${SITE_URL}/tunes`,
			lastModified: PUBLIC_LIBRARY_LAST_MODIFIED,
			changeFrequency: "weekly",
			priority: 0.8,
		},
		{
			url: `${SITE_URL}/alternatives`,
			lastModified: PUBLIC_LIBRARY_LAST_MODIFIED,
			changeFrequency: "weekly",
			priority: 0.82,
		},
		{
			url: `${SITE_URL}/use-cases`,
			lastModified: PUBLIC_LIBRARY_LAST_MODIFIED,
			changeFrequency: "weekly",
			priority: 0.82,
		},
		...getPublicLibrarySitemapEntries(),
		{
			url: `${SITE_URL}/whitepaper.pdf`,
			lastModified: PUBLIC_LIBRARY_LAST_MODIFIED,
			changeFrequency: "monthly",
			priority: 0.7,
		},
		{
			url: `${SITE_URL}/terms`,
			lastModified: PUBLIC_LIBRARY_LAST_MODIFIED,
			changeFrequency: "yearly",
			priority: 0.3,
		},
	];
}
