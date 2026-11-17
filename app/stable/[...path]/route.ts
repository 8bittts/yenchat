import { realpathSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { isAbsolute, relative, resolve } from "node:path";
import { type NextRequest, NextResponse } from "next/server";

const NOINDEX_HEADER = "noindex, nofollow, noarchive, nosnippet, noimageindex";

function stableNotFoundResponse() {
	return new NextResponse("Not Found", {
		status: 404,
		headers: {
			"X-Robots-Tag": NOINDEX_HEADER,
		},
	});
}

function isUnsafeStablePathSegment(segment: string): boolean {
	return (
		!segment ||
		segment === "." ||
		segment === ".." ||
		segment.includes("/") ||
		segment.includes("\\") ||
		segment.includes("\0")
	);
}

function isOutsideBasePath(basePath: string, candidatePath: string): boolean {
	const rel = relative(basePath, candidatePath);
	return rel.startsWith("..") || isAbsolute(rel);
}

function buildAttachmentDisposition(filename: string): string {
	const safeFilename = filename.replace(/["\\\r\n]/g, "_");
	const encodedFilename = encodeURIComponent(safeFilename);
	return `attachment; filename="${safeFilename}"; filename*=UTF-8''${encodedFilename}`;
}

// Next.js serves public/ statically, so this route only handles edge cases;
// the primary serving mechanism is Vercel's CDN.
export async function GET(
	_request: NextRequest,
	{ params }: { params: Promise<{ path: string[] }> },
) {
	try {
		const { path } = await params;

		if (!path || path.length === 0) {
			return stableNotFoundResponse();
		}

		const sanitizedPath = path.filter(
			(segment) => !isUnsafeStablePathSegment(segment),
		);

		if (sanitizedPath.length !== path.length) {
			return stableNotFoundResponse();
		}

		const basePath = resolve(process.cwd(), "public", "stable");
		const filePath = resolve(basePath, ...sanitizedPath);

		if (isOutsideBasePath(basePath, filePath)) {
			return stableNotFoundResponse();
		}

		// Defense-in-depth: Resolve symlinks and verify real path is within base directory
		let realPath: string;
		try {
			realPath = realpathSync(filePath);
			const realBasePath = realpathSync(basePath);
			if (isOutsideBasePath(realBasePath, realPath)) {
				return stableNotFoundResponse();
			}
		} catch {
			// File doesn't exist or can't be resolved — treat as 404
			return stableNotFoundResponse();
		}

		// realPath is derived from request params; each request reads a different file from public/stable/.
		// react-doctor-disable-next-line react-doctor/server-hoist-static-io
		const file = await readFile(realPath);

		// Determine content type based on file extension
		const lastSegment = sanitizedPath[sanitizedPath.length - 1];
		const ext = lastSegment?.split(".").pop()?.toLowerCase() || "";
		const contentType = getContentType(ext);

		// Build headers for safe downloads
		// Use short cache for the update feed (appcast.xml) and the version
		// manifest (version.json) — both should be fresh, matching the 300s
		// policy in vercel.json. version.sig is left immutable (vercel.json).
		// Use long cache for immutable files (dmg, checksum)
		const isShortCache =
			lastSegment === "appcast.xml" || lastSegment === "version.json";
		const cacheControl = isShortCache
			? "public, max-age=300, stale-while-revalidate=60"
			: "public, max-age=31536000, immutable";

		const isAttachment = ext === "dmg" || ext === "zip";

		return new NextResponse(file, {
			headers: {
				"Content-Type": contentType,
				"Cache-Control": cacheControl,
				"X-Content-Type-Options": "nosniff",
				"X-Robots-Tag": NOINDEX_HEADER,
				...(isAttachment && lastSegment
					? {
							"Content-Disposition": buildAttachmentDisposition(lastSegment),
							"Content-Length": file.length.toString(),
							"X-Download-Options": "noopen",
							"Cross-Origin-Resource-Policy": "cross-origin",
						}
					: {}),
			},
		});
	} catch (error) {
		// Log error for debugging but don't expose details to client
		const errorMessage =
			error instanceof Error ? error.message : "Unknown error";
		// biome-ignore lint/suspicious/noConsole: Server-side error logging for production debugging
		console.error("Error serving file from public/stable/:", errorMessage);
		return stableNotFoundResponse();
	}
}

function getContentType(ext: string): string {
	const types: Record<string, string> = {
		dmg: "application/x-apple-diskimage",
		zip: "application/zip",
		json: "application/json",
		xml: "application/xml",
		md: "text/markdown",
		txt: "text/plain",
		sha256: "text/plain",
	};
	return types[ext] || "application/octet-stream";
}
