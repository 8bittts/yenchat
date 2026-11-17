import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { type NextRequest, NextResponse } from "next/server";
import { RELEASE_HOSTNAME, RELEASES_PATH_PREFIX } from "@/lib/release-host";

const NOINDEX_HEADER = "noindex, nofollow, noarchive, nosnippet, noimageindex";

function downloadNotFoundResponse() {
	return new NextResponse("Download not available", {
		status: 404,
		headers: {
			"Cache-Control": "no-store",
			"X-Robots-Tag": NOINDEX_HEADER,
		},
	});
}

function downloadPrefetchResponse() {
	return new NextResponse(null, {
		status: 204,
		headers: {
			"Cache-Control": "no-store",
			"X-Robots-Tag": NOINDEX_HEADER,
		},
	});
}

export function resolveDownloadRedirectTarget(raw: unknown): string | null {
	if (typeof raw !== "string") {
		return null;
	}
	const trimmed = raw.trim();
	if (!trimmed) {
		return null;
	}

	try {
		const parsed = new URL(trimmed);
		if (parsed.protocol !== "https:") {
			return null;
		}
		if (
			parsed.hostname !== RELEASE_HOSTNAME ||
			parsed.pathname.length <= RELEASES_PATH_PREFIX.length ||
			!parsed.pathname.startsWith(RELEASES_PATH_PREFIX) ||
			!parsed.pathname.toLowerCase().endsWith(".dmg")
		) {
			return null;
		}
		if (parsed.username || parsed.password || parsed.search || parsed.hash) {
			return null;
		}
		return parsed.toString();
	} catch {
		return null;
	}
}

function isPrefetchRequest(request: Request) {
	const purpose = request.headers.get("purpose")?.toLowerCase();
	const secPurpose = request.headers.get("sec-purpose")?.toLowerCase();
	return (
		request.headers.has("next-router-prefetch") ||
		purpose?.includes("prefetch") === true ||
		secPurpose?.includes("prefetch") === true
	);
}

type ReleaseRedirectManifest = {
	url: string;
};

// Read version manifest once per Fluid Compute instance, not per request.
// version.json ships with the deploy bundle and is replaced by the release pipeline,
// so the cached value is always the version that was current at instance cold-start.
const RELEASE_REDIRECT_MANIFEST: ReleaseRedirectManifest | null =
	await (async () => {
		try {
			const versionPath = join(
				process.cwd(),
				"public",
				"stable",
				"version.json",
			);
			const versionData = await readFile(versionPath, "utf-8");
			const versionJson = JSON.parse(versionData);
			const url = resolveDownloadRedirectTarget(versionJson.url);
			if (!url) {
				return null;
			}
			return { url };
		} catch (error) {
			const errorMessage =
				error instanceof Error ? error.message : "Unknown error";
			// biome-ignore lint/suspicious/noConsole: Boot-time diagnostic for missing/malformed version.json
			console.error("Error loading download manifest:", errorMessage);
			return null;
		}
	})();

// Stable marketing URL that redirects to the latest DMG on GitHub Releases;
// version.json is read at module load. Downloads are not recorded.
export async function GET(request: NextRequest) {
	if (isPrefetchRequest(request)) {
		return downloadPrefetchResponse();
	}
	if (!RELEASE_REDIRECT_MANIFEST) {
		return downloadNotFoundResponse();
	}

	return NextResponse.redirect(RELEASE_REDIRECT_MANIFEST.url, {
		status: 302,
		headers: {
			"Cache-Control": "no-store",
			"X-Robots-Tag": NOINDEX_HEADER,
		},
	});
}
