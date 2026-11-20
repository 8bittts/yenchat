import type { Metadata } from "next";

export const SITE_URL = "https://yen.chat";
const DEFAULT_OG_IMAGE = {
	url: `${SITE_URL}/og-image.png`,
	width: 2004,
	height: 1262,
} as const;
export const SEO_TITLE_MAX_LENGTH = 60;
export const SEO_DESCRIPTION_MAX_LENGTH = 160;

export const PUBLIC_PAGE_SEO = {
	home: {
		title: "YEN - Fast GPU-Accelerated Terminal for macOS",
		description:
			"YEN is a fast GPU-accelerated macOS terminal whose panes keep running through a quit, crash, or update, with speech-to-text, browser preview, and IDE workflows.",
		url: SITE_URL,
		imageAlt: "YEN Terminal - Fast GPU-Accelerated Terminal",
	},
	docs: {
		title: "YEN Docs - Terminal Features, IDE Workflows, and CLI",
		description:
			"Set up YEN for macOS: terminal shortcuts, speech-to-text, themes, native WebKit browser preview, Git drawer, and CLI workflows with their requirements.",
		url: `${SITE_URL}/docs`,
		imageAlt: "YEN Documentation",
	},
	tunes: {
		title: "YEN Tunes - Music for Coding, Focus, and Deep Work",
		description:
			"YEN Tunes is music for coding, terminal sessions, focused work, and the beats behind every line of code written for YEN.",
		url: `${SITE_URL}/tunes`,
		imageAlt: "YEN Terminals and Tunes music project",
	},
	alternatives: {
		title: "YEN Terminal Alternatives for Developers",
		description:
			"Research-backed YEN alternative pages for developers comparing macOS terminals, AI terminals, IDEs, and terminal-first local workflows.",
		url: `${SITE_URL}/alternatives`,
		imageAlt: "YEN terminal alternatives research hub",
	},
	useCases: {
		title: "YEN Terminal Use Cases",
		description:
			"Focused YEN use cases for speech-to-text, native browser preview, local Git diffs, terminal IDE workflows, privacy, and GPU terminal work.",
		url: `${SITE_URL}/use-cases`,
		imageAlt: "YEN terminal use cases research hub",
	},
	privacy: {
		title: "YEN Privacy & Cookie Policy",
		description:
			"How YEN handles desktop app data, website analytics, cookies, update checks, and service providers.",
		url: `${SITE_URL}/privacy`,
		imageAlt: "YEN Privacy and Cookie Policy",
	},
	terms: {
		title: "YEN Terms & Privacy",
		description:
			"Terms of service, privacy policy, and cookie policy for YEN, the free GPU-accelerated macOS terminal, including data handling, license, and responsibilities.",
		url: `${SITE_URL}/terms`,
		imageAlt: "YEN Terms and Privacy Policy",
	},
	// Unlisted character bible (direct URL only — not sitemap / llms / nav).
	yeni: {
		title: "YENI — Canonical Character Bible",
		description:
			"The one locked character behind every YEN Tunes cover, loop, and thumbnail.",
		url: `${SITE_URL}/yeni`,
		imageAlt: "YENI face — locked canonical character portrait",
		image: {
			// Canonical front headshot (not a lifestyle scene) for social cards.
			url: `${SITE_URL}/yeni/yeni-canonical-front.png`,
			width: 1760,
			height: 2352,
		},
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
					type: "image/png",
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
