import { readFileSync } from "node:fs";
import { join } from "node:path";
import { assertValidReleaseVersion } from "./version-format";

interface VersionData {
	version: string;
}

// Single source of truth for all version numbers.
function getVersionData(): VersionData {
	const versionPath = join(process.cwd(), "public/stable/version.json");

	try {
		const versionData = readFileSync(versionPath, "utf-8");
		const parsed = JSON.parse(versionData) as Partial<VersionData>;
		if (typeof parsed.version !== "string") {
			throw new Error(`Missing version in ${versionPath}`);
		}

		assertValidReleaseVersion(parsed.version);
		return { version: parsed.version };
	} catch (error) {
		if (
			typeof error === "object" &&
			error !== null &&
			"code" in error &&
			error.code === "ENOENT"
		) {
			// Fallback if file doesn't exist (e.g., during initial setup)
			return { version: "0.001" };
		}

		throw error;
	}
}

// Read at build time for static generation.
export function getVersion(): string {
	return getVersionData().version;
}
