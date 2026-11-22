import type { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/seo";
export default function sitemap(): MetadataRoute.Sitemap {
	return [
		{
			url: SITE_URL,
			changeFrequency: "weekly",
			priority: 1.0,
		},
		{
			url: `${SITE_URL}/terms`,
			changeFrequency: "yearly",
			priority: 0.3,
		},
	];
}
