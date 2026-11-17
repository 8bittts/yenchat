import type { MetadataRoute } from "next";
import { COLORS } from "./constants";

export default function manifest(): MetadataRoute.Manifest {
	return {
		name: "YEN - Fast GPU-Accelerated Terminal for macOS",
		short_name: "YEN",
		description:
			"GPU-accelerated terminal for macOS with command palette, file browser, and native WebKit browser preview. Metal rendering and native macOS controls.",
		start_url: "/",
		scope: "/",
		display: "standalone",
		orientation: "portrait-primary",
		theme_color: COLORS.brand,
		background_color: COLORS.background,
		icons: [
			{
				src: "/favicons/favicon-16x16.png",
				sizes: "16x16",
				type: "image/png",
			},
			{
				src: "/favicons/favicon-32x32.png",
				sizes: "32x32",
				type: "image/png",
			},
			{
				src: "/favicons/android-chrome-192x192.png",
				sizes: "192x192",
				type: "image/png",
				purpose: "any",
			},
			{
				src: "/favicons/android-chrome-512x512.png",
				sizes: "512x512",
				type: "image/png",
				purpose: "maskable",
			},
			{
				src: "/favicons/apple-touch-icon.png",
				sizes: "180x180",
				type: "image/png",
			},
		],
		categories: ["productivity", "utilities", "developer tools"],
	};
}
