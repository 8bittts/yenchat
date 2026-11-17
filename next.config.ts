import type { NextConfig } from "next";
import { computeWebBuildId } from "./scripts/lib/web-build-id";

const nextConfig: NextConfig = {
	reactStrictMode: true,
	compress: true,
	poweredByHeader: false,
	productionBrowserSourceMaps: false,
	generateBuildId: async () => computeWebBuildId(),
	images: {
		formats: ["image/avif", "image/webp"],
		deviceSizes: [640, 750, 828, 1080, 1200, 1920, 2048, 3840],
		imageSizes: [16, 32, 48, 64, 96, 128, 256, 384],
		minimumCacheTTL: 31536000,
	},
	outputFileTracingExcludes: {
		"*": [
			"yen-terminal/**",
			"pkg/**",
			"tools/**",
			"scripts/**",
			"_docs/**",
			"public/stable/*.dmg",
			"public/stable/*.zip",
			"public/doc-images/*.mp4",
			"public/mascot/*.mp4",
			// blog.yen.chat post media is served statically, never read by a function.
			"public/blog-media/**",
		],
	},
	experimental: {
		optimizePackageImports: ["@vercel/analytics", "@vercel/speed-insights"],
	},
	// Cache + baseline security headers are defined in vercel.json.
	// CSP is selected in proxy.ts from the build-verified static hash manifest or
	// a per-request nonce for dynamic/error fallbacks.
};

export default nextConfig;
