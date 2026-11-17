import { Analytics } from "@vercel/analytics/next";
import { SpeedInsights } from "@vercel/speed-insights/next";
import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { ThemeProvider } from "@/components/shared/theme-provider";
import { DEVELOPMENT_CSP_NONCE } from "@/lib/csp/development";
import {
	ORGANIZATION_STRUCTURED_DATA_SCRIPT,
	THEME_COLOR_BOOTSTRAP_SCRIPT,
	WEBSITE_STRUCTURED_DATA_SCRIPT,
} from "@/lib/csp/inline-scripts";
import {
	buildSocialMetadata,
	INDEXABLE_ROBOTS,
	PUBLIC_PAGE_SEO,
} from "@/lib/seo";
import { COLORS } from "./constants";
import "./globals.css";

const geistSans = Geist({
	variable: "--font-geist-sans",
	subsets: ["latin"],
	display: "swap",
	preload: true,
});

const geistMono = Geist_Mono({
	variable: "--font-geist-mono",
	subsets: ["latin"],
	display: "swap",
	preload: true,
});

export const viewport: Viewport = {
	width: "device-width",
	initialScale: 1,
	maximumScale: 5,
	userScalable: true,
	viewportFit: "cover",
	colorScheme: "light dark",
};

export const metadata: Metadata = {
	metadataBase: new URL("https://yen.chat"),
	title: {
		default: PUBLIC_PAGE_SEO.home.title,
		template: "%s | YEN",
	},
	description: PUBLIC_PAGE_SEO.home.description,
	authors: [
		{
			name: "YEN",
			url: "https://yen.chat",
		},
	],
	creator: "YEN",
	publisher: "YEN",
	robots: INDEXABLE_ROBOTS,
	...buildSocialMetadata({
		title: PUBLIC_PAGE_SEO.home.title,
		description: PUBLIC_PAGE_SEO.home.description,
		url: PUBLIC_PAGE_SEO.home.url,
		imageAlt: PUBLIC_PAGE_SEO.home.imageAlt,
	}),
	category: "Productivity",
	applicationName: "YEN",
	appleWebApp: {
		capable: true,
		statusBarStyle: "black-translucent",
		title: "YEN Terminal",
	},
	formatDetection: {
		telephone: false,
		email: false,
		address: false,
	},
	icons: {
		icon: [
			{ url: "/favicons/favicon.ico", sizes: "any" },
			{ url: "/favicons/favicon-16x16.png", sizes: "16x16", type: "image/png" },
			{ url: "/favicons/favicon-32x32.png", sizes: "32x32", type: "image/png" },
		],
		apple: "/favicons/apple-touch-icon.png",
		shortcut: "/favicons/favicon.ico",
	},
};

export default function RootLayout({
	children,
}: Readonly<{
	children: React.ReactNode;
}>) {
	const developmentNonce =
		process.env.NODE_ENV === "development" ? DEVELOPMENT_CSP_NONCE : undefined;

	return (
		<html lang="en" className="scroll-smooth" suppressHydrationWarning>
			<head>
				<meta charSet="utf-8" />
				{/* apple-mobile-web-app-* is emitted by metadata.appleWebApp; the
				    obsolete X-UA-Compatible (IE-only) meta was removed. */}
				{/* Background color from constants (matches --background ≈ #f5f5f0) */}
				<meta name="theme-color" content={COLORS.background} />
				<meta name="msapplication-TileColor" content={COLORS.background} />
				{/* Pre-paint theme-color sync: next-themes sets the html class before
				    paint but not the theme-color meta, so dark-mode users otherwise
				    saw a light browser-chrome flash. ThemeMetaSync keeps it live after. */}
				{/* react-doctor-disable-next-line react/no-danger */}
				<script
					nonce={developmentNonce}
					suppressHydrationWarning
					dangerouslySetInnerHTML={{
						__html: THEME_COLOR_BOOTSTRAP_SCRIPT,
					}}
				/>
				<link rel="manifest" href="/manifest.webmanifest" />
				<link rel="sitemap" type="application/xml" href="/sitemap.xml" />
				<link rel="author" href="/llms.txt" />
				{/* JSON-LD Structured Data for SEO and LLMs. Content is static JSON.stringify output, no user input. */}
				{/* react-doctor-disable-next-line react/no-danger */}
				<script
					type="application/ld+json"
					nonce={developmentNonce}
					suppressHydrationWarning
					dangerouslySetInnerHTML={{
						__html: ORGANIZATION_STRUCTURED_DATA_SCRIPT,
					}}
				/>
				{/* react-doctor-disable-next-line react/no-danger */}
				<script
					type="application/ld+json"
					nonce={developmentNonce}
					suppressHydrationWarning
					dangerouslySetInnerHTML={{
						__html: WEBSITE_STRUCTURED_DATA_SCRIPT,
					}}
				/>
			</head>
			<body
				className={`${geistSans.variable} ${geistMono.variable} antialiased`}
			>
				<ThemeProvider nonce={developmentNonce}>
					{children}
					{process.env.NODE_ENV === "production" && (
						<>
							<Analytics />
							<SpeedInsights />
						</>
					)}
				</ThemeProvider>
			</body>
		</html>
	);
}
