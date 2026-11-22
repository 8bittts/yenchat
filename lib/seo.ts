import type { Metadata } from "next";

export const SITE_URL = "https://yen.chat";
const DEFAULT_OG_IMAGE = {
	url: `${SITE_URL}/og-image.png`,
	width: 1200,
	height: 630,
} as const;
export const SEO_TITLE_MAX_LENGTH = 60;
export const SEO_DESCRIPTION_MAX_LENGTH = 160;

export const PUBLIC_PAGE_SEO = {
	home: {
		title: "YEN - Fast GPU-Accelerated Terminal for macOS",
		description:
			"Quit YEN and return to the same running shell. Explore focused split panes, agent token counts, and the field guide for this independent macOS terminal.",
		url: SITE_URL,
		imageAlt: "YEN Terminal - Fast GPU-Accelerated Terminal",
	},
	terms: {
		title: "YEN Terms & Privacy",
		description:
			"Terms of service, privacy policy, and cookie policy for YEN, the free GPU-accelerated macOS terminal, including data handling, license, and responsibilities.",
		url: `${SITE_URL}/terms`,
		imageAlt: "YEN Terms and privacy with the desktop privacy receipt",
		image: { url: `${SITE_URL}/social/terms.png`, width: 1200, height: 630 },
	},
} as const;

export const INDEXABLE_ROBOTS: NonNullable<Metadata["robots"]> = {
	index: true,
	follow: true,
	googleBot: {
		index: true,
		follow: true,
		"max-video-preview": -1,
		"max-image-preview": "large",
		"max-snippet": -1,
	},
	"max-image-preview": "large",
	"max-snippet": -1,
};

export const NOINDEX_ROBOTS: NonNullable<Metadata["robots"]> = {
	index: false,
	follow: false,
	noarchive: true,
	noimageindex: true,
	nosnippet: true,
	nocache: true,
	googleBot: {
		index: false,
		follow: false,
		noarchive: true,
		noimageindex: true,
		nosnippet: true,
	},
};

interface SocialImageInput {
	url: string;
	width: number;
	height: number;
}

interface SocialMetadataInput {
	title: string;
	description: string;
	url: string;
	imageAlt: string;
	/** Defaults to the site-wide terminal OG card when omitted. */
	image?: SocialImageInput;
}

export function buildPublicPageMetadata(seo: SocialMetadataInput): Metadata {
	return {
		title: { absolute: seo.title },
		description: seo.description,
		...buildSocialMetadata(seo),
		alternates: { canonical: seo.url },
		robots: INDEXABLE_ROBOTS,
	};
}

export function buildSocialMetadata({
	title,
	description,
	url,
	imageAlt,
	image = DEFAULT_OG_IMAGE,
}: SocialMetadataInput): Pick<Metadata, "openGraph" | "twitter"> {
	return {
		openGraph: {
			type: "website",
			locale: "en_US",
			url,
			siteName: "YEN Terminal",
			title,
			description,
			images: [
				{
					url: image.url,
					width: image.width,
					height: image.height,
					alt: imageAlt,
				},
			],
		},
		twitter: {
			card: "summary_large_image",
			title,
			description,
			images: [
				{
					url: image.url,
					width: image.width,
					height: image.height,
					alt: imageAlt,
				},
			],
			creator: "@yenFTW",
			site: "@yenFTW",
		},
	};
}
